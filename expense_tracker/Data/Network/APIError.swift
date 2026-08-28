//
//  APIError.swift
//  Data Layer — Network
//
//  Every way an HTTP call can fail, as one type.
//
//  The server sends `{ "error": { "code": ..., "message": ... } }` on every
//  rejection. `code` is stable and switchable; `message` is human copy the
//  server may reword. This type keeps both: code drives behaviour, message
//  drives what the user reads.
//

import Foundation

nonisolated struct APIErrorBody: Decodable, Equatable {
    struct Payload: Decodable, Equatable {
        let code: String
        let message: String
    }
    let error: Payload
}

nonisolated enum APIError: LocalizedError, Equatable {

    /// No usable connection. Distinct from every other case because it is the
    /// one the app treats as normal — offline is a supported state, not a bug.
    case offline

    /// The request went out but nothing came back in time.
    case timedOut

    /// Server replied with a non-2xx and a parseable error body.
    case server(status: Int, code: String, message: String)

    /// Server replied with a non-2xx we could not parse.
    case unexpectedStatus(Int)

    /// 2xx, but the body was not the shape we expected. A contract mismatch.
    case decoding(String)

    /// Could not build a valid URL from the configured base and path.
    case invalidURL

    /// Access token missing or rejected, and refreshing did not help.
    case unauthenticated

    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .offline:
            return "You're offline. Changes are saved on this device."
        case .timedOut:
            return "The server took too long to respond."
        case .server(_, _, let message):
            return message
        case .unexpectedStatus(let status):
            return "The server returned an unexpected response (\(status))."
        case .decoding:
            return "The server sent something this app didn't understand."
        case .invalidURL:
            return "The app is misconfigured and can't reach the server."
        case .unauthenticated:
            return "Your session expired. Please sign in again."
        case .underlying(let message):
            return message
        }
    }

    /// Whether retrying the identical request could plausibly succeed.
    /// Drives both the UI's Retry button and the sync engine's backoff.
    var isRetryable: Bool {
        switch self {
        case .offline, .timedOut:
            return true
        case .server(let status, _, _):
            // 5xx is the server's problem and may pass; 429 explicitly says
            // "later". 4xx otherwise means the request itself is wrong.
            return status >= 500 || status == 429
        case .unexpectedStatus(let status):
            return status >= 500
        case .decoding, .invalidURL, .unauthenticated, .underlying:
            return false
        }
    }

    /// True when the failure means "no server right now", which the app
    /// answers by staying on local data rather than showing an error.
    var isConnectivityFailure: Bool {
        switch self {
        case .offline, .timedOut:
            return true
        case .server(let status, _, _):
            return status >= 500
        default:
            return false
        }
    }

    /// The server's machine-readable code, when there was one.
    var serverCode: String? {
        if case .server(_, let code, _) = self { return code }
        return nil
    }

    /// Maps a `URLError` onto the cases the app reasons about.
    static func from(urlError: URLError) -> APIError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost,
             .cannotConnectToHost, .cannotFindHost, .dataNotAllowed,
             .internationalRoamingOff, .secureConnectionFailed:
            return .offline
        case .timedOut:
            return .timedOut
        case .badURL, .unsupportedURL:
            return .invalidURL
        default:
            return .underlying(urlError.localizedDescription)
        }
    }
}
