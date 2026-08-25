//
//  SyncStateStore.swift
//  Data Layer — Storage
//
//  The sync watermark: the `serverTime` from the last successful pull.
//
//  IT IS A SERVER CLOCK VALUE AND IS NEVER COMPUTED LOCALLY. The client stores
//  whatever the server sent and hands the same number back on the next pull.
//  Deriving it from `Date()` would silently break sync on any device whose
//  clock runs ahead — changes stamped between the two clocks would never be
//  returned by any future pull, and the data would simply go missing.
//

import Foundation

nonisolated protocol SyncStateStoring: Sendable {
    func watermark() async -> Double
    func setWatermark(_ value: Double) async
    func reset() async
}

actor SyncStateStore: SyncStateStoring {

    private let store: KeyValueStore
    private var cached: Double?

    init(store: KeyValueStore) {
        self.store = store
    }

    /// Zero means "never synced", which the server reads as "send everything".
    func watermark() async -> Double {
        if let cached { return cached }

        guard let data = store.data(forKey: StorageKey.syncWatermark),
              let value = try? JSONDecoder().decode(Double.self, from: data)
        else {
            cached = 0
            return 0
        }

        cached = value
        return value
    }

    func setWatermark(_ value: Double) async {
        // Never move backwards. A stale response arriving after a newer one
        // would otherwise rewind the cursor and re-download everything.
        let current = await watermark()
        guard value > current else { return }

        cached = value
        if let data = try? JSONEncoder().encode(value) {
            store.set(data, forKey: StorageKey.syncWatermark)
        }
    }

    /// Called on sign-out. The next account on this device must start from
    /// scratch rather than inherit a cursor into someone else's history.
    func reset() async {
        cached = 0
        store.removeObject(forKey: StorageKey.syncWatermark)
    }
}

/// In-memory variant for tests and previews.
actor InMemorySyncStateStore: SyncStateStoring {
    private var value: Double = 0

    init(seed: Double = 0) { self.value = seed }

    func watermark() async -> Double { value }
    func setWatermark(_ newValue: Double) async {
        guard newValue > value else { return }
        value = newValue
    }
    func reset() async { value = 0 }
}
