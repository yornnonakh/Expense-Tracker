//
//  ExpenseDraft.swift
//  Domain Layer — Entities
//
//  Unvalidated user input on its way to becoming an `Expense`.
//
//  Why a separate type: a form holds a half-filled, possibly invalid state
//  (amount is still a String being typed, category may be unpicked). Modelling
//  that as an `Expense` would force the entity to carry optionals and invalid
//  values forever. The draft absorbs the mess; `Expense` stays always-valid.
//

import Foundation

nonisolated struct ExpenseDraft: Equatable, Sendable {

    /// Raw text straight from the amount field, e.g. "12.50" or "12,50".
    var amountText: String

    var description: String

    /// Optional because nothing is selected when the form first opens.
    var category: ExpenseCategory?

    var date: Date

    init(
        amountText: String = "",
        description: String = "",
        category: ExpenseCategory? = nil,
        date: Date = Date()
    ) {
        self.amountText = amountText
        self.description = description
        self.category = category
        self.date = date
    }

    /// Seeds a draft from an existing expense, for the edit form.
    init(expense: Expense) {
        self.amountText = ExpenseDraft.amountFormatter.string(
            from: NSNumber(value: expense.amount)
        ) ?? String(expense.amount)
        self.description = expense.description
        self.category = expense.category
        self.date = expense.date
    }

    /// Fixed to the POSIX locale: this produces the canonical "1234.56" form
    /// that the parser in `ExpenseValidator` round-trips reliably.
    private static let amountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
