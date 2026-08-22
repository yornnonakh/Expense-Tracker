//
//  ExpenseDetailView.swift
//  Presentation Layer — Views
//

import SwiftUI

struct ExpenseDetailView: View {

    /// Local copy so an edit can update the screen without a round-trip
    /// through the parent list.
    @State private var expense: Expense

    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    private let container: DIContainer

    init(expense: Expense, container: DIContainer = .shared) {
        _expense = State(initialValue: expense)
        self.container = container
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {

                if let errorMessage {
                    ErrorBanner(message: errorMessage, onDismiss: {
                        self.errorMessage = nil
                    })
                    .padding(.horizontal, AppTheme.Spacing.md)
                }

                amountHeader

                details

                actions
            }
            .padding(.vertical, AppTheme.Spacing.md)
        }
        .screenBackground()
        .navigationTitle("Expense")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Edit expense")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditExpenseView(expense: expense, container: container)
        }
        // The edit sheet writes through the repository, which broadcasts.
        // Re-reading here keeps this screen truthful after an edit without
        // the sheet having to call back into it.
        .task(id: showEditSheet) {
            guard !showEditSheet else { return }
            await refresh()
        }
        .confirmationDialog(
            "Delete this expense?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await delete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    // MARK: - Sections

    private var amountHeader: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Text(expense.category.emoji)
                .font(.system(size: 40))
                .frame(width: 84, height: 84)
                .background(Circle().fill(expense.category.softColor))

            Text(AppFormatters.currency(expense.amount))
                .font(AppTheme.Typography.bigAmount)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(expense.description)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var details: some View {
        VStack(spacing: 0) {
            DetailRow(
                label: "Category",
                value: "\(expense.category.emoji)  \(expense.category.displayName)",
                systemImage: "square.grid.2x2"
            )
            ThemedDivider()
            DetailRow(
                label: "Date",
                value: AppFormatters.fullDateTime(expense.date),
                systemImage: "calendar"
            )
            ThemedDivider()
            DetailRow(
                label: "Amount",
                value: AppFormatters.currency(expense.amount),
                systemImage: "dollarsign.circle"
            )
            ThemedDivider()
            DetailRow(
                label: "Reference",
                // Short prefix is enough to identify a record without
                // showing an unreadable 36-character UUID.
                value: String(expense.id.uuidString.prefix(8)).uppercased(),
                systemImage: "number"
            )
        }
        .cardStyle()
        .padding(.horizontal, AppTheme.Spacing.md)
    }

    private var actions: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            PrimaryButton(title: "Edit Expense", systemImage: "square.and.pencil") {
                showEditSheet = true
            }
            DestructiveButton(title: "Delete Expense") {
                showDeleteConfirmation = true
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .opacity(isDeleting ? 0.5 : 1)
        .disabled(isDeleting)
    }

    // MARK: - Actions

    private func refresh() async {
        do {
            if let updated = try await container.expenseRepository.fetch(id: expense.id) {
                expense = updated
            } else {
                // Deleted from the edit sheet — nothing left to show.
                dismiss()
            }
        } catch {
            errorMessage = (error as? ExpenseError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await container.deleteExpenseUseCase.execute(id: expense.id)
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
            errorMessage = (error as? ExpenseError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview("Expense detail") {
    NavigationStack {
        ExpenseDetailView(
            expense: Expense(
                amount: 142.00,
                description: "New running shoes",
                category: .shopping,
                date: Date()
            ),
            container: .preview
        )
    }
}
