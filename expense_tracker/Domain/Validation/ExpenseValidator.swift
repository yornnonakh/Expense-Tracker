//
//  ExpenseValidator.swift
//  Domain Layer — Validation
//
//  Turns unvalidated `ExpenseDraft` input into a guaranteed-valid `Expense`.
//
//  Validation lives in the domain, not in the view. That way the same rules
//  apply no matter what calls them — the add form, the edit form, a future
//  CSV import or a widget — and they can be unit-tested without any UI.
//

import Foundation

enum ExpenseValidator {

    /// Longest description we accept. Keeps list rows from being unbounded and
    /// keeps the stored JSON small.
    static let descriptionCharacterLimit = 120

    /// Above this, the value is almost certainly a typo (or an overflow
    /// attempt) rather than a real purchase.
    static let maximumAmount: Double = 1_000_000_000

    /// Validates every field, throwing on the first problem found.
    ///
    /// - Parameters:
    ///   - draft: raw form input.
    ///   - id: pass the existing id when editing so identity is preserved;
    ///         omit it when adding and a fresh one is minted.
    static func makeExpense(from draft: ExpenseDraft, id: UUID = UUID()) throws -> Expense {
        let amount = try validateAmount(draft.amountText)
        let description = try validateDescription(draft.description)
        let category = try validateCategory(draft.category)

        return Expense(
            id: id,
            amount: amount,
            description: description,
            category: category,
            date: draft.date
        )
    }

    // MARK: - Field rules

    /// Parses the amount text and enforces `0 < amount <= maximumAmount`.
    ///
    /// Accepts both "12.50" and "12,50": users on comma-decimal locales type
    /// the separator their keyboard offers, and rejecting it reads as a bug.
    static func validateAmount(_ text: String) throws -> Double {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard
            !normalized.isEmpty,
            let amount = Double(normalized),
            amount.isFinite
        else {
            throw ExpenseError.invalidAmount
        }

        guard amount > 0 else { throw ExpenseError.invalidAmount }
        guard amount <= maximumAmount else { throw ExpenseError.amountTooLarge }

        // Round to cents so 0.1 + 0.2 style float drift never accumulates
        // across the totals shown in Statistics.
        return (amount * 100).rounded() / 100
    }

    static func validateDescription(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExpenseError.emptyDescription }
        guard trimmed.count <= descriptionCharacterLimit else {
            throw ExpenseError.descriptionTooLong(limit: descriptionCharacterLimit)
        }
        return trimmed
    }

    static func validateCategory(_ category: ExpenseCategory?) throws -> ExpenseCategory {
        guard let category else { throw ExpenseError.missingCategory }
        return category
    }

    static func validateBudgetLimit(_ text: String) throws -> Double {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard
            !normalized.isEmpty,
            let limit = Double(normalized),
            limit.isFinite,
            limit > 0
        else {
            throw ExpenseError.invalidBudgetLimit
        }

        guard limit <= maximumAmount else { throw ExpenseError.amountTooLarge }
        return (limit * 100).rounded() / 100
    }

    // MARK: - Non-throwing checks, for live form feedback

    /// Cheap "can I enable the Save button?" test. Mirrors the throwing rules
    /// above but returns a Bool so the view can call it on every keystroke.
    static func isValid(_ draft: ExpenseDraft) -> Bool {
        (try? makeExpense(from: draft)) != nil
    }
}
