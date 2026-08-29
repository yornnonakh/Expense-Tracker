//
//  ExpenseListItem.swift
//  Presentation Layer — Components
//
//  The expense row, used by the Expenses, Transactions and Home screens.
//

import SwiftUI

struct ExpenseListItem: View {

    @EnvironmentObject private var currency: CurrencyStore

    let expense: Expense

    /// Hidden inside date-grouped sections, where the header already says it.
    var showsDate: Bool = true
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {

            CategoryBadge(category: expense.category)

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.description)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: AppTheme.Spacing.xxs) {
                    Text(expense.category.displayName)
                    if showsDate {
                        Text("·")
                        Text(AppFormatters.dayAndMonth(expense.date))
                    }
                }
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1)
            }

            Spacer(minLength: AppTheme.Spacing.xs)

            // Dollars lead and keep the amount typography; riel sits under
            // them in caption style. Stacked rather than inline because a row
            // is already tight, and two full-size figures would fight for the
            // same horizontal space on a narrow phone.
            VStack(alignment: .trailing, spacing: 0) {
                Text(AppFormatters.currency(expense.amount))
                    .font(AppTheme.Typography.amount)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(currency.riel(expense.amount))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
        .contentShape(Rectangle())
        // Collapse the row into one VoiceOver element reading as a sentence,
        // rather than four separate labels the user has to swipe through.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(expense.description), \(expense.category.displayName), "
            + "\(AppFormatters.currency(expense.amount)), "
            + "\(currency.riel(expense.amount)), "
            + AppFormatters.mediumDate(expense.date)
        )
    }
}

/// Card-wrapped variant for the dashboard's recent-transactions preview.
struct ExpenseRowCard: View {

    let expense: Expense

    var body: some View {
        ExpenseListItem(expense: expense, showsChevron: true)
            .cardStyle(padding: AppTheme.Spacing.sm)
    }
}

#if DEBUG

// MARK: - Preview

#Preview("Expense rows") {
    VStack(spacing: AppTheme.Spacing.sm) {
        ExpenseRowCard(
            expense: Expense(
                amount: 24.50, description: "Lunch with Sara",
                category: .food, date: Date()
            )
        )
        ExpenseRowCard(
            expense: Expense(
                amount: 1284.00, description: "New laptop for work",
                category: .shopping, date: Date()
            )
        )
    }
    .padding()
    .environmentObject(DIContainer.previewCurrencyStore)
    .screenBackground()
}

#endif
