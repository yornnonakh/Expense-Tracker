//
//  StatisticsViewModel.swift
//  Presentation Layer — ViewModels
//
//  Pie chart, legend, metric cards and the category drill-down.
//

import Combine
import Foundation

@MainActor
final class StatisticsViewModel: ObservableObject, ErrorPresenting {

    @Published private(set) var statistics: ExpenseStatistics = .empty()

    @Published var dateRange: DateRangeFilter = .thisMonth {
        didSet {
            // The window changed, so the previous slice selection may no
            // longer exist. Reload rather than filter locally: statistics are
            // an aggregate, not a subset of what's already loaded.
            reloadTask?.cancel()
            reloadTask = Task { await load() }
        }
    }

    /// Currently highlighted pie slice, shared with the legend.
    @Published var selectedCategory: ExpenseCategory?

    /// Expenses behind the selected slice, loaded on demand.
    @Published private(set) var categoryDetail: [Expense] = []
    @Published private(set) var isLoadingDetail = false

    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedOnce = false
    @Published var errorMessage: String?
    @Published var errorIsRetryable = false

    private let getStatistics: GetStatisticsUseCase

    /// Retained so a rapid series of range changes cancels the stale request
    /// instead of racing it to the finish.
    private var reloadTask: Task<Void, Never>?

    nonisolated init(getStatistics: GetStatisticsUseCase) {
        self.getStatistics = getStatistics
    }

    deinit {
        reloadTask?.cancel()
    }

    // MARK: - Derived

    var breakdown: [CategoryBreakdown] { statistics.categoryBreakdown }

    var hasData: Bool { !statistics.isEmpty }

    var selectedBreakdown: CategoryBreakdown? {
        guard let selectedCategory else { return nil }
        return breakdown.first { $0.category == selectedCategory }
    }

    // MARK: - Lifecycle

    func start() async {
        await load()
        await observeChanges()
    }

    func observeChanges() async {
        for await _ in NotificationCenter.default.notifications(
            named: .expenseDataDidChange
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
            let loaded = try await getStatistics.execute(range: dateRange)
            guard !Task.isCancelled else { return }
            statistics = loaded

            // Drop a selection whose category has no spending in the new
            // window, so the chart's centre label can't show a stale figure.
            if let selectedCategory,
               loaded.spendingByCategory[selectedCategory] == nil {
                self.selectedCategory = nil
            }
        } catch {
            present(error)
        }
    }

    func retry() async {
        await load()
    }

    // MARK: - Drill-down

    /// Loads the expenses behind a slice when the user taps into it.
    func loadDetail(for category: ExpenseCategory) async {
        isLoadingDetail = true
        defer { isLoadingDetail = false }

        do {
            categoryDetail = try await getStatistics.executeCategoryDetail(
                category: category,
                range: dateRange
            )
        } catch {
            present(error)
            categoryDetail = []
        }
    }

    func clearSelection() {
        selectedCategory = nil
        categoryDetail = []
    }
}
