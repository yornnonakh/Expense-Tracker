//
//  AuthValidator.swift
//  Domain Layer — Validation
//
//  Credential rules for the sign-in / sign-up forms.
//

import Foundation

enum AuthValidator {

    /// Matches the server's `MIN_PASSWORD_LENGTH` exactly.
    ///
    /// These two numbers must not drift: a client that accepts a shorter
    /// password than the server does produces a form that passes validation
    /// and then fails on submit, with an error the user cannot act on.
    static let minimumPasswordLength = 8

    /// Deliberately permissive. Strict RFC-5322 regexes reject addresses that
    /// really do work; the only authority on deliverability is a confirmation
    /// email. We just catch obvious typos.
    static func validateEmail(_ email: String) throws -> String {
        let trimmed = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // Requires: something @ something . something, no spaces.
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else {
            throw AuthError.invalidEmail
        }
        return trimmed
    }

    static func validateName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AuthError.emptyName }
        return trimmed
    }

    static func validatePassword(_ password: String) throws -> String {
        guard password.count >= minimumPasswordLength else {
            throw AuthError.weakPassword(minimumLength: minimumPasswordLength)
        }
        return password
    }

    static func validatePasswordConfirmation(
        _ password: String,
        confirmation: String
    ) throws {
        guard password == confirmation else {
            throw AuthError.passwordsDoNotMatch
        }
    }

    static func isValidEmail(_ email: String) -> Bool {
        (try? validateEmail(email)) != nil
    }
}
