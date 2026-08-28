//
//  StatisticsView.swift
//  Presentation Layer — Views — Tab 4
//
//  Pie chart, legend, metric cards and category drill-down.
//

import SwiftUI

struct StatisticsView: View {

    @StateObject private var viewModel: StatisticsViewModel
    private let container: DIContainer

    init(container: DIContainer? = nil) {
        // `nil` rather than `= .shared`; see `DIContainer.shared`.
        let container = container ?? .shared
        self.container = container
        _viewModel = StateObject(wrappedValue: container.makeStatisticsViewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {

                    DateRangePicker(selection: $viewModel.dateRange)

                    if let errorMessage = viewModel.errorMessage {
                        ErrorBanner(
                            message: errorMessage,
                            isRetryable: viewModel.errorIsRetryable,
                            onRetry: { Task { await viewModel.retry() } },
                            onDismiss: { viewModel.clearError() }
                        )
                    }

                    if !viewModel.hasLoadedOnce && viewModel.isLoading {
                        loadingState
                    } else if !viewModel.hasData {
                        EmptyStateView(
                            title: "No data to chart",
                            message: "Record some expenses for "
                                + "\(viewModel.dateRange.displayName.lowercased()) "
                                + "and your breakdown will appear here.",
                            systemImage: "chart.pie"
                        )
                        .cardStyle()
                    } else {
                        chartCard
                        metricCards
                        legendCard
                    }
                }
                .padding(AppTheme.Spacing.md)
            }
            .screenBackground()
            .navigationTitle("Statistics")
            // Inline, not large, on purpose. This screen is a `ScrollView`
            // whose content grows when the loading skeleton is replaced by the
            // chart, and a large title collapses against that height change —
            // the screen would open already scrolled, hiding the chart. The
            // List-based tabs (Expenses, History) don't have this problem and
            // keep their large titles.
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await viewModel.load() }
            .navigationDestination(for: ExpenseCategory.self) { category in
                CategoryDetailView(
                    category: category,
                    range: viewModel.dateRange,
                    container: container
                )
            }
        }
        .task { await viewModel.start() }
    }

    // MARK: - Sections

    private var loadingState: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Circle()
                .fill(AppTheme.Colors.divider)
                .frame(
                    width: AppTheme.Metrics.pieChartSize,
                    height: AppTheme.Metrics.pieChartSize
                )
            ExpenseListSkeleton(rowCount: 4)
        }
        .accessibilityHidden(true)
    }

    private var chartCard: some View {
        VStack(spacing: AppTheme.Spacing.md) {

            PieChartView(
                slices: viewModel.breakdown,
                selection: $viewModel.selectedCategory
            )

            // Only offered once a slice is picked, so the drill-down button
            // always has a concrete target.
            if let selected = viewModel.selectedBreakdown {
                NavigationLink(value: selected.category) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Text("View \(selected.category.displayName) expenses")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(AppTheme.Typography.callout)
                    .foregroundStyle(selected.category.color)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(Capsule().fill(selected.category.softColor))
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                Text("Tap a slice to explore a category")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: AppTheme.Spacing.lg)
        .animation(AppTheme.Motion.spring, value: viewModel.selectedCategory)
    }

    /// Two-by-two grid of headline metrics.
    private var metricCards: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: AppTheme.Spacing.sm),
                GridItem(.flexible(), spacing: AppTheme.Spacing.sm)
            ],
            spacing: AppTheme.Spacing.sm
        ) {
            StatisticCard(
                title: "Total spent",
                value: AppFormatters.currency(viewModel.statistics.totalSpending),
                systemImage: "creditcard.fill",
                tint: AppTheme.Colors.primary,
                subtitle: "\(viewModel.statistics.expenseCount) expenses"
            )

            StatisticCard(
                title: "Average",
                value: AppFormatters.currency(viewModel.statistics.averageExpense),
                systemImage: "chart.bar.fill",
                tint: AppTheme.Colors.secondary,
                subtitle: "per expense"
            )

            StatisticCard(
                title: "Highest",
                value: AppFormatters.currency(
                    viewModel.statistics.highestExpense?.amount ?? 0
                ),
                systemImage: "arrow.up.right",
                tint: AppTheme.Colors.danger,
                subtitle: viewModel.statistics.highestExpense?.description
            )

            StatisticCard(
                title: "Lowest",
                value: AppFormatters.currency(
                    viewModel.statistics.lowestExpense?.amount ?? 0
                ),
                systemImage: "arrow.down.right",
                tint: AppTheme.Colors.success,
                subtitle: viewModel.statistics.lowestExpense?.description
            )
        }
    }

    private var legendCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("By category")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .padding(.bottom, AppTheme.Spacing.xxs)

            ForEach(viewModel.breakdown) { item in
                Button {
                    Haptics.selection()
                    withAnimation(AppTheme.Motion.spring) {
                        // Legend and chart drive the same selection, so
                        // tapping either highlights both.
                        viewModel.selectedCategory =
                            viewModel.selectedCategory == item.category
                                ? nil
                                : item.category
                    }
                } label: {
                    CategoryLegendRow(
                        breakdown: item,
                        isHighlighted: viewModel.selectedCategory == item.category
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }
}

// MARK: - Preview

#Preview("Statistics") {
    StatisticsView(container: .preview)
}
