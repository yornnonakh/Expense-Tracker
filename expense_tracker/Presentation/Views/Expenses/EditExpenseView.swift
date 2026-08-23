//
//  EditExpenseView.swift
//  Presentation Layer — Views
//

import SwiftUI

struct EditExpenseView: View {

    @StateObject private var viewModel: EditExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirmation = false
    @State private var showDiscardConfirmation = false

    init(expense: Expense, container: DIContainer = .shared) {
        _viewModel = StateObject(
            wrappedValue: container.makeEditExpenseViewModel(expense: expense)
        )
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

                    DestructiveButton(title: "Delete Expense") {
                        showDeleteConfirmation = true
                    }
                    .padding(.top, AppTheme.Spacing.xs)
                }
                .padding(AppTheme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle("Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Guard unsaved edits — silently discarding typed
                        // changes on a stray tap is the classic form bug.
                        if viewModel.hasChanges {
                            showDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
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
                    title: "Save Changes",
                    systemImage: "checkmark",
                    isLoading: viewModel.isLoading,
                    isEnabled: viewModel.canSave
                ) {
                    Task { await viewModel.save() }
                }
                .padding(AppTheme.Spacing.md)
                .background(.ultraThinMaterial)
            }
            .confirmationDialog(
                "Delete this expense?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task { await viewModel.delete() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
            .confirmationDialog(
                "Discard your changes?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
        }
        .onChange(of: viewModel.isSuccess) { _, isSuccess in
            if isSuccess { dismiss() }
        }
        .onChange(of: viewModel.didDelete) { _, didDelete in
            if didDelete { dismiss() }
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
                    .foregroundStyle(AppTheme.Colors.textSecondary)
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
            HStack {
                Text("Date")
                    .font(AppTheme.Typography.captionBold)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Spacer()
                if viewModel.hasChanges {
                    Button("Revert") { viewModel.revert() }
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.secondary)
                }
            }

            DatePicker(
                "Date",
                selection: $viewModel.draft.date,
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

#Preview("Edit expense") {
    EditExpenseView(
        expense: Expense(
            amount: 42.50,
            description: "Dinner with friends",
            category: .food,
            date: Date()
        ),
        container: .preview
    )
}
