//
//  BudgetDTO.swift
//  Data Layer — DTOs
//

import Foundation

struct BudgetDTO: Codable, Equatable {

    let id: String
    let category: String
    let limit: Double
    let createdAt: Double
    let schemaVersion: Int

    static let currentSchemaVersion = 1

    init(
        id: String,
        category: String,
        limit: Double,
        createdAt: Double,
        schemaVersion: Int = BudgetDTO.currentSchemaVersion
    ) {
        self.id = id
        self.category = category
        self.limit = limit
        self.createdAt = createdAt
        self.schemaVersion = schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.category = try container.decode(String.self, forKey: .category)
        self.limit = try container.decode(Double.self, forKey: .limit)
        self.createdAt = try container.decode(Double.self, forKey: .createdAt)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }
}
