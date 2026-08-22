//
//  ManageBudgetUseCase.swift
//  Domain Layer — Use Cases
//
//  Budget CRUD plus the join against actual spending. This is the one place
//  that knows how a budget and an expense list combine into a `BudgetStatus`.
//

import Foundation

struct ManageBudgetUseCase: Sendable {

    private let budgetRepository: BudgetRepository
    private let expenseRepository: ExpenseRepository

    init(budgetRepository: BudgetRepository, expenseRepository: ExpenseRepository) {
        self.budgetRepository = budgetRepository
        self.expenseRepository = expenseRepository
    }

    // MARK: - Reads

    func fetchBudgets() async throws -> [Budget] {
        try await budgetRepository.fetchAll()
    }

    /// Every budget joined with what has actually been spent against it.
    ///
    /// Spending is scoped to `range` (the current month by default) because a
    /// budget is a per-period allowance — measuring it against all-time
    /// spending would show every budget as blown after a few months.
    func fetchStatuses(
        range: DateRangeFilter = .thisMonth,
        referenceDate: Date = Date()
    ) async throws -> [BudgetStatus] {
        async let budgetsTask = budgetRepository.fetchAll()
        async let expensesTask = expenseRepository.fetchAll()
        let (budgets, expenses) = try await (budgetsTask, expensesTask)

        let scoped: [Expense]
        if let interval = range.interval(referenceDate: referenceDate) {
            scoped = expenses.filter { $0.falls(in: interval) }
        } else {
            scoped = expenses
        }

        var spentByCategory: [ExpenseCategory: Double] = [:]
        for expense in scoped {
            spentByCategory[expense.category, default: 0] += expense.amount
        }

        return budgets
            .map { budget in
                BudgetStatus(budget: budget, spent: spentByCategory[budget.category] ?? 0)
            }
            // Most-at-risk first: the user cares about what is blown, not what
            // is comfortably under.
            .sorted { $0.rawPercentageUsed > $1.rawPercentageUsed }
    }

    /// Categories that don't have a budget yet — the picker's option list.
    func availableCategories() async throws -> [ExpenseCategory] {
        let budgeted = Set(try await budgetRepository.fetchAll().map(\.category))
        return ExpenseCategory.allCases.filter { !budgeted.contains($0) }
    }

    /// Total remaining across every budget, shown on the dashboard.
    func totalRemaining(
        range: DateRangeFilter = .thisMonth,
        referenceDate: Date = Date()
    ) async throws -> BudgetSummary {
        let statuses = try await fetchStatuses(range: range, referenceDate: referenceDate)
        return BudgetSummary(
            totalLimit: statuses.reduce(0) { $0 + $1.limit },
            totalSpent: statuses.reduce(0) { $0 + $1.spent },
            exceededCount: statuses.filter(\.isExceeded).count,
            budgetCount: statuses.count
        )
    }

    // MARK: - Writes

    /// Creates a budget for a category that doesn't have one yet.
    @discardableResult
    func createBudget(category: ExpenseCategory, limitText: String) async throws -> Budget {
        let limit = try ExpenseValidator.validateBudgetLimit(limitText)

        // One budget per category is a domain rule, enforced here so every
        // caller gets it for free.
        if try await budgetRepository.fetch(category: category) != nil {
            throw ExpenseError.duplicateBudget(category)
        }

        let budget = Budget(category: category, limit: limit)
        try await budgetRepository.upsert(budget)
        return budget
    }

    /// Changes the limit on an existing budget, preserving its id and
    /// `createdAt` so history stays intact.
    @discardableResult
    func updateLimit(for budget: Budget, limitText: String) async throws -> Budget {
        let limit = try ExpenseValidator.validateBudgetLimit(limitText)
        var updated = budget
        updated.limit = limit
        try await budgetRepository.upsert(updated)
        return updated
    }

    func deleteBudget(id: UUID) async throws {
        try await budgetRepository.delete(id: id)
    }
}

/// Roll-up of every budget, for the dashboard header.
struct BudgetSummary: Equatable, Sendable {
    let totalLimit: Double
    let totalSpent: Double
    let exceededCount: Int
    let budgetCount: Int

    static let empty = BudgetSummary(
        totalLimit: 0, totalSpent: 0, exceededCount: 0, budgetCount: 0
    )

    var hasBudgets: Bool { budgetCount > 0 }

    var remaining: Double { max(0, totalLimit - totalSpent) }

    /// 0...1 for the header progress ring. Guarded against a zero limit.
    var fractionUsed: Double {
        guard totalLimit > 0 else { return 0 }
        return min(1, max(0, totalSpent / totalLimit))
    }

    var isOverBudget: Bool { totalSpent > totalLimit && totalLimit > 0 }
}
