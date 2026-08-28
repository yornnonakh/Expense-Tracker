//
//  ExpensesListView.swift
//  Presentation Layer — Views — Tab 2
//
//  Filterable expense list with swipe actions.
//

import SwiftUI

struct ExpensesListView: View {

    @StateObject private var viewModel: ExpensesListViewModel

    @State private var showAddExpense = false
    @State private var expenseToEdit: Expense?

    private let container: DIContainer

    init(container: DIContainer? = nil) {
        // `nil` rather than `= .shared`; see `DIContainer.shared`.
        let container = container ?? .shared
        self.container = container
        _viewModel = StateObject(wrappedValue: container.makeExpensesListViewModel())
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    filterBar
                    summaryStrip
                    listContent
                }

                FloatingActionButton {
                    showAddExpense = true
                }
                .padding(AppTheme.Spacing.lg)
            }
            .screenBackground()
            .navigationTitle("Expenses")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { categoryMenu }
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Search description or category"
            )
            .navigationDestination(for: Expense.self) { expense in
                ExpenseDetailView(expense: expense, container: container)
            }
        }
        .sheet(isPresented: $showAddExpense) {
            AddExpenseSheetView(
                initialCategory: viewModel.selectedCategory,
                container: container
            )
        }
        .sheet(item: $expenseToEdit) { expense in
            EditExpenseView(expense: expense, container: container)
        }
        .toast(message: $viewModel.toastMessage)
        .task { await viewModel.start() }
    }

    // MARK: - Toolbar

    /// Dropdown category filter, mirroring the pill row for users who prefer
    /// a menu (and for when the pill row is scrolled out of reach).
    private var categoryMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    viewModel.selectedCategory = nil
                } label: {
                    Label("All categories", systemImage: "square.grid.2x2")
                }

                Divider()

                ForEach(ExpenseCategory.allCases) { category in
                    Button {
                        viewModel.selectedCategory = category
                    } label: {
                        Label(
                            "\(category.emoji)  \(category.displayName)",
                            systemImage: viewModel.selectedCategory == category
                                ? "checkmark"
                                : ""
                        )
                    }
                }

                if viewModel.isFiltering {
                    Divider()
                    Button(role: .destructive) {
                        viewModel.clearFilters()
                    } label: {
                        Label("Clear filters", systemImage: "xmark.circle")
                    }
                }
            } label: {
                Image(
                    systemName: viewModel.isFiltering
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }
            .accessibilityLabel("Filter by category")
        }
    }

    // MARK: - Sections

    private var filterBar: some View {
        CategoryFilterBar(
            selected: $viewModel.selectedCategory,
            counts: viewModel.categoryCounts
        )
        .padding(.top, AppTheme.Spacing.xxs)
    }

    @ViewBuilder
    private var summaryStrip: some View {
        if !viewModel.filteredExpenses.isEmpty {
            HStack {
                Text("\(viewModel.filteredExpenses.count) expenses")
                Spacer()
                Text(AppFormatters.currency(viewModel.filteredTotal))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .font(AppTheme.Typography.caption)
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.xs)
        }
    }

    @ViewBuilder
    private var listContent: some View {
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
        } else if viewModel.filteredExpenses.isEmpty {
            ScrollView {
                emptyState
                    .padding(.top, AppTheme.Spacing.xxl)
            }
        } else {
            expenseList
        }
    }

    private var expenseList: some View {
        List {
            ForEach(viewModel.filteredExpenses) { expense in
                NavigationLink(value: expense) {
                    ExpenseListItem(expense: expense)
                }
                .listRowBackground(AppTheme.Colors.card)
                .listRowSeparatorTint(AppTheme.Colors.divider)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await viewModel.delete(expense) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        expenseToEdit = expense
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(AppTheme.Colors.secondary)
                }
            }
            // Also wired so the system Edit mode and accessibility delete
            // both work, not just the swipe gesture.
            .onDelete { offsets in
                Task { await viewModel.delete(at: offsets) }
            }

            // Keeps the last row clear of the floating action button.
            Color.clear
                .frame(height: AppTheme.Metrics.fabSize)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel.load() }
    }

    private var emptyState: some View {
        Group {
            if viewModel.isFiltering {
                EmptyStateView(
                    title: "No matches",
                    message: "No expenses match the filters you've applied.",
                    systemImage: "line.3.horizontal.decrease.circle",
                    actionTitle: "Clear filters"
                ) {
                    viewModel.clearFilters()
                }
            } else {
                EmptyStateView(
                    title: "No expenses yet",
                    message: "Record your first expense and it'll show up here.",
                    systemImage: "creditcard",
                    actionTitle: "Add Expense"
                ) {
                    showAddExpense = true
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Expenses") {
    ExpensesListView(container: .preview)
}
