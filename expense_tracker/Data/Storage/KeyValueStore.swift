//
//  KeyValueStore.swift
//  Data Layer — Storage
//
//  A thin seam over UserDefaults.
//
//  Data sources talk to this protocol instead of `UserDefaults.standard`
//  directly, which buys two things: tests get an in-memory store with no
//  global state to clean up between runs, and swapping in the Keychain or a
//  file store later is a one-line change at the composition root.
//

import Foundation

nonisolated protocol KeyValueStore: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    func removeObject(forKey key: String)
}

// MARK: - UserDefaults

/// Production store. `UserDefaults` is documented as thread-safe, so this is
/// safe to call from any actor.
nonisolated final class UserDefaultsStore: KeyValueStore, @unchecked Sendable {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func set(_ data: Data?, forKey key: String) {
        guard let data else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    func removeObject(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - In-memory (tests & previews)

/// Drop-in replacement that keeps everything in RAM. Used by SwiftUI previews
/// so preview data never pollutes the simulator's real defaults.
nonisolated final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {

    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    init(seed: [String: Data] = [:]) {
        self.storage = seed
    }

    func data(forKey key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    func set(_ data: Data?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }

    func removeObject(forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}

// MARK: - Keys

/// Every persistence key in the app, in one place. Typos in a string literal
/// scattered across data sources are silent data loss; this makes them a
/// compile error instead.
nonisolated enum StorageKey {
    static let expenses = "expenses"
    static let budgets = "budgets"
    static let accounts = "auth.accounts"
    static let session = "auth.session"
    static let hasSeededSampleData = "app.hasSeededSampleData"

    /// Server-clock watermark for the sync cursor. See `SyncStateStore`.
    static let syncWatermark = "sync.watermark"
}
