//
//  CustomTextField.swift
//  Presentation Layer — Components
//
//  Text entry with a consistent shell: label, icon, inline error, and an
//  optional reveal toggle for passwords.
//

import SwiftUI

struct CustomTextField: View {

    let title: String
    @Binding var text: String

    var placeholder: String = ""
    var systemImage: String?
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .sentences
    var submitLabel: SubmitLabel = .next

    /// Inline validation message. Non-nil switches the field to its error look.
    var errorMessage: String?

    var onSubmit: (() -> Void)?

    /// Tracks whether a secure field is currently revealed.
    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    private var hasError: Bool { errorMessage != nil }

    private var borderColor: Color {
        if hasError { return AppTheme.Colors.danger }
        if isFocused { return AppTheme.Colors.primary }
        return .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {

            Text(title)
                .font(AppTheme.Typography.captionBold)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            HStack(spacing: AppTheme.Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15))
                        .foregroundStyle(
                            hasError ? AppTheme.Colors.danger : AppTheme.Colors.textSecondary
                        )
                        .frame(width: 18)
                }

                field

                if isSecure {
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .frame(height: AppTheme.Metrics.fieldHeight)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(AppTheme.Colors.background)
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1.5)
            }
            .animation(AppTheme.Motion.quick, value: isFocused)
            .animation(AppTheme.Motion.quick, value: hasError)

            // Reserve no space when valid — the row collapses so the form
            // doesn't jump around, and the transition softens the shift.
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.danger)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilityLabel("Error: \(errorMessage)")
            }
        }
        .animation(AppTheme.Motion.quick, value: errorMessage)
    }

    /// `SecureField` and `TextField` are different types, so the reveal toggle
    /// has to swap between them rather than flip a flag.
    @ViewBuilder
    private var field: some View {
        Group {
            if isSecure && !isRevealed {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .font(AppTheme.Typography.field)
        .foregroundStyle(AppTheme.Colors.textPrimary)
        .keyboardType(keyboardType)
        .textContentType(textContentType)
        .textInputAutocapitalization(autocapitalization)
        .autocorrectionDisabled(isSecure || keyboardType == .emailAddress)
        .submitLabel(submitLabel)
        .focused($isFocused)
        .onSubmit { onSubmit?() }
    }
}

// MARK: - Amount field

/// Decimal entry with a leading currency symbol, used by the add/edit forms
/// and the budget editor.
struct AmountInputField: View {

    let title: String
    @Binding var amountText: String
    var errorMessage: String?
    var currencySymbol: String = Locale.current.currencySymbol ?? "$"

    @FocusState private var isFocused: Bool

    private var hasError: Bool { errorMessage != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {

            Text(title)
                .font(AppTheme.Typography.captionBold)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xs) {
                Text(currencySymbol)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                TextField("0.00", text: $amountText)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .keyboardType(.decimalPad)
                    .focused($isFocused)
                    .accessibilityLabel(title)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .fill(AppTheme.Colors.background)
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .strokeBorder(
                        hasError
                            ? AppTheme.Colors.danger
                            : (isFocused ? AppTheme.Colors.primary : .clear),
                        lineWidth: 1.5
                    )
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.danger)
                    .transition(.opacity)
            }
        }
        .animation(AppTheme.Motion.quick, value: errorMessage)
    }
}

// MARK: - Preview

#Preview("Fields") {
    struct Harness: View {
        @State private var email = ""
        @State private var password = ""
        @State private var amount = "24.50"

        var body: some View {
            VStack(spacing: AppTheme.Spacing.lg) {
                CustomTextField(
                    title: "Email",
                    text: $email,
                    placeholder: "you@example.com",
                    systemImage: "envelope",
                    keyboardType: .emailAddress,
                    autocapitalization: .never
                )
                CustomTextField(
                    title: "Password",
                    text: $password,
                    placeholder: "••••••••",
                    systemImage: "lock",
                    isSecure: true,
                    errorMessage: "Password must be at least 6 characters."
                )
                AmountInputField(title: "Amount", amountText: $amount)
            }
            .padding()
            .screenBackground()
        }
    }
    return Harness()
}
