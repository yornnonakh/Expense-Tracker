//
//  LocalExpenseDataSource.swift
//  Data Layer — Data Sources
//
//  On-device persistence for expenses, backed by a `KeyValueStore`.
//
//  Declared as an `actor` for two reasons: JSON encoding of the whole list
//  happens off the main thread (so a large history never janks a scroll), and
//  read-modify-write sequences are serialised — two concurrent adds cannot
//  read the same array and clobber each other's write.
//

import Foundation

actor LocalExpenseDataSource {

    private let store: KeyValueStore
    private let key: String

    /// Cache of the decoded list. Avoids re-reading and re-decoding the whole
    /// blob on every query; invalidated implicitly because every write goes
    /// through this actor and updates it.
    private var cache: [ExpenseDTO]?

    init(store: KeyValueStore, key: String = StorageKey.expenses) {
        self.store = store
        self.key = key
    }

    // MARK: - Reads

    func fetchAll() throws -> [ExpenseDTO] {
        if let cache { return cache }
        let loaded = try load()
        cache = loaded
        return loaded
    }

    func fetch(id: String) throws -> ExpenseDTO? {
        try fetchAll().first { $0.id == id }
    }

    // MARK: - Writes

    func insert(_ dto: ExpenseDTO) throws {
        var all = try fetchAll()
        guard !all.contains(where: { $0.id == dto.id }) else {
            // Re-inserting an existing id would create a duplicate row that
            // the user could never delete cleanly.
            throw ExpenseError.persistenceFailed("An expense with that id already exists.")
        }
        all.append(dto)
        try persist(all)
    }

    func update(_ dto: ExpenseDTO) throws {
        var all = try fetchAll()
        guard let index = all.firstIndex(where: { $0.id == dto.id }) else {
            throw ExpenseError.expenseNotFound
        }
        all[index] = dto
        try persist(all)
    }

    func delete(id: String) throws {
        var all = try fetchAll()
        let originalCount = all.count
        all.removeAll { $0.id == id }
        guard all.count < originalCount else { throw ExpenseError.expenseNotFound }
        try persist(all)
    }

    func deleteAll() throws {
        try persist([])
    }

    /// Bulk replace, used when seeding sample data.
    func replaceAll(with dtos: [ExpenseDTO]) throws {
        try persist(dtos)
    }

    // MARK: - Storage plumbing

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
