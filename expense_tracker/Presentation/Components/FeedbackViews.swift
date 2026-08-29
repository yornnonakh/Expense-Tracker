//
//  FeedbackViews.swift
//  Presentation Layer — Components
//
//  ErrorBanner, EmptyStateView, LoadingOverlay, SkeletonView, ToastView.
//
//  Every screen needs the same three non-happy states — loading, empty and
//  failed — so they live here once instead of being re-improvised per screen.
//

import SwiftUI

// MARK: - Error banner

/// Dismissible error strip pinned to the top of a screen, with an optional
/// Retry for failures that are actually worth retrying.
struct ErrorBanner: View {

    let message: String
    var isRetryable: Bool = false
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.Colors.danger)

            Text(message)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isRetryable, let onRetry {
                Button("Retry", action: onRetry)
                    .font(AppTheme.Typography.captionBold)
                    .foregroundStyle(AppTheme.Colors.secondary)
            }

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .accessibilityLabel("Dismiss error")
            }
        }
        .padding(AppTheme.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.Colors.danger.opacity(0.12))
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(AppTheme.Colors.danger.opacity(0.35), lineWidth: 1)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        // Announced by VoiceOver as soon as it appears.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Empty state

/// Icon + headline + explanation, with an optional call to action.
struct EmptyStateView: View {

    let title: String
    let message: String
    var systemImage: String = "tray"
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {

            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AppTheme.Colors.primary.opacity(0.7))
                .frame(width: 88, height: 88)
                .background(Circle().fill(AppTheme.Colors.primary.opacity(0.10)))

            VStack(spacing: AppTheme.Spacing.xxs) {
                Text(title)
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(message)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppTheme.Spacing.xl)
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .background(Capsule().fill(AppTheme.Colors.primaryGradient))
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(AppTheme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Loading

/// Full-screen dimmed spinner for blocking operations.
struct LoadingOverlay: View {

    var message: String = "Loading"

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: AppTheme.Spacing.sm) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppTheme.Colors.primary)
                Text(message)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(AppTheme.Spacing.lg)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .fill(AppTheme.Colors.card)
            }
            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        }
        .transition(.opacity)
        .accessibilityLabel(message)
    }
}

// MARK: - Skeleton

/// Shimmering placeholder shown while the first load is in flight.
///
/// Preferred over a spinner for list content: it communicates the shape of
/// what's coming, so the screen doesn't visibly reflow when data lands.
struct SkeletonView: View {

    var height: CGFloat = 16
    var cornerRadius: CGFloat = AppTheme.Radius.sm

    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppTheme.Colors.divider)
            .frame(height: height)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [
                            .clear,
                            AppTheme.Colors.card.opacity(0.65),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.5)
                    .offset(x: shimmerOffset * proxy.size.width * 1.5)
                }
            }
            .clipShape(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1
                }
            }
            .accessibilityHidden(true)
    }
}

/// A few skeleton rows shaped like `ExpenseListItem`.
struct ExpenseListSkeleton: View {

    var rowCount: Int = 5

    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ForEach(0..<rowCount, id: \.self) { _ in
                HStack(spacing: AppTheme.Spacing.sm) {
                    Circle()
                        .fill(AppTheme.Colors.divider)
                        .frame(
                            width: AppTheme.Metrics.iconCircle,
                            height: AppTheme.Metrics.iconCircle
                        )
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                        SkeletonView(height: 14)
                            .frame(maxWidth: .infinity)
                        SkeletonView(height: 10)
                            .frame(maxWidth: 120)
                    }
                    SkeletonView(height: 14)
                        .frame(width: 60)
                }
                .padding(AppTheme.Spacing.sm)
                .background {
                    RoundedRectangle(
                        cornerRadius: AppTheme.Radius.lg, style: .continuous
                    )
                    .fill(AppTheme.Colors.card)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Toast

/// Transient success confirmation that slides in from the top.
struct ToastView: View {

    let message: String
    var systemImage: String = "checkmark.circle.fill"
    var tint: Color = AppTheme.Colors.success

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(message)
                .font(AppTheme.Typography.callout)
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background {
            Capsule().fill(AppTheme.Colors.card)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}

/// Presents a toast over any view and clears it automatically.
struct ToastModifier: ViewModifier {

    @Binding var message: String?
    var duration: TimeInterval = 2

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    ToastView(message: message)
                        .padding(.top, AppTheme.Spacing.xs)
                        // Keyed on the message so a second toast restarts the
                        // timer instead of inheriting the first one's.
                        .task(id: message) {
                            try? await Task.sleep(
                                for: .seconds(duration)
                            )
                            // Cancellation means the view went away or a new
                            // toast replaced this one; don't clear in that case.
                            guard !Task.isCancelled else { return }
                            withAnimation(AppTheme.Motion.standard) {
                                self.message = nil
                            }
                        }
                }
            }
            .animation(AppTheme.Motion.spring, value: message)
    }
}

extension View {
    /// Shows a toast whenever `message` becomes non-nil.
    func toast(message: Binding<String?>, duration: TimeInterval = 2) -> some View {
        modifier(ToastModifier(message: message, duration: duration))
    }
}

#if DEBUG

// MARK: - Preview

#Preview("Feedback") {
    ScrollView {
        VStack(spacing: AppTheme.Spacing.lg) {
            ErrorBanner(
                message: "We couldn't save your changes.",
                isRetryable: true,
                onRetry: {},
                onDismiss: {}
            )
            ToastView(message: "Expense saved")
            EmptyStateView(
                title: "No expenses yet",
                message: "Add your first expense to see it here.",
                systemImage: "creditcard",
                actionTitle: "Add Expense",
                action: {}
            )
            ExpenseListSkeleton(rowCount: 3)
        }
        .padding()
    }
    .screenBackground()
}

#endif
