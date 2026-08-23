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

import Foundation

nonisolated struct ExpenseDTO: Codable, Equatable {

    let id: String
    let amount: Double
    let description: String
    let category: String
    /// Seconds since 1970. A plain number is unambiguous across time zones.
    let date: Double

    /// Bumped when the stored shape changes, so a future migration can tell
    /// old records from new ones.
    let schemaVersion: Int

    static let currentSchemaVersion = 1

    init(
        id: String,
        amount: Double,
        description: String,
        category: String,
        date: Double,
        schemaVersion: Int = ExpenseDTO.currentSchemaVersion
    ) {
        self.id = id
        self.amount = amount
        self.description = description
        self.category = category
        self.date = date
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
    }
}
