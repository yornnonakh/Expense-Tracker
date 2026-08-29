//
//  DIContainer.swift
//  Dependency Injection
//
//  The composition root: the one place that knows which concrete type
//  satisfies each protocol.
//
//  Everything else in the app receives its dependencies through an
//  initializer and names only protocols. That is what makes the layers
//  independently testable — a test builds `DIContainer.preview` (or wires its
//  own fakes) and no production code changes.
//
//  Object graph, built once at launch:
//
//      KeyValueStore (UserDefaults) ── ProfileImageStore (files)
//      KeychainTokenStore  ─────────────┐
//                                       ├── APIClient (URLSession)
//                                       │        └── Remote data sources
//      Local data sources (actors) ─────┤
//                                       └── Repositories
//                                                └── Use cases
//                                                        └── ViewModels
//                                                                └── Views
//
//      SyncEngine (local + remote) ── SyncCoordinator (when to run)
//

import Foundation
import OSLog

@MainActor
final class DIContainer {

    /// Shared graph used by the running app. Views take it as a defaulted
    /// initializer parameter, so any of them can be handed a different
    /// container in a test or preview without touching the call sites.
    ///
    /// That parameter defaults to `nil` and resolves to this inside the init
    /// body, rather than defaulting to `.shared` directly. A default argument
    /// expression is evaluated at the call site and is nonisolated ahead of
    /// SE-0411, so `= .shared` reads a main-actor property from a nonisolated
    /// context — a warning today and an error in Swift 6 language mode, once
    /// per call site. The init body is main-actor isolated, so the same lookup
    /// is simply legal there.
    ///
    /// Turning on the `IsolatedDefaultValues` upcoming feature to get SE-0411
    /// early is not the way out: it also isolates stored-property defaults,
    /// which breaks the `nonisolated init` every ViewModel here relies on.
    static let shared = DIContainer()

    // MARK: - Storage

    let keyValueStore: KeyValueStore
    /// Separate from `keyValueStore` on purpose — see `ProfileImageStore`.
    let profileImageStore: ProfileImageStore
    /// Keychain-backed. Never UserDefaults — see `TokenStore`.
    let tokenStore: TokenStoring

    // MARK: - Networking

    private let apiClient: APIClient?
    private let remoteAuth: RemoteAuthDataSourceProtocol
    private let remoteSync: RemoteSyncDataSourceProtocol?

    // MARK: - Data sources

    private let localExpenseDataSource: LocalExpenseDataSource
    private let localBudgetDataSource: LocalBudgetDataSource
    private let localSessionDataSource: LocalSessionDataSource
    private let syncStateStore: SyncStateStoring
    private let exchangeRateRepository: ExchangeRateRepository

    // MARK: - Repositories

    let expenseRepository: ExpenseRepository
    let budgetRepository: BudgetRepository
    let authRepository: AuthRepository

    /// Concrete type as well as the protocol: the API client's refresh hook
    /// needs `refreshTokens()`, which is not part of `AuthRepository` because
    /// nothing in the domain should know tokens exist.
    private let authRepositoryImpl: AuthRepositoryImpl

    // MARK: - Sync

    let syncEngine: SyncEngine?
    let syncCoordinator: SyncCoordinator?

    // MARK: - Use cases

    let addExpenseUseCase: AddExpenseUseCase
    let getExpensesUseCase: GetExpensesUseCase
    let updateExpenseUseCase: UpdateExpenseUseCase
    let deleteExpenseUseCase: DeleteExpenseUseCase
    let getStatisticsUseCase: GetStatisticsUseCase
    let getWeeklySpendingUseCase: GetWeeklySpendingUseCase
    let filterExpensesUseCase: FilterExpensesUseCase
    let manageBudgetUseCase: ManageBudgetUseCase

    let signInUseCase: SignInUseCase
    let signUpUseCase: SignUpUseCase
    let requestPasswordResetUseCase: RequestPasswordResetUseCase
    let restoreSessionUseCase: RestoreSessionUseCase
    let signOutUseCase: SignOutUseCase
    let updateProfileImageUseCase: UpdateProfileImageUseCase
    let removeProfileImageUseCase: RemoveProfileImageUseCase

    // MARK: - Services

    let sampleDataSeeder: SampleDataSeeder

    // MARK: - Construction

