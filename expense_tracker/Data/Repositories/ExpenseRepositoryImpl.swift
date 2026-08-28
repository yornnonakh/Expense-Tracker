//
//  ExpenseRepositoryImpl.swift
//  Data Layer — Repository Implementations
//
//  Reads and writes the local store, and translates everything the data layer
//  can throw into `ExpenseError`.
//
//  STRATEGY: offline-first. The local store is the source of truth — every
//  read and write completes against it and returns immediately. This type
//  performs NO network calls at all; it announces the change and
//  `SyncCoordinator`, listening for that announcement, decides when to talk to
//  the server.
//
//  That split is deliberate. When this type pushed to the server itself, every
//  write paid for a network round trip it did not need, and a save could not
//  be reasoned about without also reasoning about connectivity. Now a save is
//  a local write; replication is somebody else's job.
//

import Foundation

final class ExpenseRepositoryImpl: ExpenseRepository {

    private let local: LocalExpenseDataSource

    /// Posted after any successful write, so open screens refresh and the sync
    /// coordinator learns there is something to upload.
    /// See `AppNotification` for why this is a notification and not a callback.
    private let notificationCenter: NotificationCenter

    init(
        local: LocalExpenseDataSource,
        notificationCenter: NotificationCenter = .default
    ) {
        self.local = local
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

    /// Writes a tombstone rather than removing the row, so the deletion can
    /// replicate to other devices.
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

    // MARK: - Change fan-out

    private func announceChange() async {
        notificationCenter.post(name: .expenseDataDidChange, object: nil)
    }

    /// Hard-wipes local expenses without leaving tombstones. Sign-out only —
    /// see `LocalExpenseDataSource.purgeAll`.
    func purgeLocal() async throws {
        do {
            try await local.purgeAll()
        } catch {
            throw ExpenseError.wrapping(error)
        }
        await announceChange()
    }
}
