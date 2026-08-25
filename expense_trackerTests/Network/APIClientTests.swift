//
//  APIClientTests.swift
//  expense_trackerTests
//
//  Transport behaviour, driven through a real URLSession with a stubbed
//  protocol — so request building, header attachment and response handling are
//  all genuinely exercised.
//

import XCTest
@testable import expense_tracker

final class APIClientTests: XCTestCase {

    private let baseURL = URL(string: "https://api.test.invalid")!
    private var tokenStore: InMemoryTokenStore!

    override func setUp() async throws {
        try await super.setUp()
        StubURLProtocol.reset()
        tokenStore = InMemoryTokenStore()
    }

    override func tearDown() async throws {
        StubURLProtocol.reset()
        try await super.tearDown()
    }

    private func makeClient() -> APIClient {
        APIClient(
            baseURL: baseURL,
            tokenStore: tokenStore,
            session: StubURLProtocol.makeSession()
        )
    }

    private func storeValidToken(_ value: String = "access-token-1") async {
        await tokenStore.store(
            TokenPair(accessToken: value, refreshToken: "refresh-1", expiresIn: 900)
        )
    }

    // MARK: - Request building

    func testBuildsTheURLFromBasePathAndQuery() async throws {
        StubURLProtocol.enqueue(.json(#"{"ok":true}"#))
        await storeValidToken()

        _ = try await makeClient().send(
            APIRequest(
                method: .get,
                path: "/api/v1/sync",
                query: [URLQueryItem(name: "since", value: "42")]
            ),
            as: OKResponse.self
        )

        let request = try XCTUnwrap(StubURLProtocol.recordedRequests.first)
        XCTAssertEqual(request.url?.path, "/api/v1/sync")
        XCTAssertEqual(request.url?.query, "since=42")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testAttachesTheBearerTokenWhenAuthenticationIsRequired() async throws {
        StubURLProtocol.enqueue(.json(#"{"ok":true}"#))
        await storeValidToken("secret-token")

        _ = try await makeClient().send(
            APIRequest(method: .get, path: "/api/v1/auth/me"),
            as: OKResponse.self
        )

        let request = try XCTUnwrap(StubURLProtocol.recordedRequests.first)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer secret-token"
        )
    }

    func testOmitsTheTokenOnUnauthenticatedRequests() async throws {
        StubURLProtocol.enqueue(.json(#"{"ok":true}"#))
        await storeValidToken()

        _ = try await makeClient().send(
            APIRequest(method: .post, path: "/api/v1/auth/signin", requiresAuthentication: false),
            as: OKResponse.self
        )

        let request = try XCTUnwrap(StubURLProtocol.recordedRequests.first)
        // Sending a stale token to the sign-in endpoint would be pointless at
        // best and confusing to debug at worst.
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testSendsJSONContentTypeOnlyWhenThereIsABody() async throws {
        StubURLProtocol.enqueue(.json(#"{"ok":true}"#))
        StubURLProtocol.enqueue(.json(#"{"ok":true}"#))
        await storeValidToken()

        let client = makeClient()

        _ = try await client.send(APIRequest(method: .get, path: "/a"), as: OKResponse.self)
        _ = try await client.send(
            try APIRequest.json(.post, path: "/b", body: NumberBody(value: 1)),
            as: OKResponse.self
        )

        let requests = StubURLProtocol.recordedRequests
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Content-Type"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    // MARK: - Error translation

    func testMapsAServerErrorBodyOntoTheServerCase() async throws {
        StubURLProtocol.enqueue(
            .json(#"{"error":{"code":"validation_failed","message":"Enter an amount."}}"#,
                  statusCode: 422)
        )
        await storeValidToken()


        do {
            _ = try await makeClient().send(
                APIRequest(method: .post, path: "/api/v1/sync"), as: OKResponse.self
            )
            XCTFail("Expected a thrown error")
        } catch let error as APIError {
            XCTAssertEqual(error.serverCode, "validation_failed")
            XCTAssertEqual(error.localizedDescription, "Enter an amount.")
            XCTAssertFalse(error.isRetryable, "422 means the request itself is wrong")
        }
    }

    func testMapsNoConnectionOntoOffline() async throws {
        StubURLProtocol.enqueue(
            .init(error: URLError(.notConnectedToInternet))
        )
        await storeValidToken()


        do {
            _ = try await makeClient().send(
                APIRequest(method: .get, path: "/api/v1/sync"), as: OKResponse.self
            )
            XCTFail("Expected a thrown error")
        } catch let error as APIError {
            XCTAssertEqual(error, .offline)
            XCTAssertTrue(error.isConnectivityFailure)
            XCTAssertTrue(error.isRetryable)
        }
    }

    func testTreatsA500AsRetryableAndA400AsNot() async throws {
        await storeValidToken()

        StubURLProtocol.enqueue(
            .json(#"{"error":{"code":"internal_error","message":"boom"}}"#, statusCode: 500)
        )
        do {
            _ = try await makeClient().send(
                APIRequest(method: .get, path: "/a"), as: OKResponse.self
            )
            XCTFail("Expected a thrown error")
        } catch let error as APIError {
            XCTAssertTrue(error.isRetryable)
        }

        StubURLProtocol.enqueue(
            .json(#"{"error":{"code":"conflict","message":"nope"}}"#, statusCode: 409)
        )
        do {
            _ = try await makeClient().send(
                APIRequest(method: .get, path: "/b"), as: OKResponse.self
            )
            XCTFail("Expected a thrown error")
        } catch let error as APIError {
            XCTAssertFalse(error.isRetryable)
        }
    }

    func testReportsAMalformedBodyAsDecodingRatherThanCrashing() async throws {
        StubURLProtocol.enqueue(.json(#"{"unexpected":"shape"}"#))
        await storeValidToken()


        do {
            _ = try await makeClient().send(
                APIRequest(method: .get, path: "/a"), as: RequiredFieldResponse.self
            )
            XCTFail("Expected a thrown error")
        } catch let error as APIError {
            guard case .decoding = error else {
                return XCTFail("Expected .decoding, got \(error)")
            }
        }
    }

    // MARK: - Token refresh

    func testRefreshesOnceAndRetriesAfterAnExpiredTokenResponse() async throws {
        await storeValidToken("stale-token")

        StubURLProtocol.enqueue(
            .json(#"{"error":{"code":"token_expired","message":"Access token expired."}}"#,
                  statusCode: 401)
        )
        StubURLProtocol.enqueue(.json(#"{"ok":true}"#))

        let client = makeClient()
        let refreshCount = RefreshCounter()

        await client.setRefreshHandler {
            await refreshCount.increment()
            return true
        }

        let response = try await client.send(
            APIRequest(method: .get, path: "/api/v1/sync"), as: OKResponse.self
        )

        XCTAssertTrue(response.ok)
        let count = await refreshCount.value
        XCTAssertEqual(count, 1)
        XCTAssertEqual(StubURLProtocol.recordedRequests.count, 2, "Should have retried once")
    }

    func testDoesNotRefreshWhenTheTokenIsRejectedRatherThanExpired() async throws {
        await storeValidToken()

        StubURLProtocol.enqueue(
            .json(#"{"error":{"code":"unauthorized","message":"Invalid token."}}"#,
                  statusCode: 401)
        )

        let client = makeClient()
        let refreshCount = RefreshCounter()
        await client.setRefreshHandler {
            await refreshCount.increment()
            return true
        }


        do {
            _ = try await client.send(
                APIRequest(method: .get, path: "/api/v1/sync"), as: OKResponse.self
            )
            XCTFail("Expected a thrown error")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthenticated)
        }

        // Refreshing on a token the server called invalid would loop forever.
        let count = await refreshCount.value
        XCTAssertEqual(count, 0)
    }

    func testDoesNotRetryMoreThanOnce() async throws {
        await storeValidToken()

        // Two consecutive expiries. The client must give up, not spin.
        StubURLProtocol.enqueue(
            .json(#"{"error":{"code":"token_expired","message":"expired"}}"#, statusCode: 401)
        )
        StubURLProtocol.enqueue(
            .json(#"{"error":{"code":"token_expired","message":"expired"}}"#, statusCode: 401)
        )

        let client = makeClient()
        await client.setRefreshHandler { true }

        _ = try? await client.send(
            APIRequest(method: .get, path: "/api/v1/sync"), as: OKResponse.self
        )

        XCTAssertEqual(StubURLProtocol.recordedRequests.count, 2)
    }

    /// Five requests hitting an expired token at once must produce ONE
    /// refresh. Because refresh tokens rotate, five would invalidate each
    /// other and sign the user out.
    func testCoalescesConcurrentRefreshes() async throws {
        await storeValidToken()

        for _ in 0..<5 {
            StubURLProtocol.enqueue(
                .json(#"{"error":{"code":"token_expired","message":"expired"}}"#, statusCode: 401)
            )
            StubURLProtocol.enqueue(.json(#"{"ok":true}"#))
        }

        let client = makeClient()
        let refreshCount = RefreshCounter()
        await client.setRefreshHandler {
            // A real refresh is a network round trip; the delay is what makes
            // the requests actually overlap.
            try? await Task.sleep(for: .milliseconds(50))
            await refreshCount.increment()
            return true
        }


        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    _ = try? await client.send(
                        APIRequest(method: .get, path: "/api/v1/sync"), as: OKResponse.self
                    )
                }
            }
        }

        let count = await refreshCount.value
        XCTAssertEqual(count, 1, "Concurrent 401s must share one refresh")
    }
}

// MARK: - Test payloads
//
// Declared at file scope and `nonisolated`. The target builds with
// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so a struct declared inside a
// test method picks up main-actor isolation and its `Decodable` conformance
// can no longer satisfy `APIClient`'s `Sendable` requirement.

private nonisolated struct OKResponse: Decodable, Sendable {
    let ok: Bool
}

private nonisolated struct RequiredFieldResponse: Decodable, Sendable {
    let requiredField: String
}

private nonisolated struct NumberBody: Encodable, Sendable {
    let value: Int
}

/// Counts refresh invocations across concurrent tasks.
private actor RefreshCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
