//
//  WireTimestampTests.swift
//  expense_trackerTests
//
//  The server validates every millisecond field as an integer and rejects a
//  float, failing the entire push rather than the one record. `Date()
//  .timeIntervalSince1970 * 1000` is fractional, so every real sync from the
//  app 400'd while the sync tests stayed green: they inject a fake remote,
//  which has no validation, and the server's own tests build fixtures from
//  `Date.now()`, which is already integral. Nothing exercised the seam.
//
//  These tests pin the contract on the client side, where it is cheap to
//  check, so the next timestamp added cannot quietly reintroduce a float.
//

import XCTest
@testable import expense_tracker

final class WireTimestampTests: XCTestCase {

    /// The rule the server enforces, restated locally.
    private func assertWholeMillis(
        _ value: Double?,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let value else { return }
        XCTAssertEqual(
            value, value.rounded(.down),
            "\(label) must be whole milliseconds; the server rejects a float.",
            file: file, line: line
        )
    }

    // MARK: - Generation

    func testANewExpenseStampsWholeMilliseconds() {
        let dto = ExpenseDTO(
            id: UUID().uuidString,
            amount: 12.5,
            description: "Lunch",
            category: "food",
            date: 1_700_000_000
        )
        assertWholeMillis(dto.updatedAt, "updatedAt")
    }

    func testANewBudgetStampsWholeMilliseconds() {
        let dto = BudgetDTO(
            id: UUID().uuidString,
            category: "food",
            limit: 300,
            createdAt: 1_700_000_000
        )
        assertWholeMillis(dto.updatedAt, "updatedAt")
    }

    /// The clock is only whole-millisecond by luck at any single instant, so a
    /// single sample would pass against the unfixed code roughly one time in a
    /// thousand. Sampling repeatedly makes the failure deterministic.
    func testRepeatedStampsAreAlwaysWhole() {
        for _ in 0..<200 {
            let expense = ExpenseDTO(
                id: UUID().uuidString,
                amount: 1,
                description: "Tick",
                category: "food",
                date: 1_700_000_000
            )
            assertWholeMillis(expense.updatedAt, "updatedAt")
        }
    }

    // MARK: - Derived copies

    func testMarkedEditedStampsWholeMilliseconds() {
        let dto = ExpenseDTO(
            id: UUID().uuidString,
            amount: 12.5,
            description: "Lunch",
            category: "food",
            date: 1_700_000_000
        ).markedEdited(at: Date(timeIntervalSince1970: 1_700_000_000.123_456))

        assertWholeMillis(dto.updatedAt, "updatedAt")
    }

    func testTombstoneStampsWholeMilliseconds() {
        let dto = ExpenseDTO(
            id: UUID().uuidString,
            amount: 12.5,
            description: "Lunch",
            category: "food",
            date: 1_700_000_000
        ).tombstoned(at: Date(timeIntervalSince1970: 1_700_000_000.987_654))

        assertWholeMillis(dto.updatedAt, "updatedAt")
        assertWholeMillis(dto.deletedAt, "deletedAt")
    }

    func testBudgetTombstoneStampsWholeMilliseconds() {
        let dto = BudgetDTO(
            id: UUID().uuidString,
            category: "food",
            limit: 300,
            createdAt: 1_700_000_000
        ).tombstoned(at: Date(timeIntervalSince1970: 1_700_000_000.987_654))

        assertWholeMillis(dto.updatedAt, "updatedAt")
        assertWholeMillis(dto.deletedAt, "deletedAt")
    }

    // MARK: - Legacy rows

    /// Rows written before the fix are still on disk holding a fractional
    /// value. They have to be normalised on read, or one stale record keeps
    /// 400ing the batch that carries every other record with it.
    func testAStoredFractionalTimestampIsTruncatedOnDecode() throws {
        let legacy = """
        {
          "id": "3F2504E0-4F89-41D3-9A0C-0305E82C3301",
          "amount": 12.5,
          "description": "Fractional",
          "category": "food",
          "date": 1700000000,
          "updatedAt": 1787744118838.855,
          "deletedAt": 1787744118840.221,
          "schemaVersion": 2
        }
        """

        let dto = try JSONCoding.decode(ExpenseDTO.self, from: Data(legacy.utf8))

        XCTAssertEqual(dto.updatedAt, 1_787_744_118_838)
        XCTAssertEqual(dto.deletedAt, 1_787_744_118_840)
    }

    func testAStoredFractionalBudgetTimestampIsTruncatedOnDecode() throws {
        let legacy = """
        {
          "id": "3F2504E0-4F89-41D3-9A0C-0305E82C3302",
          "category": "food",
          "limit": 300,
          "createdAt": 1700000000,
          "updatedAt": 1787744118838.855,
          "schemaVersion": 2
        }
        """

        let dto = try JSONCoding.decode(BudgetDTO.self, from: Data(legacy.utf8))

        XCTAssertEqual(dto.updatedAt, 1_787_744_118_838)
    }

    // MARK: - Encoded form

    /// The end of the chain: what actually lands in the request body. A whole
    /// `Double` must not encode as `…838.0`, which is the shape the server's
    /// integer check refuses.
    func testEncodedExpenseCarriesNoDecimalPoint() throws {
        let api = SyncMapper.toAPI(
            ExpenseDTO(
                id: UUID().uuidString,
                amount: 12.5,
                description: "Lunch",
                category: "food",
                date: 1_700_000_000
            )
        )

        let json = String(decoding: try JSONCoding.encode(api), as: UTF8.self)

        // Locate the encoded number for `updatedAt` and assert it is integral.
        let pattern = #""updatedAt"\s*:\s*([0-9.eE+-]+)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(json.startIndex..., in: json)
        let match = try XCTUnwrap(
            regex.firstMatch(in: json, range: range),
            "updatedAt missing from encoded payload: \(json)"
        )
        let encoded = String(json[Range(match.range(at: 1), in: json)!])
        let value = try XCTUnwrap(Double(encoded))

        assertWholeMillis(value, "encoded updatedAt")
        XCTAssertFalse(
            encoded.contains("."),
            "updatedAt encoded as \"\(encoded)\"; the server parses this as a float."
        )
    }
}
