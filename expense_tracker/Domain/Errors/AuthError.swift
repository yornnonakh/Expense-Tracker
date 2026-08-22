//
//  AuthError.swift
//  Domain Layer — Errors
//
//  Authentication failures, kept separate from `ExpenseError` so the two
//  feature areas can evolve independently (single responsibility).
//

import Foundation

enum AuthError: LocalizedError, Equatable {

    case invalidEmail
    case emptyName
    case weakPassword(minimumLength: Int)
    case passwordsDoNotMatch
    case emailAlreadyRegistered
    case invalidCredentials
    case accountNotFound
    case sessionExpired
    case storageFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Enter a valid email address."
        case .emptyName:
            return "Enter your name."
        case .weakPassword(let minimumLength):
            return "Password must be at least \(minimumLength) characters."
        case .passwordsDoNotMatch:
            return "Passwords don't match."
        case .emailAlreadyRegistered:
            return "An account already exists for that email."
        case .invalidCredentials:
            // Deliberately vague: saying "wrong password" versus "no such
            // account" tells an attacker which emails are registered.
            return "Incorrect email or password."
        case .accountNotFound:
            return "We couldn't find an account for that email."
        case .sessionExpired:
            return "Your session expired. Please sign in again."
        case .storageFailure:
            return "We couldn't complete that. Please try again."
        }
    }

    var isValidation: Bool {
        switch self {
        case .invalidEmail, .emptyName, .weakPassword, .passwordsDoNotMatch:
            return true
        default:
            return false
        }
    }

    static func wrapping(_ error: Error) -> AuthError {
        if let authError = error as? AuthError { return authError }
        return .storageFailure(error.localizedDescription)
    }
}
