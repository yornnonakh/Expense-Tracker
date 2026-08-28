//
//  CategoryDetailView.swift
//  Presentation Layer — Views
//
//  Drill-down from a pie slice: every expense in one category, for one window.
//

import SwiftUI

struct CategoryDetailView: View {

    let category: ExpenseCategory
    let range: DateRangeFilter

    @State private var expenses: [Expense] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let container: DIContainer

    init(
        category: ExpenseCategory,
        range: DateRangeFilter,
        container: DIContainer? = nil
    ) {
        // `nil` rather than `= .shared`; see `DIContainer.shared`.
        let container = container ?? .shared
        self.category = category
        self.range = range
        self.container = container
    }

    private var total: Double { expenses.totalAmount }

    private var average: Double {
        guard !expenses.isEmpty else { return 0 }
        return total / Double(expenses.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.md) {

                header

                if let errorMessage {
                    ErrorBanner(message: errorMessage, onDismiss: {
                        self.errorMessage = nil
                    })
                }

                if isLoading {
                    ExpenseListSkeleton(rowCount: 4)
                } else if expenses.isEmpty {
                    EmptyStateView(
                        title: "Nothing here",
                        message: "No \(category.displayName.lowercased()) expenses "
                            + "in \(range.displayName.lowercased()).",
                        systemImage: category.systemImageName
                    )
                    .cardStyle()
                } else {
                    expenseList
                }
            }
            .padding(AppTheme.Spacing.md)
        }
        .screenBackground()
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Expense.self) { expense in
            ExpenseDetailView(expense: expense, container: container)
        }
        .task { await load() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Text(category.emoji)
                .font(.system(size: 34))
                .frame(width: 72, height: 72)
                .background(Circle().fill(category.softColor))

            Text(AppFormatters.currency(total))
                .font(AppTheme.Typography.bigAmount)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text("\(expenses.count) expenses · \(range.displayName)")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            HStack(spacing: AppTheme.Spacing.sm) {
                StatisticCard(
                    title: "Average",
                    value: AppFormatters.currency(average),
                    systemImage: "chart.bar.fill",
                    tint: category.color
                )
                StatisticCard(
                    title: "Largest",
                    value: AppFormatters.currency(
                        expenses.map(\.amount).max() ?? 0
                    ),
                    systemImage: "arrow.up.right",
                    tint: category.color
                )
            }
            .padding(.top, AppTheme.Spacing.xs)
        }
        .frame(maxWidth: .infinity)
    }

    private var expenseList: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            ForEach(expenses) { expense in
                NavigationLink(value: expense) {
                    ExpenseListItem(expense: expense, showsChevron: true)
                }
                .buttonStyle(.plain)

                if expense.id != expenses.last?.id {
                    ThemedDivider()
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            expenses = try await container.getStatisticsUseCase.executeCategoryDetail(
                category: category,
                range: range
            )
        } catch {
            errorMessage = (error as? ExpenseError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview("Category detail") {
    NavigationStack {
        CategoryDetailView(
            category: .food,
            range: .thisMonth,
            container: .preview
        )
    }
}
