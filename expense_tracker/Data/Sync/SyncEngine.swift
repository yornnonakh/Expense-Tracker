//
//  SyncEngine.swift
//  Data Layer — Sync
//
//  One sync cycle: push what this device changed, pull what changed
//  elsewhere, reconcile the two.
//
//  ORDER OF OPERATIONS, and why each step has to be where it is:
//
//    1. Read the watermark and the pending records.
//    2. Push, asking for changes since the watermark in the same request.
//    3. Clear the pending flag on records the server accepted — BEFORE
//       applying anything pulled. A record we just uploaded comes straight
//       back in the pull (its server timestamp is now past the watermark); if
//       it were still marked pending, the merge would treat the echo as a
//       conflict with itself.
//    4. Adopt the server's copy for conflicts. These are records the server
//       refused because it held something newer, and they may be older than
//       the watermark, so the pull would not have included them.
//    5. Apply pulled changes.
//    6. Advance the watermark — last, so a failure anywhere above leaves the
//       cursor where it was and the next cycle retries the same window.
//
//  Steps 3–5 are local writes that cannot fail on the network, so a crash
//  between them costs at most a repeated download, never a lost edit.
//

import Foundation
import OSLog

nonisolated struct SyncReport: Equatable, Sendable {
    var pushedExpenses = 0
    var pushedBudgets = 0
    var appliedByServer = 0
    var conflicts = 0
    var pulledExpenses = 0
    var pulledBudgets = 0

    /// Whether anything on this device changed, which is what decides if the
    /// UI needs to reload.
    var didChangeLocalData: Bool {
        conflicts > 0 || pulledExpenses > 0 || pulledBudgets > 0
    }

    var isEmpty: Bool {
        pushedExpenses == 0 && pushedBudgets == 0
            && pulledExpenses == 0 && pulledBudgets == 0 && conflicts == 0
    }
}

actor SyncEngine {

    private let localExpenses: LocalExpenseDataSource
    private let localBudgets: LocalBudgetDataSource
    private let remote: RemoteSyncDataSourceProtocol
    private let syncState: SyncStateStoring
    private let notificationCenter: NotificationCenter

    /// How long an acknowledged tombstone is kept before being compacted away.
    ///
    /// Generous on purpose. A tombstone dropped while some other device is
    /// still behind the watermark stops suppressing the record there, and the
    /// deleted expense reappears. 90 days is far longer than any realistic
    /// offline window, and tombstones are tiny.
    private static let tombstoneRetention: TimeInterval = 90 * 24 * 60 * 60

    init(
        localExpenses: LocalExpenseDataSource,
        localBudgets: LocalBudgetDataSource,
        remote: RemoteSyncDataSourceProtocol,
        syncState: SyncStateStoring,
        notificationCenter: NotificationCenter = .default
    ) {
        self.localExpenses = localExpenses
        self.localBudgets = localBudgets
        self.remote = remote
        self.syncState = syncState
        self.notificationCenter = notificationCenter
    }

    /// Runs one full cycle. Throws on transport failures so the caller can
    /// decide whether to retry, back off, or stay quiet about it.
    @discardableResult
    func sync() async throws -> SyncReport {
        let watermark = await syncState.watermark()

        let pendingExpenses = try await localExpenses.pendingChanges()
        let pendingBudgets = try await localBudgets.pendingChanges()

        AppLog.sync.debug(
            "cycle start: \(pendingExpenses.count, privacy: .public) expenses, \(pendingBudgets.count, privacy: .public) budgets pending, watermark \(Int64(watermark), privacy: .public)"
        )

        let response = try await remote.push(
            expenses: pendingExpenses.map(SyncMapper.toAPI),
            budgets: pendingBudgets.map(SyncMapper.toAPI),
            since: watermark
        )

        var report = SyncReport(
            pushedExpenses: pendingExpenses.count,
            pushedBudgets: pendingBudgets.count,
            appliedByServer: response.applied,
            conflicts: response.conflicts.count
        )

        // Step 3 — clear pending for everything the server did NOT reject.
        let rejectedIds = Set(response.conflicts.map(\.id))

        let acknowledgedExpenses = Dictionary(
            uniqueKeysWithValues: pendingExpenses
                .filter { !rejectedIds.contains($0.id) }
                .map { ($0.id, $0.updatedAt) }
        )
        let acknowledgedBudgets = Dictionary(
            uniqueKeysWithValues: pendingBudgets
                .filter { !rejectedIds.contains($0.id) }
                .map { ($0.id, $0.updatedAt) }
        )

        try await localExpenses.markSynced(acknowledgedExpenses)
        try await localBudgets.markSynced(acknowledgedBudgets)

        // Step 4 — adopt the server's version of every conflict.
        let conflictExpenses = response.conflicts.compactMap(\.serverExpense).map(SyncMapper.toDTO)
        let conflictBudgets = response.conflicts.compactMap(\.serverBudget).map(SyncMapper.toDTO)

        if !conflictExpenses.isEmpty {
            try await localExpenses.applyRemote(conflictExpenses)
        }
        if !conflictBudgets.isEmpty {
            try await localBudgets.applyRemote(conflictBudgets)
        }

        // Step 5 — apply pulled changes.
        let pulledExpenses = (response.expenses ?? []).map(SyncMapper.toDTO)
        let pulledBudgets = (response.budgets ?? []).map(SyncMapper.toDTO)

        if !pulledExpenses.isEmpty {
            try await localExpenses.applyRemote(pulledExpenses)
        }
        if !pulledBudgets.isEmpty {
            try await localBudgets.applyRemote(pulledBudgets)
        }

        report.pulledExpenses = pulledExpenses.count
        report.pulledBudgets = pulledBudgets.count

        // Step 6 — the cursor moves only once everything above has landed.
        await syncState.setWatermark(response.serverTime)

        try? await compactTombstones()

        if report.didChangeLocalData {
            await announceChanges(report)
        }

        AppLog.sync.info(
            "cycle done: applied \(report.appliedByServer, privacy: .public), conflicts \(report.conflicts, privacy: .public), pulled \(report.pulledExpenses + report.pulledBudgets, privacy: .public)"
        )

        return report
    }

    /// Clears the local store and cursor. Called on sign-out.
    func reset() async throws {
        try await localExpenses.purgeAll()
        try await localBudgets.purgeAll()
        await syncState.reset()
    }

    // MARK: - Helpers

    private func compactTombstones() async throws {
        let cutoff = Date().addingTimeInterval(-Self.tombstoneRetention)
        try await localExpenses.compact(olderThan: cutoff)
        try await localBudgets.compact(olderThan: cutoff)
    }

    private func announceChanges(_ report: SyncReport) async {
        if report.pulledExpenses > 0 || report.conflicts > 0 {
            notificationCenter.post(name: .expenseDataDidChange, object: nil)
        }
        if report.pulledBudgets > 0 || report.conflicts > 0 {
            notificationCenter.post(name: .budgetDataDidChange, object: nil)
        }
    }
}
