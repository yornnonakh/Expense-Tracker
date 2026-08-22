//
//  GetWeeklySpendingUseCase.swift
//  Domain Layer — Use Cases
//
//  Feeds the Home tab's bar chart.
//

import Foundation

struct GetWeeklySpendingUseCase: Sendable {

    private let repository: ExpenseRepository

    init(repository: ExpenseRepository) {
        self.repository = repository
    }

    /// Daily totals for the last `days` days, oldest bar on the left.
    ///
    /// Days with no spending are included with an amount of 0 — a chart that
    /// skipped empty days would silently compress the time axis and mislead.
    func execute(
        days: Int = 7,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> [DailySpending] {
        let expenses = try await repository.fetchAll()
        return Self.aggregate(
            expenses,
            days: days,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    /// Pure aggregation, testable without storage.
    static func aggregate(
        _ expenses: [Expense],
        days: Int = 7,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailySpending] {
        guard days > 0 else { return [] }

        let today = calendar.startOfDay(for: referenceDate)

        // Bucket once up front: O(n) over the expenses instead of re-scanning
        // the whole list for each of the seven days.
        var totals: [Date: Double] = [:]
        for expense in expenses {
            let day = calendar.startOfDay(for: expense.date)
            totals[day, default: 0] += expense.amount
        }

        // Build oldest -> newest so the chart reads left to right.
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            return DailySpending(date: day, amount: totals[day] ?? 0)
        }
    }
}
