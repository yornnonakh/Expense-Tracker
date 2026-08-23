//
//  DateRangeFilter.swift
//  Domain Layer — Entities
//
//  Named time windows used by the Transactions and Statistics tabs.
//

import Foundation

nonisolated enum DateRangeFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case thisMonth
    case lastMonth
    case thisYear
    case allTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thisMonth: return "This Month"
        case .lastMonth: return "Last Month"
        case .thisYear:  return "This Year"
        case .allTime:   return "All Time"
        }
    }

    /// Resolves to a concrete half-open interval `[start, end)`.
    ///
    /// Returns nil for `.allTime`, which deliberately has no bounds — callers
    /// treat nil as "do not filter" rather than inventing a distant-past date.
    /// Calendar arithmetic is done through `Calendar`, never by adding seconds,
    /// so DST shifts and month lengths are handled correctly.
    func interval(referenceDate: Date = Date(), calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .allTime:
            return nil

        case .thisMonth:
            return calendar.dateInterval(of: .month, for: referenceDate)

        case .lastMonth:
            guard
                let lastMonthDate = calendar.date(
                    byAdding: .month, value: -1, to: referenceDate
                )
            else { return nil }
            return calendar.dateInterval(of: .month, for: lastMonthDate)

        case .thisYear:
            return calendar.dateInterval(of: .year, for: referenceDate)
        }
    }
}
