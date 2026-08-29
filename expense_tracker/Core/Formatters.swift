//
//  Formatters.swift
//  Core
//
//  Shared, cached formatters.
//
//  `NumberFormatter` and `DateFormatter` are genuinely expensive to build —
//  allocating one inside a SwiftUI `body` rebuilds it on every frame of a
//  scroll. These are created once and reused.
//

import Foundation

enum AppFormatters {

    // MARK: - Currency

    /// Pinned to USD rather than the device locale.
    ///
    /// Amounts are stored in dollars, so the symbol is a fact about the data,
    /// not a display preference. Left locale-derived, a phone set to Cambodia
    /// would render a stored dollar amount with a riel symbol — labelling
    /// $3.00 as ៛3.00, off by a factor of four thousand — and the riel figure
    /// beside it would then repeat the same symbol for a different number.
    private static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()

    /// Currency with no decimals, for large headline figures.
    private static let compactCurrency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// "$1,234.50". Falls back to a plain 2dp string if the formatter fails,
    /// so the UI never renders an empty amount.
    static func currency(_ amount: Double) -> String {
        currency.string(from: NSNumber(value: amount))
            ?? String(format: "%.2f", amount)
    }

    /// "$1,235" — used where the cents would be noise.
    static func currencyRounded(_ amount: Double) -> String {
        compactCurrency.string(from: NSNumber(value: amount))
            ?? String(format: "%.0f", amount)
    }

    // MARK: - Khmer riel

    /// Riel are written without a minor unit — there is no "cent" in
    /// circulation — so a fractional riel would be a quantity that cannot
    /// exist. Grouping is fixed rather than locale-derived so the figure reads
    /// the same on a phone set to any region.
    private static let riel: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    static let rielSymbol = "\u{17DB}"

    /// "៛12,100".
    static func riel(_ amount: Double) -> String {
        let digits = riel.string(from: NSNumber(value: amount))
            ?? String(format: "%.0f", amount)
        return rielSymbol + digits
    }

    /// "$3.00 · ៛12,100" — the stored amount first, the derived one second.
    /// The order is deliberate: USD is what was recorded, riel is a courtesy.
    static func dual(usd: Double, rate: ExchangeRate) -> String {
        "\(currency(usd)) \u{00B7} \(riel(rate.khr(fromUSD: usd)))"
    }

    /// "$1.2K" / "$3.4M" for tight spaces like chart axis labels.
    static func abbreviatedCurrency(_ amount: Double) -> String {
        let symbol = currency.currencySymbol ?? "$"
        let magnitude = abs(amount)

        switch magnitude {
        case 1_000_000...:
            return "\(symbol)\(String(format: "%.1f", amount / 1_000_000))M"
        case 1_000...:
            return "\(symbol)\(String(format: "%.1f", amount / 1_000))K"
        default:
            return "\(symbol)\(String(format: "%.0f", amount))"
        }
    }

    /// "42.5%"
    static func percentage(_ fraction: Double) -> String {
        String(format: "%.1f%%", fraction * 100)
    }

    // MARK: - Dates

    private static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let dayAndMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter
    }()

    private static let fullDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }()

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// "12 Aug 2026"
    static func mediumDate(_ date: Date) -> String {
        mediumDate.string(from: date)
    }

    /// "12 Aug"
    static func dayAndMonth(_ date: Date) -> String {
        dayAndMonth.string(from: date)
    }

    /// "Wednesday, 12 August 2026 at 14:30"
    static func fullDateTime(_ date: Date) -> String {
        fullDateTime.string(from: date)
    }

    /// "14:30"
    static func time(_ date: Date) -> String {
        time.string(from: date)
    }

    /// Section headers in the Transactions tab: "Today" / "Yesterday" and
    /// otherwise a full date. Relative labels are what people scan for.
    static func relativeDayLabel(_ date: Date, referenceDate: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        // Inside the last week, the weekday name is more useful than a date.
        if let daysAgo = calendar.dateComponents([.day], from: date, to: referenceDate).day,
           daysAgo < 7, daysAgo >= 0 {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
            return formatter.string(from: date)
        }

        return mediumDate.string(from: date)
    }

    /// Time-of-day greeting for the dashboard.
    static func greeting(for date: Date = Date()) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 0..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }
}
