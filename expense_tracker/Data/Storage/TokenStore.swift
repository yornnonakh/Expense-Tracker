//
//  TokenStore.swift
//  Data Layer — Storage
//
//  Where session tokens live.
//
//  NOT UserDefaults. A defaults plist is a plain file inside the app
//  container: readable from a filesystem backup, from a jailbroken device, and
//  by anything that can reach the container. A token in there is a credential
//  sitting in the clear. The Keychain is encrypted at rest, tied to the device,
//  and — with `ThisDeviceOnly` — excluded from backups, so a restored backup
//  on someone else's phone carries no live session.
//
//  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` rather than
//  `WhenUnlocked`: background sync has to read the token while the phone is
//  locked, which `WhenUnlocked` would refuse.
//

import Foundation
import OSLog
import Security

// MARK: - Model

nonisolated struct TokenPair: Equatable, Sendable, Codable {
    let accessToken: String
    let refreshToken: String
    /// When the access token stops being accepted.
    let accessTokenExpiresAt: Date

    init(accessToken: String, refreshToken: String, expiresIn: TimeInterval) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = Date().addingTimeInterval(expiresIn)
    }

    init(accessToken: String, refreshToken: String, accessTokenExpiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
    }

    /// Treated as expired slightly early, so a token that would die in transit
    /// is refreshed before it is used rather than after it fails.
    func isAccessTokenExpired(now: Date = Date(), leeway: TimeInterval = 30) -> Bool {
        now.addingTimeInterval(leeway) >= accessTokenExpiresAt
    }
}

// MARK: - Protocol

nonisolated protocol TokenStoring: Sendable {
    func accessToken() async -> String?
    func refreshToken() async -> String?
    func tokens() async -> TokenPair?
    func store(_ tokens: TokenPair) async
    func clear() async
}

// MARK: - Keychain

actor KeychainTokenStore: TokenStoring {

    private let service: String
    private let account: String

    /// Read-through cache. The Keychain is fast but not free, and the access
    /// token is read on every single request.
    private var cached: TokenPair?
    private var hasLoaded = false

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.yornnona.expensetracker",
        account: String = "session-tokens"
    ) {
        self.service = service
        self.account = account
    }

    func accessToken() async -> String? {
        await tokens()?.accessToken
    }

    func refreshToken() async -> String? {
        await tokens()?.refreshToken
    }

    func tokens() async -> TokenPair? {
        if hasLoaded { return cached }
        cached = load()
        hasLoaded = true
        return cached
    }

    func store(_ tokens: TokenPair) async {
        cached = tokens
        hasLoaded = true

        guard let data = try? JSONEncoder().encode(tokens) else {
            AppLog.auth.error("could not encode tokens for keychain")
            return
        }

        // Delete-then-add rather than SecItemUpdate: it is one code path
        // instead of two, and an update against a missing item would fail in a
        // way that silently loses the new token.
        SecItemDelete(baseQuery() as CFDictionary)

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            AppLog.auth.error("keychain write failed: \(status, privacy: .public)")
        }
    }

    func clear() async {
        cached = nil
        hasLoaded = true
        SecItemDelete(baseQuery() as CFDictionary)
    }

    // MARK: - Keychain plumbing

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func load() -> TokenPair? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                AppLog.auth.error("keychain read failed: \(status, privacy: .public)")
            }
            return nil
        }

        return try? JSONDecoder().decode(TokenPair.self, from: data)
    }
}

// MARK: - In-memory (tests & previews)

/// Drop-in replacement with no Keychain access.
///
/// Unit tests need this: the simulator's Keychain is shared across test runs,
/// so a real store would leak a session from one test into the next.
actor InMemoryTokenStore: TokenStoring {

    private var cached: TokenPair?

    init(seed: TokenPair? = nil) {
        self.cached = seed
    }

    func accessToken() async -> String? { cached?.accessToken }
    func refreshToken() async -> String? { cached?.refreshToken }
    func tokens() async -> TokenPair? { cached }
    func store(_ tokens: TokenPair) async { cached = tokens }
    func clear() async { cached = nil }
}
