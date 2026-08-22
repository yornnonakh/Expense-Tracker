//
//  AuthRepositoryImpl.swift
//  Data Layer — Repository Implementations
//

import Foundation

final class AuthRepositoryImpl: AuthRepository {

    private let local: LocalAuthDataSource

    init(local: LocalAuthDataSource) {
        self.local = local
    }

    func currentSession() async throws -> AuthSession? {
        do {
            guard let dto = try await local.loadSession() else { return nil }
            let session = try AccountMapper.toDomain(dto)

            // An expired token must not silently log the user in.
            guard !session.isExpired() else {
                await local.clearSession()
                return nil
            }
            return session
        } catch {
            throw AuthError.wrapping(error)
        }
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        do {
            guard let account = try await local.account(email: email) else {
                // Same error as a wrong password, so the response doesn't
                // reveal which emails have accounts.
                throw AuthError.invalidCredentials
            }
            guard await local.verify(password: password, against: account) else {
                throw AuthError.invalidCredentials
            }

            let user = try AccountMapper.toDomain(account)
            return try await issueSession(for: user)
        } catch {
            throw AuthError.wrapping(error)
        }
    }

    func signUp(name: String, email: String, password: String) async throws -> AuthSession {
        do {
            let account = try await local.createAccount(
                name: name, email: email, password: password
            )
            let user = try AccountMapper.toDomain(account)
            return try await issueSession(for: user)
        } catch {
            throw AuthError.wrapping(error)
        }
    }

    func requestPasswordReset(email: String) async throws {
        do {
            guard try await local.account(email: email) != nil else {
                throw AuthError.accountNotFound
            }
            // A real implementation would ask the backend to send an email.
            // Locally there is nothing to send, so we just confirm the account
            // exists and let the UI show its "check your inbox" state.
        } catch {
            throw AuthError.wrapping(error)
        }
    }

    func signOut() async throws {
        await local.clearSession()
    }

    // MARK: - Helpers

    private func issueSession(for user: User) async throws -> AuthSession {
        let session = AuthSession(token: LocalAuthDataSource.makeToken(), user: user)
        try await local.saveSession(AccountMapper.toDTO(session))
        return session
    }
}
