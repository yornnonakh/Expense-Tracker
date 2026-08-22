//
//  User.swift
//  Domain Layer — Entities
//
//  The signed-in account and its session.
//

import Foundation

struct User: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var email: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, email: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.email = email
        self.createdAt = createdAt
    }

    /// Up to two letters for the avatar circle, e.g. "Yorn Nona" -> "YN".
    /// Falls back to the email's first character for single-word names.
    var initials: String {
        let parts = name
            .split(separator: " ")
            .compactMap { $0.first.map(String.init) }

        if parts.isEmpty {
            return email.first.map { String($0).uppercased() } ?? "?"
        }
        return parts.prefix(2).joined().uppercased()
    }

    /// "Yorn" from "Yorn Nona" — used in the dashboard greeting.
    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

/// Proof of an authenticated user. In a real app the token would come from a
/// server and live in the Keychain; here it is a locally minted opaque string.
struct AuthSession: Codable, Hashable, Sendable {
    let token: String
    let user: User
    let issuedAt: Date

    init(token: String, user: User, issuedAt: Date = Date()) {
        self.token = token
        self.user = user
        self.issuedAt = issuedAt
    }

    /// Sessions are valid for 30 days, after which auto-login is refused.
    static let lifetime: TimeInterval = 60 * 60 * 24 * 30

    func isExpired(now: Date = Date()) -> Bool {
        now.timeIntervalSince(issuedAt) > Self.lifetime
    }
}
