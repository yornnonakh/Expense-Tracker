//
//  AuthUseCases.swift
//  Domain Layer — Use Cases
//
//  The four authentication actions. Grouped in one file because each is a
//  handful of lines and they share the same repository; splitting them into
//  four files would be ceremony without benefit.
//

import Foundation

// MARK: - Sign in

struct SignInUseCase: Sendable {

    private let repository: AuthRepository

    init(repository: AuthRepository) {
        self.repository = repository
    }

    func execute(email: String, password: String) async throws -> AuthSession {
        // Validate shape before hitting storage: no point looking up an
        // address that could never have been registered.
        let normalizedEmail = try AuthValidator.validateEmail(email)
        guard !password.isEmpty else { throw AuthError.invalidCredentials }

        return try await repository.signIn(email: normalizedEmail, password: password)
    }
}

// MARK: - Sign up

struct SignUpUseCase: Sendable {

    private let repository: AuthRepository

    init(repository: AuthRepository) {
        self.repository = repository
    }

    func execute(
        name: String,
        email: String,
        password: String,
        confirmPassword: String
    ) async throws -> AuthSession {
        let validatedName = try AuthValidator.validateName(name)
        let normalizedEmail = try AuthValidator.validateEmail(email)
        let validatedPassword = try AuthValidator.validatePassword(password)
        try AuthValidator.validatePasswordConfirmation(
            validatedPassword,
            confirmation: confirmPassword
        )

        return try await repository.signUp(
            name: validatedName,
            email: normalizedEmail,
            password: validatedPassword
        )
    }
}

// MARK: - Password reset

struct RequestPasswordResetUseCase: Sendable {

    private let repository: AuthRepository

    init(repository: AuthRepository) {
        self.repository = repository
    }

    func execute(email: String) async throws {
        let normalizedEmail = try AuthValidator.validateEmail(email)
        try await repository.requestPasswordReset(email: normalizedEmail)
    }
}

// MARK: - Session lifecycle

struct RestoreSessionUseCase: Sendable {

    private let repository: AuthRepository

    init(repository: AuthRepository) {
        self.repository = repository
    }

    /// Powers auto-login at launch. Returns nil rather than throwing when
    /// there is simply no session — "not signed in" is a normal state, not an
    /// error worth showing the user.
    func execute() async throws -> AuthSession? {
        try await repository.currentSession()
    }
}

struct SignOutUseCase: Sendable {

    private let repository: AuthRepository

    init(repository: AuthRepository) {
        self.repository = repository
    }

    func execute() async throws {
        try await repository.signOut()
    }
}
