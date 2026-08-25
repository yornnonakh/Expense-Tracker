//
//  TestFactories.swift
//  expense_trackerTests — Support
//
//  Builders for the types the tests need.
//
//  Every factory takes defaults for everything, so a test names only the one
//  field it is actually about. A test that reads `makeExpense(amount: 50)`
//  says "this test is about the amount"; one that spells out six arguments
//  buries that.
//

import Foundation
@testable import expense_tracker

// MARK: - Domain

func makeExpense(
    id: UUID = UUID(),
    amount: Double = 25,
    description: String = "Test expense",
    category: ExpenseCategory = .food,
    date: Date = Date()
) -> Expense {
    Expense(id: id, amount: amount, description: description, category: category, date: date)
}

func makeBudget(
    id: UUID = UUID(),
    category: ExpenseCategory = .food,
    limit: Double = 300,
    createdAt: Date = Date()
) -> Budget {
    Budget(id: id, category: category, limit: limit, createdAt: createdAt)
}

func makeUser(
    id: UUID = UUID(),
    name: String = "Yorn Nona",
    email: String = "test@example.com",
    createdAt: Date = Date(),
    avatarImageData: Data? = nil
) -> User {
    User(
        id: id, name: name, email: email,
        createdAt: createdAt, avatarImageData: avatarImageData
    )
}

// MARK: - DTOs

/// Epoch millis, the unit every `updatedAt` uses.
func millis(_ value: Double) -> Double { value }

func makeExpenseDTO(
    id: String = UUID().uuidString,
    amount: Double = 25,
    description: String = "Test expense",
    category: String = "food",
    date: Double = 1_700_000_000,
    updatedAt: Double = 1_000,
    deletedAt: Double? = nil,
    isPendingSync: Bool = true
) -> ExpenseDTO {
    ExpenseDTO(
        id: id,
        amount: amount,
        description: description,
        category: category,
        date: date,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        isPendingSync: isPendingSync
    )
}

func makeBudgetDTO(
    id: String = UUID().uuidString,
    category: String = "food",
    limit: Double = 300,
    createdAt: Double = 1_700_000_000,
    updatedAt: Double = 1_000,
    deletedAt: Double? = nil,
    isPendingSync: Bool = true
) -> BudgetDTO {
    BudgetDTO(
        id: id,
        category: category,
        limit: limit,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        isPendingSync: isPendingSync
    )
}

// MARK: - Wire DTOs

func makeAPIExpense(
    id: String = UUID().uuidString,
    amount: Double = 25,
    description: String = "Test expense",
    category: String = "food",
    date: Double = 1_700_000_000,
    updatedAt: Double = 1_000,
    deletedAt: Double? = nil
) -> APIExpense {
    APIExpense(
        id: id, amount: amount, description: description,
        category: category, date: date, updatedAt: updatedAt, deletedAt: deletedAt
    )
}

func makeAPIBudget(
    id: String = UUID().uuidString,
    category: String = "food",
    limit: Double = 300,
    createdAt: Double = 1_700_000_000,
    updatedAt: Double = 1_000,
    deletedAt: Double? = nil
) -> APIBudget {
    APIBudget(
        id: id, category: category, limit: limit,
        createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt
    )
}

func makeAPIUser(
    id: String = "8B2D2A5E-2E4C-4E1B-9C0F-6C5B7A1D3E4F",
    name: String = "Yorn Nona",
    email: String = "test@example.com",
    createdAt: Double = 1_700_000_000_000,
    hasAvatar: Bool = false
) -> APIUser {
    APIUser(id: id, name: name, email: email, createdAt: createdAt, hasAvatar: hasAvatar)
}

// MARK: - Wiring

/// A local expense store backed by memory, with no shared state between tests.
func makeLocalExpenseDataSource(
    seed: [ExpenseDTO] = []
) throws -> (LocalExpenseDataSource, InMemoryKeyValueStore) {
    let store = InMemoryKeyValueStore()
    if !seed.isEmpty {
        store.set(try JSONCoding.encode(seed), forKey: StorageKey.expenses)
    }
    return (LocalExpenseDataSource(store: store), store)
}

func makeLocalBudgetDataSource(
    seed: [BudgetDTO] = []
) throws -> (LocalBudgetDataSource, InMemoryKeyValueStore) {
    let store = InMemoryKeyValueStore()
    if !seed.isEmpty {
        store.set(try JSONCoding.encode(seed), forKey: StorageKey.budgets)
    }
    return (LocalBudgetDataSource(store: store), store)
}
