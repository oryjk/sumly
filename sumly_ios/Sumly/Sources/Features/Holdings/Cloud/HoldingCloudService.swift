import Foundation

protocol HoldingCloudServicing: Sendable {
    func fetch(token: String) async throws -> HoldingCloudSnapshot
    func put(_ document: HoldingDocument, revision: Int64, token: String) async throws -> HoldingCloudSnapshot
}

enum HoldingCloudError: Error, LocalizedError {
    case conflict, malformed, tooLarge
    var errorDescription: String? {
        switch self {
        case .conflict: "云端数据已有更新，请重试同步。"
        case .malformed: "云同步服务返回异常，本机记录已保留。"
        case .tooLarge: "记录数量或内容超过云同步限制，本机记录已保留。"
        }
    }
}
struct HoldingCloudService: HoldingCloudServicing {
    let baseURL: URL
    var session: URLSession = .shared
    static let maxBytes = 4 * 1024 * 1024
    func fetch(token: String) async throws -> HoldingCloudSnapshot { try await execute(token: token) }
    func put(_ document: HoldingDocument, revision: Int64, token: String) async throws -> HoldingCloudSnapshot {
        struct Mutation: Encodable { let expectedRevision: Int64; let document: HoldingDocument }
        return try await execute(token: token, body: HoldingCloudCoding.encode(Mutation(expectedRevision: revision, document: document)))
    }
    static func makeRequest(baseURL: URL, token: String, body: Data?) throws -> URLRequest {
        // Reuse the auth URL policy: TLS except explicit loopback development.
        _ = try NativeAuthService.makeRequest(.me(token), baseURL: baseURL)
        guard body.map({ $0.count <= maxBytes }) ?? true else { throw HoldingCloudError.tooLarge }
        var request = URLRequest(url: baseURL.appendingPathComponent("app/holdings"))
        request.httpMethod = body == nil ? "GET" : "PUT"
        request.timeoutInterval = 20
        request.httpBody = body
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
    static func unwrap(_ data: Data, status: Int) throws -> HoldingCloudSnapshot {
        if status == 401 { throw AuthError.unauthorized }
        if status == 409 { throw HoldingCloudError.conflict }
        if status == 413 { throw HoldingCloudError.tooLarge }
        struct Envelope: Decodable { var code: Int; var message: String; var data: HoldingCloudSnapshot? }
        guard data.count <= maxBytes, let envelope = try? HoldingCloudCoding.decode(Envelope.self, from: data) else { throw HoldingCloudError.malformed }
        guard (200..<300).contains(status), envelope.code == 0 else {
            throw AuthError.server(status, String(envelope.message.prefix(300)))
        }
        guard let value = envelope.data, value.isValid else { throw HoldingCloudError.malformed }
        return value
    }
    private func execute(token: String, body: Data? = nil) async throws -> HoldingCloudSnapshot {
        let request = try Self.makeRequest(baseURL: baseURL, token: token, body: body)
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: NoHoldingRedirects())
            guard let http = response as? HTTPURLResponse else { throw HoldingCloudError.malformed }
            var data = Data()
            for try await byte in bytes {
                guard data.count < Self.maxBytes else { throw HoldingCloudError.tooLarge }
                data.append(byte)
            }
            return try Self.unwrap(data, status: http.statusCode)
        } catch let error as AuthError { throw error }
        catch let error as HoldingCloudError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch { throw AuthError.network }
    }
}
private final class NoHoldingRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
