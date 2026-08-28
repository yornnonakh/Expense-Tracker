//
//  LocalExpenseDataSourceTests.swift
//  expense_trackerTests
//
//  The local store is the app's source of truth, so its tombstone and merge
//  rules are what stand between an offline edit and silent data loss.
//

import XCTest
@testable import expense_tracker

final class LocalExpenseDataSourceTests: XCTestCase {

    private var source: LocalExpenseDataSource!
    private var store: InMemoryKeyValueStore!

    override func setUp() async throws {
        try await super.setUp()
        (source, store) = try makeLocalExpenseDataSource()
    }

    // MARK: - Basics

    func testInsertThenFetch() async throws {
        let dto = makeExpenseDTO(description: "Lunch")
        try await source.insert(dto)

        let all = try await source.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.description, "Lunch")
    }

    func testRejectsADuplicateLiveId() async throws {
        let dto = makeExpenseDTO()
        try await source.insert(dto)

        do {
            try await source.insert(dto)
            XCTFail("Expected a duplicate-id error")
        } catch let error as ExpenseError {
            guard case .persistenceFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testAllowsReusingTheIdOfATombstonedRecord() async throws {
        let dto = makeExpenseDTO()
        try await source.insert(dto)
        try await source.delete(id: dto.id)

        // Re-inserting is how an undo works. Refusing would make the id
        // permanently unusable.
        try await source.insert(dto)

        let live = try await source.fetchAll()
        XCTAssertEqual(live.count, 1)
    }

    func testUpdatingAMissingRecordThrows() async throws {
        do {
            try await source.update(makeExpenseDTO())
            XCTFail("Expected expenseNotFound")
        } catch let error as ExpenseError {
            XCTAssertEqual(error, .expenseNotFound)
        }
    }

    // MARK: - Tombstones

    func testDeleteWritesATombstoneRatherThanRemovingTheRow() async throws {
        let dto = makeExpenseDTO()
        try await source.insert(dto)
        try await source.delete(id: dto.id)

        let visible = try await source.fetchAll()
        XCTAssertTrue(visible.isEmpty)

        // The row must survive so the deletion can replicate.
        let everything = try await source.fetchAllIncludingDeleted()
        XCTAssertEqual(everything.count, 1)
        XCTAssertNotNil(everything.first?.deletedAt)
        XCTAssertTrue(everything.first!.isPendingSync)
    }

    func testDeletingTwiceThrows() async throws {
        let dto = makeExpenseDTO()
        try await source.insert(dto)
        try await source.delete(id: dto.id)

        do {
            try await source.delete(id: dto.id)
            XCTFail("Expected expenseNotFound")
        } catch let error as ExpenseError {
            XCTAssertEqual(error, .expenseNotFound)
        }
    }

    func testFetchByIdIgnoresTombstones() async throws {
        let dto = makeExpenseDTO()
        try await source.insert(dto)
        try await source.delete(id: dto.id)

        let found = try await source.fetch(id: dto.id)
        XCTAssertNil(found)
    }

    func testDeleteAllTombstonesEveryLiveRecord() async throws {
        try await source.insert(makeExpenseDTO())
        try await source.insert(makeExpenseDTO())

        try await source.deleteAll()

        let live = try await source.fetchAll()
        XCTAssertTrue(live.isEmpty)
        let everything = try await source.fetchAllIncludingDeleted()
        XCTAssertEqual(everything.count, 2)
        XCTAssertTrue(everything.allSatisfy(\.isDeleted))
    }

    func testPurgeAllLeavesNothingBehind() async throws {
        try await source.insert(makeExpenseDTO())
        try await source.delete(id: try await source.fetchAllIncludingDeleted()[0].id)

        try await source.purgeAll()

        // Sign-out must not leave tombstones that would upload as the next
        // account's deletions.
        let everything = try await source.fetchAllIncludingDeleted()
        XCTAssertTrue(everything.isEmpty)
    }

    // MARK: - Pending tracking

    func testNewRecordsArePending() async throws {
        try await source.insert(makeExpenseDTO(isPendingSync: true))
        let pending = try await source.pendingChanges()
        XCTAssertEqual(pending.count, 1)
    }

    func testMarkSyncedClearsThePendingFlag() async throws {
        let dto = makeExpenseDTO(updatedAt: 5_000, isPendingSync: true)
        try await source.insert(dto)

        try await source.markSynced([dto.id: 5_000])

        let pending = try await source.pendingChanges()
        XCTAssertTrue(pending.isEmpty)
    }

    func testMarkSyncedIgnoresARecordEditedSinceThePush() async throws {
        let dto = makeExpenseDTO(updatedAt: 5_000, isPendingSync: true)
        try await source.insert(dto)

        // Acknowledging an older timestamp than the one now stored.
        try await source.markSynced([dto.id: 1_000])

        let pending = try await source.pendingChanges()
        XCTAssertEqual(pending.count, 1)
    }

    // MARK: - Remote merge

    func testApplyRemoteAddsUnknownRecords() async throws {
        try await source.applyRemote([makeExpenseDTO(description: "Remote", isPendingSync: false)])

        let all = try await source.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.description, "Remote")
    }

    func testApplyRemoteOverwritesANonPendingLocalRecord() async throws {
        let id = UUID().uuidString
        try await source.insert(makeExpenseDTO(id: id, amount: 10, isPendingSync: false))

        try await source.applyRemote([
            makeExpenseDTO(id: id, amount: 99, updatedAt: 9_000, isPendingSync: false)
        ])

        let all = try await source.fetchAll()
        XCTAssertEqual(all.first?.amount, 99)
    }

    func testApplyRemoteKeepsANewerPendingLocalEdit() async throws {
        let id = UUID().uuidString
        try await source.insert(
            makeExpenseDTO(id: id, amount: 42, updatedAt: 9_000, isPendingSync: true)
        )

        try await source.applyRemote([
            makeExpenseDTO(id: id, amount: 10, updatedAt: 1_000, isPendingSync: false)
        ])

        let all = try await source.fetchAll()
        XCTAssertEqual(all.first?.amount, 42, "A newer unsent local edit must not be overwritten")
    }

    func testApplyRemoteOverwritesAnOlderPendingLocalEdit() async throws {
        let id = UUID().uuidString
        try await source.insert(
            makeExpenseDTO(id: id, amount: 42, updatedAt: 1_000, isPendingSync: true)
        )

        try await source.applyRemote([
            makeExpenseDTO(id: id, amount: 10, updatedAt: 9_000, isPendingSync: false)
        ])

        let all = try await source.fetchAll()
        XCTAssertEqual(all.first?.amount, 10)
    }

    // MARK: - Persistence

    func testSurvivesAFreshDataSourceOverTheSameStore() async throws {
        try await source.insert(makeExpenseDTO(description: "Persisted"))

        // A new actor instance re-reads from the store rather than the cache.
        let reopened = LocalExpenseDataSource(store: store)
        let all = try await reopened.fetchAll()

        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.description, "Persisted")
    }

    func testReportsUnreadableStorageRatherThanPretendingItIsEmpty() async throws {
        store.set(Data("not json".utf8), forKey: StorageKey.expenses)
        let broken = LocalExpenseDataSource(store: store)

        do {
            _ = try await broken.fetchAll()
            XCTFail("Expected a decoding error")
        } catch let error as ExpenseError {
            guard case .decodingFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testConcurrentInsertsAllLand() async throws {
        // The actor serialises read-modify-write, so none of these may clobber
        // another's append.
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask { [source] in
                    try? await source?.insert(makeExpenseDTO(description: "Expense \(index)"))
                }
            }
        }

        let all = try await source.fetchAll()
        XCTAssertEqual(all.count, 50)
    }
}
