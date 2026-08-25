//
//  LocalExpenseDataSource.swift
//  Data Layer — Data Sources
//
//  On-device persistence for expenses, backed by a `KeyValueStore`. This is
//  the app's source of truth: every read and write the user makes lands here
//  first, and the server catches up afterwards.
//
//  Declared as an `actor` for two reasons: JSON encoding of the whole list
//  happens off the main thread (so a large history never janks a scroll), and
//  read-modify-write sequences are serialised — two concurrent adds cannot
//  read the same array and clobber each other's write. That second property is
//  what makes the sync merge below safe to run while the user is editing.
//
//  DELETES ARE TOMBSTONES. `delete` marks a record rather than removing it, so
//  the deletion can be replicated. Rows only leave storage in `purgeAll` (sign
//  out) and `compact` (tombstones the server has already accepted).
//

import Foundation

actor LocalExpenseDataSource {

    private let store: KeyValueStore
    private let key: String

    /// Cache of the decoded list, tombstones included. Avoids re-reading and
    /// re-decoding the whole blob on every query; invalidated implicitly
    /// because every write goes through this actor and updates it.
    private var cache: [ExpenseDTO]?

    init(store: KeyValueStore, key: String = StorageKey.expenses) {
        self.store = store
        self.key = key
    }

    // MARK: - Reads

    /// Live records only. This is what the app displays.
    func fetchAll() throws -> [ExpenseDTO] {
        try all().filter { !$0.isDeleted }
    }

    /// Everything, tombstones included. Only the sync engine wants this.
    func fetchAllIncludingDeleted() throws -> [ExpenseDTO] {
        try all()
    }

    func fetch(id: String) throws -> ExpenseDTO? {
        try all().first { $0.id == id && !$0.isDeleted }
    }

    /// Records this device has changed and the server has not acknowledged.
    func pendingChanges() throws -> [ExpenseDTO] {
        try all().filter(\.isPendingSync)
    }

    // MARK: - Writes

    func insert(_ dto: ExpenseDTO) throws {
        var all = try all()

        // Only a *live* duplicate is a conflict. Re-using the id of a
        // tombstoned record is how an undo would work, and rejecting it would
        // make the id unusable forever.
        guard !all.contains(where: { $0.id == dto.id && !$0.isDeleted }) else {
            throw ExpenseError.persistenceFailed("An expense with that id already exists.")
        }

        if let index = all.firstIndex(where: { $0.id == dto.id }) {
            all[index] = dto
        } else {
            all.append(dto)
        }
        try persist(all)
    }

    func update(_ dto: ExpenseDTO) throws {
        var all = try all()
        guard let index = all.firstIndex(where: { $0.id == dto.id && !$0.isDeleted }) else {
            throw ExpenseError.expenseNotFound
        }
        all[index] = dto
        try persist(all)
    }

    /// Tombstones a record. Throws when there is no live record to delete, so
    /// deleting twice is an error rather than a silent no-op.
    func delete(id: String, at now: Date = Date()) throws {
        var all = try all()
        guard let index = all.firstIndex(where: { $0.id == id && !$0.isDeleted }) else {
            throw ExpenseError.expenseNotFound
        }
        all[index] = all[index].tombstoned(at: now)
        try persist(all)
    }

    /// Tombstones every live record, so the deletions replicate.
    func deleteAll(at now: Date = Date()) throws {
        let updated = try all().map { $0.isDeleted ? $0 : $0.tombstoned(at: now) }
        try persist(updated)
    }

    /// Hard-wipes storage, leaving nothing to replicate.
    ///
    /// Sign-out only. The next account to use this device must not inherit the
    /// previous one's expenses, and tombstoning would upload deletions for
    /// records that belong to someone else.
    func purgeAll() throws {
        try persist([])
    }

    /// Bulk replace, used when seeding sample data.
    func replaceAll(with dtos: [ExpenseDTO]) throws {
        try persist(dtos)
    }

    // MARK: - Sync

    /// Clears the pending flag on records the server accepted.
    ///
    /// Only clears when the stored `updatedAt` still matches what was pushed.
    /// If the user edited the record while the push was in flight, the stored
    /// copy is newer than what the server acknowledged and must stay pending —
    /// otherwise that edit would never be uploaded.
    func markSynced(_ acknowledged: [String: Double]) throws {
        let updated = try all().map { dto -> ExpenseDTO in
            guard let pushedUpdatedAt = acknowledged[dto.id],
                  dto.updatedAt == pushedUpdatedAt else { return dto }
            return dto.markedSynced()
        }
        try persist(updated)
    }

    /// Merges records pulled from the server.
    ///
    /// A local record that is still pending wins only when it is strictly
    /// newer; otherwise the server's copy is adopted. Adopted records are
    /// written with `isPendingSync = false` — they came *from* the server, so
    /// pushing them back would be a pointless round trip that also risks
    /// clobbering a concurrent edit from another device.
    func applyRemote(_ remote: [ExpenseDTO]) throws {
        guard !remote.isEmpty else { return }

        var all = try all()
        var indexById = Dictionary(
            uniqueKeysWithValues: all.enumerated().map { ($0.element.id, $0.offset) }
        )

        for incoming in remote {
            guard let index = indexById[incoming.id] else {
                all.append(incoming)
                indexById[incoming.id] = all.count - 1
                continue
            }

            let local = all[index]
            if local.isPendingSync && local.updatedAt > incoming.updatedAt {
                continue
            }
            all[index] = incoming
        }

        try persist(all)
    }

    /// Drops tombstones the server has acknowledged and that are older than
    /// `olderThan`.
    ///
    /// Without this, storage grows forever: every delete the user ever made
    /// stays on disk. The age window matters — a tombstone removed too early
    /// stops suppressing the record, and the next pull would resurrect it.
    func compact(olderThan cutoff: Date) throws {
        let cutoffMillis = cutoff.timeIntervalSince1970 * 1000
        let remaining = try all().filter { dto in
            guard let deletedAt = dto.deletedAt else { return true }
            if dto.isPendingSync { return true }
            return deletedAt > cutoffMillis
        }
        try persist(remaining)
    }

    // MARK: - Storage plumbing

    private func all() throws -> [ExpenseDTO] {
        if let cache { return cache }
        let loaded = try load()
        cache = loaded
        return loaded
    }

    private func load() throws -> [ExpenseDTO] {
        // No key yet means a first launch, not a failure.
        guard let data = store.data(forKey: key) else { return [] }

        do {
            return try JSONCoding.decode([ExpenseDTO].self, from: data)
        } catch {
            // The blob exists but is unreadable. Surfacing the error lets the
            // UI offer a reset instead of pretending the user has no history.
            throw ExpenseError.decodingFailed(
                "Stored expenses could not be read. \(error.localizedDescription)"
            )
        }
    }

    private func persist(_ dtos: [ExpenseDTO]) throws {
        let data = try JSONCoding.encode(dtos)
        store.set(data, forKey: key)
        cache = dtos
    }
}
