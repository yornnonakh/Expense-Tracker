//
//  APIDTOs.swift
//  Data Layer — DTOs
//
//  The wire format, mirroring the server's JSON exactly.
//
//  Kept separate from the on-disk DTOs (`ExpenseDTO`, `BudgetDTO`) even where
//  the fields overlap. The server's contract and the local storage format
//  change for different reasons and on different schedules; one type serving
//  both would mean a server rename forcing a local migration.
//
//  TIME UNITS match the server:
//    `date`, `createdAt`  -> epoch SECONDS
//    `updatedAt`, `deletedAt`, `serverTime` -> epoch MILLISECONDS
//

import Foundation

// MARK: - Auth

nonisolated struct APIUser: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let email: String
    /// Epoch millis.
    let createdAt: Double
    let hasAvatar: Bool
}

nonisolated struct APISessionResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    /// Seconds until `accessToken` expires.
    let expiresIn: Double
    let user: APIUser
}

nonisolated struct APIUserResponse: Decodable, Sendable {
    let user: APIUser
}

nonisolated struct SignUpRequest: Encodable, Sendable {
    let name: String
    let email: String
    let password: String
}

nonisolated struct SignInRequest: Encodable, Sendable {
    let email: String
    let password: String
}

nonisolated struct RefreshRequest: Encodable, Sendable {
    let refreshToken: String
}

nonisolated struct PasswordResetRequest: Encodable, Sendable {
    let email: String
}

nonisolated struct AvatarUploadRequest: Encodable, Sendable {
    let imageBase64: String
    let mimeType: String
}

// MARK: - Sync records

nonisolated struct APIExpense: Codable, Sendable, Equatable {
    let id: String
    let amount: Double
    let description: String
    let category: String
    /// Epoch seconds.
    let date: Double
    /// Epoch millis, originating device's clock.
    let updatedAt: Double
    /// Epoch millis, or nil for a live row.
    let deletedAt: Double?
}

nonisolated struct APIBudget: Codable, Sendable, Equatable {
    let id: String
    let category: String
    let limit: Double
    /// Epoch seconds.
    let createdAt: Double
    let updatedAt: Double
    let deletedAt: Double?
}

// MARK: - Sync envelopes

nonisolated struct SyncPullResponse: Decodable, Sendable {
    /// Epoch millis. Stored verbatim as the next `since` watermark.
    let serverTime: Double
    let expenses: [APIExpense]
    let budgets: [APIBudget]
}

nonisolated struct SyncPushRequest: Encodable, Sendable {
    /// Asking for changes in the same round trip as the push.
    let since: Double?
    let expenses: [APIExpense]
    let budgets: [APIBudget]
}

/// One record the server refused because it held something newer.
nonisolated struct SyncConflict: Decodable, Sendable {
    let status: String
    let id: String

    /// The server's copy. Decoded leniently: the same JSON field carries an
    /// expense on one conflict and a budget on the next, and only the caller
    /// knows which it pushed.
    let serverExpense: APIExpense?
    let serverBudget: APIBudget?

    private enum CodingKeys: String, CodingKey {
        case status, id, server
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decode(String.self, forKey: .status)
        self.id = try container.decode(String.self, forKey: .id)

        // Try both shapes. A budget lacks `amount`, an expense lacks `limit`,
        // so exactly one of these succeeds for any well-formed payload.
        self.serverExpense = try? container.decode(APIExpense.self, forKey: .server)
        self.serverBudget = self.serverExpense == nil
            ? try? container.decode(APIBudget.self, forKey: .server)
            : nil
    }
}

nonisolated struct SyncPushResponse: Decodable, Sendable {
    let serverTime: Double
    let applied: Int
    let conflicts: [SyncConflict]
    /// Present only when the push carried a `since`.
    let expenses: [APIExpense]?
    let budgets: [APIBudget]?
}
