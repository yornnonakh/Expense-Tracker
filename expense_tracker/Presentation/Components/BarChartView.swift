//
//  BarChartView.swift
//  Presentation Layer — Components
//
//  Weekly spending bars for the dashboard.
//

import SwiftUI

// MARK: - Single bar

/// One column: value label, bar, day label.
struct BarChartItem: View {

    let day: DailySpending
    /// Largest value in the series, used to scale every bar consistently.
    let maxAmount: Double
    var isToday: Bool = false
    var barWidth: CGFloat = 26

    /// Height as a fraction of the plot area.
    ///
    /// A flat-zero week would divide by zero, so that case returns 0 and every
    /// bar renders as the minimum stub instead of NaN.
    private var fraction: CGFloat {
        guard maxAmount > 0, day.amount > 0 else { return 0 }
        return CGFloat(day.amount / maxAmount)
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xxs) {

            // Only label bars that have spending, otherwise the axis is
            // cluttered with "$0" on every empty day.
            Text(day.amount > 0 ? AppFormatters.abbreviatedCurrency(day.amount) : "")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            GeometryReader { proxy in
                VStack {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            isToday
                                ? AnyShapeStyle(AppTheme.Colors.primaryGradient)
                                : AnyShapeStyle(AppTheme.Colors.primary.opacity(0.35))
                        )
                        // A 4pt floor keeps empty days visible as a baseline
                        // tick rather than vanishing entirely.
                        .frame(
                            width: barWidth,
                            height: max(4, proxy.size.height * fraction)
                        )
                }
                .frame(maxWidth: .infinity)
            }

            Text(day.shortWeekdayLabel)
                .font(.system(size: 11, weight: isToday ? .bold : .regular))
                .foregroundStyle(
                    isToday ? AppTheme.Colors.primary : AppTheme.Colors.textSecondary
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(AppFormatters.mediumDate(day.date)): "
            + AppFormatters.currency(day.amount)
        )
    }
}

// MARK: - Chart

/// The full seven-bar weekly chart.
struct WeeklyBarChartView: View {

    let days: [DailySpending]
    var height: CGFloat = AppTheme.Metrics.chartHeight

    private var maxAmount: Double {
        days.map(\.amount).max() ?? 0
    }

    private var total: Double {
        days.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {

            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Spacer()

                Text(AppFormatters.currency(total))
                    .font(AppTheme.Typography.amount)
                    .foregroundStyle(AppTheme.Colors.primary)
            }

            if days.isEmpty {
                Text("No spending recorded yet.")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: height)
            } else {
                HStack(alignment: .bottom, spacing: AppTheme.Spacing.xxs) {
                    ForEach(days) { day in
                        BarChartItem(
                            day: day,
                            maxAmount: maxAmount,
                            isToday: Calendar.current.isDateInToday(day.date)
                        )
                    }
                }
                .frame(height: height)
                .animation(AppTheme.Motion.standard, value: days)
            }
        }
        .cardStyle()
    }
}

#if DEBUG

// MARK: - Preview

#Preview("Weekly chart") {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let amounts: [Double] = [42, 0, 118, 64, 12, 96, 51]

    let days: [DailySpending] = amounts.enumerated().compactMap { index, amount in
        guard let date = calendar.date(
            byAdding: .day, value: index - 6, to: today
        ) else { return nil }
        return DailySpending(date: date, amount: amount)
    }

    return WeeklyBarChartView(days: days)
        .padding()
        .screenBackground()
}

#endif
