//
//  Expense.swift
//  Domain Layer — Entities
//
//  A single recorded spend. Value type: copying is cheap and there is no
//  shared mutable state to reason about.
//

import Foundation

struct Expense: Identifiable, Codable, Hashable, Sendable {

    /// Stable identity. Assigned once at creation and never rewritten, so an
    /// edit of an existing expense keeps pointing at the same record.
    let id: UUID

    /// Always a positive amount in the user's local currency.
    var amount: Double

    /// Free-form label the user typed, e.g. "Lunch with Sara".
    var description: String

    var category: ExpenseCategory

    /// When the money was spent — not when the row was created.
    var date: Date

    init(
        id: UUID = UUID(),
        amount: Double,
        description: String,
        category: ExpenseCategory,
        date: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.description = description
        self.category = category
        self.date = date
    }
}

// MARK: - Derived values

extension Expense {

    /// Start-of-day for this expense, the key we group transactions by.
    /// Uses the current calendar so grouping follows the user's locale.
    var dayKey: Date {
        Calendar.current.startOfDay(for: date)
    }

    /// True when the expense falls inside the supplied half-open interval.
    func falls(in interval: DateInterval) -> Bool {
        date >= interval.start && date < interval.end
    }
}

// MARK: - Sorting

extension Array where Element == Expense {

    /// The app shows spending newest-first everywhere. Ties break on `id` so
    /// the order is deterministic — important for stable SwiftUI list identity
    /// and for tests that assert on ordering.
    func sortedByDateDescending() -> [Expense] {
        sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.id.uuidString > rhs.id.uuidString
            }
            return lhs.date > rhs.date
        }
    }

    /// Total of every amount in the collection.
    var totalAmount: Double {
        reduce(0) { $0 + $1.amount }
    }
}
