//
//  RootView.swift
//  Presentation Layer — Views
//
//  Chooses between the splash, the auth flow and the main app based on
//  session state. This is the only place that decision is made.
//

import SwiftUI

struct RootView: View {

    @EnvironmentObject private var authViewModel: AuthViewModel
    private let container: DIContainer

    init(container: DIContainer = .shared) {
        self.container = container
    }

    var body: some View {
        Group {
            switch authViewModel.state {
            case .restoring:
                SplashView()

            case .signedOut:
                NavigationStack {
                    SignInView(authViewModel: authViewModel, container: container)
                }

            case .signedIn:
                MainTabView(container: container)
            }
        }
        .animation(AppTheme.Motion.standard, value: authViewModel.state)
        // Auto-login runs once at launch. `.task` fires before the first
        // frame is shown, so a returning user goes straight to the dashboard
        // without the sign-in screen flashing.
        .task { await authViewModel.restore() }
    }
}

/// Shown for the moment it takes to check for a stored session.
struct SplashView: View {

    /// Drives a gentle pulse so the splash doesn't look frozen.
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "wallet.bifold.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 92, height: 92)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                        .fill(AppTheme.Colors.primaryGradient)
                )
                .scaleEffect(isAnimating ? 1.05 : 0.95)
                .animation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: isAnimating
                )

            Text("Expense Tracker")
                .font(AppTheme.Typography.title2)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            ProgressView()
                .tint(AppTheme.Colors.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .onAppear { isAnimating = true }
        .accessibilityLabel("Loading Expense Tracker")
    }
}

// MARK: - Preview

#Preview("Root") {
    let container = DIContainer.preview
    return RootView(container: container)
        .environmentObject(container.makeAuthViewModel())
}
