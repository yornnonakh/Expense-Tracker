//
//  BudgetView.swift
//  Presentation Layer — Views — Tab 5
//
//  Per-category budgets with progress, warnings and editing.
//

import SwiftUI

struct BudgetView: View {

    @StateObject private var viewModel: BudgetViewModel
    @State private var budgetPendingDeletion: BudgetStatus?

    init(container: DIContainer = .shared) {
        _viewModel = StateObject(wrappedValue: container.makeBudgetViewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.md) {

                    DateRangePicker(
                        selection: $viewModel.dateRange,
                        options: [.thisMonth, .lastMonth, .thisYear]
                    )

                    if let errorMessage = viewModel.errorMessage {
                        ErrorBanner(
                            message: errorMessage,
                            isRetryable: viewModel.errorIsRetryable,
                            onRetry: { Task { await viewModel.retry() } },
                            onDismiss: { viewModel.clearError() }
                        )
                    }

                    if !viewModel.hasLoadedOnce && viewModel.isLoading {
                        ExpenseListSkeleton(rowCount: 3)
                    } else if !viewModel.hasBudgets {
                        emptyState
                    } else {
                        overviewCard
                        exceededWarning
                        budgetCards
                    }
                }
                .padding(AppTheme.Spacing.md)
            }
            .screenBackground()
            .navigationTitle("Budgets")
            // Inline for the same reason as Statistics: a `ScrollView` whose
            // content height jumps when the skeleton is replaced would open
            // already scrolled past the Overall summary card.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.beginAdding()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(!viewModel.canAddBudget)
                    .accessibilityLabel("Add budget")
                }
            }
            .refreshable { await viewModel.load() }
        }
        .sheet(isPresented: $viewModel.isPresentingEditor) {
            BudgetEditorSheet(viewModel: viewModel)
        }
        .confirmationDialog(
            "Delete this budget?",
            isPresented: Binding(
                get: { budgetPendingDeletion != nil },
                set: { if !$0 { budgetPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = budgetPendingDeletion {
                    Task { await viewModel.deleteBudget(target) }
                }
                budgetPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { budgetPendingDeletion = nil }
        } message: {
            Text("Your expenses stay; only the limit is removed.")
        }
        .toast(message: $viewModel.toastMessage)
        // Budget progress moves when either a budget or an expense changes,
        // so this screen watches both streams.
        .task { await viewModel.start() }
        .task { await viewModel.observeExpenseChanges() }
    }

    // MARK: - Sections

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text("Overall")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer()
                Text("\(viewModel.budgetStatuses.count) budgets")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xxs) {
                Text(AppFormatters.currency(viewModel.summary.remaining))
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(
                        viewModel.summary.isOverBudget
                            ? AppTheme.Colors.danger
                            : AppTheme.Colors.textPrimary
                    )
                Text("left of \(AppFormatters.currency(viewModel.summary.totalLimit))")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            ProgressBarView(
                fraction: viewModel.summary.fractionUsed,
                tint: viewModel.summary.isOverBudget
                    ? AppTheme.Colors.danger
                    : AppTheme.Colors.primary
            )
        }
        .cardStyle()
    }

    @ViewBuilder
    private var exceededWarning: some View {
        if !viewModel.exceededBudgets.isEmpty {
            let names = viewModel.exceededBudgets
                .map(\.category.displayName)
                .joined(separator: ", ")

            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.Colors.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Over budget")
                        .font(AppTheme.Typography.callout)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(names)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Spacer()
            }
            .padding(AppTheme.Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(AppTheme.Colors.danger.opacity(0.12))
            }
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }

    private var budgetCards: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ForEach(viewModel.budgetStatuses) { status in
                BudgetCard(
                    status: status,
                    onEdit: { viewModel.beginEditing(status) },
                    onDelete: { budgetPendingDeletion = status }
                )
            }
        }
        .animation(AppTheme.Motion.standard, value: viewModel.budgetStatuses)
    }

    private var emptyState: some View {
        EmptyStateView(
            title: "No budgets set",
            message: "Set a limit for a category and track how much is left "
                + "as you spend.",
            systemImage: "target",
            actionTitle: viewModel.canAddBudget ? "Create a Budget" : nil
        ) {
            viewModel.beginAdding()
        }
        .cardStyle()
    }
}

// MARK: - Editor sheet

/// Add / edit form for a single budget.
private struct BudgetEditorSheet: View {

    @ObservedObject var viewModel: BudgetViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {

                    if let errorMessage = viewModel.errorMessage {
                        ErrorBanner(message: errorMessage, onDismiss: {
                            viewModel.clearError()
                        })
                    }

                    // Category is fixed once a budget exists — changing it
                    // would silently retarget the limit and orphan the
                    // spending already measured against it.
                    if viewModel.isEditing {
                        lockedCategory
                    } else {
                        categoryPicker
                    }

                    AmountInputField(
                        title: "Monthly limit",
                        amountText: Binding(
                            get: { viewModel.limitText },
                            set: {
                                viewModel.limitText = $0
                                viewModel.limitChanged()
                            }
                        ),
                        errorMessage: viewModel.limitError
                    )

                    PrimaryButton(
                        title: viewModel.isEditing ? "Save Changes" : "Create Budget",
                        isLoading: viewModel.isSaving,
                        isEnabled: viewModel.canSave
                    ) {
                        Task { await viewModel.saveBudget() }
                    }
                }
                .padding(AppTheme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle(viewModel.editorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.cancelEditor() }
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var lockedCategory: some View {
        if let category = viewModel.selectedCategory {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("Category")
                    .font(AppTheme.Typography.captionBold)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                CategoryBadge(category: category, showsLabel: true)
            }
            .cardStyle()
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("Category")
                .font(AppTheme.Typography.captionBold)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            if viewModel.availableCategories.isEmpty {
                Text("Every category already has a budget.")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            } else {
                CategorySelector(
                    selected: $viewModel.selectedCategory,
                    // Only categories without a budget: creating a second one
                    // for the same category is rejected by the domain anyway.
                    categories: viewModel.availableCategories
                )
            }
        }
        .cardStyle()
    }
}

// MARK: - Preview

#Preview("Budgets") {
    BudgetView(container: .preview)
}
