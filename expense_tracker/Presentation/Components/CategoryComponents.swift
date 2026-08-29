//
//  CategoryComponents.swift
//  Presentation Layer — Components
//
//  CategoryBadge, CategorySelector, FilterPill, CategoryLegendRow.
//

import SwiftUI

// MARK: - Category badge

/// Emoji inside a tinted circle, optionally captioned with the category name.
struct CategoryBadge: View {

    let category: ExpenseCategory
    var size: CGFloat = AppTheme.Metrics.iconCircle
    var showsLabel: Bool = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(category.emoji)
                .font(.system(size: size * 0.45))
                .frame(width: size, height: size)
                .background(Circle().fill(category.softColor))

            if showsLabel {
                Text(category.displayName)
                    .font(AppTheme.Typography.callout)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
        }
        // One label for the pair, so VoiceOver reads "Food" rather than
        // announcing the emoji and the text as two separate elements.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.displayName)
    }
}

// MARK: - Category selector

/// Horizontally scrolling category picker used by the add/edit forms.
struct CategorySelector: View {

    @Binding var selected: ExpenseCategory?
    var categories: [ExpenseCategory] = ExpenseCategory.allCases

    /// When true, tapping the selected chip clears the selection.
    var allowsDeselection: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(categories) { category in
                    chip(for: category)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func chip(for category: ExpenseCategory) -> some View {
        let isSelected = selected == category

        Button {
            Haptics.selection()
            withAnimation(AppTheme.Motion.spring) {
                if isSelected && allowsDeselection {
                    selected = nil
                } else {
                    selected = category
                }
            }
        } label: {
            VStack(spacing: AppTheme.Spacing.xxs) {
                Text(category.emoji)
                    .font(.system(size: 22))
                    .frame(width: 52, height: 52)
                    .background {
                        Circle()
                            .fill(isSelected ? category.color : category.softColor)
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(
                                isSelected ? category.color : .clear,
                                lineWidth: 2
                            )
                            .padding(-3)
                    }

                Text(category.displayName)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(
                        isSelected ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary
                    )
                    .lineLimit(1)
            }
            .frame(width: 74)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(category.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Filter pill

/// Toggleable chip used for quick category filtering.
struct FilterPill: View {

    let title: String
    var emoji: String?
    var tint: Color = AppTheme.Colors.primary
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: AppTheme.Spacing.xxs) {
                if let emoji {
                    Text(emoji).font(.system(size: 13))
                }
                Text(title)
                    .font(AppTheme.Typography.callout)
            }
            .foregroundStyle(isSelected ? .white : AppTheme.Colors.textSecondary)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background {
                Capsule()
                    .fill(isSelected ? tint : AppTheme.Colors.card)
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        isSelected ? .clear : AppTheme.Colors.divider,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The full "All + one pill per category" filter row.
struct CategoryFilterBar: View {

    @Binding var selected: ExpenseCategory?
    /// Optional counts shown next to each pill.
    var counts: [ExpenseCategory: Int] = [:]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.xs) {

                FilterPill(
                    title: "All",
                    tint: AppTheme.Colors.primary,
                    isSelected: selected == nil
                ) {
                    withAnimation(AppTheme.Motion.quick) { selected = nil }
                }

                ForEach(ExpenseCategory.allCases) { category in
                    let count = counts[category]
                    FilterPill(
                        title: count.map { "\(category.displayName) \($0)" }
                            ?? category.displayName,
                        emoji: category.emoji,
                        tint: category.color,
                        isSelected: selected == category
                    ) {
                        withAnimation(AppTheme.Motion.quick) {
                            // Tapping the active pill clears it — a filter you
                            // can't switch off is a trap.
                            selected = (selected == category) ? nil : category
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.xxs)
        }
    }
}

// MARK: - Legend row

/// One line of the pie chart legend: swatch, name, amount, share.
struct CategoryLegendRow: View {

    let breakdown: CategoryBreakdown
    var isHighlighted: Bool = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {

            RoundedRectangle(cornerRadius: 3)
                .fill(breakdown.category.color)
                .frame(width: 12, height: 12)

            Text(breakdown.category.emoji)
                .font(.system(size: 13))

            Text(breakdown.category.displayName)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Spacer(minLength: AppTheme.Spacing.xs)

            Text(AppFormatters.currency(breakdown.amount))
                .font(AppTheme.Typography.callout)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text(AppFormatters.percentage(breakdown.fraction))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, AppTheme.Spacing.xs)
        .padding(.horizontal, AppTheme.Spacing.xs)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                .fill(isHighlighted ? breakdown.category.softColor : .clear)
        }
        .animation(AppTheme.Motion.quick, value: isHighlighted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(breakdown.category.displayName), "
            + "\(AppFormatters.currency(breakdown.amount)), "
            + "\(AppFormatters.percentage(breakdown.fraction)) of spending"
        )
    }
}

#if DEBUG

// MARK: - Preview

#Preview("Category components") {
    struct Harness: View {
        @State private var selected: ExpenseCategory? = .food
        @State private var filter: ExpenseCategory?

        var body: some View {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                CategoryBadge(category: .food, showsLabel: true)
                CategorySelector(selected: $selected)
                CategoryFilterBar(selected: $filter)
                CategoryLegendRow(
                    breakdown: CategoryBreakdown(
                        category: .transport, amount: 142.50, fraction: 0.32
                    )
                )
            }
            .padding(.vertical)
            .screenBackground()
        }
    }
    return Harness()
}

#endif
