//
//  AccountSheetView.swift
//  Presentation Layer — Views
//
//  Account summary and sign-out, reached from the dashboard avatar.
//

import SwiftUI

struct AccountSheetView: View {

    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {

                    if let user = authViewModel.currentUser {
                        profile(user)
                        details(user)
                    }

                    DestructiveButton(title: "Sign Out", systemImage: "arrow.right.square") {
                        showSignOutConfirmation = true
                    }

                    Text(
                        "Accounts and expenses in this build are stored on this "
                        + "device only. Signing out keeps your data — it stays "
                        + "here until you delete the app."
                    )
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.Spacing.md)
                }
                .padding(AppTheme.Spacing.md)
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
        }
    }

    // MARK: - Sections

    private func profile(_ user: User) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            AvatarView(initials: user.initials, size: 84)

            Text(user.name)
                .font(AppTheme.Typography.title2)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text(user.email)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .padding(.top, AppTheme.Spacing.md)
        .accessibilityElement(children: .combine)
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
    AccountSheetView()
        .environmentObject(DIContainer.preview.makeAuthViewModel())
}
