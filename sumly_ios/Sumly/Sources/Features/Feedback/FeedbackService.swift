import Foundation

// MARK: - 1. 反馈服务协议与错误定义（Swift 6 Sendable）

protocol FeedbackServicing: Sendable {
    var baseURL: URL { get }
    func uploadAttachment(jpegData: Data, filename: String, deviceHash: String) async throws -> FeedbackUploadedAttachment
    func submitFeedback(_ payload: FeedbackSubmitPayload, bearerToken: String?) async throws -> FeedbackItem
    func fetchMyFeedbacks(deviceHash: String, limit: Int, bearerToken: String?) async throws -> [FeedbackItem]
}

enum FeedbackServiceError: Error, LocalizedError, Equatable, Sendable {
    case badResponse
    case rateLimited(String)
    case serviceUnavailable(String)
    case httpStatus(Int, String)
    case envelope(Int, String)
    case emptyData
    case attachmentTooLarge
    case network

    var errorDescription: String? {
        switch self {
        case .badResponse:
            "服务返回异常，请稍后重试。"
        case .rateLimited(let message):
            message.isEmpty ? "操作过于频繁，请稍后再试。" : message
        case .serviceUnavailable(let message):
            message.isEmpty ? "服务暂不可用，请稍后重试。" : message
        case .httpStatus(_, let message):
            message.isEmpty ? "请求失败，请稍后重试。" : message
        case .envelope(_, let message):
            message.isEmpty ? "提交失败，请稍后重试。" : message
        case .emptyData:
            "服务返回内容为空，请稍后重试。"
        case .attachmentTooLarge:
            "单张截图不能超过 3MB，请重新选择。"
        case .network:
            "网络连接失败，请检查网络后重试。"
        }
    }
}

// MARK: - 2. Multipart 表单构建器（纯函数，可注入 boundary 单测）

enum FeedbackMultipartBuilder {
    static func build(
        boundary: String,
        fieldName: String = "file",
        filename: String,
        mimeType: String = "image/jpeg",
        fileData: Data
    ) -> Data {
        let safeFilename = filename
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(safeFilename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}

// MARK: - 3. 后端反馈 API 客户端（对齐 sumly_go /api/v1/app/feedback*）

struct BackendFeedbackService: FeedbackServicing, Sendable {
    static let attachmentsPath = "app/feedback/attachments"
    static let submitPath = "app/feedback"
    static let minePath = "app/feedback/mine"

    var baseURL: URL = BackendGoldPriceService.defaultBaseURL
    var session: URLSession = .shared

    private struct Envelope<T: Decodable>: Decodable {
        let code: Int
        let message: String?
        let data: T?
    }

    private struct ErrorEnvelope: Decodable {
        let code: Int?
        let message: String?
    }

    // MARK: - Request Builders（独立可测）

    static func makeUploadAttachmentRequest(
        baseURL: URL,
        jpegData: Data,
        filename: String,
        deviceHash: String,
        boundary: String = "SumlyFeedback-\(UUID().uuidString)"
    ) throws -> URLRequest {
        guard jpegData.count <= FeedbackValidation.maxAttachmentBytes else {
            throw FeedbackServiceError.attachmentTooLarge
        }
        let url = BackendGoldPriceService.requestURL(baseURL: baseURL, path: attachmentsPath)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceHash, forHTTPHeaderField: "X-Device-ID")
        request.httpBody = FeedbackMultipartBuilder.build(
            boundary: boundary,
            fieldName: "file",
            filename: filename,
            mimeType: "image/jpeg",
            fileData: jpegData
        )
        return request
    }

    static func makeSubmitFeedbackRequest(
        baseURL: URL,
        payload: FeedbackSubmitPayload,
        bearerToken: String?
    ) throws -> URLRequest {
        let url = BackendGoldPriceService.requestURL(baseURL: baseURL, path: submitPath)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = normalizedToken(bearerToken) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    static func makeMyFeedbacksRequest(
        baseURL: URL,
        deviceHash: String,
        limit: Int = 50,
        bearerToken: String?
    ) -> URLRequest {
        let clampedLimit = max(1, min(limit, 50))
        let baseEndpoint = BackendGoldPriceService.requestURL(baseURL: baseURL, path: minePath)
        var components = URLComponents(url: baseEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "device_hash", value: deviceHash),
            URLQueryItem(name: "limit", value: String(clampedLimit))
        ]
        let finalURL = components?.url ?? baseEndpoint
        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if let token = normalizedToken(bearerToken) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: - Envelope Decoding（独立可测）

    static func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data, statusCode: Int) throws -> T {
        guard (200..<300).contains(statusCode) else {
            let serverMessage = extractServerMessage(from: data)
            switch statusCode {
            case 429:
                throw FeedbackServiceError.rateLimited(serverMessage)
            case 503:
                throw FeedbackServiceError.serviceUnavailable(serverMessage)
            default:
                throw FeedbackServiceError.httpStatus(statusCode, serverMessage)
            }
        }
        let envelope: Envelope<T>
        do {
            envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        } catch {
            throw FeedbackServiceError.badResponse
        }
        guard envelope.code == 0 else {
            throw FeedbackServiceError.envelope(envelope.code, (envelope.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let payload = envelope.data else {
            throw FeedbackServiceError.emptyData
        }
        return payload
    }

    // MARK: - FeedbackServicing

    func uploadAttachment(jpegData: Data, filename: String, deviceHash: String) async throws -> FeedbackUploadedAttachment {
        let request = try Self.makeUploadAttachmentRequest(
            baseURL: baseURL,
            jpegData: jpegData,
            filename: filename,
            deviceHash: deviceHash
        )
        return try await execute(FeedbackUploadedAttachment.self, request: request)
    }

    func submitFeedback(_ payload: FeedbackSubmitPayload, bearerToken: String?) async throws -> FeedbackItem {
        let request = try Self.makeSubmitFeedbackRequest(
            baseURL: baseURL,
            payload: payload,
            bearerToken: bearerToken
        )
        return try await execute(FeedbackItem.self, request: request)
    }

    func fetchMyFeedbacks(deviceHash: String, limit: Int = 50, bearerToken: String?) async throws -> [FeedbackItem] {
        let request = Self.makeMyFeedbacksRequest(
            baseURL: baseURL,
            deviceHash: deviceHash,
            limit: limit,
            bearerToken: bearerToken
        )
        let response = try await execute(FeedbackListResponse.self, request: request)
        return response.items
    }

    // MARK: - Private

    private func execute<T: Decodable>(_ type: T.Type, request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FeedbackServiceError.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw FeedbackServiceError.badResponse
        }
        return try Self.decodeEnvelope(type, from: data, statusCode: http.statusCode)
    }

    private static func normalizedToken(_ token: String?) -> String? {
        guard let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func extractServerMessage(from data: Data) -> String {
        guard let parsed = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
              let message = parsed.message?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return ""
        }
        return String(message.prefix(200))
    }
}
