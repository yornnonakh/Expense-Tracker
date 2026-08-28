//
//  AddExpenseSheetView.swift
//  Presentation Layer — Views
//

import SwiftUI

struct AddExpenseSheetView: View {

    @StateObject private var viewModel: AddExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    /// Pre-selects a category when the sheet is opened from a category
    /// context (e.g. an empty budget card).
    private let initialCategory: ExpenseCategory?

    init(initialCategory: ExpenseCategory? = nil, container: DIContainer? = nil) {
        // `nil` rather than `= .shared`; see `DIContainer.shared`.
        let container = container ?? .shared
        self.initialCategory = initialCategory
        _viewModel = StateObject(wrappedValue: container.makeAddExpenseViewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {

                    if let errorMessage = viewModel.errorMessage {
                        ErrorBanner(
                            message: errorMessage,
                            isRetryable: viewModel.errorIsRetryable,
                            onRetry: { Task { await viewModel.save() } },
                            onDismiss: { viewModel.clearError() }
                        )
                    }

                    AmountInputField(
                        title: "Amount",
                        amountText: Binding(
                            get: { viewModel.draft.amountText },
                            set: {
                                viewModel.draft.amountText = $0
                                viewModel.amountChanged()
                            }
                        ),
                        errorMessage: viewModel.amountError
                    )

                    descriptionField

                    categoryField

                    dateField
                }
                .padding(AppTheme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await viewModel.save() }
                    }
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.primary)
                    .disabled(!viewModel.canSave)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(
                    title: "Save Expense",
                    systemImage: "checkmark",
                    isLoading: viewModel.isLoading,
                    isEnabled: viewModel.canSave
                ) {
                    Task { await viewModel.save() }
                }
                .padding(AppTheme.Spacing.md)
                .background(.ultraThinMaterial)
            }
        }
        .onAppear {
            // Seed the pre-selected category once, on first presentation.
            if viewModel.draft.category == nil, let initialCategory {
                viewModel.draft.category = initialCategory
            }
        }
        // Dismissal is driven by the view model's success flag rather than
        // inline in the button, so the sheet closes only after the write
        // actually committed.
        .onChange(of: viewModel.isSuccess) { _, isSuccess in
            if isSuccess { dismiss() }
        }
    }

    // MARK: - Fields

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            CustomTextField(
                title: "Description",
                text: Binding(
                    get: { viewModel.draft.description },
                    set: {
                        viewModel.draft.description = $0
                        viewModel.descriptionChanged()
                    }
                ),
                placeholder: "What was it for?",
                systemImage: "text.alignleft",
                errorMessage: viewModel.descriptionError
            )

            HStack {
                Spacer()
                Text("\(viewModel.draft.description.count)/\(viewModel.descriptionCharacterLimit)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(
                        viewModel.draft.description.count > viewModel.descriptionCharacterLimit
                            ? AppTheme.Colors.danger
                            : AppTheme.Colors.textSecondary
                    )
            }
        }
        .cardStyle()
    }

    private var categoryField: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("Category")
                .font(AppTheme.Typography.captionBold)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            CategorySelector(
                selected: Binding(
                    get: { viewModel.draft.category },
                    set: {
                        viewModel.draft.category = $0
                        viewModel.categoryChanged()
                    }
                )
            )

            if let categoryError = viewModel.categoryError {
                Label(categoryError, systemImage: "exclamationmark.circle.fill")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.danger)
            }
        }
        .cardStyle()
    }

    private var dateField: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("Date")
                .font(AppTheme.Typography.captionBold)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            DatePicker(
                "Date",
                selection: $viewModel.draft.date,
                // Future-dated spending isn't a thing you can have already
                // done, so the picker stops at today.
                in: ...Date(),
                displayedComponents: [.date]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(AppTheme.Colors.primary)
        }
        .cardStyle()
    }
}

// MARK: - Preview

#Preview("Add expense") {
    AddExpenseSheetView(container: .preview)
}
