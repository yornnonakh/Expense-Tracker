//
//  AuthRepository.swift
//  Domain Layer — Repository Protocols
//

import Foundation

protocol AuthRepository: Sendable {

    /// Restores a previously saved session for auto-login, or nil when there
    /// is none / it has expired.
    func currentSession() async throws -> AuthSession?

    func signIn(email: String, password: String) async throws -> AuthSession

    func signUp(name: String, email: String, password: String) async throws -> AuthSession

    /// Local demo stands in for "send a reset email". Throws
    /// `AuthError.accountNotFound` when no account matches.
    func requestPasswordReset(email: String) async throws

    func signOut() async throws
}
