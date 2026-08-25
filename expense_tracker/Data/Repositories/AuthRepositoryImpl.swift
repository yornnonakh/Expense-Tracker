//
//  AuthRepositoryImpl.swift
//  Data Layer — Repository Implementations
//
//  Authenticates against the server and keeps just enough on device to survive
//  a launch without a network.
//
//  THE SPLIT:
//    Keychain (`TokenStoring`)   — access and refresh tokens. The credentials.
//    Local cache (`LocalSessionDataSource`) — name, email, avatar. Convenience.
//
//  Restoring a session reads the Keychain, not the cache. The cache can be
//  stale or absent without any security consequence; the tokens are what
//  actually authorise anything.
//

import Foundation
import OSLog

final class AuthRepositoryImpl: AuthRepository {

    private let remote: RemoteAuthDataSourceProtocol
    private let local: LocalSessionDataSource
    private let tokenStore: TokenStoring

    init(
        remote: RemoteAuthDataSourceProtocol,
        local: LocalSessionDataSource,
        tokenStore: TokenStoring
    ) {
        self.remote = remote
        self.local = local
        self.tokenStore = tokenStore
    }

    // MARK: - Session

    /// Auto-login.
    ///
    /// Works offline on purpose: if there are tokens and a cached profile, the
    /// user is signed in, full stop. Requiring the server to confirm would
    /// lock people out of their own local data whenever the network is down —
    /// which is exactly when an offline-first app should still work.
    func currentSession() async throws -> AuthSession? {
        guard let tokens = await tokenStore.tokens() else { return nil }

        // An expired access token is normal after a few hours in the
        // background; refresh before deciding anything is wrong.
        var accessToken = tokens.accessToken
        if tokens.isAccessTokenExpired() {
            if let refreshed = await refreshTokens() {
                accessToken = refreshed.accessToken
            } else {
                // Refresh may have failed because the refresh token is dead
                // (sign out) or because there is no network (stay signed in).
                // Only the former should end the session.
                if await tokenStore.tokens() == nil { return nil }
            }
        }

        guard let cached = await local.cachedUser() else {
            // Tokens but no profile: fetch it, and treat a network failure as
            // "cannot restore right now" rather than "signed out".
            guard let user = try? await remote.currentUser() else { return nil }
            try await local.cache(AccountMapper.toCached(user))
            let domainUser = try AccountMapper.toDomain(user)
            return AuthSession(token: accessToken, user: domainUser)
        }

        let avatarData = await local.avatarData(fileName: cached.avatarFileName)
        let user = try AccountMapper.toDomain(cached, avatarImageData: avatarData)
        return AuthSession(token: accessToken, user: user)
    }

    // MARK: - Credentials

    func signIn(email: String, password: String) async throws -> AuthSession {
        do {
            let response = try await remote.signIn(email: email, password: password)
            return try await adopt(response)
        } catch {
            throw Self.authError(from: error)
        }
    }

    func signUp(name: String, email: String, password: String) async throws -> AuthSession {
        do {
            let response = try await remote.signUp(name: name, email: email, password: password)
            return try await adopt(response)
        } catch {
            throw Self.authError(from: error)
        }
    }

    func requestPasswordReset(email: String) async throws {
        do {
            try await remote.requestPasswordReset(email: email)
        } catch {
            throw Self.authError(from: error)
        }
    }

    func signOut() async throws {
        // Tell the server first so the refresh token is revoked rather than
        // left live for its full 30 days. Best effort: a failure here must not
        // strand the user in a signed-in state they asked to leave.
        if let refreshToken = await tokenStore.refreshToken() {
            try? await remote.signOut(refreshToken: refreshToken)
        }

        await tokenStore.clear()
        await local.clear()
    }

    // MARK: - Profile

    func updateProfileImage(_ imageData: Data?) async throws -> User {
        guard await tokenStore.tokens() != nil else { throw AuthError.sessionExpired }

        do {
            let updated: APIUser
            if let imageData {
                updated = try await remote.uploadAvatar(imageData)
            } else {
                updated = try await remote.removeAvatar()
            }

            // Cache the profile first so the local write below has a record to
            // attach the photo to.
            let existing = await local.cachedUser()
            try await local.cache(
                AccountMapper.toCached(updated, avatarFileName: existing?.avatarFileName)
            )
            let cached = try await local.setAvatar(
                imageData, hasRemoteAvatar: updated.hasAvatar
            )

            // Hand back the bytes we were given rather than re-reading the
            // file we just wrote.
            return try AccountMapper.toDomain(cached, avatarImageData: imageData)
        } catch {
            throw Self.authError(from: error)
        }
    }

    // MARK: - Helpers

    private func adopt(_ response: APISessionResponse) async throws -> AuthSession {
        await tokenStore.store(
            TokenPair(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresIn: response.expiresIn
            )
        )

        try await local.cache(AccountMapper.toCached(response.user))

        // Pull the photo down so a fresh install shows it immediately. A
        // failure is not fatal — the account screen falls back to initials.
        var avatarData: Data?
        if response.user.hasAvatar, let downloaded = try? await remote.downloadAvatar() {
            avatarData = downloaded
            _ = try? await local.setAvatar(downloaded, hasRemoteAvatar: true)
        }

        let user = try AccountMapper.toDomain(response.user, avatarImageData: avatarData)
        AppLog.auth.info("session established for user \(user.id.uuidString, privacy: .public)")
        return AuthSession(token: response.accessToken, user: user)
    }

    /// Exchanges the refresh token for a new pair.
    ///
    /// Also wired into `APIClient` as its refresh handler, which is why it
    /// returns an optional instead of throwing: the client only needs to know
    /// whether to retry.
    @discardableResult
    func refreshTokens() async -> TokenPair? {
        guard let refreshToken = await tokenStore.refreshToken() else { return nil }

        do {
            let response = try await remote.refresh(refreshToken: refreshToken)
            let pair = TokenPair(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresIn: response.expiresIn
            )
            await tokenStore.store(pair)
            try? await local.cache(
                AccountMapper.toCached(
                    response.user,
                    avatarFileName: await local.cachedUser()?.avatarFileName
                )
            )
            return pair
        } catch let error as APIError where error.isConnectivityFailure {
            // No network. The tokens are probably still valid; keep them so
            // the user stays signed in and retry when connectivity returns.
            AppLog.auth.debug("token refresh deferred: offline")
            return nil
        } catch {
            // The server rejected the refresh token. It is dead, and keeping
            // it would mean retrying a call that can never succeed.
            AppLog.auth.error("refresh token rejected; clearing session")
            await tokenStore.clear()
            return nil
        }
    }

    /// Maps transport failures onto the domain's auth vocabulary.
    private static func authError(from error: Error) -> AuthError {
        guard let apiError = error as? APIError else { return AuthError.wrapping(error) }

        switch apiError.serverCode {
        case "invalid_credentials":
            return .invalidCredentials
        case "email_already_registered":
            return .emailAlreadyRegistered
        case "not_found":
            return .accountNotFound
        default:
            break
        }

        if case .unauthenticated = apiError { return .sessionExpired }
        if apiError.isConnectivityFailure {
            return .storageFailure(apiError.localizedDescription)
        }
        return .storageFailure(apiError.localizedDescription)
    }
}
