//
//  AppLog.swift
//  Core
//
//  Logging via OSLog, split into categories so Console.app can filter to one
//  subsystem of the app.
//
//  ON PRIVACY: OSLog redacts interpolated values by default and requires an
//  explicit `privacy: .public` to reveal them. That default is right, and this
//  file leans on it — anything user-identifying (email, description text,
//  amounts) is logged without an override and so appears as `<private>` on a
//  device. Only ids, counts, and error codes are marked public, because those
//  are what make a log actionable and none of them identify a person.
//

import Foundation
import OSLog

nonisolated enum AppLog {

    private static let subsystem =
        Bundle.main.bundleIdentifier ?? "com.yornnona.expensetracker"

    /// HTTP traffic: method, path, status, duration.
    static let network = Logger(subsystem: subsystem, category: "network")

    /// The sync engine: pushes, pulls, merges, conflicts.
    static let sync = Logger(subsystem: subsystem, category: "sync")

    /// Sign-in, sign-up, token refresh, session restore.
    static let auth = Logger(subsystem: subsystem, category: "auth")

    /// Local persistence: reads, writes, decode failures.
    static let data = Logger(subsystem: subsystem, category: "data")

    /// Screen lifecycle and user-visible errors.
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
