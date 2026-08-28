//
//  ValidatorTests.swift
//  expense_trackerTests
//
//  Validation is the app's contract with the user's typing. These rules are
//  duplicated on the server, so a drift here shows up as a form that accepts
//  input the server then rejects.
//

import XCTest
@testable import expense_tracker

final class ExpenseValidatorTests: XCTestCase {

    // MARK: - Amount

    func testAcceptsAPlainDecimal() throws {
        XCTAssertEqual(try ExpenseValidator.validateAmount("12.50"), 12.50)
    }

    func testAcceptsACommaDecimalSeparator() throws {
        // Users on comma-decimal locales type what their keyboard offers.
        XCTAssertEqual(try ExpenseValidator.validateAmount("12,50"), 12.50)
    }

    func testTrimsSurroundingWhitespace() throws {
        XCTAssertEqual(try ExpenseValidator.validateAmount("  8.25  "), 8.25)
    }

    func testRoundsToCents() throws {
        // Keeps float drift from accumulating across the Statistics totals.
        XCTAssertEqual(try ExpenseValidator.validateAmount("10.999"), 11.00)
        XCTAssertEqual(try ExpenseValidator.validateAmount("0.005"), 0.01)
    }

    func testRejectsZeroAndNegatives() {
        for input in ["0", "0.00", "-5", "-0.01"] {
            XCTAssertThrowsError(try ExpenseValidator.validateAmount(input)) { error in
                XCTAssertEqual(error as? ExpenseError, .invalidAmount, "input: \(input)")
            }
        }
    }

    func testRejectsNonNumericInput() {
        for input in ["", "   ", "abc", "1.2.3", "$5"] {
            XCTAssertThrowsError(try ExpenseValidator.validateAmount(input)) { error in
                XCTAssertEqual(error as? ExpenseError, .invalidAmount, "input: \(input)")
            }
        }
    }

    func testRejectsNonFiniteValues() {
        // "inf" parses as a Double, and would otherwise reach storage and
        // render as an unformattable total.
        XCTAssertThrowsError(try ExpenseValidator.validateAmount("inf"))
        XCTAssertThrowsError(try ExpenseValidator.validateAmount("nan"))
    }

    func testRejectsAnAmountAboveTheCeiling() {
        XCTAssertThrowsError(
            try ExpenseValidator.validateAmount("1000000001")
        ) { error in
            XCTAssertEqual(error as? ExpenseError, .amountTooLarge)
        }
    }

    func testAcceptsExactlyTheCeiling() throws {
        XCTAssertEqual(try ExpenseValidator.validateAmount("1000000000"), 1_000_000_000)
    }

    // MARK: - Description

    func testTrimsAndRequiresADescription() throws {
        XCTAssertEqual(try ExpenseValidator.validateDescription("  Lunch  "), "Lunch")

        XCTAssertThrowsError(try ExpenseValidator.validateDescription("   ")) { error in
            XCTAssertEqual(error as? ExpenseError, .emptyDescription)
        }
    }

    func testEnforcesTheDescriptionLimit() {
        let limit = ExpenseValidator.descriptionCharacterLimit
        XCTAssertNoThrow(
            try ExpenseValidator.validateDescription(String(repeating: "a", count: limit))
        )
        XCTAssertThrowsError(
            try ExpenseValidator.validateDescription(String(repeating: "a", count: limit + 1))
        ) { error in
            XCTAssertEqual(error as? ExpenseError, .descriptionTooLong(limit: limit))
        }
    }

    // MARK: - Whole draft

    func testBuildsAnExpenseFromAValidDraft() throws {
        let draft = ExpenseDraft(
            amountText: "42.00", description: "Dinner", category: .food, date: Date()
        )
        let expense = try ExpenseValidator.makeExpense(from: draft)

        XCTAssertEqual(expense.amount, 42)
        XCTAssertEqual(expense.description, "Dinner")
        XCTAssertEqual(expense.category, .food)
    }

    func testPreservesTheIdWhenEditing() throws {
        let id = UUID()
        let draft = ExpenseDraft(amountText: "1.00", description: "x", category: .food)
        let expense = try ExpenseValidator.makeExpense(from: draft, id: id)

        XCTAssertEqual(expense.id, id, "Editing must not re-key the record")
    }

