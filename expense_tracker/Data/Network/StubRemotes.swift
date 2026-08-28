//
//  StubRemotes.swift
//  Data Layer — Network
//
//  In-memory stand-ins for the two remote data sources.
//
//  Compiled into DEBUG builds only, so nothing here ships. They exist for two
//  callers: SwiftUI previews, which must never open a socket, and tests, which
//  want to drive specific server responses (a conflict, a 401, an outage)
//  without running a server.
//

#if DEBUG

import Foundation

// MARK: - Auth

/// Accepts any credentials and hands back a canned session.
///
/// Configurable failure so a test can exercise the error paths: set
/// `errorToThrow` and every call rejects with it.
actor StubRemoteAuthDataSource: RemoteAuthDataSourceProtocol {

    var errorToThrow: Error?
    private(set) var signUpCallCount = 0
    private(set) var signInCallCount = 0
    private(set) var refreshCallCount = 0
    private(set) var signOutCallCount = 0

    private var avatarData: Data?
    private var user: APIUser

    init(
        user: APIUser = APIUser(
            id: "8B2D2A5E-2E4C-4E1B-9C0F-6C5B7A1D3E4F",
            name: "Preview User",
            email: "preview@example.com",
            createdAt: 1_700_000_000_000,
            hasAvatar: false
        ),
        errorToThrow: Error? = nil
    ) {
        self.user = user
        self.errorToThrow = errorToThrow
    }

    func setError(_ error: Error?) { errorToThrow = error }

    private func session() -> APISessionResponse {
        APISessionResponse(
            accessToken: "stub-access-token",
            refreshToken: "stub-refresh-token",
            expiresIn: 900,
            user: user
        )
    }

    private func throwIfConfigured() throws {
        if let errorToThrow { throw errorToThrow }
    }

    func signUp(name: String, email: String, password: String) async throws -> APISessionResponse {
        signUpCallCount += 1
        try throwIfConfigured()
        user = APIUser(
            id: user.id, name: name, email: email,
            createdAt: user.createdAt, hasAvatar: user.hasAvatar
        )
        return session()
    }

    func signIn(email: String, password: String) async throws -> APISessionResponse {
        signInCallCount += 1
        try throwIfConfigured()
        return session()
    }

    func refresh(refreshToken: String) async throws -> APISessionResponse {
        refreshCallCount += 1
        try throwIfConfigured()
        return session()
    }

    func signOut(refreshToken: String) async throws {
        signOutCallCount += 1
        try throwIfConfigured()
    }

    func requestPasswordReset(email: String) async throws {
        try throwIfConfigured()
    }

    func currentUser() async throws -> APIUser {
        try throwIfConfigured()
        return user
    }

    func uploadAvatar(_ imageData: Data) async throws -> APIUser {
        try throwIfConfigured()
        avatarData = imageData
        user = APIUser(
            id: user.id, name: user.name, email: user.email,
            createdAt: user.createdAt, hasAvatar: true
        )
        return user
    }

    func removeAvatar() async throws -> APIUser {
        try throwIfConfigured()
        avatarData = nil
        user = APIUser(
            id: user.id, name: user.name, email: user.email,
            createdAt: user.createdAt, hasAvatar: false
        )
        return user
    }

    func downloadAvatar() async throws -> Data? {
        try throwIfConfigured()
        return avatarData
    }
}

// MARK: - Sync

