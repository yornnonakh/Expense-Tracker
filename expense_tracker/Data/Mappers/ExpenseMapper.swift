//
//  ExpenseMapper.swift
//  Data Layer — Mappers
//
//  The only place `Expense` and `ExpenseDTO` know about each other.
//

import Foundation

enum ExpenseMapper {

    /// Domain -> storage. Total: every valid `Expense` has a representation.
    static func toDTO(_ expense: Expense) -> ExpenseDTO {
        ExpenseDTO(
            id: expense.id.uuidString,
            amount: expense.amount,
            description: expense.description,
            category: expense.category.rawValue,
            date: expense.date.timeIntervalSince1970
        )
    }

    /// Storage -> domain. Partial: a hand-edited or corrupted record may not
    /// map, so this throws rather than inventing values.
    static func toDomain(_ dto: ExpenseDTO) throws -> Expense {
        guard let id = UUID(uuidString: dto.id) else {
            throw ExpenseError.decodingFailed("Expense has a malformed id: \(dto.id)")
        }

        // Unknown category strings fall back to `.other` rather than throwing —
        // losing the bucket is recoverable, losing the expense is not.
        let category = ExpenseCategory(rawValue: dto.category) ?? .other

        return Expense(
            id: id,
            amount: dto.amount,
            description: dto.description,
            category: category,
            date: Date(timeIntervalSince1970: dto.date)
        )
    }

    static func toDTOs(_ expenses: [Expense]) -> [ExpenseDTO] {
        expenses.map(toDTO)
    }

    /// Maps a whole stored batch, skipping individual records that cannot be
    /// read. One bad row shouldn't cost the user every other expense they have.
    static func toDomain(_ dtos: [ExpenseDTO]) -> [Expense] {
        dtos.compactMap { try? toDomain($0) }
    }
}