    /// - Parameters:
    ///   - keyValueStore: swap for `InMemoryKeyValueStore` in tests/previews.
    ///   - profileImageStore: swap for `InMemoryProfileImageStore` in
    ///     tests/previews, so neither writes photos into the real container.
    ///   - tokenStore: swap for `InMemoryTokenStore` in tests, so a test run
    ///     never reads or writes the simulator's shared Keychain.
    ///   - remoteAuth / remoteSync: pass fakes to run the whole graph with no
    ///     network. `nil` for `remoteSync` disables sync entirely.
    ///   - baseURL: which server to talk to.
    init(
        keyValueStore: KeyValueStore = UserDefaultsStore(),
        profileImageStore: ProfileImageStore = FileProfileImageStore(),
        tokenStore: TokenStoring = KeychainTokenStore(),
        baseURL: URL = AppEnvironment.apiBaseURL,
        remoteAuth: RemoteAuthDataSourceProtocol? = nil,
        remoteSync: RemoteSyncDataSourceProtocol? = nil,
        remoteExchangeRate: RemoteExchangeRateDataSourceProtocol? = nil,
        enableSync: Bool = true
    ) {
        self.keyValueStore = keyValueStore
        self.profileImageStore = profileImageStore
        self.tokenStore = tokenStore

        // Networking. A caller that supplied both remotes wants no URLSession
        // at all, which is what makes an offline test graph possible.
        let needsClient = remoteAuth == nil || (enableSync && remoteSync == nil)
        let client: APIClient? = needsClient
            ? APIClient(baseURL: baseURL, tokenStore: tokenStore)
            : nil
        self.apiClient = client

        self.remoteAuth = remoteAuth ?? RemoteAuthDataSource(client: client!)
        if enableSync {
            self.remoteSync = remoteSync ?? RemoteSyncDataSource(client: client!)
        } else {
            self.remoteSync = nil
        }

        // Data sources
        self.localExpenseDataSource = LocalExpenseDataSource(store: keyValueStore)
        self.localBudgetDataSource = LocalBudgetDataSource(store: keyValueStore)
        self.localSessionDataSource = LocalSessionDataSource(
            store: keyValueStore, imageStore: profileImageStore
        )
        self.syncStateStore = SyncStateStore(store: keyValueStore)

        // Rates come from a third party, never through `client` — see
        // RemoteExchangeRateDataSource on why our token must not go there.
        self.exchangeRateRepository = ExchangeRateRepositoryImpl(
            remote: remoteExchangeRate ?? RemoteExchangeRateDataSource(),
            store: keyValueStore
        )

        // Repositories
        let expenseRepository = ExpenseRepositoryImpl(local: localExpenseDataSource)
        let budgetRepository = BudgetRepositoryImpl(local: localBudgetDataSource)
        let authRepository = AuthRepositoryImpl(
            remote: self.remoteAuth,
            local: localSessionDataSource,
            tokenStore: tokenStore
        )

        self.expenseRepository = expenseRepository
        self.budgetRepository = budgetRepository
        self.authRepository = authRepository
        self.authRepositoryImpl = authRepository

        // Sync
        if let remoteSyncSource = self.remoteSync {
            let engine = SyncEngine(
                localExpenses: localExpenseDataSource,
                localBudgets: localBudgetDataSource,
                remote: remoteSyncSource,
                syncState: syncStateStore
            )
            self.syncEngine = engine
            self.syncCoordinator = SyncCoordinator(engine: engine)
        } else {
            self.syncEngine = nil
            self.syncCoordinator = nil
        }

        // Expense use cases
        self.addExpenseUseCase = AddExpenseUseCase(repository: expenseRepository)
        self.getExpensesUseCase = GetExpensesUseCase(repository: expenseRepository)
        self.updateExpenseUseCase = UpdateExpenseUseCase(repository: expenseRepository)
        self.deleteExpenseUseCase = DeleteExpenseUseCase(repository: expenseRepository)
        self.getStatisticsUseCase = GetStatisticsUseCase(repository: expenseRepository)
        self.getWeeklySpendingUseCase = GetWeeklySpendingUseCase(
            repository: expenseRepository
        )
        self.filterExpensesUseCase = FilterExpensesUseCase()
        self.manageBudgetUseCase = ManageBudgetUseCase(
            budgetRepository: budgetRepository,
            expenseRepository: expenseRepository
        )

        // Auth use cases
        self.signInUseCase = SignInUseCase(repository: authRepository)
        self.signUpUseCase = SignUpUseCase(repository: authRepository)
        self.requestPasswordResetUseCase = RequestPasswordResetUseCase(
            repository: authRepository
        )
        self.restoreSessionUseCase = RestoreSessionUseCase(repository: authRepository)
        self.signOutUseCase = SignOutUseCase(repository: authRepository)
        self.updateProfileImageUseCase = UpdateProfileImageUseCase(
            repository: authRepository
        )
        self.removeProfileImageUseCase = RemoveProfileImageUseCase(
            repository: authRepository
        )

        // Services
        self.sampleDataSeeder = SampleDataSeeder(
            expenseRepository: expenseRepository,
            budgetRepository: budgetRepository,
            store: keyValueStore
        )
    }

    /// Async wiring that cannot happen in `init`.
    ///
    /// The API client refreshes expired tokens by calling back into the auth
    /// repository, and the auth repository sends its requests through the API
    /// client. Constructing that cycle is impossible; closing it afterwards is
    /// trivial. Called once from the root view before anything else runs.
    func bootstrap() async {
        guard let apiClient else { return }

        let repository = authRepositoryImpl
        await apiClient.setRefreshHandler {
            await repository.refreshTokens() != nil
        }

        if AppEnvironment.buildConfiguration == .release,
           !AppEnvironment.isProductionEndpointConfigured {
            AppLog.network.error(
                "Release build has no APIBaseURL configured; the app will run offline-only."
            )
        }
    }

