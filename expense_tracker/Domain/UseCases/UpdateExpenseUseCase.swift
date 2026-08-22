//
//  UpdateExpenseUseCase.swift
//  Domain Layer — Use Cases
//

import Foundation

struct UpdateExpenseUseCase: Sendable {

    private let repository: ExpenseRepository

    init(repository: ExpenseRepository) {
        self.repository = repository
    }

    /// Applies edited form input to an existing expense.
    ///
    /// The original `id` is carried through explicitly rather than minted
    /// fresh — otherwise an edit would silently create a second record and
    /// orphan the first.
    @discardableResult
    func execute(id: UUID, draft: ExpenseDraft) async throws -> Expense {
        let updated = try ExpenseValidator.makeExpense(from: draft, id: id)
        try await repository.update(updated)
        return updated
    }
}
