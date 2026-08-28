//
//  BudgetDTO.swift
//  Data Layer — DTOs
//
//  Same sync fields, and the same reasoning, as `ExpenseDTO`.
//

import Foundation

nonisolated struct BudgetDTO: Codable, Equatable {

    let id: String
    let category: String
    let limit: Double
    /// Epoch seconds.
    let createdAt: Double

    // MARK: Sync metadata (schema 2)

    /// Epoch millis, this device's clock.
    var updatedAt: Double
    var deletedAt: Double?
    var isPendingSync: Bool

    let schemaVersion: Int

    static let currentSchemaVersion = 2

    var isDeleted: Bool { deletedAt != nil }

    init(
        id: String,
        category: String,
        limit: Double,
        createdAt: Double,
        updatedAt: Double = Date().epochMillis,
        deletedAt: Double? = nil,
        isPendingSync: Bool = true,
        schemaVersion: Int = BudgetDTO.currentSchemaVersion
    ) {
        self.id = id
        self.category = category
        self.limit = limit
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.isPendingSync = isPendingSync
        self.schemaVersion = schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.category = try container.decode(String.self, forKey: .category)
        self.limit = try container.decode(Double.self, forKey: .limit)
        self.createdAt = try container.decode(Double.self, forKey: .createdAt)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1

        self.deletedAt = try container
            .decodeIfPresent(Double.self, forKey: .deletedAt)?.wholeEpochMillis
        // See the migration note in `ExpenseDTO.init(from:)`.
        self.updatedAt =
            try container.decodeIfPresent(Double.self, forKey: .updatedAt)?
            .wholeEpochMillis ?? 0
        self.isPendingSync =
            try container.decodeIfPresent(Bool.self, forKey: .isPendingSync) ?? true
    }

    func markedEdited(at now: Date = Date()) -> BudgetDTO {
        var copy = self
        copy.updatedAt = EpochMillis.stamp(after: updatedAt, now: now)
        copy.isPendingSync = true
        return copy
    }

    func tombstoned(at now: Date = Date()) -> BudgetDTO {
        var copy = self
        let millis = EpochMillis.stamp(after: updatedAt, now: now)
        copy.deletedAt = millis
        copy.updatedAt = millis
        copy.isPendingSync = true
        return copy
    }

    func markedSynced() -> BudgetDTO {
        var copy = self
        copy.isPendingSync = false
        return copy
    }
}
