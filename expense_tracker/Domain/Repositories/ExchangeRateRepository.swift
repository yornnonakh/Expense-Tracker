//
//  ExchangeRateRepository.swift
//  Domain Layer — Repositories
//

import Foundation

nonisolated protocol ExchangeRateRepository: Sendable {

    /// The rate to display with, available immediately.
    ///
    /// Never throws and never blocks on the network: returns the cached rate,
    /// or the fallback when there has never been one. An offline-first app
    /// must be able to render an amount before any request completes.
    func currentRate() async -> ExchangeRate

    /// Fetches a fresh rate if the cached one is stale, and returns whatever
    /// is authoritative afterwards. A failed refresh keeps the old rate rather
    /// than surfacing an error: a slightly old conversion is worth more to the
    /// user than an error banner about a secondary figure.
    @discardableResult
    func refreshIfNeeded() async -> ExchangeRate
}
