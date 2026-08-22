//
//  ExpensesListViewModel.swift
//  Presentation Layer — ViewModels
//
//  Filterable expense list with swipe-to-delete.
//

import Combine
import Foundation

@MainActor
final class ExpensesListViewModel: ObservableObject, ErrorPresenting {

    /// Everything from storage. Kept whole so filtering stays local and
    /// instant — changing a filter never re-reads from disk.
    @Published private(set) var allExpenses: [Expense] = []

    @Published var selectedCategory: ExpenseCategory? {
        didSet { recomputeFiltered() }
    }
    @Published var searchText: String = "" {
        didSet { recomputeFiltered() }
    }
    @Published var dateRange: DateRangeFilter = .allTime {
        didSet { recomputeFiltered() }
    }

    @Published private(set) var filteredExpenses: [Expense] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedOnce = false
    @Published var errorMessage: String?
    @Published var errorIsRetryable = false

    /// Set after a delete so the view can toast it.
    @Published var toastMessage: String?

    private let getExpenses: GetExpensesUseCase
    private let deleteExpense: DeleteExpenseUseCase
    private let filterExpenses: FilterExpensesUseCase

    nonisolated init(
        getExpenses: GetExpensesUseCase,
        deleteExpense: DeleteExpenseUseCase,
        filterExpenses: FilterExpensesUseCase
    ) {
        self.getExpenses = getExpenses
        self.deleteExpense = deleteExpense
        self.filterExpenses = filterExpenses
    }

    // MARK: - Derived

    var criteria: ExpenseFilterCriteria {
        ExpenseFilterCriteria(
            category: selectedCategory,
            range: dateRange,
            searchText: searchText
        )
    }

    var isFiltering: Bool { criteria.isActive }

    var filteredTotal: Double { filteredExpenses.totalAmount }

    /// Row counts per category, shown on the filter pills.
    var categoryCounts: [ExpenseCategory: Int] {
        Dictionary(grouping: allExpenses, by: \.category)
            .mapValues(\.count)
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
            recomputeFiltered()
        } catch {
            present(error)
        }
    }

    func retry() async {
        await load()
    }

    // MARK: - Filtering

    /// Re-runs the pure filter over the in-memory list. Cheap enough to call
    /// from a `didSet` on every keystroke.
    private func recomputeFiltered() {
        filteredExpenses = filterExpenses.execute(
            expenses: allExpenses,
            criteria: criteria
        )
    }

    func clearFilters() {
        // Assign through the backing properties one at a time; each `didSet`
        // recomputes, which is three cheap passes rather than a special case.
        selectedCategory = nil
        searchText = ""
        dateRange = .allTime
    }

    // MARK: - Mutations

    func delete(_ expense: Expense) async {
        // Optimistic removal: the row disappears with the swipe instead of
        // after a storage round-trip, and is restored if the delete fails.
        let snapshot = allExpenses
        allExpenses.removeAll { $0.id == expense.id }
        recomputeFiltered()

        do {
            try await deleteExpense.execute(id: expense.id)
            Haptics.success()
            toastMessage = "Expense deleted"
        } catch {
            allExpenses = snapshot
            recomputeFiltered()
            present(error)
            Haptics.error()
        }
    }

    /// Bridges SwiftUI's offset-based `onDelete` to entity ids. Resolving the
    /// offsets against `filteredExpenses` — the array the List actually
    /// renders — is what keeps deletes correct while a filter is active.
    func delete(at offsets: IndexSet) async {
        let targets = offsets.compactMap { index -> Expense? in
            guard filteredExpenses.indices.contains(index) else { return nil }
            return filteredExpenses[index]
        }

        for expense in targets {
            await delete(expense)
        }
    }
}
