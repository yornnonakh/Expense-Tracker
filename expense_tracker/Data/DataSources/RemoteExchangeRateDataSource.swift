//
//  RemoteExchangeRateDataSource.swift
//  Data Layer — Data Sources
//
//  Fetches USD→KHR from a public rates feed.
//
//  Deliberately NOT routed through `APIClient`: this is a third-party host,
//  not our API. Sending it our `Authorization` header would leak a session
//  token to someone else's server, and a 401 from it must never trigger our
//  token-refresh path.
//
//  The provider is free and unauthenticated, which is why it is reachable
//  from a shipped app without shipping a key. It also means it can disappear,
//  so every failure here is non-fatal — the repository keeps the cached rate.
//

import Foundation

nonisolated protocol RemoteExchangeRateDataSourceProtocol: Sendable {
    func fetchKHRPerUSD() async throws -> Double
}

nonisolated struct RemoteExchangeRateDataSource: RemoteExchangeRateDataSourceProtocol {

    /// HTTPS is not optional: App Transport Security blocks cleartext in a
    /// Release build, and this host is outside the local-networking exemption
    /// that Debug builds grant.
    static let endpoint = URL(string: "https://open.er-api.com/v6/latest/USD")!

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            // A secondary display figure must never hold up the UI.
            configuration.timeoutIntervalForRequest = 10
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    private struct Response: Decodable {
        let result: String
        let rates: [String: Double]
    }

    func fetchKHRPerUSD() async throws -> Double {
        let (data, response) = try await session.data(from: Self.endpoint)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ExchangeRateError.badResponse
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)

        guard decoded.result == "success", let khr = decoded.rates["KHR"] else {
            throw ExchangeRateError.missingRate
        }

        // A zero or negative rate would make every converted amount nonsense,
        // and a wildly wrong one is likelier to be a provider bug than a
        // currency collapse. Reject rather than cache it.
        guard khr > 1000, khr < 10_000 else {
            throw ExchangeRateError.implausibleRate(khr)
        }

        return khr
    }
}

nonisolated enum ExchangeRateError: Error, Equatable {
    case badResponse
    case missingRate
    case implausibleRate(Double)
}
