//
//  RemoteExpenseDataSource.swift
//  Data Layer — Data Sources
//
//  Stand-in for a backend.
//
//  There is no server in this build, so this simulates one: artificial
//  latency, an in-memory mirror of what was "uploaded", and a switch to force
//  failures. It exists so the repository's offline-first sync path is real
//  code that runs and can be tested, rather than a comment promising a future
//  integration. Swapping this for a URLSession client later changes this file
//  and nothing else.
//

import Foundation

protocol RemoteExpenseDataSourceProtocol: Sendable {
    func push(_ dtos: [ExpenseDTO]) async throws
    func pull() async throws -> [ExpenseDTO]
    var isReachable: Bool { get async }
}

actor RemoteExpenseDataSource: RemoteExpenseDataSourceProtocol {

    /// Simulated round-trip time.
    private let latency: Duration

    /// Flip to false in tests/previews to exercise the offline path.
    private var reachable: Bool

    /// What the "server" currently holds.
    private var storedDTOs: [ExpenseDTO] = []

    init(latency: Duration = .milliseconds(400), reachable: Bool = true) {
        self.latency = latency
        self.reachable = reachable
    }

    var isReachable: Bool { reachable }

    func setReachable(_ value: Bool) {
        reachable = value
    }

    func push(_ dtos: [ExpenseDTO]) async throws {
        try await simulateRoundTrip()
        storedDTOs = dtos
    }

    func pull() async throws -> [ExpenseDTO] {
        try await simulateRoundTrip()
        return storedDTOs
    }

    private func simulateRoundTrip() async throws {
        guard reachable else { throw ExpenseError.remoteUnavailable }
        // `Task.sleep` is cancellation-aware, so a screen dismissed mid-sync
        // tears the operation down instead of leaking it.
        try await Task.sleep(for: latency)
    }
}
