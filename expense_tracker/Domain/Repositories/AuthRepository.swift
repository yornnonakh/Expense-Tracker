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

    /// Replaces the signed-in user's profile photo, or clears it when
    /// `imageData` is nil, and returns the updated user.
    ///
    /// Takes no user id: the account being changed is always the one holding
    /// the current session, so there is no way to spell "edit someone else".
    /// Throws `AuthError.sessionExpired` when nobody is signed in.
    func updateProfileImage(_ imageData: Data?) async throws -> User

    func signOut() async throws
}
