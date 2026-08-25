//
//  APIRequest.swift
//  Data Layer — Network
//
//  A request described as data rather than as a built `URLRequest`.
//
//  Keeping it declarative means the client is the only code that knows about
//  headers, encoding and the base URL, and a test can assert on a request's
//  shape without intercepting URLSession.
//

import Foundation

nonisolated enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

nonisolated struct APIRequest: Sendable {

    let method: HTTPMethod
    /// Appended to the base URL, e.g. "/api/v1/sync".
    let path: String
    let query: [URLQueryItem]
    /// Already-encoded JSON body, or nil.
    let body: Data?
    /// When false, the client sends no Authorization header — used by sign-in
    /// and sign-up, which are how you get a token in the first place.
    let requiresAuthentication: Bool

    init(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        requiresAuthentication: Bool = true
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.requiresAuthentication = requiresAuthentication
    }

    /// Builds a request with a JSON-encoded body.
    static func json<Body: Encodable>(
        _ method: HTTPMethod,
        path: String,
        body: Body,
        query: [URLQueryItem] = [],
        requiresAuthentication: Bool = true
    ) throws -> APIRequest {
        APIRequest(
            method: method,
            path: path,
            query: query,
            body: try APICoding.encode(body),
            requiresAuthentication: requiresAuthentication
        )
    }
}

// MARK: - Routes

/// Every path the app calls, in one place, so a server-side rename is a
/// single-file change rather than a search across data sources.
nonisolated enum APIRoute {

    static let prefix = "/api/v1"

    // Auth
    static let signUp = "\(prefix)/auth/signup"
    static let signIn = "\(prefix)/auth/signin"
    static let refresh = "\(prefix)/auth/refresh"
    static let signOut = "\(prefix)/auth/signout"
    static let passwordReset = "\(prefix)/auth/password-reset"
    static let me = "\(prefix)/auth/me"
    static let avatar = "\(prefix)/auth/me/avatar"

    // Sync
    static let sync = "\(prefix)/sync"

    // Health
    static let health = "\(prefix)/health"
}
