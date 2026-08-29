//
//  TransactionsView.swift
//  Presentation Layer — Views — Tab 3
//
//  Date-grouped history with a range filter.
//

import SwiftUI

struct TransactionsView: View {

    @EnvironmentObject private var currency: CurrencyStore

    @StateObject private var viewModel: TransactionsViewModel
    private let container: DIContainer

    init(container: DIContainer? = nil) {
        // `nil` rather than `= .shared`; see `DIContainer.shared`.
        let container = container ?? .shared
        self.container = container
        _viewModel = StateObject(wrappedValue: container.makeTransactionsViewModel())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                rangePicker
                summaryStrip
                content
            }
            .screenBackground()
            .navigationTitle("Transactions")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $viewModel.searchText,
                prompt: "Search transactions"
            )
            .navigationDestination(for: Expense.self) { expense in
                ExpenseDetailView(expense: expense, container: container)
            }
        }
        .task { await viewModel.start() }
    }

    // MARK: - Sections

    private var rangePicker: some View {
        DateRangePicker(
            selection: $viewModel.dateRange,
            options: viewModel.availableRanges
        )
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    @ViewBuilder
    private var summaryStrip: some View {
        if viewModel.transactionCount > 0 {
            HStack {
                Text("\(viewModel.transactionCount) transactions")
                Spacer()
                Text(currency.dual(viewModel.rangeTotal))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .font(AppTheme.Typography.caption)
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.xs)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = viewModel.errorMessage {
            ErrorBanner(
                message: errorMessage,
                isRetryable: viewModel.errorIsRetryable,
                onRetry: { Task { await viewModel.retry() } },
                onDismiss: { viewModel.clearError() }
            )
            .padding(AppTheme.Spacing.md)
        }

        if !viewModel.hasLoadedOnce && viewModel.isLoading {
            ScrollView {
                ExpenseListSkeleton()
                    .padding(AppTheme.Spacing.md)
            }
        } else if viewModel.groups.isEmpty {
            ScrollView {
                EmptyStateView(
                    title: "Nothing in this period",
                    message: emptyMessage,
                    systemImage: "calendar.badge.clock"
                )
                .padding(.top, AppTheme.Spacing.xxl)
            }
        } else {
            groupedList
        }
    }

    private var emptyMessage: String {
        viewModel.searchText.isEmpty
            ? "No transactions recorded for \(viewModel.dateRange.displayName.lowercased())."
            : "No transactions match \"\(viewModel.searchText)\"."
    }

    /// One `Section` per day, with the date and daily total in the header.
    private var groupedList: some View {
        List {
            ForEach(viewModel.groups) { group in
                Section {
                    ForEach(group.expenses) { expense in
                        NavigationLink(value: expense) {
                            // Date is redundant inside a date-grouped section.
                            ExpenseListItem(expense: expense, showsDate: false)
                        }
                        .listRowBackground(AppTheme.Colors.card)
                        .listRowSeparatorTint(AppTheme.Colors.divider)
                    }
                } header: {
                    TransactionGroupHeader(group: group)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel.load() }
    }
}

#if DEBUG

// MARK: - Preview

#Preview("Transactions") {
    TransactionsView(container: .preview)
        .environmentObject(DIContainer.previewCurrencyStore)
}

#endif
