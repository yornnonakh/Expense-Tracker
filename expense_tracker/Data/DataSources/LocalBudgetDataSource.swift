//
//  LocalBudgetDataSource.swift
//  Data Layer — Data Sources
//
//  On-device persistence for budgets. Same actor-serialised design as
//  `LocalExpenseDataSource`.
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
        if let cache { return cache }
        let loaded = try load()
        cache = loaded
        return loaded
    }

    func fetch(category: String) throws -> BudgetDTO? {
        try fetchAll().first { $0.category == category }
    }

    // MARK: - Writes

    /// Insert-or-replace keyed on category, which is the real uniqueness rule
    /// for budgets. Matching on category (not id) is what makes "edit the
    /// Food budget" idempotent no matter which id the caller passes.
    func upsert(_ dto: BudgetDTO) throws {
        var all = try fetchAll()
        if let index = all.firstIndex(where: { $0.category == dto.category }) {
            all[index] = dto
        } else {
            all.append(dto)
        }
        try persist(all)
    }

    func delete(id: String) throws {
        var all = try fetchAll()
        let originalCount = all.count
        all.removeAll { $0.id == id }
        guard all.count < originalCount else { throw ExpenseError.budgetNotFound }
        try persist(all)
    }

    func deleteAll() throws {
        try persist([])
    }

    func replaceAll(with dtos: [BudgetDTO]) throws {
        try persist(dtos)
    }

    // MARK: - Storage plumbing

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
