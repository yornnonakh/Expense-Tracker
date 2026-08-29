//
//  ExchangeRateTests.swift
//  expense_trackerTests
//
//  Conversion and the rate's caching behaviour.
//
//  The behaviour that matters is not "it multiplies": it is that a rate the
//  app cannot fetch never blocks or corrupts a displayed amount, because
//  expenses are stored in dollars and riel is derived.
//

import SwiftUI
import XCTest
@testable import expense_tracker

final class ExchangeRateTests: XCTestCase {

    // MARK: - Conversion

    func testConvertsDollarsToRiel() {
        let rate = ExchangeRate(khrPerUSD: 4000, fetchedAt: Date())
        XCTAssertEqual(rate.khr(fromUSD: 3), 12_000)
    }

    func testRoundsToTheNearestHundredRiel() {
        let rate = ExchangeRate(khrPerUSD: 4043.815712, fetchedAt: Date())
        // 3 × 4043.8… = 12,131.4, which is not a sum anyone can hand over:
        // the smallest note is 100 riel.
        XCTAssertEqual(rate.khr(fromUSD: 3), 12_100)
    }

    func testConvertsZeroToZero() {
        let rate = ExchangeRate(khrPerUSD: 4043.8, fetchedAt: Date())
        XCTAssertEqual(rate.khr(fromUSD: 0), 0)
    }

    // MARK: - Staleness

    func testFallbackRateIsUsableButMarked() {
        XCTAssertEqual(ExchangeRate.fallback.khrPerUSD, 4000)
        XCTAssertTrue(ExchangeRate.fallback.isFallback)
        XCTAssertTrue(ExchangeRate.fallback.isStale, "Never fetched, so always worth replacing")
    }

    func testAFreshRateIsNotStale() {
        let rate = ExchangeRate(khrPerUSD: 4043.8, fetchedAt: Date())
        XCTAssertFalse(rate.isStale)
        XCTAssertFalse(rate.isFallback)
    }

    func testARateOlderThanADayIsStale() {
        let yesterday = Date().addingTimeInterval(-25 * 60 * 60)
        XCTAssertTrue(ExchangeRate(khrPerUSD: 4043.8, fetchedAt: yesterday).isStale)
    }

    // MARK: - Formatting

    func testRielIsWrittenWithoutDecimals() {
        XCTAssertEqual(AppFormatters.riel(12_100), "\u{17DB}12,100")
    }

    func testDualPutsDollarsFirst() {
        let rate = ExchangeRate(khrPerUSD: 4000, fetchedAt: Date())
        let formatted = AppFormatters.dual(usd: 3, rate: rate)
        XCTAssertTrue(formatted.contains("12,000"))
        XCTAssertTrue(
            formatted.firstIndex(of: "3")! < formatted.firstIndex(of: "\u{17DB}")!,
            "USD is the stored figure and leads; riel is derived and follows"
        )
    }
}

// MARK: - Repository

final class ExchangeRateRepositoryTests: XCTestCase {

    private struct FailingRemote: RemoteExchangeRateDataSourceProtocol {
        func fetchKHRPerUSD() async throws -> Double { throw ExchangeRateError.badResponse }
    }

    private struct FixedRemote: RemoteExchangeRateDataSourceProtocol {
        let value: Double
        func fetchKHRPerUSD() async throws -> Double { value }
    }

    func testReturnsFallbackWhenNothingIsCached() async {
        let repository = ExchangeRateRepositoryImpl(
            remote: FixedRemote(value: 4100), store: InMemoryKeyValueStore()
        )
        let rate = await repository.currentRate()
        XCTAssertTrue(rate.isFallback, "A cold launch must still be able to show riel")
    }

    func testAFailedRefreshKeepsShowingSomething() async {
        let repository = ExchangeRateRepositoryImpl(
            remote: FailingRemote(), store: InMemoryKeyValueStore()
        )
        let rate = await repository.refreshIfNeeded()
        XCTAssertEqual(rate.khrPerUSD, ExchangeRate.fallback.khrPerUSD,
                       "A dead rates provider must not blank out every amount")
    }

    func testAFetchedRateIsCachedForTheNextLaunch() async {
        let store = InMemoryKeyValueStore()

        let first = ExchangeRateRepositoryImpl(remote: FixedRemote(value: 4100), store: store)
        let fetched = await first.refreshIfNeeded()
        XCTAssertEqual(fetched.khrPerUSD, 4100)

        // A second repository over the same storage stands in for a relaunch.
        let second = ExchangeRateRepositoryImpl(remote: FailingRemote(), store: store)
        let restored = await second.currentRate()
        XCTAssertEqual(restored.khrPerUSD, 4100, "The cached rate must survive a cold start")
        XCTAssertFalse(restored.isFallback)
    }
}

// MARK: - Locale independence

final class CurrencySymbolTests: XCTestCase {

    /// Amounts are stored in dollars, so the symbol must not follow the phone.
    /// A device set to Cambodia previously rendered a stored $3.00 as ៛3.00 —
    /// the right number against the wrong currency, off by ~4,000×.
    func testDollarsRenderAsDollarsRegardlessOfDeviceRegion() {
        let formatted = AppFormatters.currency(3)
        XCTAssertTrue(formatted.contains("$"), "Got \(formatted)")
        XCTAssertFalse(formatted.contains("\u{17DB}"), "Got \(formatted)")
    }

    /// The add/edit/budget forms all share this field. Its symbol says what
    /// the typed number means, so a device in Cambodia must not label a
    /// dollars field with ៛ and invite 12000 for a $3 coffee.
    func testAmountInputFieldIsLabelledInDollars() {
        XCTAssertEqual(AmountInputField(title: "Amount", amountText: .constant("")).currencySymbol, "$")
    }

    /// Abbreviated chart labels read their symbol from the pinned formatter
    /// rather than the locale, so they must agree with the full format.
    func testAbbreviatedAmountsUseTheSameSymbol() {
        XCTAssertTrue(AppFormatters.abbreviatedCurrency(1500).hasPrefix("$"))
    }
}
