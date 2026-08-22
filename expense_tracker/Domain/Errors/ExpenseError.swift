//
//  ExpenseError.swift
//  Domain Layer — Errors
//
//  Every failure the expense/budget side of the app can surface, in one place.
//
//  Data-layer errors (a corrupt JSON blob, a failed write) are translated into
//  these cases at the repository boundary. That is what stops `DecodingError`
//  or `NSError` from leaking upward: the presentation layer only ever switches
//  on `ExpenseError`, so adding a new storage backend cannot break the UI.
//

import Foundation

enum ExpenseError: LocalizedError, Equatable {

    // MARK: Validation
    case invalidAmount
    case amountTooLarge
    case emptyDescription
    case descriptionTooLong(limit: Int)
    case missingCategory

    // MARK: Budget rules
    case invalidBudgetLimit
    case duplicateBudget(ExpenseCategory)

    // MARK: Lookup
    case expenseNotFound
    case budgetNotFound

    // MARK: Storage
    case encodingFailed(String)
    case decodingFailed(String)
    case persistenceFailed(String)

    // MARK: Remote
    case remoteUnavailable

    // MARK: Fallback
    case unknown(String)

    // MARK: - User-facing copy

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "Enter an amount greater than 0."
        case .amountTooLarge:
            return "That amount is too large to record."
        case .emptyDescription:
            return "Add a short description."
        case .descriptionTooLong(let limit):
            return "Keep the description under \(limit) characters."
        case .missingCategory:
            return "Pick a category."
        case .invalidBudgetLimit:
            return "Enter a budget limit greater than 0."
        case .duplicateBudget(let category):
            return "You already have a budget for \(category.displayName)."
        case .expenseNotFound:
            return "That expense no longer exists."
        case .budgetNotFound:
            return "That budget no longer exists."
        case .encodingFailed:
            return "We couldn't save your changes."
        case .decodingFailed:
            return "We couldn't read your saved data."
        case .persistenceFailed:
            return "Saving to this device failed."
        case .remoteUnavailable:
            return "You're offline. Changes are saved on this device."
        case .unknown:
            return "Something went wrong."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidAmount, .amountTooLarge, .emptyDescription,
             .descriptionTooLong, .missingCategory, .invalidBudgetLimit:
            return "Fix the highlighted field and try again."
        case .duplicateBudget:
            return "Edit the existing budget instead."
        case .expenseNotFound, .budgetNotFound:
            return "Pull to refresh the list."
        case .encodingFailed, .persistenceFailed, .unknown:
            return "Try again in a moment."
        case .decodingFailed:
            return "Your data may be corrupted. Resetting it will start you fresh."
        case .remoteUnavailable:
            return "We'll sync when you're back online."
        }
    }

    /// Whether the UI should offer a Retry button. Validation errors are the
    /// user's to fix, so retrying the same input would just fail again.
    var isRetryable: Bool {
        switch self {
        case .encodingFailed, .persistenceFailed, .remoteUnavailable, .unknown:
            return true
        case .invalidAmount, .amountTooLarge, .emptyDescription,
             .descriptionTooLong, .missingCategory, .invalidBudgetLimit,
             .duplicateBudget, .expenseNotFound, .budgetNotFound, .decodingFailed:
            return false
        }
    }

    /// Validation problems render inline under a field; everything else
    /// renders in the banner at the top of the screen.
    var isValidation: Bool {
        switch self {
        case .invalidAmount, .amountTooLarge, .emptyDescription,
             .descriptionTooLong, .missingCategory, .invalidBudgetLimit,
             .duplicateBudget:
            return true
        default:
            return false
        }
    }

    /// Wraps an arbitrary error, passing `ExpenseError` through unchanged so
    /// repeated wrapping never nests one of these inside `.unknown`.
    static func wrapping(_ error: Error) -> ExpenseError {
        if let expenseError = error as? ExpenseError { return expenseError }
        if error is EncodingError { return .encodingFailed(error.localizedDescription) }
        if error is DecodingError { return .decodingFailed(error.localizedDescription) }
        return .unknown(error.localizedDescription)
    }
}
