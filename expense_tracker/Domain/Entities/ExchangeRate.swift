//
//  ExchangeRate.swift
//  Domain Layer — Entities
//
//  How many riel a dollar is worth, and when we last checked.
//
//  Expenses are stored in USD alone; the riel figure beside every amount is
//  derived at display time. Nothing persisted depends on this rate, so a rate
//  that changes — or that we never manage to fetch — can never corrupt a
//  recorded amount. That is the whole reason the base currency is stored
//  rather than the pair.
//

import Foundation

nonisolated struct ExchangeRate: Sendable, Codable, Equatable {

    /// Riel per one US dollar.
    let khrPerUSD: Double

    /// When this figure was retrieved, used to decide staleness.
    let fetchedAt: Date

    /// Used until a real rate arrives, and if the network never cooperates.
    ///
    /// 4,000 is the everyday street rate: the riel is managed against the
    /// dollar, prices are quoted at this figure, and change is given at it.
    /// Being a few tens of riel from the interbank rate matters far less than
    /// showing nothing at all.
    static let fallback = ExchangeRate(khrPerUSD: 4000, fetchedAt: .distantPast)

    /// The published rate moves once a day, so anything older than that is
    /// worth replacing — but staleness is not failure. A stale rate still
    /// converts; it just triggers a refresh attempt.
    var isStale: Bool {
        Date().timeIntervalSince(fetchedAt) > 24 * 60 * 60
    }

    /// True when this is the compiled-in guess rather than a fetched figure.
    var isFallback: Bool { fetchedAt == .distantPast }

    /// Converts a dollar amount to riel.
    ///
    /// Rounded to the nearest 100: the smallest note in circulation is 100
    /// riel, so a figure like ៛12,131 is not a quantity anyone can hand over.
    /// Showing ៛12,100 matches what the amount actually looks like in a wallet.
    func khr(fromUSD usd: Double) -> Double {
        (usd * khrPerUSD / 100).rounded() * 100
    }
}
