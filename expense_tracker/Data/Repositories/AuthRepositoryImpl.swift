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
            let avatarData = await local.avatarData(fileName: dto.avatarFileName)
            let session = try AccountMapper.toDomain(dto, avatarImageData: avatarData)

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

            let avatarData = await local.avatarData(fileName: account.avatarFileName)
            let user = try AccountMapper.toDomain(account, avatarImageData: avatarData)
            return try await issueSession(
                for: user, avatarFileName: account.avatarFileName
            )
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
            // A brand-new account has no photo yet, so nothing to look up.
            return try await issueSession(for: user, avatarFileName: nil)
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

    func updateProfileImage(_ imageData: Data?) async throws -> User {
        do {
            // The session is the only thing that says who "me" is, so an
            // expired or missing one means there is nobody to edit.
            guard let session = try await local.loadSession() else {
                throw AuthError.sessionExpired
            }

            let account = try await local.setAvatar(
                imageData, forAccountId: session.userId
            )
            try await local.updateSessionAvatar(fileName: account.avatarFileName)

            // Hand back the bytes we were given rather than re-reading the
            // file we just wrote.
            return try AccountMapper.toDomain(account, avatarImageData: imageData)
        } catch {
            throw AuthError.wrapping(error)
        }
    }

    func signOut() async throws {
        await local.clearSession()
    }

    // MARK: - Helpers

    private func issueSession(
        for user: User,
        avatarFileName: String?
    ) async throws -> AuthSession {
        let session = AuthSession(token: LocalAuthDataSource.makeToken(), user: user)
        try await local.saveSession(
            AccountMapper.toDTO(session, avatarFileName: avatarFileName)
        )
        return session
    }
}
