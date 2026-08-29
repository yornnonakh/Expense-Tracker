//
//  Cards.swift
//  Presentation Layer — Components
//
//  StatisticCard, BudgetCard, ProgressBarView, SectionHeader, AvatarView.
//

import SwiftUI

// MARK: - Statistic card

/// A single headline metric: icon, caption, value.
struct StatisticCard: View {

    let title: String
    let value: String
    /// The same figure in riel, shown under the dollar value. Separate from
    /// `subtitle`, which already carries context like "per expense" — the two
    /// say different things and a card can want both.
    var secondaryValue: String?
    let systemImage: String
    var tint: Color = AppTheme.Colors.primary
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {

            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(tint.opacity(0.15)))

                Text(title)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(AppTheme.Typography.title2)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                // Long currency values shrink rather than truncate — a
                // clipped amount is worse than a slightly smaller one.
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            if let secondaryValue {
                Text(secondaryValue)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            if let subtitle {
                Text(subtitle)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            secondaryValue.map { "\(title): \(value), \($0)" } ?? "\(title): \(value)"
        )
    }
}

// MARK: - Progress bar

/// Rounded track + fill, driven by a 0...1 fraction.
struct ProgressBarView: View {

    /// Clamped by the caller; values outside 0...1 are clamped again here so
    /// a bad input can never draw outside the track.
    let fraction: Double
    var tint: Color = AppTheme.Colors.primary
    var height: CGFloat = AppTheme.Metrics.progressBarHeight

    private var safeFraction: CGFloat {
        // Also filters NaN, which would otherwise crash the layout engine.
        guard fraction.isFinite else { return 0 }
        return CGFloat(min(1, max(0, fraction)))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.Colors.divider)

                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * safeFraction)
            }
        }
        .frame(height: height)
        .animation(AppTheme.Motion.standard, value: safeFraction)
        .accessibilityHidden(true)
    }
}

// MARK: - Budget card

/// Category, limit, spent, remaining and a status-coloured progress bar.
struct BudgetCard: View {

    let status: BudgetStatus
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    /// Green under 80%, amber approaching the limit, red once over it.
    private var tint: Color {
        switch status.level {
        case .healthy:  return AppTheme.Colors.success
        case .warning:  return AppTheme.Colors.warning
        case .exceeded: return AppTheme.Colors.danger
        }
    }

    private var statusText: String {
        switch status.level {
        case .healthy, .warning:
            return "\(AppFormatters.currency(status.remaining)) left"
        case .exceeded:
            return "\(AppFormatters.currency(status.overspend)) over"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {

            HStack(spacing: AppTheme.Spacing.sm) {
                CategoryBadge(category: status.category, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(status.category.displayName)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    Text("Limit \(AppFormatters.currency(status.limit))")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                Spacer(minLength: AppTheme.Spacing.xs)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(AppFormatters.currency(status.spent))
                        .font(AppTheme.Typography.amount)
                        .foregroundStyle(tint)
                    Text(statusText)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }

            ProgressBarView(fraction: status.percentageUsed, tint: tint)

            HStack {
                Text("\(Int(status.rawPercentageUsed * 100))% used")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Spacer()

                if let onEdit {
                    Button("Edit", action: onEdit)
                        .font(AppTheme.Typography.captionBold)
                        .foregroundStyle(AppTheme.Colors.secondary)
                }

                if let onDelete {
                    Button("Delete", action: onDelete)
                        .font(AppTheme.Typography.captionBold)
                        .foregroundStyle(AppTheme.Colors.danger)
                }
            }

            // Only shown once the limit is actually breached, so the warning
            // keeps its weight.
            if status.isExceeded {
                Label(
                    "You've gone over this budget.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.danger)
                .padding(.top, 2)
                .transition(.opacity)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(status.category.displayName) budget. "
            + "Spent \(AppFormatters.currency(status.spent)) "
            + "of \(AppFormatters.currency(status.limit)). \(statusText)."
        )
    }
}

// MARK: - Section header

/// "Title  ·  optional action" row used above list sections.
struct SectionHeader: View {

    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AppTheme.Typography.title2)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(AppTheme.Typography.callout)
                    .foregroundStyle(AppTheme.Colors.primary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Avatar

/// The user's profile photo, falling back to their initials when there isn't
/// one — a missing or unreadable photo degrades to the initials circle rather
/// than to a gap.
struct AvatarView: View {

    /// How the initials circle looks when there is no photo. The photo itself
    /// looks the same either way.
    enum Fallback {
        /// White initials on the orange gradient. The default, for anywhere
        /// the avatar sits on a plain background.
        case gradient
        /// Orange initials on white, for use on the gradient header where a
        /// gradient circle would disappear into its backdrop.
        case light
    }

    let initials: String
    var imageData: Data?
    var size: CGFloat = AppTheme.Metrics.avatarSize
    var fallback: Fallback = .gradient

    /// Decoded once per photo rather than per render.
    ///
    /// `Image(uiImage:)` in `body` would re-decode the JPEG on every pass —
    /// including every dashboard refresh, since the avatar sits in the header
    /// that redraws with the budget figures.
    @State private var decodedImage: Image?

    var body: some View {
        Group {
            if let decodedImage {
                decodedImage
                    .resizable()
                    // Fill, not fit: a non-square photo must cover the circle,
                    // and `clipShape` trims the overflow.
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(initialsColor)
                    .frame(width: size, height: size)
                    .background(Circle().fill(fallbackFill))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: imageData) { decode() }
        .accessibilityHidden(true)
    }

    private var initialsColor: Color {
        switch fallback {
        case .gradient: return .white
        case .light: return AppTheme.Colors.primary
        }
    }

    private var fallbackFill: AnyShapeStyle {
        switch fallback {
        case .gradient: return AnyShapeStyle(AppTheme.Colors.primaryGradient)
        case .light: return AnyShapeStyle(Color.white)
        }
    }

    private func decode() {
        decodedImage = imageData
            .flatMap(UIImage.init(data:))
            .map(Image.init(uiImage:))
    }
}

#if DEBUG

// MARK: - Preview

#Preview("Cards") {
    ScrollView {
        VStack(spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                StatisticCard(
                    title: "Total", value: "$1,284.50",
                    systemImage: "creditcard.fill"
                )
                StatisticCard(
                    title: "Average", value: "$64.20",
                    systemImage: "chart.bar.fill",
                    tint: AppTheme.Colors.secondary
                )
            }

            BudgetCard(
                status: BudgetStatus(
                    budget: Budget(category: .food, limit: 400), spent: 312
                ),
                onEdit: {}, onDelete: {}
            )
            BudgetCard(
                status: BudgetStatus(
                    budget: Budget(category: .shopping, limit: 200), spent: 268
                ),
                onEdit: {}, onDelete: {}
            )

            SectionHeader(title: "Recent", actionTitle: "See all") {}
            AvatarView(initials: "YN")
        }
        .padding()
    }
    .screenBackground()
}

#endif
