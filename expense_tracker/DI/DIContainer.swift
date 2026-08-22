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
//      KeyValueStore (UserDefaults)
//          └── DataSources (actors)
//                  └── Repositories  (protocol conformances)
//                          └── UseCases
//                                  └── ViewModels
//                                          └── Views
//

import Foundation

final class DIContainer {

    /// Shared graph used by the running app. Views take it as a defaulted
    /// initializer parameter, so any of them can be handed a different
    /// container in a test or preview without touching the call sites.
    static let shared = DIContainer()

    // MARK: - Storage

    let keyValueStore: KeyValueStore

    // MARK: - Data sources

    private let localExpenseDataSource: LocalExpenseDataSource
    private let localBudgetDataSource: LocalBudgetDataSource
    private let localAuthDataSource: LocalAuthDataSource
    private let remoteExpenseDataSource: RemoteExpenseDataSourceProtocol?

    // MARK: - Repositories

    let expenseRepository: ExpenseRepository
    let budgetRepository: BudgetRepository
    let authRepository: AuthRepository

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

    // MARK: - Services

    let sampleDataSeeder: SampleDataSeeder

    // MARK: - Construction

    /// - Parameters:
    ///   - keyValueStore: swap for `InMemoryKeyValueStore` in tests/previews.
    ///   - enableRemoteSync: when false, no simulated backend is wired in and
    ///     the repository stays purely local.
    init(
        keyValueStore: KeyValueStore = UserDefaultsStore(),
        enableRemoteSync: Bool = true
    ) {
        self.keyValueStore = keyValueStore

        // Data sources
        self.localExpenseDataSource = LocalExpenseDataSource(store: keyValueStore)
        self.localBudgetDataSource = LocalBudgetDataSource(store: keyValueStore)
        self.localAuthDataSource = LocalAuthDataSource(store: keyValueStore)
        self.remoteExpenseDataSource = enableRemoteSync
            ? RemoteExpenseDataSource()
            : nil

        // Repositories
        let expenseRepository = ExpenseRepositoryImpl(
            local: localExpenseDataSource,
            remote: remoteExpenseDataSource
        )
        let budgetRepository = BudgetRepositoryImpl(local: localBudgetDataSource)
        let authRepository = AuthRepositoryImpl(local: localAuthDataSource)

        self.expenseRepository = expenseRepository
        self.budgetRepository = budgetRepository
        self.authRepository = authRepository

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

        // Services
        self.sampleDataSeeder = SampleDataSeeder(
            expenseRepository: expenseRepository,
            budgetRepository: budgetRepository,
            store: keyValueStore
        )
    }

    // MARK: - ViewModel factories
    //
    // Views call these instead of building ViewModels themselves, so a change
    // to a ViewModel's dependencies never ripples into view code.

    func makeAuthViewModel() -> AuthViewModel {
        AuthViewModel(
            restoreSession: restoreSessionUseCase,
            signOutUseCase: signOutUseCase,
            seeder: sampleDataSeeder
        )
    }

    func makeSignInViewModel(authViewModel: AuthViewModel) -> SignInViewModel {
        SignInViewModel(signIn: signInUseCase, authViewModel: authViewModel)
    }

    func makeSignUpViewModel(authViewModel: AuthViewModel) -> SignUpViewModel {
        SignUpViewModel(signUp: signUpUseCase, authViewModel: authViewModel)
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

extension DIContainer {

    /// An isolated in-memory graph pre-loaded with sample data.
    ///
    /// Previews must never share `UserDefaults.standard` with the running
    /// app — a preview that writes would corrupt the simulator's real data.
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

        return DIContainer(keyValueStore: store, enableRemoteSync: false)
    }()

    /// An empty in-memory graph, for exercising empty states.
    static func makeEmptyPreview() -> DIContainer {
        DIContainer(keyValueStore: InMemoryKeyValueStore(), enableRemoteSync: false)
    }
}
