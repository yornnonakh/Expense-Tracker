//
//  EntityTests.swift
//  expense_trackerTests
//
//  Business rules that live on the entities themselves.
//

import XCTest
@testable import expense_tracker

final class BudgetTests: XCTestCase {

    func testSpendingExactlyTheLimitIsNotExceeding() {
        let budget = makeBudget(limit: 100)
        XCTAssertFalse(budget.isExceeded(spent: 100), "You may spend your whole budget")
        XCTAssertTrue(budget.isExceeded(spent: 100.01))
    }

    func testRemainingClampsAtZero() {
        let budget = makeBudget(limit: 100)
        XCTAssertEqual(budget.remaining(spent: 30), 70)
        XCTAssertEqual(budget.remaining(spent: 130), 0, "Negative remaining is not useful copy")
    }

    func testOverspendIsZeroWhileInsideTheLimit() {
        let budget = makeBudget(limit: 100)
        XCTAssertEqual(budget.overspend(spent: 40), 0)
        XCTAssertEqual(budget.overspend(spent: 130), 30)
    }

    func testPercentageUsedIsClampedForProgressViews() {
        let budget = makeBudget(limit: 100)
        XCTAssertEqual(budget.percentageUsed(spent: 50), 0.5)
        XCTAssertEqual(budget.percentageUsed(spent: 250), 1.0)
        XCTAssertEqual(budget.percentageUsed(spent: -10), 0)
    }

    func testRawPercentageIsUncappedForLabels() {
        let budget = makeBudget(limit: 100)
        XCTAssertEqual(budget.rawPercentageUsed(spent: 128), 1.28)
    }

    /// A zero limit would divide by zero and hand SwiftUI a NaN, which traps
    /// inside `ProgressView` at runtime.
    func testAZeroLimitNeverProducesNaN() {
        let budget = makeBudget(limit: 0)
        XCTAssertFalse(budget.percentageUsed(spent: 50).isNaN)
        XCTAssertFalse(budget.percentageUsed(spent: 0).isNaN)
        XCTAssertEqual(budget.percentageUsed(spent: 50), 1)
        XCTAssertEqual(budget.percentageUsed(spent: 0), 0)
    }

    func testStatusLevelThresholds() {
        let budget = makeBudget(limit: 100)

        XCTAssertEqual(BudgetStatus(budget: budget, spent: 50).level, .healthy)
        XCTAssertEqual(BudgetStatus(budget: budget, spent: 79.99).level, .healthy)
        XCTAssertEqual(BudgetStatus(budget: budget, spent: 80).level, .warning)
        XCTAssertEqual(BudgetStatus(budget: budget, spent: 100).level, .warning)
        XCTAssertEqual(BudgetStatus(budget: budget, spent: 100.01).level, .exceeded)
    }
}

final class ExpenseTests: XCTestCase {

    func testSortsNewestFirst() {
        let older = makeExpense(date: Date(timeIntervalSince1970: 1_000))
        let newer = makeExpense(date: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual([older, newer].sortedByDateDescending().map(\.id), [newer.id, older.id])
    }

    func testSortIsDeterministicForIdenticalDates() {
        let date = Date(timeIntervalSince1970: 1_000)
        let a = makeExpense(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, date: date)
        let b = makeExpense(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, date: date)

        // Stable ordering matters for SwiftUI list identity, so ties break on
        // id rather than being left to the sort's discretion.
        XCTAssertEqual([a, b].sortedByDateDescending().map(\.id), [b.id, a.id])
        XCTAssertEqual([b, a].sortedByDateDescending().map(\.id), [b.id, a.id])
    }

    func testTotalAmount() {
        let expenses = [makeExpense(amount: 10), makeExpense(amount: 20.5)]
        XCTAssertEqual(expenses.totalAmount, 30.5)
        XCTAssertEqual([Expense]().totalAmount, 0)
    }

    func testFallsInUsesAHalfOpenInterval() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        let interval = DateInterval(start: start, end: end)

        XCTAssertTrue(makeExpense(date: start).falls(in: interval), "Start is inclusive")
        XCTAssertTrue(makeExpense(date: Date(timeIntervalSince1970: 1_500)).falls(in: interval))
        XCTAssertFalse(makeExpense(date: end).falls(in: interval), "End is exclusive")
    }
}

final class ExpenseCategoryTests: XCTestCase {

    func testEveryCategoryHasDisplayMetadata() {
        for category in ExpenseCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty)
            XCTAssertFalse(category.emoji.isEmpty)
            XCTAssertFalse(category.systemImageName.isEmpty)
        }
    }

    /// A future build may add categories this one has never seen. Failing the
    /// decode would cost the user every expense in the file, so unknown values
    /// degrade to `.other` instead.
    func testUnknownRawValuesDecodeToOther() throws {
        let decoded = try JSONDecoder().decode(
            ExpenseCategory.self, from: Data(#""crypto""#.utf8)
        )
        XCTAssertEqual(decoded, .other)
    }

    func testKnownRawValuesDecodeExactly() throws {
        let decoded = try JSONDecoder().decode(
            ExpenseCategory.self, from: Data(#""transport""#.utf8)
        )
        XCTAssertEqual(decoded, .transport)
    }
}

final class UserTests: XCTestCase {

    func testInitialsFromATwoPartName() {
        XCTAssertEqual(makeUser(name: "Yorn Nona").initials, "YN")
    }

    func testInitialsFromASingleName() {
        XCTAssertEqual(makeUser(name: "Yorn").initials, "Y")
    }

    func testInitialsUseAtMostTwoLetters() {
        XCTAssertEqual(makeUser(name: "Ada Grace Byron King").initials, "AG")
    }

    func testInitialsFallBackToTheEmail() {
        XCTAssertEqual(makeUser(name: "", email: "zoe@example.com").initials, "Z")
    }

    func testFirstName() {
        XCTAssertEqual(makeUser(name: "Yorn Nona").firstName, "Yorn")
        XCTAssertEqual(makeUser(name: "Yorn").firstName, "Yorn")
    }

    func testSessionExpiry() {
        let issued = Date(timeIntervalSince1970: 0)
        let session = AuthSession(token: "t", user: makeUser(), issuedAt: issued)

        XCTAssertFalse(session.isExpired(now: issued.addingTimeInterval(AuthSession.lifetime - 1)))
        XCTAssertTrue(session.isExpired(now: issued.addingTimeInterval(AuthSession.lifetime + 1)))
    }
}
