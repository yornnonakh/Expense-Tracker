//
//  Budget.swift
//  Domain Layer — Entities
//
//  A spending ceiling the user sets for one category.
//
//  The budget itself does NOT know how much has been spent — that is a
//  property of the expense list, not of the budget. Callers pass `spent` in.
//  Keeping the two apart means a budget never holds stale totals.
//

import Foundation

struct Budget: Identifiable, Codable, Hashable, Sendable {

    let id: UUID
    var category: ExpenseCategory

    /// Maximum the user intends to spend in this category. Always > 0.
    var limit: Double

    let createdAt: Date

    init(
        id: UUID = UUID(),
        category: ExpenseCategory,
        limit: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.limit = limit
        self.createdAt = createdAt
    }

    // MARK: - Business rules

    /// True once spending has gone past the limit. Exactly hitting the limit
    /// is *not* exceeding it — you are allowed to spend your whole budget.
    func isExceeded(spent: Double) -> Bool {
        spent > limit
    }

    /// Money left to spend. Clamped at zero: "you are $30 under" is useful,
    /// "you have -$30 remaining" is not, and the UI would have to clamp anyway.
    func remaining(spent: Double) -> Double {
        Swift.max(0, limit - spent)
    }

    /// How far past the limit the user has gone, zero when still inside it.
    func overspend(spent: Double) -> Double {
        Swift.max(0, spent - limit)
    }

    /// Fraction of the budget consumed, as 0...1 for progress bars.
    ///
    /// Guards against a zero limit, which would otherwise divide by zero and
    /// hand SwiftUI a NaN — that traps inside `ProgressView` at runtime.
    func percentageUsed(spent: Double) -> Double {
        guard limit > 0 else { return spent > 0 ? 1 : 0 }
        return Swift.min(1, Swift.max(0, spent / limit))
    }

    /// Uncapped ratio, used to label things like "128% of budget".
    func rawPercentageUsed(spent: Double) -> Double {
        guard limit > 0 else { return spent > 0 ? 1 : 0 }
        return Swift.max(0, spent / limit)
    }
}

// MARK: - Budget + spending, combined

/// A budget paired with the actual spending measured against it.
/// This is what the Budget tab renders; it is derived, never persisted.
struct BudgetStatus: Identifiable, Hashable, Sendable {

    let budget: Budget
    let spent: Double

    var id: UUID { budget.id }
    var category: ExpenseCategory { budget.category }
    var limit: Double { budget.limit }

    var remaining: Double { budget.remaining(spent: spent) }
    var overspend: Double { budget.overspend(spent: spent) }
    var isExceeded: Bool { budget.isExceeded(spent: spent) }
    var percentageUsed: Double { budget.percentageUsed(spent: spent) }
    var rawPercentageUsed: Double { budget.rawPercentageUsed(spent: spent) }

    /// Drives the colour of the progress bar and the warning banner.
    var level: Level {
        if isExceeded { return .exceeded }
        if percentageUsed >= 0.8 { return .warning }
        return .healthy
    }

    enum Level: Sendable {
        case healthy   // under 80% used
        case warning   // 80%–100% used
        case exceeded  // over the limit
    }
}
