//
//  DeleteExpenseUseCase.swift
//  Domain Layer — Use Cases
//

import Foundation

struct DeleteExpenseUseCase: Sendable {

    private let repository: ExpenseRepository

    init(repository: ExpenseRepository) {
        self.repository = repository
    }

    func execute(id: UUID) async throws {
        try await repository.delete(id: id)
    }

    func execute(expense: Expense) async throws {
        try await repository.delete(id: expense.id)
    }

    /// Batch delete for `onDelete` in a SwiftUI List, which hands back the
    /// offsets of the rows the user swiped away.
    func execute(ids: [UUID]) async throws {
        for id in ids {
            try await repository.delete(id: id)
        }
    }
}
