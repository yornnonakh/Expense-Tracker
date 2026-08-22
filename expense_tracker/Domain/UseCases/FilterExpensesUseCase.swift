//
//  FilterExpensesUseCase.swift
//  Domain Layer — Use Cases
//
//  Pure, synchronous filtering. No repository dependency: the caller already
//  holds the list, and re-fetching from storage on every keystroke would be
//  wasteful. Being synchronous also means the list updates within the same
//  frame as the tap, with no loading flicker.
//

import Foundation

/// The full set of things the user can narrow a list by.
struct ExpenseFilterCriteria: Equatable, Sendable {

    /// nil means "All categories".
    var category: ExpenseCategory?
    var range: DateRangeFilter
    var searchText: String

    init(
        category: ExpenseCategory? = nil,
        range: DateRangeFilter = .allTime,
        searchText: String = ""
    ) {
        self.category = category
        self.range = range
        self.searchText = searchText
    }

    static let none = ExpenseFilterCriteria()

    /// True when at least one filter would actually remove something — drives
    /// the "Clear filters" affordance and the wording of the empty state.
    var isActive: Bool {
        category != nil
            || range != .allTime
            || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

struct FilterExpensesUseCase: Sendable {

    init() {}

    /// Applies every criterion, then sorts newest first.
    func execute(
        expenses: [Expense],
        criteria: ExpenseFilterCriteria,
        referenceDate: Date = Date()
    ) -> [Expense] {
        let interval = criteria.range.interval(referenceDate: referenceDate)
        let query = criteria.searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let filtered = expenses.filter { expense in
            if let category = criteria.category, expense.category != category {
                return false
            }
            if let interval, !expense.falls(in: interval) {
                return false
            }
            if !query.isEmpty {
                // Case- and diacritic-insensitive so "cafe" finds "Café".
                let matchesDescription = expense.description.range(
                    of: query,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) != nil
                let matchesCategory = expense.category.displayName.range(
                    of: query,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) != nil
                if !matchesDescription && !matchesCategory { return false }
            }
            return true
        }

        return filtered.sortedByDateDescending()
    }

    /// Groups expenses under start-of-day keys for the Transactions tab,
    /// returned newest day first with each day's rows newest first.
    func groupByDay(
        _ expenses: [Expense],
        calendar: Calendar = .current
    ) -> [ExpenseDayGroup] {
        let grouped = Dictionary(grouping: expenses) { expense in
            calendar.startOfDay(for: expense.date)
        }

        return grouped
            .map { day, items in
                ExpenseDayGroup(day: day, expenses: items.sortedByDateDescending())
            }
            .sorted { $0.day > $1.day }
    }
}

/// One date-header section in the Transactions list.
struct ExpenseDayGroup: Identifiable, Equatable, Sendable {
    let day: Date
    let expenses: [Expense]

    var id: Date { day }
    var total: Double { expenses.totalAmount }
}
