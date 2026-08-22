//
//  AddExpenseViewModel.swift
//  Presentation Layer — ViewModels
//

import Combine
import Foundation

@MainActor
final class AddExpenseViewModel: ObservableObject, ErrorPresenting {

    /// The whole form as one value. Editing a draft rather than four loose
    /// `@Published` strings means validation takes a single argument and the
    /// same shape is reused by the edit screen.
    @Published var draft = ExpenseDraft()

    @Published private(set) var amountError: String?
    @Published private(set) var descriptionError: String?
    @Published private(set) var categoryError: String?

    @Published private(set) var isLoading = false
    @Published private(set) var isSuccess = false
    @Published var errorMessage: String?
    @Published var errorIsRetryable = false

    private let addExpense: AddExpenseUseCase

    nonisolated init(addExpense: AddExpenseUseCase) {
        self.addExpense = addExpense
    }

    /// Live check for the Save button. Uses the same validator as submit, so
    /// the button can never be enabled for input that would be rejected.
    var canSave: Bool {
        ExpenseValidator.isValid(draft) && !isLoading
    }

    var descriptionCharacterLimit: Int {
        ExpenseValidator.descriptionCharacterLimit
    }

    /// Formatted preview of the typed amount, shown above the form.
    var previewAmount: String {
        guard let amount = try? ExpenseValidator.validateAmount(draft.amountText) else {
            return AppFormatters.currency(0)
        }
        return AppFormatters.currency(amount)
    }

    // MARK: - Actions

    func save() async {
        guard !isLoading else { return }

        clearFieldErrors()
        clearError()

        // Validate first so field errors land before any spinner appears.
        do {
            _ = try ExpenseValidator.makeExpense(from: draft)
        } catch let error as ExpenseError {
            assign(error)
            Haptics.error()
            return
        } catch {
            present(error)
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await addExpense.execute(draft: draft)
            Haptics.success()
            isSuccess = true
        } catch let error as ExpenseError where error.isValidation {
            assign(error)
            Haptics.error()
        } catch {
            present(error)
            Haptics.error()
        }
    }

    /// Puts a validation error under the field it belongs to.
    private func assign(_ error: ExpenseError) {
        switch error {
        case .invalidAmount, .amountTooLarge:
            amountError = error.errorDescription
        case .emptyDescription, .descriptionTooLong:
            descriptionError = error.errorDescription
        case .missingCategory:
            categoryError = error.errorDescription
        default:
            present(error)
        }
    }

    private func clearFieldErrors() {
        amountError = nil
        descriptionError = nil
        categoryError = nil
    }

    func amountChanged() {
        if amountError != nil { amountError = nil }
    }

    func descriptionChanged() {
        if descriptionError != nil { descriptionError = nil }
    }

    func categoryChanged() {
        if categoryError != nil { categoryError = nil }
    }

    /// Returns the form to empty so the sheet can be reused.
    func reset() {
        draft = ExpenseDraft()
        clearFieldErrors()
        clearError()
        isSuccess = false
    }
}