    func testRequiresACategory() {
        let draft = ExpenseDraft(amountText: "10", description: "x", category: nil)
        XCTAssertThrowsError(try ExpenseValidator.makeExpense(from: draft)) { error in
            XCTAssertEqual(error as? ExpenseError, .missingCategory)
        }
    }

    func testIsValidMirrorsTheThrowingRules() {
        XCTAssertTrue(ExpenseValidator.isValid(
            ExpenseDraft(amountText: "5", description: "ok", category: .food)
        ))
        XCTAssertFalse(ExpenseValidator.isValid(
            ExpenseDraft(amountText: "0", description: "ok", category: .food)
        ))
        XCTAssertFalse(ExpenseValidator.isValid(
            ExpenseDraft(amountText: "5", description: "", category: .food)
        ))
    }

    // MARK: - Budget limits

    func testValidatesBudgetLimits() throws {
        XCTAssertEqual(try ExpenseValidator.validateBudgetLimit("250,50"), 250.50)
        XCTAssertThrowsError(try ExpenseValidator.validateBudgetLimit("0")) { error in
            XCTAssertEqual(error as? ExpenseError, .invalidBudgetLimit)
        }
    }

    // MARK: - Round trip

    func testADraftBuiltFromAnExpenseValidatesBackToTheSameAmount() throws {
        let original = makeExpense(amount: 1234.56)
        let draft = ExpenseDraft(expense: original)
        let rebuilt = try ExpenseValidator.makeExpense(from: draft, id: original.id)

        // The draft formats with the POSIX locale precisely so this holds.
        XCTAssertEqual(rebuilt.amount, original.amount)
        XCTAssertEqual(rebuilt.id, original.id)
    }
}

final class AuthValidatorTests: XCTestCase {

    func testAcceptsOrdinaryAddressesAndLowercasesThem() throws {
        XCTAssertEqual(try AuthValidator.validateEmail("  User@Example.COM "), "user@example.com")
        XCTAssertNoThrow(try AuthValidator.validateEmail("a.b+tag@sub.domain.co.uk"))
    }

    func testRejectsObviousTypos() {
        for input in ["", "no-at-sign", "@example.com", "user@", "user@host", "a b@c.com"] {
            XCTAssertThrowsError(try AuthValidator.validateEmail(input)) { error in
                XCTAssertEqual(error as? AuthError, .invalidEmail, "input: \(input)")
            }
        }
    }

    func testRequiresAName() {
        XCTAssertEqual(try? AuthValidator.validateName("  Yorn  "), "Yorn")
        XCTAssertThrowsError(try AuthValidator.validateName("   ")) { error in
            XCTAssertEqual(error as? AuthError, .emptyName)
        }
    }

    func testEnforcesTheMinimumPasswordLength() {
        let minimum = AuthValidator.minimumPasswordLength

        XCTAssertNoThrow(
            try AuthValidator.validatePassword(String(repeating: "a", count: minimum))
        )
        XCTAssertThrowsError(
            try AuthValidator.validatePassword(String(repeating: "a", count: minimum - 1))
        ) { error in
            XCTAssertEqual(error as? AuthError, .weakPassword(minimumLength: minimum))
        }
    }

    /// The client's minimum must not be looser than the server's, or the form
    /// accepts a password the server then rejects with an error the user
    /// cannot act on. The server's value lives in `server/src/lib/password.ts`.
    func testMinimumPasswordLengthMatchesTheServer() {
        XCTAssertEqual(AuthValidator.minimumPasswordLength, 8)
    }

    func testRequiresMatchingConfirmation() {
        XCTAssertNoThrow(
            try AuthValidator.validatePasswordConfirmation("secret123", confirmation: "secret123")
        )
        XCTAssertThrowsError(
            try AuthValidator.validatePasswordConfirmation("secret123", confirmation: "secret124")
        ) { error in
            XCTAssertEqual(error as? AuthError, .passwordsDoNotMatch)
        }
    }
}
