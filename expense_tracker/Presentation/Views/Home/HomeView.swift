//
//  HomeView.swift
//  Presentation Layer — Views — Tab 1
//
//  Dashboard: budget headline, weekly chart, top categories, recents.
//

import SwiftUI

struct HomeView: View {

    @StateObject private var viewModel: HomeViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var showAddExpense = false
    @State private var showAccountSheet = false

    private let container: DIContainer

    /// Lets the dashboard's "See all" jump the user to another tab.
    @Binding private var selectedTab: MainTabView.Tab

    init(selectedTab: Binding<MainTabView.Tab>, container: DIContainer? = nil) {
        // `nil` rather than `= .shared`; see `DIContainer.shared`.
        let container = container ?? .shared
        _selectedTab = selectedTab
        self.container = container
        _viewModel = StateObject(wrappedValue: container.makeHomeViewModel())
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                content

                FloatingActionButton {
                    showAddExpense = true
                }
                .padding(AppTheme.Spacing.lg)
            }
            .screenBackground()
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            // Value-based destination: rows push by handing the stack an
            // `Expense`, so no per-row navigation state is needed.
            .navigationDestination(for: Expense.self) { expense in
                ExpenseDetailView(expense: expense, container: container)
            }
        }
        .sheet(isPresented: $showAddExpense) {
            AddExpenseSheetView(container: container)
        }
        .sheet(isPresented: $showAccountSheet) {
            AccountSheetView(authViewModel: authViewModel, container: container)
        }
        // Two subscriptions: the first loads and then watches expense writes,
        // the second watches budget writes. Both are torn down with the view.
        .task { await viewModel.start() }
        .task { await viewModel.observeBudgetChanges() }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {

                BudgetSummaryHeader(
                    summary: viewModel.budgetSummary,
                    greeting: viewModel.greeting,
                    userName: authViewModel.currentUser?.firstName ?? "there",
                    initials: authViewModel.currentUser?.initials ?? "?",
                    avatarImageData: authViewModel.currentUser?.avatarImageData,
                    spentThisMonth: viewModel.statistics.totalSpending
                ) {
                    showAccountSheet = true
                }

                if let errorMessage = viewModel.errorMessage {
                    ErrorBanner(
                        message: errorMessage,
                        isRetryable: viewModel.errorIsRetryable,
                        onRetry: { Task { await viewModel.retry() } },
                        onDismiss: { viewModel.clearError() }
                    )
                }

                // Skeletons only on the very first load — a background refresh
                // keeps showing real data rather than flashing placeholders.
                if !viewModel.hasLoadedOnce && viewModel.isLoading {
                    ExpenseListSkeleton(rowCount: 4)
                } else {
                    WeeklyBarChartView(days: viewModel.weeklySpending)
                    topCategories
                    recentTransactions
                }
            }
            .padding(AppTheme.Spacing.md)
            // Clears the floating button so the last row is always reachable.
            .padding(.bottom, AppTheme.Metrics.fabSize + AppTheme.Spacing.lg)
        }
        .refreshable { await viewModel.load() }
    }

    private var topCategories: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionHeader(title: "Top categories", actionTitle: "Statistics") {
                selectedTab = .statistics
            }

            if viewModel.topCategories.isEmpty {
                Text("No spending this month yet.")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AppTheme.Spacing.sm)
            } else {
                VStack(spacing: AppTheme.Spacing.md) {
                    ForEach(viewModel.topCategories) { breakdown in
                        CategoryBreakdownRow(breakdown: breakdown) {
                            selectedTab = .statistics
                        }
                    }
                }
                .cardStyle()
            }
        }
    }

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionHeader(title: "Recent", actionTitle: "See all") {
                selectedTab = .expenses
            }

            if viewModel.recentExpenses.isEmpty {
                EmptyStateView(
                    title: "Nothing here yet",
                    message: "Tap the + button to record your first expense.",
                    systemImage: "creditcard",
                    actionTitle: "Add Expense"
                ) {
                    showAddExpense = true
                }
                .cardStyle()
            } else {
                VStack(spacing: AppTheme.Spacing.xs) {
                    ForEach(viewModel.recentExpenses) { expense in
                        NavigationLink(value: expense) {
                            ExpenseListItem(expense: expense, showsChevron: true)
                        }
                        .buttonStyle(.plain)

                        if expense.id != viewModel.recentExpenses.last?.id {
                            ThemedDivider()
                        }
                    }
                }
                .cardStyle()
            }
        }
    }
}

// MARK: - Preview

#Preview("Home") {
    struct Harness: View {
        @State private var tab: MainTabView.Tab = .home
        private let container = DIContainer.preview

        var body: some View {
            HomeView(selectedTab: $tab, container: container)
                .environmentObject(container.makeAuthViewModel())
        }
    }
    return Harness()
}