    // MARK: - ViewModel factories
    //
    // Views call these instead of building ViewModels themselves, so a change
    // to a ViewModel's dependencies never ripples into view code.

    func makeCurrencyStore() -> CurrencyStore {
        CurrencyStore(repository: exchangeRateRepository)
    }

    func makeAuthViewModel() -> AuthViewModel {
        AuthViewModel(
            restoreSession: restoreSessionUseCase,
            signOutUseCase: signOutUseCase,
            seeder: sampleDataSeeder,
            syncCoordinator: syncCoordinator
        )
    }

    func makeSignInViewModel(authViewModel: AuthViewModel) -> SignInViewModel {
        SignInViewModel(signIn: signInUseCase, authViewModel: authViewModel)
    }

    func makeSignUpViewModel(authViewModel: AuthViewModel) -> SignUpViewModel {
        SignUpViewModel(signUp: signUpUseCase, authViewModel: authViewModel)
    }

    func makeProfileViewModel(authViewModel: AuthViewModel) -> ProfileViewModel {
        ProfileViewModel(
            updateProfileImage: updateProfileImageUseCase,
            removeProfileImage: removeProfileImageUseCase,
            authViewModel: authViewModel
        )
    }

    func makeForgotPasswordViewModel() -> ForgotPasswordViewModel {
        ForgotPasswordViewModel(requestReset: requestPasswordResetUseCase)
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(
            getExpenses: getExpensesUseCase,
            getStatistics: getStatisticsUseCase,
            getWeeklySpending: getWeeklySpendingUseCase,
            manageBudget: manageBudgetUseCase
        )
    }

    func makeExpensesListViewModel() -> ExpensesListViewModel {
        ExpensesListViewModel(
            getExpenses: getExpensesUseCase,
            deleteExpense: deleteExpenseUseCase,
            filterExpenses: filterExpensesUseCase
        )
    }

    func makeAddExpenseViewModel() -> AddExpenseViewModel {
        AddExpenseViewModel(addExpense: addExpenseUseCase)
    }

    /// `@MainActor`, unlike its siblings: `EditExpenseViewModel` seeds a
    /// published property in its initializer and so is main-actor isolated.
    @MainActor
    func makeEditExpenseViewModel(expense: Expense) -> EditExpenseViewModel {
        EditExpenseViewModel(
            expense: expense,
            updateExpense: updateExpenseUseCase,
            deleteExpense: deleteExpenseUseCase
        )
    }

    func makeTransactionsViewModel() -> TransactionsViewModel {
        TransactionsViewModel(
            getExpenses: getExpensesUseCase,
            filterExpenses: filterExpensesUseCase
        )
    }

    func makeStatisticsViewModel() -> StatisticsViewModel {
        StatisticsViewModel(getStatistics: getStatisticsUseCase)
    }

    func makeBudgetViewModel() -> BudgetViewModel {
        BudgetViewModel(manageBudget: manageBudgetUseCase)
    }
}

// MARK: - Previews

#if DEBUG
extension DIContainer {

    /// An isolated in-memory graph pre-loaded with sample data.
    ///
    /// Previews must never share `UserDefaults.standard` with the running
    /// app — a preview that writes would corrupt the simulator's real data —
    /// and must never touch the network or the Keychain.
    static let preview: DIContainer = {
        let store = InMemoryKeyValueStore()

        // Seed synchronously so previews render populated on first frame
        // instead of flashing an empty state.
        let expenseDTOs = ExpenseMapper.toDTOs(SampleDataSeeder.sampleExpenses())
        let budgetDTOs = BudgetMapper.toDTOs(SampleDataSeeder.sampleBudgets())

        if let expenseData = try? JSONCoding.encode(expenseDTOs) {
            store.set(expenseData, forKey: StorageKey.expenses)
        }
        if let budgetData = try? JSONCoding.encode(budgetDTOs) {
            store.set(budgetData, forKey: StorageKey.budgets)
        }
        // Mark seeding done so the seeder doesn't duplicate the above.
        store.set(Data([1]), forKey: StorageKey.hasSeededSampleData)

        return DIContainer(
            keyValueStore: store,
            profileImageStore: InMemoryProfileImageStore(),
            tokenStore: InMemoryTokenStore(),
            remoteAuth: StubRemoteAuthDataSource(),
            remoteSync: StubRemoteSyncDataSource(),
            enableSync: false
        )
    }()

    /// An empty in-memory graph, for exercising empty states.
    /// A rate store for previews. Uses the compiled-in fallback rate rather
    /// than reaching the network, so a canvas render is deterministic and
    /// works with no connection.
    static var previewCurrencyStore: CurrencyStore {
        CurrencyStore(repository: StubExchangeRateRepository())
    }

    static func makeEmptyPreview() -> DIContainer {
        DIContainer(
            keyValueStore: InMemoryKeyValueStore(),
            profileImageStore: InMemoryProfileImageStore(),
            tokenStore: InMemoryTokenStore(),
            remoteAuth: StubRemoteAuthDataSource(),
            remoteSync: StubRemoteSyncDataSource(),
            enableSync: false
        )
    }
}
#endif
