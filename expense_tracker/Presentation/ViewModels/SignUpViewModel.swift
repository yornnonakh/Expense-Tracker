//
//  SignUpViewModel.swift
//  Presentation Layer — ViewModels
//

import Combine
import Foundation

@MainActor
final class SignUpViewModel: ObservableObject, ErrorPresenting {

    @Published var name = ""
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""

    @Published private(set) var nameError: String?
    @Published private(set) var emailError: String?
    @Published private(set) var passwordError: String?
    @Published private(set) var confirmPasswordError: String?

    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var errorIsRetryable = false
    @Published private(set) var shakeCount: CGFloat = 0

    private let signUp: SignUpUseCase
    private let authViewModel: AuthViewModel

    nonisolated init(signUp: SignUpUseCase, authViewModel: AuthViewModel) {
        self.signUp = signUp
        self.authViewModel = authViewModel
    }

    var canSubmit: Bool {
        !name.isEmpty
            && !email.isEmpty
            && !password.isEmpty
            && !confirmPassword.isEmpty
            && !isLoading
    }

    /// Live strength hint under the password field, 0...1.
    var passwordStrength: Double {
        var score = 0.0
        if password.count >= AuthValidator.minimumPasswordLength { score += 0.4 }
        if password.count >= 10 { score += 0.2 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { score += 0.2 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { score += 0.2 }
        return min(1, score)
    }

    var passwordStrengthLabel: String {
        switch passwordStrength {
        case ..<0.4:  return "Too short"
        case ..<0.7:  return "Okay"
        case ..<1.0:  return "Good"
        default:      return "Strong"
        }
    }

    func submit() async {
        guard !isLoading else { return }

        clearFieldErrors()
        clearError()
        isLoading = true
        defer { isLoading = false }

        do {
            let session = try await signUp.execute(
                name: name,
                email: email,
                password: password,
                confirmPassword: confirmPassword
            )
            Haptics.success()
            await authViewModel.adopt(session)
        } catch let error as AuthError {
            handle(error)
        } catch {
            present(error)
        }
    }

    private func handle(_ error: AuthError) {
        switch error {
        case .emptyName:
            nameError = error.errorDescription
        case .invalidEmail, .emailAlreadyRegistered:
            emailError = error.errorDescription
        case .weakPassword:
            passwordError = error.errorDescription
        case .passwordsDoNotMatch:
            confirmPasswordError = error.errorDescription
        default:
            present(error)
        }

        Haptics.error()
        shakeCount += 1
    }

    private func clearFieldErrors() {
        nameError = nil
        emailError = nil
        passwordError = nil
        confirmPasswordError = nil
    }

    func fieldChanged(_ field: Field) {
        switch field {
        case .name:            nameError = nil
        case .email:           emailError = nil
        case .password:        passwordError = nil
        case .confirmPassword: confirmPasswordError = nil
        }
    }

    enum Field {
        case name, email, password, confirmPassword
    }
}