/// A server that keeps everything in memory and applies the same
/// last-write-wins rule the real one does.
///
/// Enough fidelity to test the client's half of the protocol — watermarks,
/// tombstones, conflict adoption — without a process to start and stop.
actor StubRemoteSyncDataSource: RemoteSyncDataSourceProtocol {

    /// When set, every call throws this instead of responding. Used to drive
    /// the offline path.
    var errorToThrow: Error?

    private var expenses: [String: APIExpense] = [:]
    private var budgets: [String: APIBudget] = [:]

    /// Server-clock stamp per record, mirroring the real server's separate
    /// sync cursor. Starts at 1 so a watermark of 0 means "send everything".
    private var expenseServerTime: [String: Double] = [:]
    private var budgetServerTime: [String: Double] = [:]
    private var clock: Double = 1

    private(set) var pushCallCount = 0
    private(set) var pullCallCount = 0

    init(errorToThrow: Error? = nil) {
        self.errorToThrow = errorToThrow
    }

    func setError(_ error: Error?) { errorToThrow = error }

    /// Seeds a record as if another device had pushed it.
    func seed(expense: APIExpense) {
        clock += 1
        expenses[expense.id] = expense
        expenseServerTime[expense.id] = clock
    }

    func seed(budget: APIBudget) {
        clock += 1
        budgets[budget.id] = budget
        budgetServerTime[budget.id] = clock
    }

    func storedExpense(id: String) -> APIExpense? { expenses[id] }
    func storedBudget(id: String) -> APIBudget? { budgets[id] }
    func storedExpenseCount() -> Int { expenses.count }

    func pull(since watermark: Double) async throws -> SyncPullResponse {
        pullCallCount += 1
        if let errorToThrow { throw errorToThrow }

        clock += 1
        return SyncPullResponse(
            serverTime: clock,
            expenses: changedExpenses(since: watermark),
            budgets: changedBudgets(since: watermark)
        )
    }

    func push(
        expenses incoming: [APIExpense],
        budgets incomingBudgets: [APIBudget],
        since watermark: Double?
    ) async throws -> SyncPushResponse {
        pushCallCount += 1
        if let errorToThrow { throw errorToThrow }

        var conflicts: [SyncConflict] = []
        var applied = 0

        for record in incoming {
            if let existing = expenses[record.id], record.updatedAt <= existing.updatedAt {
                conflicts.append(Self.conflict(id: record.id, expense: existing))
                continue
            }
            clock += 1
            expenses[record.id] = record
            expenseServerTime[record.id] = clock
            applied += 1
        }

        for record in incomingBudgets {
            if let existing = budgets[record.id], record.updatedAt <= existing.updatedAt {
                conflicts.append(Self.conflict(id: record.id, budget: existing))
                continue
            }
            clock += 1
            budgets[record.id] = record
            budgetServerTime[record.id] = clock
            applied += 1
        }

        clock += 1
        let serverTime = clock

        return SyncPushResponse(
            serverTime: serverTime,
            applied: applied,
            conflicts: conflicts,
            expenses: watermark.map { changedExpenses(since: $0) },
            budgets: watermark.map { changedBudgets(since: $0) }
        )
    }

    private func changedExpenses(since watermark: Double) -> [APIExpense] {
        expenses.values
            .filter { (expenseServerTime[$0.id] ?? 0) > watermark }
            .sorted { $0.id < $1.id }
    }

    private func changedBudgets(since watermark: Double) -> [APIBudget] {
        budgets.values
            .filter { (budgetServerTime[$0.id] ?? 0) > watermark }
            .sorted { $0.id < $1.id }
    }

    /// `SyncConflict` decodes from JSON and has no memberwise initializer, so
    /// the stub builds one the same way the network would.
    private static func conflict(id: String, expense: APIExpense? = nil, budget: APIBudget? = nil) -> SyncConflict {
        var payload: [String: Any] = ["status": "conflict", "id": id]

        if let expense, let encoded = try? APICoding.encoder.encode(expense),
           let object = try? JSONSerialization.jsonObject(with: encoded) {
            payload["server"] = object
        } else if let budget, let encoded = try? APICoding.encoder.encode(budget),
                  let object = try? JSONSerialization.jsonObject(with: encoded) {
            payload["server"] = object
        }

        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        // Force-try is safe: the payload was just built from encodable values
        // in exactly the shape `SyncConflict` decodes.
        return try! APICoding.decoder.decode(SyncConflict.self, from: data)
    }
}

#endif
