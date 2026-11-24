import Foundation
import os
import Testing
@testable import Sumly

private let mainHost = "oryjk.cn"
private let backupHost = "backup.oryjk.cn"
private let mainBase = URL(string: "https://oryjk.cn:18443/sumly/api/v1")!

@Test func apiFailoverKeepsPathQueryAndBearerThenReturnsToMain() async throws {
    let uptime = OSAllocatedUnfairLock(initialState: TimeInterval(0))
    let transport = SumlyAPITransport(uptime: { uptime.withLock { $0 } })
    let stub = TransportStub([.status(503), .status(200), .status(200), .status(200), .status(200), .status(200)])
    var get = URLRequest(url: URL(string: "https://oryjk.cn:18443/sumly/api/v1/app/auth/me?name=%E9%BB%84%E9%87%91&cursor=a%2Bb")!)
    get.setValue("Bearer session-token", forHTTPHeaderField: "Authorization")
    var put = get
    put.httpMethod = "PUT"
    put.httpBody = Data("mutation".utf8)

    _ = try await transport.send(get, baseURL: mainBase, using: stub.send)
    _ = try await transport.send(get, baseURL: mainBase, using: stub.send)
    uptime.withLock { $0 = 61 }
    _ = try await transport.send(put, baseURL: mainBase, using: stub.send)
    _ = try await transport.send(get, baseURL: mainBase, using: stub.send)
    _ = try await transport.send(get, baseURL: mainBase, using: stub.send)

    let requests = await stub.requests
    #expect(requests.map { $0.url?.host } == [mainHost, backupHost, backupHost, backupHost, mainHost, mainHost])
    #expect(requests.map { $0.url?.port } == [18443, 19443, 19443, 19443, 18443, 18443])
    #expect(requests.map(\.cachePolicy) == [
        .useProtocolCachePolicy, .reloadIgnoringLocalCacheData, .useProtocolCachePolicy,
        .useProtocolCachePolicy, .reloadIgnoringLocalCacheData, .useProtocolCachePolicy,
    ])
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer session-token" })
    #expect(requests.allSatisfy { $0.url?.path == "/sumly/api/v1/app/auth/me" && $0.url?.query == "name=%E9%BB%84%E9%87%91&cursor=a%2Bb" })
    #expect(requests.filter { $0.httpMethod == "PUT" }.map(\.httpBody) == [Data("mutation".utf8)])
}

@Test func apiConnectivityFailureRetriesOnlyOnce() async throws {
    let transport = SumlyAPITransport()
    let stub = TransportStub([.error(.cannotConnectToHost), .status(502), .status(200)])
    let get = URLRequest(url: mainBase.appending(path: "app/auth/me"))
    let (_, failure) = try await transport.send(get, baseURL: mainBase, using: stub.send)
    #expect((failure as? HTTPURLResponse)?.statusCode == 502)
    _ = try await transport.send(get, baseURL: mainBase, using: stub.send)
    #expect(await stub.requests.map { $0.url?.host } == [mainHost, backupHost, mainHost])
}

@Test func apiCancellationHTTPFailuresAndCustomHostsAreNotReplayed() async throws {
    let transport = SumlyAPITransport()
    let custom = URL(string: "https://example.test/sumly/api/v1")!
    let get = URLRequest(url: mainBase.appending(path: "app/auth/me"))
    var post = get
    post.httpMethod = "POST"
    let stub = TransportStub([.error(.cancelled), .status(401), .status(500), .status(504), .status(503)])

    await #expect(throws: CancellationError.self) {
        _ = try await transport.send(get, baseURL: mainBase, using: stub.send)
    }
    for code in [401, 500] {
        let (_, response) = try await transport.send(get, baseURL: mainBase, using: stub.send)
        #expect((response as? HTTPURLResponse)?.statusCode == code)
    }
    let (_, failedPost) = try await transport.send(post, baseURL: mainBase, using: stub.send)
    #expect((failedPost as? HTTPURLResponse)?.statusCode == 504)
    let customRequest = URLRequest(url: custom.appending(path: "app/auth/me"))
    let (_, failedCustom) = try await transport.send(customRequest, baseURL: custom, using: stub.send)
    #expect((failedCustom as? HTTPURLResponse)?.statusCode == 503)
    #expect(await stub.requests.map { $0.url?.host } == [mainHost, mainHost, mainHost, mainHost, "example.test"])
}

private actor TransportStub {
    enum Outcome { case status(Int), error(URLError.Code) }

    private var outcomes: [Outcome]
    private(set) var requests: [URLRequest] = []

    init(_ outcomes: [Outcome]) { self.outcomes = outcomes }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        switch outcomes.removeFirst() {
        case let .status(code):
            return (Data(), HTTPURLResponse(url: try #require(request.url), statusCode: code, httpVersion: nil, headerFields: nil)!)
        case let .error(code):
            throw URLError(code)
        }
    }
}
