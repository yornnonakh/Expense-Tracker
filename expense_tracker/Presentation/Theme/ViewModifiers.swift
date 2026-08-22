//
//  ViewModifiers.swift
//  Presentation Layer — Theme
//
//  Reusable styling, expressed as modifiers so the same look is applied by
//  writing `.cardStyle()` rather than by copy-pasting five lines of chrome.
//

import SwiftUI

// MARK: - Card

/// The standard white/dark elevated surface used for nearly every panel.
struct CardStyleModifier: ViewModifier {
    var padding: CGFloat = AppTheme.Spacing.md
    var cornerRadius: CGFloat = AppTheme.Radius.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: .black.opacity(AppTheme.Shadow.cardOpacity),
                radius: AppTheme.Shadow.cardRadius,
                x: 0,
                y: AppTheme.Shadow.cardY
            )
    }
}

// MARK: - Screen background

/// Paints the app background edge-to-edge behind a screen's content.
struct ScreenBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            AppTheme.Colors.background
                .ignoresSafeArea()
            content
        }
    }
}

// MARK: - Shake

/// Horizontal shake used to draw attention to a rejected form.
///
/// Implemented as a `GeometryEffect` so it animates on the render thread and
/// doesn't disturb layout — the field keeps its frame while it moves.
struct ShakeEffect: GeometryEffect {
    var travelDistance: CGFloat = 8
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = travelDistance * sin(animatableData * .pi * CGFloat(shakesPerUnit))
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

// MARK: - Conditional

extension View {

    func cardStyle(
        padding: CGFloat = AppTheme.Spacing.md,
        cornerRadius: CGFloat = AppTheme.Radius.lg
    ) -> some View {
        modifier(CardStyleModifier(padding: padding, cornerRadius: cornerRadius))
    }

    func screenBackground() -> some View {
        modifier(ScreenBackgroundModifier())
    }

    func shake(times: CGFloat) -> some View {
        modifier(ShakeEffect(animatableData: times))
    }

    /// Applies a transform only when `condition` holds.
    ///
    /// Use sparingly: it changes the view's type between branches, which can
    /// reset state. Fine for pure styling like the one below, not for
    /// swapping out content.
    @ViewBuilder
    func applyIf<Transformed: View>(
        _ condition: Bool,
        transform: (Self) -> Transformed
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Hides a view from VoiceOver when it is purely decorative.
    func decorative() -> some View {
        accessibilityHidden(true)
    }
}

