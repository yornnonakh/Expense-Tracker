//
//  SampleDataSeeder.swift
//  Core
//
//  Populates a brand-new account with a couple of weeks of plausible spending.
//
//  An empty dashboard makes it impossible to tell a working chart from a
//  broken one. Seeding runs exactly once per install (guarded by a flag) and
//  never touches an account that already has data.
//

import Foundation

struct SampleDataSeeder: Sendable {

    private let expenseRepository: ExpenseRepository
    private let budgetRepository: BudgetRepository
    private let store: KeyValueStore

    init(
        expenseRepository: ExpenseRepository,
        budgetRepository: BudgetRepository,
        store: KeyValueStore
    ) {
        self.expenseRepository = expenseRepository
        self.budgetRepository = budgetRepository
        self.store = store
    }

    /// Seeds once. Safe to call on every launch.
    func seedIfNeeded() async {
        guard store.data(forKey: StorageKey.hasSeededSampleData) == nil else { return }

        // Mark first: if seeding half-fails we still don't want to retry on
        // every launch and pile up duplicates.
        store.set(Data([1]), forKey: StorageKey.hasSeededSampleData)

        do {
            let existing = try await expenseRepository.fetchAll()
            guard existing.isEmpty else { return }

            for expense in Self.sampleExpenses() {
                try await expenseRepository.add(expense)
            }
            for budget in Self.sampleBudgets() {
                try await budgetRepository.upsert(budget)
            }
        } catch {
            // Seeding is a convenience. If it fails the app is still perfectly
            // usable with an empty state, so there is nothing to surface.
        }
    }

    // MARK: - Sample content

    static func sampleExpenses(referenceDate: Date = Date()) -> [Expense] {
        let calendar = Calendar.current

        // (daysAgo, amount, description, category)
        let rows: [(Int, Double, String, ExpenseCategory)] = [
            (0,  12.40, "Morning coffee & pastry", .food),
            (0,  38.90, "Weekly grocery run",      .food),
            (1,  24.00, "Taxi to the office",      .transport),
            (1,  15.99, "Streaming subscription",  .entertainment),
            (2,  86.20, "Electricity bill",        .utilities),
            (2,   9.50, "Lunch at the deli",       .food),
            (3, 142.00, "New running shoes",       .shopping),
            (3,  32.75, "Pharmacy — cold medicine", .health),
            (4,  18.30, "Metro top-up",            .transport),
            (5,  55.00, "Dinner with friends",     .food),
            (5,  29.99, "Cinema tickets",          .entertainment),
            (6,  74.60, "Internet bill",           .utilities),
            (7,  21.10, "Bookshop",                .shopping),
            (8,  11.75, "Bus pass",                .transport),
            (9,  63.40, "Dentist co-pay",          .health),
            (10, 44.25, "Takeaway night",          .food),
            (12, 19.00, "Parking garage",          .transport),
            (14, 95.00, "Winter jacket",           .shopping),
            (16,  7.80, "Snacks",                  .other),
            (18, 48.50, "Concert ticket",          .entertainment)
        ]

        return rows.compactMap { daysAgo, amount, description, category in
            guard let date = calendar.date(
                byAdding: .day, value: -daysAgo, to: referenceDate
            ) else { return nil }

            return Expense(
                amount: amount,
                description: description,
                category: category,
                date: date
            )
        }
    }

    static func sampleBudgets() -> [Budget] {
        [
            Budget(category: .food, limit: 400),
            Budget(category: .transport, limit: 150),
            Budget(category: .entertainment, limit: 120),
            Budget(category: .utilities, limit: 200),
            Budget(category: .shopping, limit: 250)
        ]
    }
}
