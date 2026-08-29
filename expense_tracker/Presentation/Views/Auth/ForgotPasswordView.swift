//
//  ForgotPasswordView.swift
//  Presentation Layer — Views
//

import SwiftUI

struct ForgotPasswordView: View {

    @StateObject private var viewModel: ForgotPasswordViewModel
    @Environment(\.dismiss) private var dismiss

    init(container: DIContainer? = nil) {
        // `nil` rather than `= .shared`; see `DIContainer.shared`.
        let container = container ?? .shared
        _viewModel = StateObject(wrappedValue: container.makeForgotPasswordViewModel())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                if viewModel.didSendReset {
                    successState
                } else {
                    requestState
                }
            }
            .padding(AppTheme.Spacing.lg)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle("Reset Password")
        .navigationBarTitleDisplayMode(.inline)
        .animation(AppTheme.Motion.spring, value: viewModel.didSendReset)
    }

    // MARK: - States

    private var requestState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {

            VStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(AppTheme.Colors.primary)
                    .frame(width: 72, height: 72)
                    .background(
                        Circle().fill(AppTheme.Colors.primary.opacity(0.12))
                    )

                Text("Forgot your password?")
                    .font(AppTheme.Typography.title2)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text("Enter the email you signed up with and we'll start the reset.")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, AppTheme.Spacing.lg)

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage, onDismiss: {
                    viewModel.clearError()
                })
            }

            CustomTextField(
                title: "Email",
                text: Binding(
                    get: { viewModel.email },
                    set: { viewModel.email = $0; viewModel.emailChanged() }
                ),
                placeholder: "you@example.com",
                systemImage: "envelope",
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                autocapitalization: .never,
                submitLabel: .send,
                errorMessage: viewModel.emailError,
                onSubmit: { Task { await viewModel.submit() } }
            )
            .cardStyle(padding: AppTheme.Spacing.lg)

            PrimaryButton(
                title: "Send Reset Link",
                isLoading: viewModel.isLoading,
                isEnabled: viewModel.canSubmit
            ) {
                Task { await viewModel.submit() }
            }
        }
    }

    private var successState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            EmptyStateView(
                title: "Check your inbox",
                message: "If an account exists for \(viewModel.email), "
                    + "you'll find reset instructions there.",
                systemImage: "envelope.badge.fill"
            )

            // This build has no mail backend. Saying so is more honest than
            // implying an email is on its way that will never arrive.
            Text(
                "Demo build: accounts live on this device only, "
                + "so no email is actually sent."
            )
            .font(AppTheme.Typography.caption)
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppTheme.Spacing.lg)

            VStack(spacing: AppTheme.Spacing.sm) {
                PrimaryButton(title: "Back to Sign In") {
                    dismiss()
                }
                SecondaryButton(title: "Use a different email") {
                    viewModel.reset()
                }
            }
        }
    }
}

#if DEBUG

// MARK: - Preview

#Preview("Forgot password") {
    NavigationStack {
        ForgotPasswordView(container: .makeEmptyPreview())
    }
}

#endif
