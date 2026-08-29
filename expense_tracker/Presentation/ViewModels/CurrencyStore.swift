//
//  CurrencyStore.swift
//  Presentation Layer — ViewModels
//
//  The live exchange rate, in a form views can read synchronously.
//
//  Formatting happens inside `body`, which cannot await. This holds the rate
//  as published state so a row renders immediately with whatever is known —
//  cached, or the fallback — and re-renders once a fresher figure lands.
//

import Combine
import Foundation

@MainActor
final class CurrencyStore: ObservableObject {

    @Published private(set) var rate: ExchangeRate = .fallback

    private let repository: ExchangeRateRepository

    nonisolated init(repository: ExchangeRateRepository) {
        self.repository = repository
    }

    /// Loads the cached rate, then refreshes if it has gone stale.
    ///
    /// Two steps rather than one so the UI never waits on the network for a
    /// figure it already has a usable answer for.
    func load() async {
        rate = await repository.currentRate()
        rate = await repository.refreshIfNeeded()
    }

    /// "$3.00 · ៛12,100".
    func dual(_ usd: Double) -> String {
        AppFormatters.dual(usd: usd, rate: rate)
    }

    /// "៛12,100" — the converted figure alone, for use beside an amount that
    /// is already shown in dollars.
    func riel(_ usd: Double) -> String {
        AppFormatters.riel(rate.khr(fromUSD: usd))
    }
}
