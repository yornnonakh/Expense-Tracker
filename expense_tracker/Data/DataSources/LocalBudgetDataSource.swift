//
//  LocalBudgetDataSource.swift
//  Data Layer — Data Sources
//
//  On-device persistence for budgets. Same actor-serialised design, tombstone
//  semantics and sync hooks as `LocalExpenseDataSource` — see that file for
//  the reasoning behind each.
//

import Foundation

actor LocalBudgetDataSource {

    private let store: KeyValueStore
    private let key: String
    private var cache: [BudgetDTO]?

    init(store: KeyValueStore, key: String = StorageKey.budgets) {
        self.store = store
        self.key = key
    }

    // MARK: - Reads

    func fetchAll() throws -> [BudgetDTO] {
        try all().filter { !$0.isDeleted }
    }

    func fetchAllIncludingDeleted() throws -> [BudgetDTO] {
        try all()
    }

    func fetch(category: String) throws -> BudgetDTO? {
        try all().first { $0.category == category && !$0.isDeleted }
    }

    func pendingChanges() throws -> [BudgetDTO] {
        try all().filter(\.isPendingSync)
    }

    // MARK: - Writes

    /// Insert-or-replace keyed on category, which is the real uniqueness rule
    /// for budgets. Matching on category (not id) is what makes "edit the
    /// Food budget" idempotent no matter which id the caller passes.
    ///
    /// A tombstoned budget for the same category is replaced outright: the
    /// user is re-creating a budget they previously deleted, and keeping both
    /// rows would leave the category with two records the server would then
    /// have to arbitrate between.
    func upsert(_ dto: BudgetDTO) throws {
        var all = try all()
        if let index = all.firstIndex(where: { $0.category == dto.category && !$0.isDeleted }) {
            all[index] = dto
        } else if let index = all.firstIndex(where: { $0.id == dto.id }) {
            all[index] = dto
        } else {
            all.append(dto)
        }
        try persist(all)
    }

    func delete(id: String, at now: Date = Date()) throws {
        var all = try all()
        guard let index = all.firstIndex(where: { $0.id == id && !$0.isDeleted }) else {
            throw ExpenseError.budgetNotFound
        }
        all[index] = all[index].tombstoned(at: now)
        try persist(all)
    }

    func deleteAll(at now: Date = Date()) throws {
        let updated = try all().map { $0.isDeleted ? $0 : $0.tombstoned(at: now) }
        try persist(updated)
    }

    /// Sign-out wipe. See `LocalExpenseDataSource.purgeAll`.
    func purgeAll() throws {
        try persist([])
    }

    func replaceAll(with dtos: [BudgetDTO]) throws {
        try persist(dtos)
    }

    // MARK: - Sync

    func markSynced(_ acknowledged: [String: Double]) throws {
        let updated = try all().map { dto -> BudgetDTO in
            guard let pushedUpdatedAt = acknowledged[dto.id],
                  dto.updatedAt == pushedUpdatedAt else { return dto }
            return dto.markedSynced()
        }
        try persist(updated)
    }

    func applyRemote(_ remote: [BudgetDTO]) throws {
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

        // The server enforces one live budget per category. If a pull leaves
        // this device holding two, the server's view is authoritative and the
        // older one is dropped — otherwise the Budget tab would render a
        // duplicate row the user cannot get rid of.
        try persist(Self.resolvingDuplicateCategories(in: all))
    }

    func compact(olderThan cutoff: Date) throws {
        let cutoffMillis = cutoff.epochMillis
        let remaining = try all().filter { dto in
            guard let deletedAt = dto.deletedAt else { return true }
            if dto.isPendingSync { return true }
            return deletedAt > cutoffMillis
        }
        try persist(remaining)
    }

    /// Keeps the most recently updated live budget per category, tombstoning
    /// the rest.
    private static func resolvingDuplicateCategories(in dtos: [BudgetDTO]) -> [BudgetDTO] {
        var winnerByCategory: [String: BudgetDTO] = [:]

        for dto in dtos where !dto.isDeleted {
            if let existing = winnerByCategory[dto.category] {
                if dto.updatedAt > existing.updatedAt {
                    winnerByCategory[dto.category] = dto
                }
            } else {
                winnerByCategory[dto.category] = dto
            }
        }

        return dtos.map { dto in
            guard !dto.isDeleted,
                  let winner = winnerByCategory[dto.category],
                  winner.id != dto.id
            else { return dto }
            return dto.tombstoned()
        }
    }

    // MARK: - Storage plumbing

    private func all() throws -> [BudgetDTO] {
        if let cache { return cache }
        let loaded = try load()
        cache = loaded
        return loaded
    }

    private func load() throws -> [BudgetDTO] {
        guard let data = store.data(forKey: key) else { return [] }
        do {
            return try JSONCoding.decode([BudgetDTO].self, from: data)
        } catch {
            throw ExpenseError.decodingFailed(
                "Stored budgets could not be read. \(error.localizedDescription)"
            )
        }
    }

    private func persist(_ dtos: [BudgetDTO]) throws {
        let data = try JSONCoding.encode(dtos)
        store.set(data, forKey: key)
        cache = dtos
    }
}
