//
//  EditExpenseViewModel.swift
//  Presentation Layer — ViewModels
//

import Combine
import Foundation

@MainActor
final class EditExpenseViewModel: ObservableObject, ErrorPresenting {

    /// Pre-filled from the expense being edited.
    @Published var draft: ExpenseDraft

    @Published private(set) var amountError: String?
    @Published private(set) var descriptionError: String?
    @Published private(set) var categoryError: String?

    @Published private(set) var isLoading = false
    @Published private(set) var isSuccess = false
    @Published private(set) var didDelete = false
    @Published var errorMessage: String?
    @Published var errorIsRetryable = false

    /// The expense as it was when the screen opened.
    let original: Expense

    private let updateExpense: UpdateExpenseUseCase
    private let deleteExpense: DeleteExpenseUseCase

    /// Main-actor isolated, unlike the other view models' `nonisolated` inits.
    ///
    /// This one seeds a `@Published` property from its argument, and writing
    /// through a published property's storage from a nonisolated context is a
    /// hard error under the Swift 6 language mode. Staying on the main actor
    /// is safe here because SwiftUI's `View` is itself `@MainActor`, so the
    /// `StateObject` autoclosure that builds this already runs there.
    init(
        expense: Expense,
        updateExpense: UpdateExpenseUseCase,
        deleteExpense: DeleteExpenseUseCase
    ) {
        self.original = expense
        self.draft = ExpenseDraft(expense: expense)
        self.updateExpense = updateExpense
        self.deleteExpense = deleteExpense
    }

    var canSave: Bool {
        ExpenseValidator.isValid(draft) && hasChanges && !isLoading
    }

    /// Nothing to save when nothing moved — keeps the user from committing a
    /// no-op write and lets the UI warn before discarding real edits.
    var hasChanges: Bool {
        draft != ExpenseDraft(expense: original)
    }

    var descriptionCharacterLimit: Int {
        ExpenseValidator.descriptionCharacterLimit
    }

    // MARK: - Actions

    func save() async {
        guard !isLoading else { return }

        clearFieldErrors()
        clearError()

        do {
            _ = try ExpenseValidator.makeExpense(from: draft, id: original.id)
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
            try await updateExpense.execute(id: original.id, draft: draft)
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

    func delete() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }
        clearError()

        do {
            try await deleteExpense.execute(id: original.id)
            Haptics.success()
            didDelete = true
        } catch {
            present(error)
            Haptics.error()
        }
    }

    func revert() {
        draft = ExpenseDraft(expense: original)
        clearFieldErrors()
        clearError()
    }

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
}
