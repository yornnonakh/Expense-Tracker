//
//  SignUpView.swift
//  Presentation Layer — Views
//

import SwiftUI

struct SignUpView: View {

    @StateObject private var viewModel: SignUpViewModel
    @Environment(\.dismiss) private var dismiss

    init(authViewModel: AuthViewModel, container: DIContainer = .shared) {
        _viewModel = StateObject(
            wrappedValue: container.makeSignUpViewModel(authViewModel: authViewModel)
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

                PrimaryButton(
                    title: "Create Account",
                    isLoading: viewModel.isLoading,
                    isEnabled: viewModel.canSubmit
                ) {
                    Task { await viewModel.submit() }
                }

                Button("Already have an account? Sign in") {
                    dismiss()
                }
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.secondary)
            }
            .padding(AppTheme.Spacing.lg)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: AppTheme.Spacing.xxs) {
            Text("Create your account")
                .font(AppTheme.Typography.title)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("Start tracking where your money goes.")
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .padding(.top, AppTheme.Spacing.md)
    }

    private var form: some View {
        VStack(spacing: AppTheme.Spacing.md) {

            CustomTextField(
                title: "Name",
                text: Binding(
                    get: { viewModel.name },
                    set: { viewModel.name = $0; viewModel.fieldChanged(.name) }
                ),
                placeholder: "Your name",
                systemImage: "person",
                textContentType: .name,
                autocapitalization: .words,
                errorMessage: viewModel.nameError
            )

            CustomTextField(
                title: "Email",
                text: Binding(
                    get: { viewModel.email },
                    set: { viewModel.email = $0; viewModel.fieldChanged(.email) }
                ),
                placeholder: "you@example.com",
                systemImage: "envelope",
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                autocapitalization: .never,
                errorMessage: viewModel.emailError
            )

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                CustomTextField(
                    title: "Password",
                    text: Binding(
                        get: { viewModel.password },
                        set: { viewModel.password = $0; viewModel.fieldChanged(.password) }
                    ),
                    placeholder: "At least \(AuthValidator.minimumPasswordLength) characters",
                    systemImage: "lock",
                    isSecure: true,
                    textContentType: .newPassword,
                    autocapitalization: .never,
                    errorMessage: viewModel.passwordError
                )

                // Only shown once typing starts, so an untouched form isn't
                // pre-emptively telling the user their password is too short.
                if !viewModel.password.isEmpty {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        ProgressBarView(
                            fraction: viewModel.passwordStrength,
                            tint: strengthColor,
                            height: 5
                        )
                        Text(viewModel.passwordStrengthLabel)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(strengthColor)
                            .frame(width: 66, alignment: .trailing)
                    }
                    .transition(.opacity)
                }
            }
            .animation(AppTheme.Motion.quick, value: viewModel.password.isEmpty)

            CustomTextField(
                title: "Confirm password",
                text: Binding(
                    get: { viewModel.confirmPassword },
                    set: {
                        viewModel.confirmPassword = $0
                        viewModel.fieldChanged(.confirmPassword)
                    }
                ),
                placeholder: "Repeat your password",
                systemImage: "lock.rotation",
                isSecure: true,
                textContentType: .newPassword,
                autocapitalization: .never,
                submitLabel: .done,
                errorMessage: viewModel.confirmPasswordError,
                onSubmit: { Task { await viewModel.submit() } }
            )
        }
        .cardStyle(padding: AppTheme.Spacing.lg)
        .shake(times: viewModel.shakeCount)
        .animation(AppTheme.Motion.spring, value: viewModel.shakeCount)
    }

    private var strengthColor: Color {
        switch viewModel.passwordStrength {
        case ..<0.4:  return AppTheme.Colors.danger
        case ..<0.7:  return AppTheme.Colors.warning
        default:      return AppTheme.Colors.success
        }
    }
}

// MARK: - Preview

#Preview("Sign up") {
    let container = DIContainer.makeEmptyPreview()
    let auth = container.makeAuthViewModel()

    return NavigationStack {
        SignUpView(authViewModel: auth, container: container)
    }
}
