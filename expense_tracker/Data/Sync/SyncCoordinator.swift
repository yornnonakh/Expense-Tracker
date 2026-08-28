//
//  SyncCoordinator.swift
//  Data Layer — Sync
//
//  Decides WHEN to sync. `SyncEngine` decides what a sync does.
//
//  Splitting the two keeps the merge logic free of timers, notifications and
//  app lifecycle, which is what lets it be tested by calling one method.
//
//  SINGLE-FLIGHT: at most one cycle runs at a time. Overlapping cycles would
//  both read the same watermark, both push the same pending records, and the
//  second would collide with the first's writes. A request arriving mid-cycle
//  sets `needsAnotherPass` instead, so nothing is dropped and nothing doubles.
//
//  THE ECHO PROBLEM: a successful sync posts `expenseDataDidChange` so open
//  screens reload — and this class listens to that same notification to know
//  when to push. Left alone that is an infinite loop. `isSyncing` is what
//  breaks it: notifications posted while a cycle is in flight are the cycle's
//  own echo and are ignored.
//

import Combine
import Foundation
import OSLog

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class SyncCoordinator: ObservableObject {

    enum Status: Equatable {
        case idle
        case syncing
        /// Last attempt failed for a connectivity reason. Not an error state —
        /// the app is designed to work here, so the UI says so quietly.
        case offline
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastSyncedAt: Date?

    private let engine: SyncEngine
    private let notificationCenter: NotificationCenter

    private var isSyncing = false
    private var needsAnotherPass = false
    private var observers: [NSObjectProtocol] = []

    /// Consecutive connectivity failures, used to back off.
    private var consecutiveFailures = 0

    /// Coalescing window for change-driven syncs. Long enough that adding
    /// three expenses in a row is one upload, short enough to feel immediate.
    private static let debounce: Duration = .milliseconds(800)

    private var debounceTask: Task<Void, Never>?

    init(engine: SyncEngine, notificationCenter: NotificationCenter = .default) {
        self.engine = engine
        self.notificationCenter = notificationCenter
    }

    deinit {
        // `observers` and `debounceTask` are main-actor state; capture what
        // deinit needs without hopping actors, which deinit cannot do.
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Lifecycle

    /// Begins watching for the events that should trigger a sync.
    /// Safe to call more than once; later calls replace the observers.
    func start() {
        stop()

        // Each closure carries its own `[weak self]`. Without the inner one,
        // the `Task` body reads the outer closure's captured variable from
        // concurrently-executing code — an error in Swift 6 language mode.
        let localChange: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in self?.requestSync() }
        }

        observers.append(
            notificationCenter.addObserver(
                forName: .expenseDataDidChange, object: nil, queue: nil, using: localChange
            )
        )
        observers.append(
            notificationCenter.addObserver(
                forName: .budgetDataDidChange, object: nil, queue: nil, using: localChange
            )
        )

        #if canImport(UIKit)
        observers.append(
            notificationCenter.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                // Coming back from the background is the single most likely
                // moment for another device's changes to be waiting.
                Task { @MainActor in await self?.syncNow() }
            }
        )
        #endif
    }

    func stop() {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        debounceTask?.cancel()
        debounceTask = nil
    }

    // MARK: - Triggering

    /// Debounced request. Use this for "something changed locally".
    func requestSync() {
        // An echo of our own cycle, not a user edit.
        guard !isSyncing else {
            needsAnotherPass = true
            return
        }

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Runs a cycle now, unless one is already running.
    func syncNow() async {
        guard !isSyncing else {
            needsAnotherPass = true
            return
        }

        isSyncing = true
        status = .syncing
        defer { isSyncing = false }

        do {
            let report = try await engine.sync()
            consecutiveFailures = 0
            lastSyncedAt = Date()
            status = .idle

            if !report.isEmpty {
                AppLog.sync.info("sync complete: \(String(describing: report), privacy: .public)")
            }
        } catch is CancellationError {
            // The screen that asked went away. Not a failure.
            status = .idle
        } catch let error as APIError where error.isConnectivityFailure {
            consecutiveFailures += 1
            status = .offline
            AppLog.sync.debug("sync skipped: offline")
        } catch let error as APIError where error == .unauthenticated {
            // Refresh already failed inside the client. Sign-out is driven by
            // the auth layer; the coordinator just stops retrying.
            consecutiveFailures += 1
            status = .failed(error.localizedDescription)
            AppLog.sync.error("sync unauthenticated; awaiting re-authentication")
        } catch {
            consecutiveFailures += 1
            status = .failed(error.localizedDescription)
            AppLog.sync.error("sync failed: \(String(describing: error), privacy: .public)")
        }

        if needsAnotherPass {
            needsAnotherPass = false
            // Yield first so a self-triggering change cannot spin.
            await Task.yield()
            await syncNow()
        }
    }

    /// Seconds to wait before the next automatic attempt.
    ///
    /// Exponential with a ceiling: a device that has been offline for an hour
    /// should not be waking the radio every few seconds, but must still
    /// recover promptly once the network returns.
    var retryDelay: Duration {
        let capped = min(consecutiveFailures, 6)
        let seconds = min(300, Int(pow(2.0, Double(capped))) * 5)
        return .seconds(seconds)
    }

    /// Clears local data and the cursor. Called on sign-out.
    func reset() async {
        stop()
        try? await engine.reset()
        status = .idle
        lastSyncedAt = nil
        consecutiveFailures = 0
    }
}
