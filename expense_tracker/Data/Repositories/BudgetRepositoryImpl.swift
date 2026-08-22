//
//  BudgetRepositoryImpl.swift
//  Data Layer — Repository Implementations
//

import Foundation

final class BudgetRepositoryImpl: BudgetRepository {

    private let local: LocalBudgetDataSource
    private let notificationCenter: NotificationCenter

    init(local: LocalBudgetDataSource, notificationCenter: NotificationCenter = .default) {
        self.local = local
        self.notificationCenter = notificationCenter
    }

    func fetchAll() async throws -> [Budget] {
        do {
            let dtos = try await local.fetchAll()
            // Stable display order: alphabetical by category name.
            return BudgetMapper.toDomain(dtos)
                .sorted { $0.category.displayName < $1.category.displayName }
        } catch {
            throw ExpenseError.wrapping(error)
        }
    }

    func fetch(category: ExpenseCategory) async throws -> Budget? {
        do {
            guard let dto = try await local.fetch(category: category.rawValue) else {
                return nil
            }
            return try BudgetMapper.toDomain(dto)
        } catch {
            throw ExpenseError.wrapping(error)
        }
    }

    func upsert(_ budget: Budget) async throws {
        do {
            try await local.upsert(BudgetMapper.toDTO(budget))
        } catch {
            throw ExpenseError.wrapping(error)
        }
        notificationCenter.post(name: .budgetDataDidChange, object: nil)
    }

    func delete(id: UUID) async throws {
        do {
            try await local.delete(id: id.uuidString)
        } catch {
            throw ExpenseError.wrapping(error)
        }
        notificationCenter.post(name: .budgetDataDidChange, object: nil)
    }

    func deleteAll() async throws {
        do {
            try await local.deleteAll()
        } catch {
            throw ExpenseError.wrapping(error)
        }
        notificationCenter.post(name: .budgetDataDidChange, object: nil)
    }
}
