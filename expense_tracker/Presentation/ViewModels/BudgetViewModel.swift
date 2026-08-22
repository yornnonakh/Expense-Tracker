//
//  BudgetViewModel.swift
//  Presentation Layer — ViewModels
//
//  Budget list, creation, limit editing and deletion.
//

import Combine
import Foundation

@MainActor
final class BudgetViewModel: ObservableObject, ErrorPresenting {

    @Published private(set) var budgetStatuses: [BudgetStatus] = []
    @Published private(set) var availableCategories: [ExpenseCategory] = []
    @Published private(set) var summary: BudgetSummary = .empty

    /// Category chosen in the add-budget sheet.
    @Published var selectedCategory: ExpenseCategory?
    @Published var limitText: String = ""
    @Published private(set) var limitError: String?

    /// Budget currently being edited; nil means the sheet is in "add" mode.
    @Published private(set) var editingBudget: Budget?

    @Published var isPresentingEditor = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var hasLoadedOnce = false

    @Published var errorMessage: String?
    @Published var errorIsRetryable = false
    @Published var toastMessage: String?

    /// Budgets are measured against a period; monthly is the default people
    /// expect, and it is switchable here.
    @Published var dateRange: DateRangeFilter = .thisMonth {
        didSet {
            reloadTask?.cancel()
            reloadTask = Task { await load() }
        }
    }

    private let manageBudget: ManageBudgetUseCase
    private var reloadTask: Task<Void, Never>?

    nonisolated init(manageBudget: ManageBudgetUseCase) {
        self.manageBudget = manageBudget
    }

    deinit {
        reloadTask?.cancel()
    }

    // MARK: - Derived

    var exceededBudgets: [BudgetStatus] {
        budgetStatuses.filter(\.isExceeded)
    }

    var hasBudgets: Bool { !budgetStatuses.isEmpty }

    var canAddBudget: Bool { !availableCategories.isEmpty }

    var isEditing: Bool { editingBudget != nil }

    var canSave: Bool {
        guard !isSaving else { return false }
        guard (try? ExpenseValidator.validateBudgetLimit(limitText)) != nil else {
            return false
        }
        // Adding needs a category; editing already has one.
        return isEditing || selectedCategory != nil
    }

    var editorTitle: String {
        isEditing ? "Edit Budget" : "New Budget"
    }

    // MARK: - Lifecycle

    func start() async {
        await load()
        await observeChanges()
    }

    /// Budgets are affected by BOTH budget writes (a new limit) and expense
    /// writes (spending moves against the limit), so this watches both.
    func observeChanges() async {
        for await _ in NotificationCenter.default.notifications(
            named: .budgetDataDidChange
        ) {
            await load()
        }
    }

    func observeExpenseChanges() async {
        for await _ in NotificationCenter.default.notifications(
            named: .expenseDataDidChange
        ) {
            await load()
        }
    }

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }
        clearError()

        do {
            async let statusesTask = manageBudget.fetchStatuses(range: dateRange)
            async let categoriesTask = manageBudget.availableCategories()
            async let summaryTask = manageBudget.totalRemaining(range: dateRange)

            let (statuses, categories, loadedSummary) =
                try await (statusesTask, categoriesTask, summaryTask)

            guard !Task.isCancelled else { return }

            budgetStatuses = statuses
            availableCategories = categories
            summary = loadedSummary
        } catch {
            present(error)
        }
    }

    func retry() async {
        await load()
    }

    // MARK: - Editor

    func beginAdding() {
        editingBudget = nil
        selectedCategory = availableCategories.first
        limitText = ""
        limitError = nil
        clearError()
        isPresentingEditor = true
    }

    func beginEditing(_ status: BudgetStatus) {
        editingBudget = status.budget
        selectedCategory = status.category
        // Seed with the current limit so a small tweak doesn't mean retyping.
        limitText = String(format: "%.2f", status.limit)
        limitError = nil
        clearError()
        isPresentingEditor = true
    }

    func cancelEditor() {
        isPresentingEditor = false
        editingBudget = nil
        limitText = ""
        limitError = nil
    }

    func saveBudget() async {
        guard !isSaving else { return }

        limitError = nil
        clearError()

        // Validate before showing a spinner, so bad input fails instantly.
        do {
            _ = try ExpenseValidator.validateBudgetLimit(limitText)
        } catch let error as ExpenseError {
            limitError = error.errorDescription
            Haptics.error()
            return
        } catch {
            present(error)
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            if let editingBudget {
                try await manageBudget.updateLimit(
                    for: editingBudget, limitText: limitText
                )
                toastMessage = "Budget updated"
            } else {
                guard let selectedCategory else {
                    limitError = ExpenseError.missingCategory.errorDescription
                    return
                }
                try await manageBudget.createBudget(
                    category: selectedCategory, limitText: limitText
                )
                toastMessage = "Budget created"
            }

            Haptics.success()
            isPresentingEditor = false
            editingBudget = nil
            limitText = ""
            await load()
        } catch let error as ExpenseError where error.isValidation {
            limitError = error.errorDescription
            Haptics.error()
        } catch {
            present(error)
            Haptics.error()
        }
    }

    func deleteBudget(_ status: BudgetStatus) async {
        // Optimistic removal, restored on failure.
        let snapshot = budgetStatuses
        budgetStatuses.removeAll { $0.id == status.id }

        do {
            try await manageBudget.deleteBudget(id: status.id)
            Haptics.success()
            toastMessage = "Budget deleted"
            await load()
        } catch {
            budgetStatuses = snapshot
            present(error)
            Haptics.error()
        }
    }

    func limitChanged() {
        if limitError != nil { limitError = nil }
    }
}
