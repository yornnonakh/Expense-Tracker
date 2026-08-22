//
//  BudgetRepository.swift
//  Domain Layer — Repository Protocols
//

import Foundation

protocol BudgetRepository: Sendable {

    func fetchAll() async throws -> [Budget]

    func fetch(category: ExpenseCategory) async throws -> Budget?

    /// Inserts a new budget, or replaces the existing one for the same
    /// category. Upsert rather than add/update because the domain rule is
    /// "one budget per category" — the caller shouldn't have to check first
    /// and race with itself between the check and the write.
    func upsert(_ budget: Budget) async throws

    func delete(id: UUID) async throws

    func deleteAll() async throws
}
