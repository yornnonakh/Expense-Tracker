//
//  ErrorPresenting.swift
//  Presentation Layer — ViewModels
//
//  Shared error-to-UI translation.
//
//  Every ViewModel surfaces failures the same way, so the mapping lives once
//  in a protocol extension instead of being re-typed in ten catch blocks.
//  This is also the layer where a typed domain error becomes a plain String —
//  views never switch on error cases themselves.
//

import Foundation

@MainActor
protocol ErrorPresenting: AnyObject {
    /// Message shown in the banner (or inline, for validation errors).
    var errorMessage: String? { get set }
    /// Whether the banner should offer a Retry button.
    var errorIsRetryable: Bool { get set }
}

extension ErrorPresenting {

    /// Converts any thrown error into presentable copy.
    func present(_ error: Error) {
        switch error {
        case let expenseError as ExpenseError:
            errorMessage = expenseError.errorDescription
            errorIsRetryable = expenseError.isRetryable

        case let authError as AuthError:
            errorMessage = authError.errorDescription
            errorIsRetryable = false

        case is CancellationError:
            // A cancelled task means the user navigated away. Showing an
            // error for work they abandoned is noise, not information.
            return

        default:
            errorMessage = error.localizedDescription
            errorIsRetryable = true
        }
    }

    func clearError() {
        errorMessage = nil
        errorIsRetryable = false
    }
}
