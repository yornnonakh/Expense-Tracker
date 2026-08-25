//
//  UseCaseTests.swift
//  expense_trackerTests
//
//  Use cases against fake repositories: no storage, no network, no clock.
//

import XCTest
@testable import expense_tracker

final class AddExpenseUseCaseTests: XCTestCase {

    func testValidatesBeforeTouchingTheRepository() async throws {
        let repository = FakeExpenseRepository()
        let useCase = AddExpenseUseCase(repository: repository)

        let invalid = ExpenseDraft(amountText: "0", description: "x", category: .food)

        do {
            _ = try await useCase.execute(draft: invalid)
            XCTFail("Expected invalidAmount")
        } catch let error as ExpenseError {
            XCTAssertEqual(error, .invalidAmount)
        }

        // An invalid draft must never reach storage.
        let addCount = await repository.addCallCount
        XCTAssertEqual(addCount, 0)
    }

    func testPersistsAValidDraftAndReturnsWhatWasStored() async throws {
        let repository = FakeExpenseRepository()
        let useCase = AddExpenseUseCase(repository: repository)

        let expense = try await useCase.execute(
            draft: ExpenseDraft(amountText: "15,75", description: "  Tea  ", category: .food)
        )

        XCTAssertEqual(expense.amount, 15.75)
        XCTAssertEqual(expense.description, "Tea")

        let stored = try await repository.fetchAll()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.id, expense.id)
    }

    func testPropagatesARepositoryFailure() async throws {
        let repository = FakeExpenseRepository(errorToThrow: .persistenceFailed("disk full"))
        let useCase = AddExpenseUseCase(repository: repository)

        do {
            _ = try await useCase.execute(
                draft: ExpenseDraft(amountText: "10", description: "x", category: .food)
            )
            XCTFail("Expected the repository error to propagate")
        } catch let error as ExpenseError {
            guard case .persistenceFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}

final class GetStatisticsUseCaseTests: XCTestCase {

    func testEmptyInputProducesAZeroedSnapshotNotNaN() {
        let statistics = GetStatisticsUseCase.aggregate([])

        XCTAssertEqual(statistics.totalSpending, 0)
        XCTAssertEqual(statistics.expenseCount, 0)
        XCTAssertFalse(statistics.averageExpense.isNaN, "0/0 must not reach the UI")
    }

    func testAggregatesTotalsAverageAndExtremes() {
        let statistics = GetStatisticsUseCase.aggregate([
            makeExpense(amount: 10, category: .food),
            makeExpense(amount: 30, category: .food),
            makeExpense(amount: 20, category: .transport),
        ])

        XCTAssertEqual(statistics.totalSpending, 60)
        XCTAssertEqual(statistics.expenseCount, 3)
        XCTAssertEqual(statistics.averageExpense, 20)
        XCTAssertEqual(statistics.highestExpense?.amount, 30)
        XCTAssertEqual(statistics.lowestExpense?.amount, 10)
        XCTAssertEqual(statistics.spendingByCategory[.food], 40)
        XCTAssertEqual(statistics.spendingByCategory[.transport], 20)
    }

    func testASingleExpenseIsBothHighestAndLowest() {
        let statistics = GetStatisticsUseCase.aggregate([makeExpense(amount: 7)])
        XCTAssertEqual(statistics.highestExpense?.amount, 7)
        XCTAssertEqual(statistics.lowestExpense?.amount, 7)
    }

    func testScopesToTheRequestedRange() async throws {
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        let insideRange = reference.addingTimeInterval(-60 * 60)
        let longAgo = reference.addingTimeInterval(-400 * 24 * 60 * 60)

        let repository = FakeExpenseRepository(seed: [
            makeExpense(amount: 10, date: insideRange),
            makeExpense(amount: 999, date: longAgo),
        ])

        let statistics = try await GetStatisticsUseCase(repository: repository)
            .execute(range: .thisMonth, referenceDate: reference)

        XCTAssertEqual(statistics.totalSpending, 10, "Out-of-range spending leaked in")
    }

    func testCategoryDetailFiltersAndSorts() async throws {
        let older = makeExpense(amount: 1, category: .food, date: Date(timeIntervalSince1970: 10))
        let newer = makeExpense(amount: 2, category: .food, date: Date(timeIntervalSince1970: 20))
        let other = makeExpense(amount: 3, category: .shopping)

        let repository = FakeExpenseRepository(seed: [older, newer, other])
        let results = try await GetStatisticsUseCase(repository: repository)
            .executeCategoryDetail(category: .food, range: .allTime)

        XCTAssertEqual(results.map(\.id), [newer.id, older.id])
    }
}

final class ManageBudgetUseCaseTests: XCTestCase {

    func testJoinsBudgetsWithActualSpending() async throws {
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        let budgets = FakeBudgetRepository(seed: [
            makeBudget(category: .food, limit: 100),
            makeBudget(category: .transport, limit: 50),
        ])
        let expenses = FakeExpenseRepository(seed: [
            makeExpense(amount: 80, category: .food, date: reference),
            makeExpense(amount: 60, category: .transport, date: reference),
        ])

        let statuses = try await ManageBudgetUseCase(
            budgetRepository: budgets, expenseRepository: expenses
        ).fetchStatuses(range: .thisMonth, referenceDate: reference)

        XCTAssertEqual(statuses.count, 2)

        // Most-at-risk first: transport is 120% used, food is 80%.
        XCTAssertEqual(statuses.first?.category, .transport)
        XCTAssertTrue(statuses.first!.isExceeded)
        XCTAssertEqual(statuses.last?.spent, 80)
        XCTAssertEqual(statuses.last?.level, .warning)
    }

    func testABudgetWithNoSpendingReportsZero() async throws {
        let budgets = FakeBudgetRepository(seed: [makeBudget(category: .health, limit: 40)])
        let statuses = try await ManageBudgetUseCase(
            budgetRepository: budgets, expenseRepository: FakeExpenseRepository()
        ).fetchStatuses()

        XCTAssertEqual(statuses.first?.spent, 0)
        XCTAssertEqual(statuses.first?.level, .healthy)
    }

    func testSpendingOutsideTheRangeDoesNotCountAgainstTheBudget() async throws {
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        let lastYear = reference.addingTimeInterval(-400 * 24 * 60 * 60)

        let budgets = FakeBudgetRepository(seed: [makeBudget(category: .food, limit: 100)])
        let expenses = FakeExpenseRepository(seed: [
            makeExpense(amount: 500, category: .food, date: lastYear)
        ])

        let statuses = try await ManageBudgetUseCase(
            budgetRepository: budgets, expenseRepository: expenses
        ).fetchStatuses(range: .thisMonth, referenceDate: reference)

        // A budget is a per-period allowance; all-time spending would show
        // every budget as blown after a few months.
        XCTAssertEqual(statuses.first?.spent, 0)
    }
}

final class AuthUseCaseTests: XCTestCase {

    func testSignInNormalizesTheEmailBeforeHittingTheRepository() async throws {
        let repository = FakeAuthRepository()
        let session = try await SignInUseCase(repository: repository)
            .execute(email: "  USER@Example.COM ", password: "correct-horse")

        XCTAssertEqual(session.user.email, "user@example.com")
    }

    func testSignInRejectsAMalformedEmailWithoutCallingTheRepository() async throws {
        let repository = FakeAuthRepository()

        do {
            _ = try await SignInUseCase(repository: repository)
                .execute(email: "not-an-email", password: "correct-horse")
            XCTFail("Expected invalidEmail")
        } catch let error as AuthError {
            XCTAssertEqual(error, .invalidEmail)
        }

        let calls = await repository.signInCallCount
        XCTAssertEqual(calls, 0)
    }

    func testSignInTreatsAnEmptyPasswordAsInvalidCredentials() async throws {
        do {
            _ = try await SignInUseCase(repository: FakeAuthRepository())
                .execute(email: "user@example.com", password: "")
            XCTFail("Expected invalidCredentials")
        } catch let error as AuthError {
            XCTAssertEqual(error, .invalidCredentials)
        }
    }

    func testSignUpRequiresMatchingPasswords() async throws {
        do {
            _ = try await SignUpUseCase(repository: FakeAuthRepository())
                .execute(
                    name: "Yorn", email: "user@example.com",
                    password: "correct-horse", confirmPassword: "different"
                )
            XCTFail("Expected passwordsDoNotMatch")
        } catch let error as AuthError {
            XCTAssertEqual(error, .passwordsDoNotMatch)
        }
    }

    func testSignUpEnforcesThePasswordMinimum() async throws {
        do {
            _ = try await SignUpUseCase(repository: FakeAuthRepository())
                .execute(name: "Yorn", email: "u@e.com", password: "short", confirmPassword: "short")
            XCTFail("Expected weakPassword")
        } catch let error as AuthError {
            XCTAssertEqual(
                error, .weakPassword(minimumLength: AuthValidator.minimumPasswordLength)
            )
        }
    }

    func testRestoreSessionReturnsNilWhenThereIsNone() async throws {
        let restored = try await RestoreSessionUseCase(repository: FakeAuthRepository())
            .execute()
        XCTAssertNil(restored, "Not signed in is a normal state, not an error")
    }

    func testUpdateProfileImageRejectsEmptyData() async throws {
        let repository = FakeAuthRepository(
            session: AuthSession(token: "t", user: makeUser())
        )

        do {
            _ = try await UpdateProfileImageUseCase(repository: repository)
                .execute(imageData: Data())
            XCTFail("Expected unreadableImage")
        } catch let error as AuthError {
            XCTAssertEqual(error, .unreadableImage)
        }
    }

    func testUpdateProfileImageRejectsAnOversizedImage() async throws {
        let repository = FakeAuthRepository(
            session: AuthSession(token: "t", user: makeUser())
        )
        let huge = Data(count: UpdateProfileImageUseCase.maximumByteCount + 1)

        do {
            _ = try await UpdateProfileImageUseCase(repository: repository).execute(imageData: huge)
            XCTFail("Expected imageTooLarge")
        } catch let error as AuthError {
            XCTAssertEqual(
                error,
                .imageTooLarge(maximumBytes: UpdateProfileImageUseCase.maximumByteCount)
            )
        }
    }
}
