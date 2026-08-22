//
//  GetExpensesUseCase.swift
//  Domain Layer — Use Cases
//

import Foundation

struct GetExpensesUseCase: Sendable {

    private let repository: ExpenseRepository

    init(repository: ExpenseRepository) {
        self.repository = repository
    }

    /// All expenses, newest first.
    func execute() async throws -> [Expense] {
        try await repository.fetchAll().sortedByDateDescending()
    }

    /// Expenses inside a named window, newest first.
    func execute(range: DateRangeFilter, referenceDate: Date = Date()) async throws -> [Expense] {
        let all = try await execute()
        guard let interval = range.interval(referenceDate: referenceDate) else {
            return all  // .allTime — no bounds to apply
        }
        return all.filter { $0.falls(in: interval) }
    }

    /// A single expense, for the detail screen.
    func execute(id: UUID) async throws -> Expense {
        guard let expense = try await repository.fetch(id: id) else {
            throw ExpenseError.expenseNotFound
        }
        return expense
    }

    /// The most recent `limit` expenses — the dashboard's "recent" preview.
    func executeRecent(limit: Int) async throws -> [Expense] {
        Array(try await execute().prefix(limit))
    }
}
