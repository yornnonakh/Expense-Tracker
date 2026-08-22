//
//  SignInView.swift
//  Presentation Layer — Views
//

import SwiftUI

struct SignInView: View {

    @StateObject private var viewModel: SignInViewModel
    private let container: DIContainer

    /// Held as a plain reference, not `@ObservedObject`: this screen only
    /// forwards it to the sign-up screen and hands it to its own view model.
    /// Observing it here would redraw the form on unrelated session changes.
    private let authViewModel: AuthViewModel

    /// Local navigation within the auth flow.
    @State private var showSignUp = false
    @State private var showForgotPassword = false

    /// The container is a defaulted parameter, so previews and tests can hand
    /// in an isolated graph while production callers omit it.
    init(authViewModel: AuthViewModel, container: DIContainer = .shared) {
        self.container = container
        self.authViewModel = authViewModel
        _viewModel = StateObject(
            wrappedValue: container.makeSignInViewModel(authViewModel: authViewModel)
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                header

                if let errorMessage = viewModel.errorMessage {
                    ErrorBanner(message: errorMessage, onDismiss: {
                        viewModel.clearError()
                    })
                }

                form

                actions

                footer
            }
            .padding(AppTheme.Spacing.lg)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationDestination(isPresented: $showSignUp) {
            SignUpView(authViewModel: authViewModel, container: container)
        }
        .navigationDestination(isPresented: $showForgotPassword) {
            ForgotPasswordView(container: container)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "wallet.bifold.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 74, height: 74)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                        .fill(AppTheme.Colors.primaryGradient)
                )
                .shadow(color: AppTheme.Colors.primary.opacity(0.3), radius: 14, y: 6)

            Text("Welcome back")
                .font(AppTheme.Typography.largeTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("Sign in to keep track of your spending.")
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, AppTheme.Spacing.xl)
        .padding(.bottom, AppTheme.Spacing.xs)
    }

    private var form: some View {
        VStack(spacing: AppTheme.Spacing.md) {
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
                errorMessage: viewModel.emailError
            )

            CustomTextField(
                title: "Password",
                text: Binding(
                    get: { viewModel.password },
                    set: { viewModel.password = $0; viewModel.passwordChanged() }
                ),
                placeholder: "Your password",
                systemImage: "lock",
                isSecure: true,
                textContentType: .password,
                autocapitalization: .never,
                submitLabel: .go,
                errorMessage: viewModel.passwordError,
                onSubmit: { Task { await viewModel.submit() } }
            )

            HStack {
                Spacer()
                Button("Forgot password?") {
                    showForgotPassword = true
                }
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.secondary)
            }
        }
        .cardStyle(padding: AppTheme.Spacing.lg)
        // Nudges the whole card when credentials are rejected.
        .shake(times: viewModel.shakeCount)
        .animation(AppTheme.Motion.spring, value: viewModel.shakeCount)
    }

    private var actions: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            PrimaryButton(
                title: "Sign In",
                isLoading: viewModel.isLoading,
                isEnabled: viewModel.canSubmit
            ) {
                Task { await viewModel.submit() }
            }

            SecondaryButton(title: "Create an account") {
                showSignUp = true
            }
        }
    }

    private var footer: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            HStack(spacing: AppTheme.Spacing.xs) {
                ThemedDivider()
                Text("First time here?")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize()
                ThemedDivider()
            }

            Text(
                "This build stores accounts on this device only — "
                + "create one to get started."
            )
            .font(AppTheme.Typography.caption)
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .multilineTextAlignment(.center)
        }
        .padding(.top, AppTheme.Spacing.xs)
    }
}

// MARK: - Preview

#Preview("Sign in") {
    let container = DIContainer.makeEmptyPreview()
    let auth = container.makeAuthViewModel()

    return NavigationStack {
        SignInView(authViewModel: auth, container: container)
    }
    .environmentObject(auth)
}
