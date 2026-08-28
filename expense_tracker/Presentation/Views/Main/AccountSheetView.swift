//
//  AccountSheetView.swift
//  Presentation Layer — Views
//
//  Account summary, profile photo and sign-out, reached from the dashboard
//  avatar.
//

import PhotosUI
import SwiftUI

struct AccountSheetView: View {

    /// Observed, not just held: changing the photo republishes the signed-in
    /// user, and that is what redraws the avatar on this screen.
    @ObservedObject private var authViewModel: AuthViewModel
    @StateObject private var viewModel: ProfileViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var showSignOutConfirmation = false
    @State private var showPhotoOptions = false
    @State private var showLibraryPicker = false
    @State private var showCamera = false
    @State private var pickedItem: PhotosPickerItem?

    init(authViewModel: AuthViewModel, container: DIContainer? = nil) {
        // `nil` rather than `= .shared`; see `DIContainer.shared`.
        let container = container ?? .shared
        self.authViewModel = authViewModel
        _viewModel = StateObject(
            wrappedValue: container.makeProfileViewModel(authViewModel: authViewModel)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {

                    if let user = authViewModel.currentUser {
                        profile(user)

                        if let errorMessage = viewModel.errorMessage {
                            ErrorBanner(message: errorMessage, onDismiss: {
                                viewModel.clearError()
                            })
                        }

                        details(user)
                    }

                    DestructiveButton(title: "Sign Out", systemImage: "arrow.right.square") {
                        showSignOutConfirmation = true
                    }

                    Text(
                        "Accounts, photos and expenses in this build are stored "
                        + "on this device only. Signing out keeps your data — it "
                        + "stays here until you delete the app."
                    )
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.Spacing.md)
                }
                .padding(AppTheme.Spacing.md)
                .animation(AppTheme.Motion.standard, value: viewModel.errorMessage)
            }
            .screenBackground()
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppTheme.Colors.primary)
                }
            }
            .overlay {
                if viewModel.isSaving {
                    LoadingOverlay(message: "Updating photo")
                }
            }
            .confirmationDialog(
                "Sign out?",
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await authViewModel.signOut()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Profile photo",
                isPresented: $showPhotoOptions,
                titleVisibility: .visible
            ) {
                Button("Choose from Library") { showLibraryPicker = true }

                // Hidden on Simulator and camera-less devices, where the
                // capture sheet would open onto nothing.
                if CameraPicker.isAvailable {
                    Button("Take Photo") { showCamera = true }
                }

                if authViewModel.currentUser?.hasAvatarImage == true {
                    Button("Remove Photo", role: .destructive) {
                        Task { await viewModel.removePhoto() }
                    }
                }

                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(
                isPresented: $showLibraryPicker,
                selection: $pickedItem,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: pickedItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await viewModel.updatePhoto(from: newItem)
                    // Cleared so re-picking the same photo is still a change
                    // the picker reports, rather than a silent no-op.
                    pickedItem = nil
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { imageData in
                    Task { await viewModel.updatePhoto(with: imageData) }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Sections

    private func profile(_ user: User) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {

            Button {
                showPhotoOptions = true
            } label: {
                AvatarView(
                    initials: user.initials,
                    imageData: user.avatarImageData,
                    size: 96
                )
                .overlay(alignment: .bottomTrailing) {
                    // Badge, rather than a caption alone: it marks the avatar
                    // as something you can act on without spending a line of
                    // copy saying so.
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(AppTheme.Colors.primary))
                        .overlay(
                            Circle().strokeBorder(AppTheme.Colors.background, lineWidth: 2)
                        )
                }
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(viewModel.isSaving)
            .accessibilityLabel(
                user.hasAvatarImage ? "Change profile photo" : "Add profile photo"
            )

            Text(user.name)
                .font(AppTheme.Typography.title2)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text(user.email)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Button(user.hasAvatarImage ? "Change photo" : "Add photo") {
                showPhotoOptions = true
            }
            .font(AppTheme.Typography.callout)
            .foregroundStyle(AppTheme.Colors.secondary)
            .disabled(viewModel.isSaving)
        }
        .padding(.top, AppTheme.Spacing.md)
    }

    private func details(_ user: User) -> some View {
        VStack(spacing: 0) {
            DetailRow(
                label: "Member since",
                value: AppFormatters.mediumDate(user.createdAt),
                systemImage: "calendar"
            )
            ThemedDivider()
            DetailRow(
                label: "Storage",
                value: "This device",
                systemImage: "internaldrive"
            )
        }
        .cardStyle()
    }
}

// MARK: - Preview

#Preview("Account") {
    struct Harness: View {
        private let container = DIContainer.preview
        @StateObject private var authViewModel = DIContainer.preview.makeAuthViewModel()

        var body: some View {
            AccountSheetView(authViewModel: authViewModel, container: container)
                .task {
                    await authViewModel.adopt(
                        AuthSession(
                            token: "preview",
                            user: User(name: "Yorn Nona", email: "yorn@example.com")
                        )
                    )
                }
        }
    }
    return Harness()
}
