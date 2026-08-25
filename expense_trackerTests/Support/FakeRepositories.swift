//
//  FakeRepositories.swift
//  expense_trackerTests — Support
//
//  In-memory repository doubles.
//
//  These exist so use-case and view-model tests never touch storage, a
//  network, or a clock. Each is an actor holding a dictionary, which also
//  makes them safe to hand to the concurrent code under test.
//

import Foundation
@testable import expense_tracker

// MARK: - Expenses

actor FakeExpenseRepository: ExpenseRepository {

    private var storage: [UUID: Expense] = [:]

    /// When set, every call throws this. Drives the error paths.
    private var errorToThrow: ExpenseError?

    private(set) var addCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var deleteCallCount = 0

    init(seed: [Expense] = [], errorToThrow: ExpenseError? = nil) {
        for expense in seed { storage[expense.id] = expense }
        self.errorToThrow = errorToThrow
    }

    func setError(_ error: ExpenseError?) { errorToThrow = error }

    func fetchAll() async throws -> [Expense] {
        if let errorToThrow { throw errorToThrow }
        return Array(storage.values).sortedByDateDescending()
    }

    func fetch(id: UUID) async throws -> Expense? {
        if let errorToThrow { throw errorToThrow }
        return storage[id]
    }

    func add(_ expense: Expense) async throws {
        addCallCount += 1
        if let errorToThrow { throw errorToThrow }
        guard storage[expense.id] == nil else {
            throw ExpenseError.persistenceFailed("An expense with that id already exists.")
        }
        storage[expense.id] = expense
    }

    func update(_ expense: Expense) async throws {
        updateCallCount += 1
        if let errorToThrow { throw errorToThrow }
        guard storage[expense.id] != nil else { throw ExpenseError.expenseNotFound }
        storage[expense.id] = expense
    }

    func delete(id: UUID) async throws {
        deleteCallCount += 1
        if let errorToThrow { throw errorToThrow }
        guard storage.removeValue(forKey: id) != nil else {
            throw ExpenseError.expenseNotFound
        }
    }

    func deleteAll() async throws {
        if let errorToThrow { throw errorToThrow }
        storage.removeAll()
    }

    func count() -> Int { storage.count }
}

// MARK: - Budgets

actor FakeBudgetRepository: BudgetRepository {

    private var storage: [UUID: Budget] = [:]
    private var errorToThrow: ExpenseError?

    init(seed: [Budget] = [], errorToThrow: ExpenseError? = nil) {
        for budget in seed { storage[budget.id] = budget }
        self.errorToThrow = errorToThrow
    }

    func setError(_ error: ExpenseError?) { errorToThrow = error }

    func fetchAll() async throws -> [Budget] {
        if let errorToThrow { throw errorToThrow }
        return Array(storage.values)
            .sorted { $0.category.displayName < $1.category.displayName }
    }

    func fetch(category: ExpenseCategory) async throws -> Budget? {
        if let errorToThrow { throw errorToThrow }
        return storage.values.first { $0.category == category }
    }

    func upsert(_ budget: Budget) async throws {
        if let errorToThrow { throw errorToThrow }
        // Mirrors the real store: uniqueness is on category, not id.
        if let existing = storage.values.first(where: { $0.category == budget.category }) {
            storage.removeValue(forKey: existing.id)
        }
        storage[budget.id] = budget
    }

    func delete(id: UUID) async throws {
        if let errorToThrow { throw errorToThrow }
        guard storage.removeValue(forKey: id) != nil else {
            throw ExpenseError.budgetNotFound
        }
    }

    func deleteAll() async throws {
        if let errorToThrow { throw errorToThrow }
        storage.removeAll()
    }

    func count() -> Int { storage.count }
}

// MARK: - Auth

actor FakeAuthRepository: AuthRepository {

    private var session: AuthSession?
    private var errorToThrow: AuthError?

    private(set) var signInCallCount = 0
    private(set) var signOutCallCount = 0

    init(session: AuthSession? = nil, errorToThrow: AuthError? = nil) {
        self.session = session
        self.errorToThrow = errorToThrow
    }

    func setError(_ error: AuthError?) { errorToThrow = error }

    func currentSession() async throws -> AuthSession? {
        if let errorToThrow { throw errorToThrow }
        return session
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        signInCallCount += 1
        if let errorToThrow { throw errorToThrow }
        let newSession = AuthSession(
            token: "fake-token",
            user: makeUser(email: email)
        )
        session = newSession
        return newSession
    }

    func signUp(name: String, email: String, password: String) async throws -> AuthSession {
        if let errorToThrow { throw errorToThrow }
        let newSession = AuthSession(
            token: "fake-token",
            user: makeUser(name: name, email: email)
        )
        session = newSession
        return newSession
    }

    func requestPasswordReset(email: String) async throws {
        if let errorToThrow { throw errorToThrow }
    }

    func updateProfileImage(_ imageData: Data?) async throws -> User {
        if let errorToThrow { throw errorToThrow }
        guard let session else { throw AuthError.sessionExpired }
        let updated = User(
            id: session.user.id,
            name: session.user.name,
            email: session.user.email,
            createdAt: session.user.createdAt,
            avatarImageData: imageData
        )
        self.session = AuthSession(token: session.token, user: updated)
        return updated
    }

    func signOut() async throws {
        signOutCallCount += 1
        if let errorToThrow { throw errorToThrow }
        session = nil
    }
}
