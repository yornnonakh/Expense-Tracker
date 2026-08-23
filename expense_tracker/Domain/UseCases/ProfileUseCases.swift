//
//  ProfileUseCases.swift
//  Domain Layer — Use Cases
//
//  Changing and clearing the signed-in user's profile photo. Grouped in one
//  file for the same reason the auth actions are: two short types over the
//  same repository.
//

import Foundation

// MARK: - Set photo

struct UpdateProfileImageUseCase: Sendable {

    /// Backstop on what may be persisted.
    ///
    /// `ProfileImageProcessor` downscales well below this — a 512px JPEG is
    /// tens of kilobytes — so hitting the ceiling means something upstream
    /// handed over an unprocessed original, which is exactly what should be
    /// refused rather than written to disk.
    static let maximumByteCount = 4 * 1_048_576

    private let repository: AuthRepository

    init(repository: AuthRepository) {
        self.repository = repository
    }

    func execute(imageData: Data) async throws -> User {
        guard !imageData.isEmpty else { throw AuthError.unreadableImage }
        guard imageData.count <= Self.maximumByteCount else {
            throw AuthError.imageTooLarge(maximumBytes: Self.maximumByteCount)
        }

        return try await repository.updateProfileImage(imageData)
    }
}

// MARK: - Clear photo

struct RemoveProfileImageUseCase: Sendable {

    private let repository: AuthRepository

    init(repository: AuthRepository) {
        self.repository = repository
    }

    /// Returns the user with the photo dropped, so callers refresh from one
    /// value instead of guessing at the new state.
    func execute() async throws -> User {
        try await repository.updateProfileImage(nil)
    }
}
