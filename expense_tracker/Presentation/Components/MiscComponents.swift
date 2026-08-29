//
//  MiscComponents.swift
//  Presentation Layer — Components
//
//  BudgetSummaryHeader, DateRangePicker, TransactionGroupHeader,
//  CategoryBreakdownRow, InfoRow, DetailRow.
//

import SwiftUI

// MARK: - Budget summary header

/// The dashboard's headline: how much of the total budget is left.
struct BudgetSummaryHeader: View {

    let summary: BudgetSummary
    let greeting: String
    let userName: String
    let initials: String
    /// The user's profile photo, when they have set one.
    var avatarImageData: Data?

    /// Total spending this month across ALL categories.
    ///
    /// Needed separately because `summary.totalSpent` only counts spending in
    /// categories that actually have a budget. Without this, a user who has
    /// recorded expenses but set no budgets would see "Spent this month
    /// $0.00" — the headline figure would silently ignore every unbudgeted
    /// category.
    let spentThisMonth: Double

    var onAvatarTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(userName)
                        .font(AppTheme.Typography.title2)
                        .foregroundStyle(.white)
                }

                Spacer()

                Button {
                    onAvatarTap?()
                } label: {
                    AvatarView(
                        initials: initials,
                        imageData: avatarImageData,
                        // Light fallback: a gradient circle would vanish into
                        // the gradient header behind it.
                        fallback: .light
                    )
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Account")
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(summary.hasBudgets ? "Budget remaining" : "Spent this month")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.white.opacity(0.85))

                Text(
                    AppFormatters.currency(
                        summary.hasBudgets ? summary.remaining : spentThisMonth
                    )
                )
                .font(AppTheme.Typography.bigAmount)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

                if summary.hasBudgets {
                    // Progress track drawn in white-on-white-alpha so it reads
                    // against the orange gradient in both appearances.
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.28))
                            Capsule()
                                .fill(.white)
                                .frame(width: proxy.size.width * summary.fractionUsed)
                        }
                    }
                    .frame(height: 8)
                    .padding(.top, AppTheme.Spacing.xxs)

                    HStack {
                        Text(
                            "\(AppFormatters.currency(summary.totalSpent)) of "
                            + AppFormatters.currency(summary.totalLimit)
                        )
                        Spacer()
                        if summary.exceededCount > 0 {
                            Label(
                                "\(summary.exceededCount) over",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                        }
                    }
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .fill(AppTheme.Colors.primaryGradient)
        }
        .shadow(color: AppTheme.Colors.primary.opacity(0.28), radius: 16, y: 8)
    }
}

// MARK: - Date range picker

/// Segmented control over `DateRangeFilter`.
struct DateRangePicker: View {

    @Binding var selection: DateRangeFilter
    var options: [DateRangeFilter] = DateRangeFilter.allCases

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let isSelected = selection == option

                Button {
                    Haptics.selection()
                    withAnimation(AppTheme.Motion.spring) { selection = option }
                } label: {
                    Text(option.displayName)
                        .font(AppTheme.Typography.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(
                            isSelected ? .white : AppTheme.Colors.textSecondary
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.xs)
                        .background {
                            if isSelected {
                                Capsule().fill(AppTheme.Colors.primary)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.displayName)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(AppTheme.Colors.card))
    }
}

// MARK: - Transaction group header

/// Date header above a day's transactions, with that day's total.
struct TransactionGroupHeader: View {

    let group: ExpenseDayGroup

    var body: some View {
        HStack {
            Text(AppFormatters.relativeDayLabel(group.day))
                .font(AppTheme.Typography.captionBold)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Spacer()

            Text(AppFormatters.currency(group.total))
                .font(AppTheme.Typography.captionBold)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .padding(.horizontal, AppTheme.Spacing.xs)
        .padding(.vertical, AppTheme.Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Category breakdown row

/// Category with an inline share bar — used in the Home tab's top-4 list.
struct CategoryBreakdownRow: View {

    let breakdown: CategoryBreakdown
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                CategoryBadge(category: breakdown.category, size: 38)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    HStack {
                        Text(breakdown.category.displayName)
                            .font(AppTheme.Typography.callout)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Spacer()
                        Text(AppFormatters.currency(breakdown.amount))
                            .font(AppTheme.Typography.callout)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }

                    ProgressBarView(
                        fraction: breakdown.fraction,
                        tint: breakdown.category.color,
                        height: 6
                    )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(breakdown.category.displayName), "
            + "\(AppFormatters.currency(breakdown.amount)), "
            + "\(AppFormatters.percentage(breakdown.fraction)) of total"
        )
    }
}

// MARK: - Detail row

/// Label/value pair used on the expense detail screen.
struct DetailRow: View {

    let label: String
    let value: String
    var systemImage: String?
    var valueColor: Color = AppTheme.Colors.textPrimary

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(width: 22)
            }

            Text(label)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Spacer(minLength: AppTheme.Spacing.md)

            Text(value)
                .font(AppTheme.Typography.callout)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, AppTheme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

/// Hairline separator that respects the theme.
struct ThemedDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.Colors.divider)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

#if DEBUG

// MARK: - Preview

#Preview("Misc") {
    struct Harness: View {
        @State private var range: DateRangeFilter = .thisMonth

        var body: some View {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    BudgetSummaryHeader(
                        summary: BudgetSummary(
                            totalLimit: 1200, totalSpent: 840,
                            exceededCount: 1, budgetCount: 5
                        ),
                        greeting: "Good evening",
                        userName: "Yorn",
                        initials: "YN",
                        spentThisMonth: 840
                    )
                    DateRangePicker(selection: $range)
                    CategoryBreakdownRow(
                        breakdown: CategoryBreakdown(
                            category: .food, amount: 320, fraction: 0.44
                        )
                    )
                    DetailRow(
                        label: "Category", value: "Food",
                        systemImage: "square.grid.2x2"
                    )
                }
                .padding()
            }
            .screenBackground()
        }
    }
    return Harness()
}

#endif
