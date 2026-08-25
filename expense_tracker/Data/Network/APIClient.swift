//
//  APIClient.swift
//  Data Layer — Network
//
//  The only type in the app that performs HTTP.
//
//  Responsibilities, and deliberately nothing else: build a URLRequest from an
//  `APIRequest`, attach the bearer token, decode the response or translate the
//  failure, and transparently refresh an expired access token once.
//
//  WHY AN ACTOR: the token refresh has to be single-flight. Five requests that
//  all 401 at the same moment must produce one refresh, not five — five would
//  race, and because refresh tokens rotate, four of them would be rejected and
//  sign the user out. The actor gives that shared `refreshTask` somewhere safe
//  to live. Individual requests still run concurrently: `await` on the network
//  call releases the actor.
//

import Foundation
import OSLog

// MARK: - Coding

/// Separate from `JSONCoding` on purpose.
///
/// `JSONCoding` encodes dates as ISO-8601 for on-disk storage and throws
/// `ExpenseError`. The wire format uses numeric timestamps and should fail as
/// `APIError`; sharing one configuration would force the storage format and
/// the network format to change together.
nonisolated enum APICoding {

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw APIError.decoding("Could not encode request: \(error)")
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decoding("Could not decode \(T.self): \(error)")
        }
    }
}

// MARK: - Protocol

nonisolated protocol APIClientProtocol: Sendable {
    func send<Response: Decodable & Sendable>(
        _ request: APIRequest,
        as type: Response.Type
    ) async throws -> Response

    /// For endpoints that return 204 or a body we do not read.
    func send(_ request: APIRequest) async throws

    /// For endpoints that return bytes rather than JSON, e.g. an avatar.
    func sendForData(_ request: APIRequest) async throws -> Data
}

// MARK: - Implementation

actor APIClient: APIClientProtocol {

    private let baseURL: URL
    private let session: URLSession
    private let tokenStore: TokenStoring

    /// Supplied by the composition root after construction.
    ///
    /// Injected rather than called directly because refreshing is itself an
    /// API call: having the client own that logic would make it depend on the
    /// auth data source, which depends on the client.
    private var refreshHandler: (@Sendable () async -> Bool)?

    /// The in-flight refresh, if any. Every 401 waits on this same task.
    private var refreshTask: Task<Bool, Never>?

    init(
        baseURL: URL = AppEnvironment.apiBaseURL,
        tokenStore: TokenStoring,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = AppEnvironment.requestTimeout
            configuration.timeoutIntervalForResource = AppEnvironment.resourceTimeout
            // The app is offline-first: it would rather fail fast and use
            // local data than have URLSession hold a request until the network
            // returns.
            configuration.waitsForConnectivity = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    func setRefreshHandler(_ handler: @escaping @Sendable () async -> Bool) {
        self.refreshHandler = handler
    }

    // MARK: - Sending

    func send<Response: Decodable & Sendable>(
        _ request: APIRequest,
        as type: Response.Type
    ) async throws -> Response {
        let data = try await sendForData(request)

        // A 204 with a Decodable expected is a contract mismatch, except for
        // the empty-struct case which decodes fine from "{}".
        if data.isEmpty, let empty = EmptyResponse() as? Response {
            return empty
        }
        return try APICoding.decode(Response.self, from: data)
    }

    func send(_ request: APIRequest) async throws {
        _ = try await sendForData(request)
    }

    func sendForData(_ request: APIRequest) async throws -> Data {
        let (data, response) = try await perform(request, allowRefresh: true)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.underlying("Response was not HTTP.")
        }

        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(from: data, status: http.statusCode)
        }

        return data
    }

    // MARK: - Transport

    private func perform(
        _ request: APIRequest,
        allowRefresh: Bool
    ) async throws -> (Data, URLResponse) {
        let urlRequest = try await makeURLRequest(request)
        let started = Date()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError {
            // Cancellation is the caller going away (a dismissed screen), not
            // a network failure — surfacing it as "offline" would show a
            // spurious banner.
            if urlError.code == .cancelled { throw CancellationError() }

            AppLog.network.error(
                "\(request.method.rawValue, privacy: .public) \(request.path, privacy: .public) failed: \(urlError.code.rawValue, privacy: .public)"
            )
            throw APIError.from(urlError: urlError)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        AppLog.network.debug(
            "\(request.method.rawValue, privacy: .public) \(request.path, privacy: .public) -> \(status, privacy: .public) in \(elapsed, privacy: .public)ms"
        )

        // One refresh attempt, and only for an expired token. A 401 from bad
        // credentials must not trigger a refresh loop.
        if status == 401,
           allowRefresh,
           request.requiresAuthentication,
           Self.isExpiredTokenResponse(data) {
            let refreshed = await refreshOnce()
            if refreshed {
                AppLog.auth.info("access token refreshed; retrying request")
                return try await perform(request, allowRefresh: false)
            }
        }

        return (data, response)
    }

    private func makeURLRequest(_ request: APIRequest) async throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(request.path),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }

        if !request.query.isEmpty {
            components.queryItems = request.query
        }

        guard let url = components.url else { throw APIError.invalidURL }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        if request.body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if request.requiresAuthentication,
           let token = await tokenStore.accessToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return urlRequest
    }

    // MARK: - Refresh

    /// Coalesces concurrent refreshes into one.
    private func refreshOnce() async -> Bool {
        if let refreshTask {
            return await refreshTask.value
        }

        guard let refreshHandler else { return false }

        let task = Task<Bool, Never> {
            await refreshHandler()
        }
        refreshTask = task

        let result = await task.value
        refreshTask = nil
        return result
    }

    // MARK: - Error translation

    private static func isExpiredTokenResponse(_ data: Data) -> Bool {
        guard let body = try? APICoding.decoder.decode(APIErrorBody.self, from: data) else {
            return false
        }
        return body.error.code == "token_expired"
    }

    private static func error(from data: Data, status: Int) -> APIError {
        guard let body = try? APICoding.decoder.decode(APIErrorBody.self, from: data) else {
            return .unexpectedStatus(status)
        }

        if status == 401 {
            return .unauthenticated
        }
        return .server(status: status, code: body.error.code, message: body.error.message)
    }
}

/// Placeholder for endpoints that return no body.
nonisolated struct EmptyResponse: Codable, Sendable {}
