//
//  ExpenseRepositoryImpl.swift
//  Data Layer — Repository Implementations
//
//  Coordinates the local store and the (simulated) remote, and translates
//  everything the data layer can throw into `ExpenseError`.
//
//  STRATEGY: offline-first. The local store is the source of truth — every
//  read and write completes against it, and the remote is synced on a
//  detached best-effort basis afterwards. That is why adding an expense feels
//  instant and still works in airplane mode.
//

import Foundation

final class ExpenseRepositoryImpl: ExpenseRepository {

    private let local: LocalExpenseDataSource
    private let remote: RemoteExpenseDataSourceProtocol?

    /// Posted after any successful write so open screens can refresh.
    /// See `AppNotification` for why this is a notification and not a callback.
    private let notificationCenter: NotificationCenter

    init(
        local: LocalExpenseDataSource,
        remote: RemoteExpenseDataSourceProtocol? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.local = local
        self.remote = remote
        self.notificationCenter = notificationCenter
    }

    // MARK: - Reads

    func fetchAll() async throws -> [Expense] {
        do {
            let dtos = try await local.fetchAll()
            return ExpenseMapper.toDomain(dtos).sortedByDateDescending()
        } catch {
            throw ExpenseError.wrapping(error)
        }
    }

    func fetch(id: UUID) async throws -> Expense? {
        do {
            guard let dto = try await local.fetch(id: id.uuidString) else { return nil }
            return try ExpenseMapper.toDomain(dto)
        } catch {
            throw ExpenseError.wrapping(error)
        }
    }

    // MARK: - Writes

    func add(_ expense: Expense) async throws {
        do {
            try await local.insert(ExpenseMapper.toDTO(expense))
        } catch {
            throw ExpenseError.wrapping(error)
        }
        await announceChange()
    }

    func update(_ expense: Expense) async throws {
        do {
            try await local.update(ExpenseMapper.toDTO(expense))
        } catch {
            throw ExpenseError.wrapping(error)
        }
        await announceChange()
    }

    func delete(id: UUID) async throws {
        do {
            try await local.delete(id: id.uuidString)
        } catch {
            throw ExpenseError.wrapping(error)
        }
        await announceChange()
    }

    func deleteAll() async throws {
        do {
            try await local.deleteAll()
        } catch {
            throw ExpenseError.wrapping(error)
        }
        await announceChange()
    }

    // MARK: - Change fan-out & sync

    private func announceChange() async {
        notificationCenter.post(name: .expenseDataDidChange, object: nil)
        await syncToRemoteIfPossible()
    }

    /// Best effort, and deliberately non-throwing: a failed background sync
    /// must never turn a successful local save into an error the user sees.
    private func syncToRemoteIfPossible() async {
        guard let remote else { return }
        do {
            let dtos = try await local.fetchAll()
            try await remote.push(dtos)
        } catch {
            // Swallowed on purpose — the local write already succeeded and the
            // next write will retry the push.
        }
    }
}
