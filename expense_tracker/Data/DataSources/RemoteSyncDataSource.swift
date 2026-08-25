//
//  RemoteSyncDataSource.swift
//  Data Layer — Data Sources
//
//  The server side of sync, as a protocol plus its HTTP implementation.
//
//  This replaces the simulated backend that used to stand in here. The
//  protocol is what makes that swap harmless: the sync engine names only
//  `RemoteSyncDataSourceProtocol`, so tests inject a fake and never open a
//  socket, and nothing above this file knows a URL exists.
//

import Foundation

nonisolated protocol RemoteSyncDataSourceProtocol: Sendable {

    /// Changes since `watermark`, tombstones included.
    func pull(since watermark: Double) async throws -> SyncPullResponse

    /// Uploads local changes, optionally pulling in the same round trip.
    func push(
        expenses: [APIExpense],
        budgets: [APIBudget],
        since watermark: Double?
    ) async throws -> SyncPushResponse
}

nonisolated struct RemoteSyncDataSource: RemoteSyncDataSourceProtocol {

    private let client: APIClientProtocol

    init(client: APIClientProtocol) {
        self.client = client
    }

    func pull(since watermark: Double) async throws -> SyncPullResponse {
        let request = APIRequest(
            method: .get,
            path: APIRoute.sync,
            // Sent as an integer: the server parses milliseconds as an int,
            // and "1.7e12" from Double's default description would not parse.
            query: [URLQueryItem(name: "since", value: String(Int64(watermark)))]
        )
        return try await client.send(request, as: SyncPullResponse.self)
    }

    func push(
        expenses: [APIExpense],
        budgets: [APIBudget],
        since watermark: Double?
    ) async throws -> SyncPushResponse {
        let body = SyncPushRequest(
            since: watermark.map { ($0).rounded(.down) },
            expenses: expenses,
            budgets: budgets
        )
        let request = try APIRequest.json(.post, path: APIRoute.sync, body: body)
        return try await client.send(request, as: SyncPushResponse.self)
    }
}
