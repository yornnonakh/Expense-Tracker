//
//  AppEnvironment.swift
//  Core
//
//  Where the app points, and how loudly it talks about it.
//
//  Resolution order, most specific first:
//    1. `API_BASE_URL` in the process environment — set by a test or an Xcode
//       scheme, and the only thing that can redirect a build already made.
//    2. `APIBaseURL` in Info.plist — the per-configuration value, so Debug and
//       Release point at different servers without a code change.
//    3. A compiled-in default.
//
//  Reading configuration rather than hardcoding it is what keeps "point the
//  app at staging" from being a commit.
//

import Foundation

nonisolated enum AppEnvironment {

    // MARK: - Build configuration

    enum BuildConfiguration: String, Sendable {
        case debug
        case release

        static var current: BuildConfiguration {
            #if DEBUG
            return .debug
            #else
            return .release
            #endif
        }
    }

    static var buildConfiguration: BuildConfiguration { .current }

    static var isDebug: Bool { buildConfiguration == .debug }

    /// True when running inside XCTest. Used to keep launch-time side effects
    /// (background sync, sample-data seeding) out of unit tests, which should
    /// exercise those paths deliberately rather than inherit them.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    // MARK: - API

    /// Local server default. Matches `PORT` in `server/.env.example`.
    private static let developmentBaseURL = URL(string: "http://localhost:8787")!

    /// Deliberately not a real host.
    ///
    /// There is no deployed production server for this project yet. Rather
    /// than invent a plausible-looking URL that would fail at runtime with a
    /// DNS error nobody can explain, Release builds fall back to this and
    /// `isProductionEndpointConfigured` reports false, so the mistake is
    /// visible before shipping instead of after.
    private static let unconfiguredProductionBaseURL =
        URL(string: "https://api.expensetracker.invalid")!

    static var apiBaseURL: URL {
        if let raw = ProcessInfo.processInfo.environment["API_BASE_URL"],
           let url = URL(string: raw) {
            return url
        }

        if let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }

        return isDebug ? developmentBaseURL : unconfiguredProductionBaseURL
    }

    /// False when a Release build is still pointing at the placeholder host.
    /// Surfaced in the app's diagnostics rather than crashing: a user who
    /// already has the build should still reach their offline data.
    static var isProductionEndpointConfigured: Bool {
        apiBaseURL.host() != unconfiguredProductionBaseURL.host()
    }

    // MARK: - Timeouts

    /// Per-request ceiling. Short enough that a dead server does not leave a
    /// spinner up indefinitely; long enough for a slow cellular round trip.
    static let requestTimeout: TimeInterval = 20

    /// Ceiling for a whole resource including retries.
    static let resourceTimeout: TimeInterval = 60
}
