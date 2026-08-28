//
//  SyncEngineTests.swift
//  expense_trackerTests
//
//  The client half of the sync protocol.
//
//  These are the tests that matter most in the app: a bug here does not throw
//  an error the user can see, it silently loses an expense or resurrects a
//  deleted one. Every case below is a specific way that could happen.
//

import XCTest
@testable import expense_tracker

final class SyncEngineTests: XCTestCase {

    private var localExpenses: LocalExpenseDataSource!
    private var localBudgets: LocalBudgetDataSource!
    private var remote: StubRemoteSyncDataSource!
    private var syncState: InMemorySyncStateStore!
    private var engine: SyncEngine!

    /// A notification centre of our own, so posts from the engine cannot reach
    /// the app's real observers or another test running in parallel.
    private var notificationCenter: NotificationCenter!

    override func setUp() async throws {
        try await super.setUp()
        (localExpenses, _) = try makeLocalExpenseDataSource()
        (localBudgets, _) = try makeLocalBudgetDataSource()
        remote = StubRemoteSyncDataSource()
        syncState = InMemorySyncStateStore()
        notificationCenter = NotificationCenter()

        engine = SyncEngine(
            localExpenses: localExpenses,
            localBudgets: localBudgets,
            remote: remote,
            syncState: syncState,
            notificationCenter: notificationCenter
        )
    }

    // MARK: - Push

    func testPushesPendingExpensesAndClearsTheirPendingFlag() async throws {
        let dto = makeExpenseDTO(description: "Coffee", isPendingSync: true)
        try await localExpenses.insert(dto)

        let report = try await engine.sync()

        XCTAssertEqual(report.pushedExpenses, 1)
        XCTAssertEqual(report.appliedByServer, 1)

        let uploaded = await remote.storedExpense(id: dto.id)
        XCTAssertEqual(uploaded?.description, "Coffee")

        // The flag must clear, or every future sync re-uploads the same record.
        let pending = try await localExpenses.pendingChanges()
        XCTAssertTrue(pending.isEmpty)
    }

    func testDoesNotPushRecordsThatAreAlreadySynced() async throws {
        try await localExpenses.insert(makeExpenseDTO(isPendingSync: false))

        let report = try await engine.sync()

        XCTAssertEqual(report.pushedExpenses, 0)
        let count = await remote.storedExpenseCount()
        XCTAssertEqual(count, 0)
    }

    func testPushesTombstonesSoDeletesReplicate() async throws {
        let dto = makeExpenseDTO(isPendingSync: false)
        try await localExpenses.insert(dto)
        try await localExpenses.delete(id: dto.id)

        _ = try await engine.sync()

        let uploaded = await remote.storedExpense(id: dto.id)
        XCTAssertNotNil(uploaded?.deletedAt, "A delete must reach the server as a tombstone")
    }

    // MARK: - Pull

    func testPullsRecordsCreatedOnAnotherDevice() async throws {
        let remoteExpense = makeAPIExpense(description: "From another phone")
        await remote.seed(expense: remoteExpense)

        let report = try await engine.sync()

        XCTAssertEqual(report.pulledExpenses, 1)

        let stored = try await localExpenses.fetchAll()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.description, "From another phone")

