//
//  AddExpenseUseCase.swift
//  Domain Layer — Use Cases
//
//  One use case = one thing the user can do. They hold no state, so they are
//  cheap to create and trivially testable: hand one a fake repository, call
//  `execute`, assert on the result.
//

import Foundation

struct AddExpenseUseCase: Sendable {

    private let repository: ExpenseRepository

    init(repository: ExpenseRepository) {
        self.repository = repository
    }

    /// Validates the draft, then persists it.
    ///
    /// Validation runs *before* the repository call so an invalid draft never
    /// reaches storage, and the caller gets the specific field error back.
    ///
    /// - Returns: the expense as it was actually stored, including its new id.
    @discardableResult
    func execute(draft: ExpenseDraft) async throws -> Expense {
        let expense = try ExpenseValidator.makeExpense(from: draft)
        try await repository.add(expense)
        return expense
    }

    /// Overload for callers that already hold a built entity (imports, seeding).
    @discardableResult
    func execute(expense: Expense) async throws -> Expense {
        guard expense.amount > 0 else { throw ExpenseError.invalidAmount }
        try await repository.add(expense)
        return expense
    }
}
