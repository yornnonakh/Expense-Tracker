//
//  Buttons.swift
//  Presentation Layer — Components
//
//  PrimaryButton, SecondaryButton, FloatingActionButton, IconButton.
//

import SwiftUI

// MARK: - Primary

/// Filled orange call-to-action, 50pt tall.
///
/// Owns its own busy/disabled presentation so no screen has to remember to
/// swap the label for a spinner — pass `isLoading` and it handles both the
/// visuals and blocking the tap.
struct PrimaryButton: View {

    let title: String
    var systemImage: String?
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    /// Whether a tap should do anything. Busy counts as non-interactive, so a
    /// second tap can't fire the action while the first is still in flight.
    private var isInteractive: Bool { isEnabled && !isLoading }

    /// Whether to fade the button out.
    ///
    /// Deliberately NOT `!isInteractive`. Callers typically compute their
    /// `isEnabled` flag as something like `isFormValid && !isLoading`, so
    /// during a save the button arrives here disabled *and* loading. Fading on
    /// `!isInteractive` would then dim the whole control — spinner included —
    /// and a working button would read as a dead one. Busy keeps full opacity;
    /// only a genuinely unavailable button is dimmed.
    private var isDimmed: Bool { !isEnabled && !isLoading }

    var body: some View {
        Button(action: {
            guard isInteractive else { return }
            action()
        }) {
            ZStack {
                // Label stays in the hierarchy while loading, just hidden, so
                // the button never changes width mid-tap.
                HStack(spacing: AppTheme.Spacing.xs) {
                    if let systemImage {
                        Image(systemName: systemImage)
                    }
                    Text(title)
                }
                .font(AppTheme.Typography.headline)
                .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.Metrics.buttonHeight)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(AppTheme.Colors.primaryGradient)
            }
            .opacity(isDimmed ? 0.55 : 1)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isInteractive)
        .accessibilityLabel(title)
        // Announce the busy state rather than leaving a silent disabled
        // control; an empty hint string would be read as no hint at all.
        .accessibilityValue(isLoading ? "Busy" : "")
        .accessibilityAddTraits(isLoading ? [.updatesFrequently] : [])
    }
}

// MARK: - Secondary

/// Blue outline, transparent fill.
struct SecondaryButton: View {

    let title: String
    var systemImage: String?
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(AppTheme.Typography.headline)
            .foregroundStyle(AppTheme.Colors.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.Metrics.buttonHeight)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(AppTheme.Colors.secondary, lineWidth: 1.5)
            }
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }
}

// MARK: - Destructive

/// Red outline, for delete actions that need confirmation.
struct DestructiveButton: View {

    let title: String
    var systemImage: String? = "trash"
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            HStack(spacing: AppTheme.Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(AppTheme.Typography.headline)
            .foregroundStyle(AppTheme.Colors.danger)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.Metrics.buttonHeight)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(AppTheme.Colors.danger.opacity(0.12))
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - Floating action button

/// Circular "+" that floats above scrolling content.
struct FloatingActionButton: View {

    var systemImage: String = "plus"
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.impact()
            action()
        }) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(
                    width: AppTheme.Metrics.fabSize,
                    height: AppTheme.Metrics.fabSize
                )
                .background {
                    Circle().fill(AppTheme.Colors.primaryGradient)
                }
                .shadow(
                    color: AppTheme.Colors.primary.opacity(0.35),
                    radius: 12, x: 0, y: 6
                )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Add expense")
    }
}

// MARK: - Icon button

/// Small circular icon button used in toolbars and card corners.
struct IconButton: View {

    let systemImage: String
    var tint: Color = AppTheme.Colors.textSecondary
    var background: Color = AppTheme.Colors.card
    var accessibilityLabelText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(background))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(accessibilityLabelText)
    }
}

// MARK: - Press feedback

/// Subtle scale-down on press. Applied to every custom button so tap feedback
/// is consistent, since a plain `Button` label gets none by default.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(AppTheme.Motion.quick, value: configuration.isPressed)
    }
}

#if DEBUG

// MARK: - Previews

#Preview("Buttons") {
    VStack(spacing: AppTheme.Spacing.md) {
        PrimaryButton(title: "Save Expense", systemImage: "checkmark") {}
        PrimaryButton(title: "Saving", isLoading: true) {}
        PrimaryButton(title: "Disabled", isEnabled: false) {}
        SecondaryButton(title: "Cancel") {}
        DestructiveButton(title: "Delete Expense") {}
        HStack {
            FloatingActionButton {}
            IconButton(
                systemImage: "pencil",
                accessibilityLabelText: "Edit"
            ) {}
        }
    }
    .padding()
    .screenBackground()
}

#endif
