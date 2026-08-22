//
//  ForgotPasswordViewModel.swift
//  Presentation Layer — ViewModels
//

import Combine
import Foundation

@MainActor
final class ForgotPasswordViewModel: ObservableObject, ErrorPresenting {

    @Published var email = ""
    @Published private(set) var emailError: String?
    @Published private(set) var isLoading = false

    /// Switches the screen to its confirmation state.
    @Published private(set) var didSendReset = false

    @Published var errorMessage: String?
    @Published var errorIsRetryable = false

    private let requestReset: RequestPasswordResetUseCase

    nonisolated init(requestReset: RequestPasswordResetUseCase) {
        self.requestReset = requestReset
    }

    var canSubmit: Bool { !email.isEmpty && !isLoading }

    func submit() async {
        guard !isLoading else { return }

        emailError = nil
        clearError()
        isLoading = true
        defer { isLoading = false }

        do {
            try await requestReset.execute(email: email)
            Haptics.success()
            didSendReset = true
        } catch let error as AuthError {
            switch error {
            case .invalidEmail, .accountNotFound:
                emailError = error.errorDescription
            default:
                present(error)
            }
            Haptics.error()
        } catch {
            present(error)
        }
    }

    /// Lets the user correct the address and try again from the success state.
    func reset() {
        didSendReset = false
        emailError = nil
        clearError()
    }

    func emailChanged() {
        if emailError != nil { emailError = nil }
    }
}
