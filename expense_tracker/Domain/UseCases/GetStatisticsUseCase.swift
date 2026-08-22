//
//  GetStatisticsUseCase.swift
//  Domain Layer — Use Cases
//
//  All spending aggregation lives here — not in a ViewModel, and not in a
//  SwiftUI computed property. Charts, cards and the budget screen all read the
//  same numbers, so there is exactly one definition of "average expense".
//

import Foundation

struct GetStatisticsUseCase: Sendable {

    private let repository: ExpenseRepository

    init(repository: ExpenseRepository) {
        self.repository = repository
    }

    /// Aggregates every expense inside `range`.
    func execute(
        range: DateRangeFilter = .allTime,
        referenceDate: Date = Date()
    ) async throws -> ExpenseStatistics {
        let all = try await repository.fetchAll()
        let scoped: [Expense]

        if let interval = range.interval(referenceDate: referenceDate) {
            scoped = all.filter { $0.falls(in: interval) }
        } else {
            scoped = all
        }

        return Self.aggregate(scoped, range: range)
    }

    /// Pure aggregation, split out so it can be unit-tested with a literal
    /// array and no repository at all.
    static func aggregate(
        _ expenses: [Expense],
        range: DateRangeFilter = .allTime
    ) -> ExpenseStatistics {
        // An empty set has no meaningful average, highest or lowest. Returning
        // a zeroed snapshot beats returning NaN from 0/0.
        guard !expenses.isEmpty else { return .empty(range: range) }

        let total = expenses.totalAmount

        // Single pass for both extremes rather than two sorts.
        var highest = expenses[0]
        var lowest = expenses[0]
        var byCategory: [ExpenseCategory: Double] = [:]

        for expense in expenses {
            if expense.amount > highest.amount { highest = expense }
            if expense.amount < lowest.amount { lowest = expense }
            byCategory[expense.category, default: 0] += expense.amount
        }

        return ExpenseStatistics(
            totalSpending: total,
            averageExpense: total / Double(expenses.count),
            highestExpense: highest,
            lowestExpense: lowest,
            expenseCount: expenses.count,
            spendingByCategory: byCategory,
            range: range
        )
    }

    /// Every expense in one category inside a range — powers the drill-down
    /// when a pie slice is tapped.
    func executeCategoryDetail(
        category: ExpenseCategory,
        range: DateRangeFilter = .allTime,
        referenceDate: Date = Date()
    ) async throws -> [Expense] {
        let all = try await repository.fetchAll()
        let interval = range.interval(referenceDate: referenceDate)

        return all
            .filter { expense in
                guard expense.category == category else { return false }
                guard let interval else { return true }
                return expense.falls(in: interval)
            }
            .sortedByDateDescending()
    }
}
