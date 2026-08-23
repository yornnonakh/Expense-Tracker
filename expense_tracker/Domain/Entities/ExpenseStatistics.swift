//
//  ExpenseStatistics.swift
//  Domain Layer — Entities
//
//  An immutable snapshot of aggregate spending, produced by
//  `GetStatisticsUseCase`. Views read it; nothing mutates it.
//

import Foundation

nonisolated struct ExpenseStatistics: Equatable, Sendable {

    let totalSpending: Double
    let averageExpense: Double
    let highestExpense: Expense?
    let lowestExpense: Expense?
    let expenseCount: Int

    /// Total per category. Categories with no spending are omitted, so the
    /// pie chart never has to render zero-width slices.
    let spendingByCategory: [ExpenseCategory: Double]

    /// The window these numbers describe, so the UI can caption them.
    let range: DateRangeFilter

    static func empty(range: DateRangeFilter = .allTime) -> ExpenseStatistics {
        ExpenseStatistics(
            totalSpending: 0,
            averageExpense: 0,
            highestExpense: nil,
            lowestExpense: nil,
            expenseCount: 0,
            spendingByCategory: [:],
            range: range
        )
    }

    var isEmpty: Bool { expenseCount == 0 }

    /// Categories ordered by spend, biggest first — the order the pie chart
    /// and its legend are drawn in.
    var categoryBreakdown: [CategoryBreakdown] {
        spendingByCategory
            .map { category, amount in
                CategoryBreakdown(
                    category: category,
                    amount: amount,
                    // Guard the divide: totalSpending is zero when there are
                    // no expenses, and NaN percentages break chart geometry.
                    fraction: totalSpending > 0 ? amount / totalSpending : 0
                )
            }
            .sorted { lhs, rhs in
                if lhs.amount == rhs.amount {
                    return lhs.category.displayName < rhs.category.displayName
                }
                return lhs.amount > rhs.amount
            }
    }
}

/// One slice of the spending pie.
nonisolated struct CategoryBreakdown: Identifiable, Equatable, Sendable {
    let category: ExpenseCategory
    let amount: Double
    /// Share of total spending, 0...1.
    let fraction: Double

    var id: String { category.rawValue }
    var percentage: Double { fraction * 100 }
}

/// One bar in the Home tab's weekly chart.
nonisolated struct DailySpending: Identifiable, Equatable, Sendable {
    /// Start-of-day for the bar.
    let date: Date
    let amount: Double

    var id: Date { date }

    /// Single-letter weekday label, e.g. "M". Locale-aware.
    var shortWeekdayLabel: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter.string(from: date)
    }
}
