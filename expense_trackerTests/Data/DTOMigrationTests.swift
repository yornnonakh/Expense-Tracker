//
//  DTOMigrationTests.swift
//  expense_trackerTests
//
//  Schema-1 records were written before the backend existed. A user updating
//  the app must not lose them, so these tests pin the decode path against
//  literal on-disk JSON rather than against a round-trip of the current type —
//  a round trip would silently pass even if the migration were removed.
//

import XCTest
@testable import expense_tracker

final class DTOMigrationTests: XCTestCase {

    // MARK: - Expenses

    func testDecodesASchema1ExpenseWithNoSyncFields() throws {
        let legacy = """
        {
          "id": "3F2504E0-4F89-41D3-9A0C-0305E82C3301",
          "amount": 12.5,
          "description": "Legacy lunch",
          "category": "food",
          "date": 1700000000
        }
        """

        let dto = try JSONCoding.decode(ExpenseDTO.self, from: Data(legacy.utf8))

        XCTAssertEqual(dto.amount, 12.5)
        XCTAssertEqual(dto.description, "Legacy lunch")
        XCTAssertEqual(dto.schemaVersion, 1)
        XCTAssertNil(dto.deletedAt)

        // Unknown edit time, so it must lose any conflict against a record
        // with a real timestamp.
        XCTAssertEqual(dto.updatedAt, 0)

        // Never uploaded, therefore pending by definition.
        XCTAssertTrue(dto.isPendingSync)
    }

    func testDecodesAnEvenOlderRecordWithNoSchemaVersion() throws {
        let ancient = """
        {"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","amount":1,
         "description":"x","category":"food","date":1}
        """
        let dto = try JSONCoding.decode(ExpenseDTO.self, from: Data(ancient.utf8))
        XCTAssertEqual(dto.schemaVersion, 1)
    }

    func testDecodesASchema2ExpenseUnchanged() throws {
        let current = """
        {
          "id": "3F2504E0-4F89-41D3-9A0C-0305E82C3301",
          "amount": 20, "description": "Modern", "category": "food",
          "date": 1700000000, "updatedAt": 1750000000000,
          "deletedAt": null, "isPendingSync": false, "schemaVersion": 2
        }
        """
        let dto = try JSONCoding.decode(ExpenseDTO.self, from: Data(current.utf8))

        XCTAssertEqual(dto.updatedAt, 1_750_000_000_000)
        XCTAssertFalse(dto.isPendingSync)
        XCTAssertEqual(dto.schemaVersion, 2)
    }

    func testAWholeLegacyListStillDecodes() throws {
        let legacyList = """
        [
          {"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","amount":1,
           "description":"a","category":"food","date":1,"schemaVersion":1},
          {"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3302","amount":2,
           "description":"b","category":"transport","date":2,"schemaVersion":1}
        ]
        """
        let dtos = try JSONCoding.decode([ExpenseDTO].self, from: Data(legacyList.utf8))
        XCTAssertEqual(dtos.count, 2)
    }

    func testRoundTripsThroughTheStoreWithoutLoss() throws {
        let original = makeExpenseDTO(updatedAt: 123_456, deletedAt: 789, isPendingSync: false)
        let data = try JSONCoding.encode([original])
        let decoded = try JSONCoding.decode([ExpenseDTO].self, from: data)

        XCTAssertEqual(decoded.first, original)
    }

    // MARK: - Budgets

    func testDecodesASchema1Budget() throws {
        let legacy = """
        {"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","category":"food",
         "limit":300,"createdAt":1700000000}
        """
        let dto = try JSONCoding.decode(BudgetDTO.self, from: Data(legacy.utf8))

        XCTAssertEqual(dto.limit, 300)
        XCTAssertEqual(dto.updatedAt, 0)
        XCTAssertTrue(dto.isPendingSync)
        XCTAssertNil(dto.deletedAt)
    }

    // MARK: - Derived copies

    func testTombstonedSetsBothTimestampsAndMarksPending() {
        let now = Date(timeIntervalSince1970: 1_000)
        let dto = makeExpenseDTO(isPendingSync: false).tombstoned(at: now)

        XCTAssertEqual(dto.deletedAt, 1_000_000)
        XCTAssertEqual(dto.updatedAt, 1_000_000)
        XCTAssertTrue(dto.isPendingSync)
    }

    func testMarkedEditedAdvancesUpdatedAtAndMarksPending() {
        let now = Date(timeIntervalSince1970: 2_000)
        let dto = makeExpenseDTO(updatedAt: 1, isPendingSync: false).markedEdited(at: now)

        XCTAssertEqual(dto.updatedAt, 2_000_000)
        XCTAssertTrue(dto.isPendingSync)
        XCTAssertNil(dto.deletedAt)
    }

    func testMarkedSyncedClearsOnlyThePendingFlag() {
        let original = makeExpenseDTO(updatedAt: 4_000, isPendingSync: true)
        let synced = original.markedSynced()

        XCTAssertFalse(synced.isPendingSync)
        XCTAssertEqual(synced.updatedAt, original.updatedAt)
        XCTAssertEqual(synced.amount, original.amount)
    }
}
