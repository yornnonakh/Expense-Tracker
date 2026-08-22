//
//  SignInViewModel.swift
//  Presentation Layer — ViewModels
//

import Combine
import Foundation

@MainActor
final class SignInViewModel: ObservableObject, ErrorPresenting {

    // Form state
    @Published var email = ""
    @Published var password = ""

    // Per-field validation, shown under the relevant input.
    @Published private(set) var emailError: String?
    @Published private(set) var passwordError: String?

    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var errorIsRetryable = false

    /// Incremented to trigger the shake animation on a rejected attempt.
    @Published private(set) var shakeCount: CGFloat = 0

    private let signIn: SignInUseCase
    private let authViewModel: AuthViewModel

    nonisolated init(signIn: SignInUseCase, authViewModel: AuthViewModel) {
        self.signIn = signIn
        self.authViewModel = authViewModel
    }

    /// Enables the Submit button. Deliberately loose — real validation happens
    /// on submit, and disabling the button on a half-typed email is hostile.
    var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && !isLoading
    }

    func submit() async {
        guard !isLoading else { return }

        clearFieldErrors()
        clearError()
        isLoading = true
        defer { isLoading = false }

        do {
            let session = try await signIn.execute(email: email, password: password)
            Haptics.success()
            await authViewModel.adopt(session)
        } catch let error as AuthError {
            handle(error)
        } catch {
            present(error)
        }
    }

    /// Routes validation failures to the field they belong to, and everything
    /// else to the banner.
    private func handle(_ error: AuthError) {
        switch error {
        case .invalidEmail:
            emailError = error.errorDescription
        case .weakPassword:
            passwordError = error.errorDescription
        case .invalidCredentials, .accountNotFound:
            // Not attributable to one field — an incorrect pair is a
            // whole-form failure.
            errorMessage = error.errorDescription
            errorIsRetryable = false
        default:
            present(error)
        }

        Haptics.error()
        shakeCount += 1
    }

    private func clearFieldErrors() {
        emailError = nil
        passwordError = nil
    }

    /// Clears a field's error as soon as the user starts fixing it.
    func emailChanged() {
        if emailError != nil { emailError = nil }
    }

    func passwordChanged() {
        if passwordError != nil { passwordError = nil }
    }

    /// Convenience for the demo credentials shortcut on the sign-in screen.
    func fillDemoCredentials() {
        email = "demo@expensetracker.app"
        password = "demo1234"
    }
}
