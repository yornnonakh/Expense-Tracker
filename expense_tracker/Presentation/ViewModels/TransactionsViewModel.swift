//
//  TransactionsViewModel.swift
//  Presentation Layer — ViewModels
//
//  Date-grouped transaction history.
//

import Combine
import Foundation

@MainActor
final class TransactionsViewModel: ObservableObject, ErrorPresenting {

    @Published private(set) var allExpenses: [Expense] = []

    @Published var dateRange: DateRangeFilter = .thisMonth {
        didSet { recomputeGroups() }
    }
    @Published var searchText: String = "" {
        didSet { recomputeGroups() }
    }

    /// Sections of expenses, newest day first.
    @Published private(set) var groups: [ExpenseDayGroup] = []

    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedOnce = false
    @Published var errorMessage: String?
    @Published var errorIsRetryable = false

    private let getExpenses: GetExpensesUseCase
    private let filterExpenses: FilterExpensesUseCase

    nonisolated init(
        getExpenses: GetExpensesUseCase,
        filterExpenses: FilterExpensesUseCase
    ) {
        self.getExpenses = getExpenses
        self.filterExpenses = filterExpenses
    }

    // MARK: - Derived

    var rangeTotal: Double {
        groups.reduce(0) { $0 + $1.total }
    }

    var transactionCount: Int {
        groups.reduce(0) { $0 + $1.expenses.count }
    }

    /// The Transactions tab offers a narrower set of windows than Statistics —
    /// "All Time" would defeat the point of a date-scoped history view.
    var availableRanges: [DateRangeFilter] {
        [.thisMonth, .lastMonth, .thisYear]
    }

    // MARK: - Lifecycle

    func start() async {
        await load()
        await observeChanges()
    }

    func observeChanges() async {
        for await _ in NotificationCenter.default.notifications(
            named: .expenseDataDidChange
        ) {
            await load()
        }
    }

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }
        clearError()

        do {
            allExpenses = try await getExpenses.execute()
            recomputeGroups()
        } catch {
            present(error)
        }
    }

    func retry() async {
        await load()
    }

    // MARK: - Grouping

    private func recomputeGroups() {
        let criteria = ExpenseFilterCriteria(
            category: nil,
            range: dateRange,
            searchText: searchText
        )
        let filtered = filterExpenses.execute(
            expenses: allExpenses,
            criteria: criteria
        )
        groups = filterExpenses.groupByDay(filtered)
    }
}