        // Pulled records are not pending: they came from the server, so
        // pushing them back would be a pointless round trip.
        XCTAssertEqual(stored.first?.isPendingSync, false)
    }

    func testPulledTombstoneRemovesTheRecordFromTheVisibleList() async throws {
        let id = UUID().uuidString
        try await localExpenses.insert(makeExpenseDTO(id: id, isPendingSync: false))

        // Another device deleted it, just now. The timestamp has to be a real
        // one: tombstone compaction drops anything older than 90 days, so a
        // token value like `9_999` would be a 1970 date and get swept away
        // before the assertions below could see it.
        let justNow = Date().timeIntervalSince1970 * 1000
        await remote.seed(
            expense: makeAPIExpense(id: id, updatedAt: justNow, deletedAt: justNow)
        )

        _ = try await engine.sync()

        let visible = try await localExpenses.fetchAll()
        XCTAssertTrue(visible.isEmpty)

        // ...but the tombstone is retained, so the record cannot come back.
        let everything = try await localExpenses.fetchAllIncludingDeleted()
        XCTAssertEqual(everything.count, 1)
        XCTAssertNotNil(everything.first?.deletedAt)
    }

    func testDoesNotResurrectALocallyDeletedRecordOnTheNextSync() async throws {
        let dto = makeExpenseDTO(isPendingSync: false)
        try await localExpenses.insert(dto)

        // First sync uploads the record.
        try await localExpenses.update(dto.markedEdited())
        _ = try await engine.sync()

        // Delete it, sync again.
        try await localExpenses.delete(id: dto.id)
        _ = try await engine.sync()

        // A third sync must not bring it back.
        _ = try await engine.sync()

        let visible = try await localExpenses.fetchAll()
        XCTAssertTrue(visible.isEmpty, "A deleted expense reappeared after syncing")
    }

    func testCompactsTombstonesOlderThanTheRetentionWindow() async throws {
        let id = UUID().uuidString
        try await localExpenses.insert(makeExpenseDTO(id: id, isPendingSync: false))

        // Deleted well over 90 days ago and already acknowledged.
        let ancient = Date().addingTimeInterval(-100 * 24 * 60 * 60)
            .timeIntervalSince1970 * 1000
        await remote.seed(
            expense: makeAPIExpense(id: id, updatedAt: ancient, deletedAt: ancient)
        )

        _ = try await engine.sync()

        // Storage must not accumulate every delete the user ever made.
        let everything = try await localExpenses.fetchAllIncludingDeleted()
        XCTAssertTrue(everything.isEmpty, "An expired tombstone should be compacted away")
    }

    func testKeepsAnUnsyncedTombstoneEvenWhenItIsOld() async throws {
        // Backdated far past the retention window, but never uploaded.
        let ancient = Date().addingTimeInterval(-100 * 24 * 60 * 60)
        let dto = makeExpenseDTO(isPendingSync: false)
        try await localExpenses.insert(dto)
        try await localExpenses.delete(id: dto.id, at: ancient)

        await remote.setError(APIError.offline)
        _ = try? await engine.sync()

        // Compacting this would drop the delete before the server ever heard
        // about it, and the record would come back on the next successful pull.
        let everything = try await localExpenses.fetchAllIncludingDeleted()
        XCTAssertEqual(everything.count, 1)
        XCTAssertTrue(everything[0].isPendingSync)
    }

    // MARK: - Watermark

    func testAdvancesTheWatermarkFromTheServersClockNotTheDevices() async throws {
        let before = await syncState.watermark()
        XCTAssertEqual(before, 0)

        _ = try await engine.sync()
        let after = await syncState.watermark()

        // The stub's clock counts in small integers. A device clock would be
        // ~1.7e12, so this also proves the value is not locally derived.
        XCTAssertGreaterThan(after, 0)
        XCTAssertLessThan(after, 1_000, "Watermark must come from the server's clock")
    }

    func testDoesNotRefetchUnchangedRecordsOnASecondSync() async throws {
        await remote.seed(expense: makeAPIExpense())

        let first = try await engine.sync()
        XCTAssertEqual(first.pulledExpenses, 1)

        let second = try await engine.sync()
        XCTAssertEqual(second.pulledExpenses, 0, "Watermark did not suppress a repeat pull")
    }

    // MARK: - Conflicts

    func testAdoptsTheServersCopyWhenTheLocalEditIsStale() async throws {
        let id = UUID().uuidString

        // The server already holds a newer version.
        await remote.seed(expense: makeAPIExpense(id: id, amount: 99, updatedAt: 5_000))

        // This device has an older pending edit.
        try await localExpenses.insert(
            makeExpenseDTO(id: id, amount: 10, updatedAt: 1_000, isPendingSync: true)
        )

        let report = try await engine.sync()

        XCTAssertEqual(report.conflicts, 1)
        XCTAssertEqual(report.appliedByServer, 0)

        let stored = try await localExpenses.fetchAll()
        XCTAssertEqual(stored.first?.amount, 99, "Server's newer copy should win")
        XCTAssertEqual(stored.first?.isPendingSync, false)
    }

    func testKeepsTheLocalEditWhenItIsNewerThanTheServersCopy() async throws {
        let id = UUID().uuidString
        await remote.seed(expense: makeAPIExpense(id: id, amount: 10, updatedAt: 1_000))

        try await localExpenses.insert(
            makeExpenseDTO(id: id, amount: 99, updatedAt: 5_000, isPendingSync: true)
        )

        let report = try await engine.sync()

        XCTAssertEqual(report.conflicts, 0)
        XCTAssertEqual(report.appliedByServer, 1)

        let stored = try await localExpenses.fetchAll()
        XCTAssertEqual(stored.first?.amount, 99)

        let uploaded = await remote.storedExpense(id: id)
        XCTAssertEqual(uploaded?.amount, 99)
    }

    /// The subtle one: the user edits a record while its push is in flight.
    func testKeepsAnEditMadeDuringAPushPending() async throws {
        let dto = makeExpenseDTO(amount: 10, updatedAt: 1_000, isPendingSync: true)
        try await localExpenses.insert(dto)

        // Simulate the edit landing after `pendingChanges` was read but before
        // `markSynced` runs: the stored copy now has a different `updatedAt`
        // from the one that was uploaded.
        let edited = ExpenseDTO(
            id: dto.id, amount: 42, description: dto.description,
            category: dto.category, date: dto.date,
            updatedAt: 7_000, deletedAt: nil, isPendingSync: true
        )
        try await localExpenses.update(edited)

        // Acknowledge only the *original* timestamp, as a push of the earlier
        // version would.
        try await localExpenses.markSynced([dto.id: 1_000])

        let pending = try await localExpenses.pendingChanges()
        XCTAssertEqual(
            pending.count, 1,
            "An edit made during a push must stay pending, or it is never uploaded"
        )
        XCTAssertEqual(pending.first?.amount, 42)
    }

    // MARK: - Budgets

    func testSyncsBudgets() async throws {
        try await localBudgets.upsert(makeBudgetDTO(category: "transport", limit: 150))

        let report = try await engine.sync()

        XCTAssertEqual(report.pushedBudgets, 1)
        let stored = try await localBudgets.fetchAll()
        XCTAssertEqual(stored.count, 1)
    }

    func testKeepsOnlyOneLiveBudgetPerCategoryAfterAPull() async throws {
        // Two different ids for the same category — what two offline devices
        // would produce.
        try await localBudgets.upsert(
            makeBudgetDTO(category: "food", limit: 100, updatedAt: 1_000, isPendingSync: false)
        )
        await remote.seed(
            budget: makeAPIBudget(category: "food", limit: 200, updatedAt: 5_000)
        )

        _ = try await engine.sync()

        let live = try await localBudgets.fetchAll()
        XCTAssertEqual(live.count, 1, "A category must never show two live budgets")
        XCTAssertEqual(live.first?.limit, 200)
    }

    // MARK: - Failure handling

    func testLeavesTheWatermarkUntouchedWhenThePushFails() async throws {
        try await localExpenses.insert(makeExpenseDTO())
        await remote.setError(APIError.offline)

        do {
            _ = try await engine.sync()
            XCTFail("Expected the sync to throw")
        } catch {
            // Expected.
        }

        let watermark = await syncState.watermark()
        XCTAssertEqual(watermark, 0, "A failed sync must not advance the cursor")

        // ...and the record is still queued for the next attempt.
        let pending = try await localExpenses.pendingChanges()
        XCTAssertEqual(pending.count, 1)
    }

    func testRecoversAndUploadsAfterAnOutage() async throws {
        try await localExpenses.insert(makeExpenseDTO(description: "Written offline"))

        await remote.setError(APIError.offline)
        _ = try? await engine.sync()

        await remote.setError(nil)
        let report = try await engine.sync()

        XCTAssertEqual(report.appliedByServer, 1)
        let uploaded = await remote.storedExpenseCount()
        XCTAssertEqual(uploaded, 1)
    }

    // MARK: - Notifications

    func testAnnouncesChangesOnlyWhenSomethingActuallyChangedLocally() async throws {
        let expectation = XCTNSNotificationExpectation(
            name: .expenseDataDidChange,
            object: nil,
            notificationCenter: notificationCenter
        )

        await remote.seed(expense: makeAPIExpense())
        _ = try await engine.sync()

        await fulfillment(of: [expectation], timeout: 2)
    }

    func testDoesNotAnnounceWhenNothingChanged() async throws {
        let expectation = XCTNSNotificationExpectation(
            name: .expenseDataDidChange,
            object: nil,
            notificationCenter: notificationCenter
        )
        expectation.isInverted = true

        _ = try await engine.sync()

        await fulfillment(of: [expectation], timeout: 0.5)
    }

    // MARK: - Reset

    func testResetClearsLocalDataAndTheCursor() async throws {
        try await localExpenses.insert(makeExpenseDTO())
        try await localBudgets.upsert(makeBudgetDTO())
        _ = try await engine.sync()

        try await engine.reset()

        let expenses = try await localExpenses.fetchAllIncludingDeleted()
        let budgets = try await localBudgets.fetchAllIncludingDeleted()
        let watermark = await syncState.watermark()

        // No tombstones either: sign-out must leave nothing to upload on
        // behalf of the account that just left.
        XCTAssertTrue(expenses.isEmpty)
        XCTAssertTrue(budgets.isEmpty)
        XCTAssertEqual(watermark, 0)
    }
}
