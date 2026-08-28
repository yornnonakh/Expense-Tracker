//
//  ExpenseDTO.swift
//  Data Layer — DTOs
//
//  The on-disk shape of an expense.
//
//  WHY A SEPARATE TYPE FROM `Expense`?
//  Because the storage format and the business model change for different
//  reasons. Renaming `description` to `note` in the UI shouldn't invalidate
//  every file already written to disk; adding a `schemaVersion` shouldn't push
//  a storage concern into the domain. The DTO absorbs format churn, and the
//  mapper is the single place the two shapes meet.
//
//  SCHEMA 2 added the three sync fields below. They live here rather than in
//  the domain because they describe the record's replication state, not the
//  user's spending — `Expense` should never have to know a server exists.
//

import Foundation

nonisolated struct ExpenseDTO: Codable, Equatable {

    let id: String
    let amount: Double
    let description: String
    let category: String
    /// Seconds since 1970. A plain number is unambiguous across time zones.
    let date: Double

    // MARK: Sync metadata (schema 2)

    /// Epoch MILLISECONDS on this device's clock, set on every local write.
    /// The server compares this to decide last-write-wins, so it must reflect
    /// when the user made the edit, not when it was uploaded.
    var updatedAt: Double

    /// Epoch millis when deleted, or nil for a live record.
    ///
    /// Deleting writes a tombstone instead of removing the row. A removed row
    /// is indistinguishable from one this device has never seen, so the next
    /// pull would download it again and resurrect it.
    var deletedAt: Double?

    /// True when this device holds changes the server has not accepted yet.
    /// Cleared once a push comes back applied.
    var isPendingSync: Bool

    /// Bumped when the stored shape changes, so a future migration can tell
    /// old records from new ones.
    let schemaVersion: Int

    static let currentSchemaVersion = 2

    var isDeleted: Bool { deletedAt != nil }

    init(
        id: String,
        amount: Double,
        description: String,
        category: String,
        date: Double,
        updatedAt: Double = Date().epochMillis,
        deletedAt: Double? = nil,
        isPendingSync: Bool = true,
        schemaVersion: Int = ExpenseDTO.currentSchemaVersion
    ) {
        self.id = id
        self.amount = amount
        self.description = description
        self.category = category
        self.date = date
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.isPendingSync = isPendingSync
        self.schemaVersion = schemaVersion
    }

    /// Records written before versioning existed have no `schemaVersion` key.
    /// Defaulting it keeps those rows readable instead of failing the decode
    /// and wiping the user's history.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.amount = try container.decode(Double.self, forKey: .amount)
        self.description = try container.decode(String.self, forKey: .description)
        self.category = try container.decode(String.self, forKey: .category)
        self.date = try container.decode(Double.self, forKey: .date)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1

        self.deletedAt = try container
            .decodeIfPresent(Double.self, forKey: .deletedAt)?.wholeEpochMillis

        // MIGRATION, schema 1 -> 2.
        //
        // A schema-1 record predates the backend, so there is genuinely no
        // record of when it was last edited. `0` is the honest answer: it says
        // "oldest possible", which means it loses any last-write-wins contest
        // against a record edited on another device. That is the right way to
        // lose — the other device's timestamp is real, this one's is invented.
        self.updatedAt =
            try container.decodeIfPresent(Double.self, forKey: .updatedAt)?
            .wholeEpochMillis ?? 0

        // ...and it has never been uploaded, so it is pending by definition.
        self.isPendingSync =
            try container.decodeIfPresent(Bool.self, forKey: .isPendingSync) ?? true
    }

    // MARK: - Derived copies

    /// A copy stamped as edited now and awaiting upload.
    func markedEdited(at now: Date = Date()) -> ExpenseDTO {
        var copy = self
        copy.updatedAt = EpochMillis.stamp(after: updatedAt, now: now)
        copy.isPendingSync = true
        return copy
    }

    /// A tombstone: same identity, marked deleted and pending.
    func tombstoned(at now: Date = Date()) -> ExpenseDTO {
        var copy = self
        let millis = EpochMillis.stamp(after: updatedAt, now: now)
        copy.deletedAt = millis
        copy.updatedAt = millis
        copy.isPendingSync = true
        return copy
    }

    /// A copy the server has acknowledged.
    func markedSynced() -> ExpenseDTO {
        var copy = self
        copy.isPendingSync = false
        return copy
    }
}
