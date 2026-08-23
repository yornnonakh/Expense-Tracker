//
//  ProfileViewModel.swift
//  Presentation Layer — ViewModels
//
//  The profile photo flow: pick, shrink, save, publish.
//
//  Owns the whole sequence in one place so the view stays declarative — it
//  says "the user chose this" and reads `isSaving`, rather than juggling
//  transfer, downscaling and session refresh itself.
//

import Combine
import Foundation
// `PhotosPickerItem` lives in PhotosUI's SwiftUI overlay, so SwiftUI has to be
// in scope for the type to resolve.
import PhotosUI
import SwiftUI

@MainActor
final class ProfileViewModel: ObservableObject, ErrorPresenting {

    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var errorIsRetryable = false

    private let updateProfileImage: UpdateProfileImageUseCase
    private let removeProfileImage: RemoveProfileImageUseCase

    /// The session owner. Held as a plain reference rather than observed: this
    /// view model writes to it and never renders from it.
    private let authViewModel: AuthViewModel

    /// `nonisolated` for the same reason as `AuthViewModel.init` — SwiftUI
    /// builds this inside a `StateObject` autoclosure, outside actor isolation.
    nonisolated init(
        updateProfileImage: UpdateProfileImageUseCase,
        removeProfileImage: RemoveProfileImageUseCase,
        authViewModel: AuthViewModel
    ) {
        self.updateProfileImage = updateProfileImage
        self.removeProfileImage = removeProfileImage
        self.authViewModel = authViewModel
    }

    // MARK: - Setting a photo

    /// Photo-library path. The picker hands back an item, not bytes, so the
    /// transfer is part of the work — and part of what `isSaving` covers.
    func updatePhoto(from item: PhotosPickerItem) async {
        await perform {
            guard let raw = try await item.loadTransferable(type: Data.self) else {
                // The item resolved to nothing loadable — a corrupt asset, or
                // one iCloud couldn't materialise.
                throw AuthError.unreadableImage
            }
            try await self.save(raw)
        }
    }

    /// Camera path, where the capture already arrives as bytes.
    func updatePhoto(with rawImageData: Data) async {
        await perform {
            try await self.save(rawImageData)
        }
    }

    func removePhoto() async {
        await perform {
            let user = try await self.removeProfileImage.execute()
            self.authViewModel.updateCurrentUser(user)
        }
    }

    // MARK: - Helpers

    private func save(_ rawImageData: Data) async throws {
        // Off the main actor deliberately: the picker can hand over a
        // 12-megapixel HEIC, and decoding one is not work for the frame loop.
        let prepared = await Task.detached(priority: .userInitiated) {
            ProfileImageProcessor.prepare(rawImageData)
        }.value

        guard let prepared else { throw AuthError.unreadableImage }

        let user = try await updateProfileImage.execute(imageData: prepared)
        authViewModel.updateCurrentUser(user)
        Haptics.success()
    }

    /// Shared busy/error scaffolding, so each action above reads as just the
    /// thing it does. The guard also makes a double tap on the picker a no-op
    /// rather than two competing writes to the same file.
    private func perform(_ work: @escaping () async throws -> Void) async {
        guard !isSaving else { return }

        clearError()
        isSaving = true
        defer { isSaving = false }

        do {
            try await work()
        } catch {
            present(error)
            Haptics.error()
        }
    }
}
