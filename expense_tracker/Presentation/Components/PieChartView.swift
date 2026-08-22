//
//  PieChartView.swift
//  Presentation Layer — Components
//
//  Interactive donut chart drawn with `Canvas`.
//
//  Canvas rather than a stack of `Path` views: one draw pass for all slices
//  instead of N view identities, which keeps the chart cheap to re-render when
//  the selection or the underlying data animates.
//
//  Hit-testing is done in polar coordinates — convert the tap into an angle
//  and radius, then find the slice whose arc contains that angle. That is far
//  more reliable than trying to attach gestures to individual arc shapes.
//

import SwiftUI

struct PieChartView: View {

    let slices: [CategoryBreakdown]

    /// Two-way so tapping a slice and tapping its legend row stay in sync.
    @Binding var selection: ExpenseCategory?

    var size: CGFloat = AppTheme.Metrics.pieChartSize
    /// Fraction of the radius left hollow. 0 draws a full pie.
    var innerRadiusRatio: CGFloat = 0.58

    /// Drives the sweep-in animation on first appearance.
    @State private var animationProgress: CGFloat = 0

    /// Precomputed slice geometry. Built once per data change rather than
    /// inside the draw closure, which runs on every frame of an animation.
    private var arcs: [PieArc] {
        var result: [PieArc] = []
        var start = Angle.degrees(-90)  // 12 o'clock

        for slice in slices where slice.fraction > 0 {
            let sweep = Angle.degrees(slice.fraction * 360)
            result.append(
                PieArc(
                    category: slice.category,
                    startAngle: start,
                    endAngle: start + sweep,
                    breakdown: slice
                )
            )
            start += sweep
        }
        return result
    }

    var body: some View {
        ZStack {
            canvas
            centerLabel
        }
        .frame(width: size, height: size)
        .onAppear {
            // Guard against re-triggering when the view is recycled.
            guard animationProgress == 0 else { return }
            withAnimation(.easeOut(duration: 0.7)) { animationProgress = 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spending by category chart")
        .accessibilityValue(accessibilitySummary)
    }

    // MARK: - Drawing

    private var canvas: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let outerRadius = min(canvasSize.width, canvasSize.height) / 2
            let innerRadius = outerRadius * innerRadiusRatio

            for arc in arcs {
                let isSelected = selection == arc.category
                let isDimmed = selection != nil && !isSelected

                // The selected slice pops outward slightly.
                let expansion: CGFloat = isSelected ? 8 : 0
                let path = donutSegment(
                    center: center,
                    innerRadius: innerRadius,
                    outerRadius: outerRadius - 8 + expansion,
                    startAngle: arc.startAngle,
                    // Multiplying the sweep by progress makes every slice
                    // grow from its own start angle, producing a clockwise
                    // wipe rather than a fade.
                    endAngle: arc.startAngle
                        + Angle.degrees(
                            (arc.endAngle - arc.startAngle).degrees
                                * Double(animationProgress)
                        )
                )

                context.fill(
                    path,
                    with: .color(
                        arc.category.color.opacity(isDimmed ? 0.28 : 1)
                    )
                )
            }
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    handleTap(at: value.location)
                }
        )
        .animation(AppTheme.Motion.spring, value: selection)
    }

    /// Builds a filled ring segment: outer arc forward, inner arc back.
    private func donutSegment(
        center: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        startAngle: Angle,
        endAngle: Angle
    ) -> Path {
        var path = Path()
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }

    // MARK: - Center label

    @ViewBuilder
    private var centerLabel: some View {
        VStack(spacing: 2) {
            if let selection, let slice = slices.first(where: { $0.category == selection }) {
                Text(selection.emoji).font(.system(size: 22))
                Text(AppFormatters.currency(slice.amount))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(AppFormatters.percentage(slice.fraction))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            } else {
                Text("Total")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(AppFormatters.currency(slices.reduce(0) { $0 + $1.amount }))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .frame(width: size * innerRadiusRatio * 1.4)
        .animation(AppTheme.Motion.quick, value: selection)
    }

    // MARK: - Hit testing

    /// Converts a tap in the canvas into the slice under the finger.
    private func handleTap(at location: CGPoint) {
        let center = CGPoint(x: size / 2, y: size / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)

        let outerRadius = size / 2
        let innerRadius = outerRadius * innerRadiusRatio

        // Taps in the hollow middle or outside the ring clear the selection.
        guard distance >= innerRadius, distance <= outerRadius else {
            withAnimation(AppTheme.Motion.spring) { selection = nil }
            return
        }

        // atan2 gives -180...180 measured from 3 o'clock. Rotate by 90° to
        // match the chart's 12 o'clock origin, then normalise to 0..<360.
        var degrees = atan2(dy, dx) * 180 / .pi + 90
        if degrees < 0 { degrees += 360 }

        let tapped = arcs.first { arc in
            var start = arc.startAngle.degrees + 90
            var end = arc.endAngle.degrees + 90
            if start < 0 { start += 360 }
            if end < 0 { end += 360 }

            // A slice that crosses the 360/0 boundary has end < start; it has
            // to be tested as two ranges.
            if end < start {
                return degrees >= start || degrees < end
            }
            return degrees >= start && degrees < end
        }

        Haptics.selection()
        withAnimation(AppTheme.Motion.spring) {
            // Tapping the active slice deselects it.
            selection = (selection == tapped?.category) ? nil : tapped?.category
        }
    }

    private var accessibilitySummary: String {
        guard !slices.isEmpty else { return "No spending recorded" }
        return slices
            .prefix(4)
            .map {
                "\($0.category.displayName) "
                + "\(AppFormatters.percentage($0.fraction))"
            }
            .joined(separator: ", ")
    }
}

/// One computed slice: which category, and the arc it occupies.
private struct PieArc {
    let category: ExpenseCategory
    let startAngle: Angle
    let endAngle: Angle
    let breakdown: CategoryBreakdown
}

// MARK: - Preview

#Preview("Pie chart") {
    struct Harness: View {
        @State private var selection: ExpenseCategory?

        private let slices = [
            CategoryBreakdown(category: .food, amount: 420, fraction: 0.42),
            CategoryBreakdown(category: .transport, amount: 240, fraction: 0.24),
            CategoryBreakdown(category: .shopping, amount: 180, fraction: 0.18),
            CategoryBreakdown(category: .utilities, amount: 100, fraction: 0.10),
            CategoryBreakdown(category: .health, amount: 60, fraction: 0.06)
        ]

        var body: some View {
            VStack(spacing: AppTheme.Spacing.lg) {
                PieChartView(slices: slices, selection: $selection)
                VStack(spacing: 0) {
                    ForEach(slices) { slice in
                        CategoryLegendRow(
                            breakdown: slice,
                            isHighlighted: selection == slice.category
                        )
                    }
                }
                .padding(.horizontal)
            }
            .padding()
            .screenBackground()
        }
    }
    return Harness()
}
