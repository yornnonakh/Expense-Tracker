//
//  StubURLProtocol.swift
//  expense_trackerTests — Support
//
//  Intercepts URLSession traffic so networking tests run with no server.
//
//  A `URLProtocol` subclass is the seam URLSession itself provides, which
//  means the code under test uses the real URLSession, the real request
//  building and the real response handling — everything except the socket.
//  Stubbing `APIClient` instead would leave all of that untested.
//

import Foundation

final class StubURLProtocol: URLProtocol {

    struct Stub {
        let statusCode: Int
        let body: Data
        let headers: [String: String]
        /// Thrown instead of responding, to exercise the offline paths.
        let error: Error?

        init(
            statusCode: Int = 200,
            body: Data = Data(),
            headers: [String: String] = ["Content-Type": "application/json"],
            error: Error? = nil
        ) {
            self.statusCode = statusCode
            self.body = body
            self.headers = headers
            self.error = error
        }

        static func json(_ raw: String, statusCode: Int = 200) -> Stub {
            Stub(statusCode: statusCode, body: Data(raw.utf8))
        }
    }

    /// Queue of responses, consumed in order. A test that needs "401 then 200"
    /// (the token-refresh path) pushes both.
    ///
    /// `nonisolated(unsafe)` because URLProtocol is instantiated by URLSession
    /// on its own queue and cannot take an isolation context. The lock is what
    /// actually makes this safe.
    nonisolated(unsafe) private static var stubs: [Stub] = []
    nonisolated(unsafe) private static var recorded: [URLRequest] = []
    private static let lock = NSLock()

    static func enqueue(_ stub: Stub) {
        lock.lock(); defer { lock.unlock() }
        stubs.append(stub)
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        stubs.removeAll()
        recorded.removeAll()
    }

    static var recordedRequests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    private static func nextStub() -> Stub? {
        lock.lock(); defer { lock.unlock() }
        return stubs.isEmpty ? nil : stubs.removeFirst()
    }

    private static func record(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
    }

    /// A session wired to this protocol and nothing else.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // `URLRequest.httpBody` is nil for a body streamed by URLSession, so
        // capture it before recording or assertions on the body see nothing.
        var toRecord = request
        if toRecord.httpBody == nil, let stream = request.httpBodyStream {
            toRecord.httpBody = Self.readAll(from: stream)
        }
        Self.record(toRecord)

        guard let stub = Self.nextStub() else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.resourceUnavailable)
            )
            return
        }

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readAll(from stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
