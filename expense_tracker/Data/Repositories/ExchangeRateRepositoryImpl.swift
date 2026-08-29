//
//  ExchangeRateRepositoryImpl.swift
//  Data Layer — Repositories
//
//  Caches the rate on device so the riel figure survives a cold launch with no
//  network. An actor because the cached value is read from the UI and written
//  by a background refresh.
//

import Foundation
import OSLog

actor ExchangeRateRepositoryImpl: ExchangeRateRepository {

    private let remote: RemoteExchangeRateDataSourceProtocol
    private let store: KeyValueStore
    private let key: String

    /// Held in memory once loaded so repeated formatting does not decode JSON
    /// on every row of a scrolling list.
    private var cached: ExchangeRate?

    /// Guards against a burst of concurrent refreshes — several screens can
    /// appear at once, and each would otherwise fire its own request.
    private var inFlight: Task<ExchangeRate, Never>?

    init(
        remote: RemoteExchangeRateDataSourceProtocol,
        store: KeyValueStore,
        key: String = "exchange_rate_usd_khr"
    ) {
        self.remote = remote
        self.store = store
        self.key = key
    }

    func currentRate() async -> ExchangeRate {
        if let cached { return cached }

        if let data = store.data(forKey: key),
           let decoded = try? JSONDecoder().decode(ExchangeRate.self, from: data) {
            cached = decoded
            return decoded
        }

        return .fallback
    }

    @discardableResult
    func refreshIfNeeded() async -> ExchangeRate {
        let current = await currentRate()
        guard current.isStale else { return current }

        if let inFlight { return await inFlight.value }

        let task = Task<ExchangeRate, Never> { [remote, store, key] in
            do {
                let khr = try await remote.fetchKHRPerUSD()
                let fresh = ExchangeRate(khrPerUSD: khr, fetchedAt: Date())
                if let data = try? JSONEncoder().encode(fresh) {
                    store.set(data, forKey: key)
                }
                AppLog.network.debug("exchange rate refreshed")
                return fresh
            } catch {
                // Non-fatal by design. The previous rate stays in use; the
                // alternative is an error about a figure shown beside the one
                // the user actually cares about.
                AppLog.network.debug("exchange rate refresh failed; keeping cached rate")
                return current
            }
        }

        inFlight = task
        let result = await task.value
        inFlight = nil
        cached = result
        return result
    }
}
