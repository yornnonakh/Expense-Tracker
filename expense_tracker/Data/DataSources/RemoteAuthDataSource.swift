//
//  RemoteAuthDataSource.swift
//  Data Layer — Data Sources
//
//  Authentication against the server.
//
//  Credentials are sent once, in exchange for tokens; the password is never
//  written to this device. That is the substantive difference from the local
//  account store this replaces, which had to keep a password digest on disk in
//  order to verify sign-ins itself.
//

import Foundation

nonisolated protocol RemoteAuthDataSourceProtocol: Sendable {
    func signUp(name: String, email: String, password: String) async throws -> APISessionResponse
    func signIn(email: String, password: String) async throws -> APISessionResponse
    func refresh(refreshToken: String) async throws -> APISessionResponse
    func signOut(refreshToken: String) async throws
    func requestPasswordReset(email: String) async throws
    func currentUser() async throws -> APIUser
    func uploadAvatar(_ imageData: Data) async throws -> APIUser
    func removeAvatar() async throws -> APIUser
    func downloadAvatar() async throws -> Data?
}

nonisolated struct RemoteAuthDataSource: RemoteAuthDataSourceProtocol {

    private let client: APIClientProtocol

    init(client: APIClientProtocol) {
        self.client = client
    }

    func signUp(name: String, email: String, password: String) async throws -> APISessionResponse {
        let request = try APIRequest.json(
            .post,
            path: APIRoute.signUp,
            body: SignUpRequest(name: name, email: email, password: password),
            requiresAuthentication: false
        )
        return try await client.send(request, as: APISessionResponse.self)
    }

    func signIn(email: String, password: String) async throws -> APISessionResponse {
        let request = try APIRequest.json(
            .post,
            path: APIRoute.signIn,
            body: SignInRequest(email: email, password: password),
            requiresAuthentication: false
        )
        return try await client.send(request, as: APISessionResponse.self)
    }

    func refresh(refreshToken: String) async throws -> APISessionResponse {
        // Explicitly unauthenticated: the whole point of this call is that the
        // access token is no longer usable, and attaching it would invite an
        // endless refresh loop.
        let request = try APIRequest.json(
            .post,
            path: APIRoute.refresh,
            body: RefreshRequest(refreshToken: refreshToken),
            requiresAuthentication: false
        )
        return try await client.send(request, as: APISessionResponse.self)
    }

    func signOut(refreshToken: String) async throws {
        let request = try APIRequest.json(
            .post,
            path: APIRoute.signOut,
            body: RefreshRequest(refreshToken: refreshToken),
            requiresAuthentication: false
        )
        try await client.send(request)
    }

    func requestPasswordReset(email: String) async throws {
        let request = try APIRequest.json(
            .post,
            path: APIRoute.passwordReset,
            body: PasswordResetRequest(email: email),
            requiresAuthentication: false
        )
        try await client.send(request)
    }

    func currentUser() async throws -> APIUser {
        try await client.send(
            APIRequest(method: .get, path: APIRoute.me),
            as: APIUserResponse.self
        ).user
    }

    func uploadAvatar(_ imageData: Data) async throws -> APIUser {
        let request = try APIRequest.json(
            .put,
            path: APIRoute.avatar,
            body: AvatarUploadRequest(
                imageBase64: imageData.base64EncodedString(),
                mimeType: "image/jpeg"
            )
        )
        return try await client.send(request, as: APIUserResponse.self).user
    }

    func removeAvatar() async throws -> APIUser {
        let request = APIRequest(method: .delete, path: APIRoute.avatar)
        return try await client.send(request, as: APIUserResponse.self).user
    }

    /// Returns nil when the account has no photo, rather than throwing: having
    /// no avatar is the normal case and the caller falls back to initials.
    func downloadAvatar() async throws -> Data? {
        do {
            return try await client.sendForData(
                APIRequest(method: .get, path: APIRoute.avatar)
            )
        } catch let error as APIError {
            if case .server(let status, _, _) = error, status == 404 { return nil }
            throw error
        }
    }
}
