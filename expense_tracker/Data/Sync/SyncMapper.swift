//
//  SyncMapper.swift
//  Data Layer — Sync
//
//  Translates between the on-disk DTOs and the wire DTOs.
//
//  The only interesting rule is the direction of `isPendingSync`: it is a
//  purely local concept and never crosses the wire. Records built from a
//  server payload arrive with it false, because they came *from* the server —
//  marking them pending would push them straight back and risk clobbering a
//  concurrent edit from another device with data that device just sent us.
//

import Foundation

nonisolated enum SyncMapper {

    // MARK: - Expenses

    static func toAPI(_ dto: ExpenseDTO) -> APIExpense {
        APIExpense(
            id: dto.id,
            amount: dto.amount,
            description: dto.description,
            category: dto.category,
            date: dto.date,
            updatedAt: dto.updatedAt,
            deletedAt: dto.deletedAt
        )
    }

    static func toDTO(_ api: APIExpense) -> ExpenseDTO {
        ExpenseDTO(
            id: api.id,
            amount: api.amount,
            description: api.description,
            category: api.category,
            date: api.date,
            updatedAt: api.updatedAt,
            deletedAt: api.deletedAt,
            isPendingSync: false
        )
    }

    // MARK: - Budgets

    static func toAPI(_ dto: BudgetDTO) -> APIBudget {
        APIBudget(
            id: dto.id,
            category: dto.category,
            limit: dto.limit,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            deletedAt: dto.deletedAt
        )
    }

    static func toDTO(_ api: APIBudget) -> BudgetDTO {
        BudgetDTO(
            id: api.id,
            category: api.category,
            limit: api.limit,
            createdAt: api.createdAt,
            updatedAt: api.updatedAt,
            deletedAt: api.deletedAt,
            isPendingSync: false
        )
    }
}
