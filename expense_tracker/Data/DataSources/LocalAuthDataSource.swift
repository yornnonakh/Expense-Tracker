//
//  LocalAuthDataSource.swift
//  Data Layer — Data Sources
//
//  Local-only account store standing in for a real auth backend.
//
//  See the security note in `AccountDTO.swift`: passwords are salted and
//  hashed rather than stored in the clear, but on-device credential storage is
//  a demo affordance, not a production pattern.
//

import CryptoKit
import Foundation

actor LocalAuthDataSource {

    private let store: KeyValueStore

    init(store: KeyValueStore) {
        self.store = store
    }

    // MARK: - Accounts

    func accounts() throws -> [AccountDTO] {
        guard let data = store.data(forKey: StorageKey.accounts) else { return [] }
        do {
            return try JSONCoding.decode([AccountDTO].self, from: data)
        } catch {
            throw AuthError.storageFailure("Saved accounts could not be read.")
        }
    }

    func account(email: String) throws -> AccountDTO? {
        let normalized = email.lowercased()
        return try accounts().first { $0.email == normalized }
    }

    func createAccount(name: String, email: String, password: String) throws -> AccountDTO {
        var all = try accounts()
        let normalized = email.lowercased()

        guard !all.contains(where: { $0.email == normalized }) else {
            throw AuthError.emailAlreadyRegistered
        }

        let salt = Self.makeSalt()
        let account = AccountDTO(
            id: UUID().uuidString,
            name: name,
            email: normalized,
            passwordHash: Self.hash(password: password, salt: salt),
            salt: salt,
            createdAt: Date().timeIntervalSince1970
        )

        all.append(account)
        try persistAccounts(all)
        return account
    }

    /// Verifies a password against a stored account.
    ///
    /// Compares digests with a constant-time check so the comparison itself
    /// doesn't leak how many leading characters were correct.
    func verify(password: String, against account: AccountDTO) -> Bool {
        let candidate = Self.hash(password: password, salt: account.salt)
        return Self.constantTimeEquals(candidate, account.passwordHash)
    }

    private func persistAccounts(_ accounts: [AccountDTO]) throws {
        do {
            let data = try JSONCoding.encode(accounts)
            store.set(data, forKey: StorageKey.accounts)
        } catch {
            throw AuthError.storageFailure("Could not save the account.")
        }
    }

    // MARK: - Session

    func loadSession() throws -> SessionDTO? {
        guard let data = store.data(forKey: StorageKey.session) else { return nil }
        do {
            return try JSONCoding.decode(SessionDTO.self, from: data)
        } catch {
            // A session we can't read is a session we can't trust. Drop it and
            // fall back to the sign-in screen rather than blocking launch.
            store.removeObject(forKey: StorageKey.session)
            return nil
        }
    }

    func saveSession(_ dto: SessionDTO) throws {
        do {
            let data = try JSONCoding.encode(dto)
            store.set(data, forKey: StorageKey.session)
        } catch {
            throw AuthError.storageFailure("Could not save your session.")
        }
    }

    func clearSession() {
        store.removeObject(forKey: StorageKey.session)
    }

    // MARK: - Crypto helpers

    /// 16 random bytes, hex-encoded. Per-account, so identical passwords on
    /// two accounts produce different digests.
    private static func makeSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: UInt8.min...UInt8.max)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func hash(password: String, salt: String) -> String {
        let input = Data((salt + password).utf8)
        let digest = SHA256.hash(data: input)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Compares every byte regardless of where the first mismatch is.
    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        guard lhsBytes.count == rhsBytes.count else { return false }

        var difference: UInt8 = 0
        for index in lhsBytes.indices {
            difference |= lhsBytes[index] ^ rhsBytes[index]
        }
        return difference == 0
    }

    /// Opaque session token. A real backend would issue and sign this.
    static func makeToken() -> String {
        UUID().uuidString + "." + UUID().uuidString
    }
}
