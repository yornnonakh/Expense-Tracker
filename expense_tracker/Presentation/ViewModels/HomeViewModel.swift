//
//  HomeViewModel.swift
//  Presentation Layer — ViewModels
//
//  Dashboard state: budget headline, weekly chart, top categories, recents.
//

import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject, ErrorPresenting {

    @Published private(set) var recentExpenses: [Expense] = []
    @Published private(set) var statistics: ExpenseStatistics = .empty(range: .thisMonth)
    @Published private(set) var weeklySpending: [DailySpending] = []
    @Published private(set) var budgetSummary: BudgetSummary = .empty

    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var errorIsRetryable = false

    /// True only for the very first load, so a background refresh doesn't
    /// replace populated content with skeletons.
    @Published private(set) var hasLoadedOnce = false

    private let getExpenses: GetExpensesUseCase
    private let getStatistics: GetStatisticsUseCase
    private let getWeeklySpending: GetWeeklySpendingUseCase
    private let manageBudget: ManageBudgetUseCase

    /// How many rows the "Recent transactions" preview shows.
    private let recentLimit = 5

    nonisolated init(
        getExpenses: GetExpensesUseCase,
        getStatistics: GetStatisticsUseCase,
        getWeeklySpending: GetWeeklySpendingUseCase,
        manageBudget: ManageBudgetUseCase
    ) {
        self.getExpenses = getExpenses
        self.getStatistics = getStatistics
        self.getWeeklySpending = getWeeklySpending
        self.manageBudget = manageBudget
    }

    /// Top four categories by spend, for the breakdown list.
    var topCategories: [CategoryBreakdown] {
        Array(statistics.categoryBreakdown.prefix(4))
    }

    var greeting: String { AppFormatters.greeting() }

    // MARK: - Lifecycle

    /// Loads, then stays subscribed to data changes for as long as the view
    /// is alive. Driven by `.task`, so SwiftUI cancels the subscription when
    /// the view goes away.
    func start() async {
        await load()
        await observeExpenseChanges()
    }

    func observeExpenseChanges() async {
        for await _ in NotificationCenter.default.notifications(
            named: .expenseDataDidChange
        ) {
            await load()
        }
    }

    func observeBudgetChanges() async {
        for await _ in NotificationCenter.default.notifications(
            named: .budgetDataDidChange
        ) {
            await load()
        }
    }

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }
        clearError()

        do {
            // Four independent reads, issued concurrently. Sequentially this
            // would be four round-trips through the storage actor for data
            // that has no ordering dependency.
            async let recents = getExpenses.executeRecent(limit: recentLimit)
            async let stats = getStatistics.execute(range: .thisMonth)
            async let weekly = getWeeklySpending.execute(days: 7)
            async let summary = manageBudget.totalRemaining(range: .thisMonth)

            let (loadedRecents, loadedStats, loadedWeekly, loadedSummary) =
                try await (recents, stats, weekly, summary)

            recentExpenses = loadedRecents
            statistics = loadedStats
            weeklySpending = loadedWeekly
            budgetSummary = loadedSummary
        } catch {
            present(error)
        }
    }

    func retry() async {
        await load()
    }
}
