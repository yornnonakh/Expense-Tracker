//
//  BudgetMapper.swift
//  Data Layer — Mappers
//

import Foundation

enum BudgetMapper {

    static func toDTO(_ budget: Budget) -> BudgetDTO {
        BudgetDTO(
            id: budget.id.uuidString,
            category: budget.category.rawValue,
            limit: budget.limit,
            createdAt: budget.createdAt.timeIntervalSince1970
        )
    }

    static func toDomain(_ dto: BudgetDTO) throws -> Budget {
        guard let id = UUID(uuidString: dto.id) else {
            throw ExpenseError.decodingFailed("Budget has a malformed id: \(dto.id)")
        }
        guard let category = ExpenseCategory(rawValue: dto.category) else {
            // Unlike an expense, a budget IS its category — a budget for an
            // unknown category has no meaning, so drop it rather than
            // silently retargeting the user's limit at "Other".
            throw ExpenseError.decodingFailed("Unknown budget category: \(dto.category)")
        }

        return Budget(
            id: id,
            category: category,
            limit: dto.limit,
            createdAt: Date(timeIntervalSince1970: dto.createdAt)
        )
    }

    static func toDTOs(_ budgets: [Budget]) -> [BudgetDTO] {
        budgets.map(toDTO)
    }

    static func toDomain(_ dtos: [BudgetDTO]) -> [Budget] {
        dtos.compactMap { try? toDomain($0) }
    }
}
