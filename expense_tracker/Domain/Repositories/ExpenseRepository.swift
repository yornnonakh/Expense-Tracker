//
//  ExpenseRepository.swift
//  Domain Layer — Repository Protocols
//
//  The domain declares WHAT it needs from storage; the data layer decides HOW.
//  This inversion is what keeps the dependency arrow pointing inward: use cases
//  depend on this protocol, and `ExpenseRepositoryImpl` depends on it too — but
//  nothing in the domain depends on the implementation.
//
//  Practical payoff: tests inject an in-memory fake and never touch
//  UserDefaults, and swapping UserDefaults for SwiftData later touches exactly
//  one file.
//

import Foundation

protocol ExpenseRepository: Sendable {

    /// Every stored expense, newest first.
    func fetchAll() async throws -> [Expense]

    /// One expense by identity, or nil when it has been deleted.
    func fetch(id: UUID) async throws -> Expense?

    /// Inserts a new expense. Throws if the id already exists.
    func add(_ expense: Expense) async throws

    /// Overwrites an existing expense, matched on `id`.
    /// Throws `ExpenseError.expenseNotFound` when there is nothing to replace.
    func update(_ expense: Expense) async throws

    func delete(id: UUID) async throws

    /// Wipes local expense storage. Used when signing out.
    func deleteAll() async throws
}
