import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Sumly

// MARK: - 测试用隔离辅助

private func makeIsolatedFeedbackDefaults() -> (UserDefaults, String) {
    let suiteName = "com.oryjk.sumly.tests.feedback.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}

private func makeSolidUIImage(width: Int, height: Int, color: UIColor = .systemYellow) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    format.opaque = true
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
        color.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

private func readBodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count > 0 {
            data.append(buffer, count: count)
        } else {
            break
        }
    }
    return data
}

/// 线程安全的 Mock URLProtocol，用于测试 `BackendFeedbackService` 真实 URLSession 链路。
private final class FeedbackMockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]

    static func register(
        host: String,
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        lock.lock()
        handlers[host] = handler
        lock.unlock()
    }

    static func unregister(host: String) {
        lock.lock()
        handlers.removeValue(forKey: host)
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        lock.lock()
        let exists = handlers[host] != nil
        lock.unlock()
        return exists
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let host = request.url?.host else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.lock.lock()
        let handler = Self.handlers[host]
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeMockURLSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FeedbackMockURLProtocol.self]
    return URLSession(configuration: config)
}

private actor MockFeedbackService: FeedbackServicing {
    nonisolated let baseURL = URL(string: "https://oryjk.cn/sumly/api/v1")!

    var uploadResults: [Result<FeedbackUploadedAttachment, any Error>] = []
    var submitResult: Result<FeedbackItem, any Error>
    var mineResult: Result<[FeedbackItem], any Error>

    private(set) var uploadCallCount = 0
    private(set) var uploadedDeviceHashes: [String] = []
    private(set) var submittedPayloads: [(FeedbackSubmitPayload, String?)] = []
    private(set) var fetchedMineParams: [(String, Int, String?)] = []

    init(
        uploadResults: [Result<FeedbackUploadedAttachment, any Error>] = [],
        submitResult: Result<FeedbackItem, any Error>,
        mineResult: Result<[FeedbackItem], any Error> = .success([])
    ) {
        self.uploadResults = uploadResults
        self.submitResult = submitResult
        self.mineResult = mineResult
    }

    func setUploadResults(_ next: [Result<FeedbackUploadedAttachment, any Error>]) {
        uploadResults = next
    }

    func setMineResult(_ next: Result<[FeedbackItem], any Error>) {
        mineResult = next
    }

    func uploadAttachment(jpegData: Data, filename: String, deviceHash: String) async throws -> FeedbackUploadedAttachment {
        uploadCallCount += 1
        uploadedDeviceHashes.append(deviceHash)
        if !uploadResults.isEmpty {
            let next = uploadResults.removeFirst()
            return try next.get()
        }
        return FeedbackUploadedAttachment(
            objectKey: "feedback/20261123/\(filename)",
            url: "/api/v1/app/feedback/attachments/20261123/\(filename)",
            contentType: "image/jpeg",
            sizeBytes: jpegData.count
        )
    }

    func submitFeedback(_ payload: FeedbackSubmitPayload, bearerToken: String?) async throws -> FeedbackItem {
        submittedPayloads.append((payload, bearerToken))
        return try submitResult.get()
    }

    func fetchMyFeedbacks(deviceHash: String, limit: Int, bearerToken: String?) async throws -> [FeedbackItem] {
        fetchedMineParams.append((deviceHash, limit, bearerToken))
        return try mineResult.get()
    }
}

private actor RecordedRequestsBox {
    struct Entry: Sendable {
        let method: String
        let url: String
        let authorization: String?
        let deviceID: String?
        let contentType: String?
        let body: Data?
    }

    private(set) var entries: [Entry] = []

    func append(_ entry: Entry) {
        entries.append(entry)
    }
}

// MARK: - 1. 模型编解码与 URL 解析

@Suite("Feedback")
struct FeedbackTests {
    @Test("反馈模型完整编解码、缺省字段兜底及相对附件地址拼接")
    func modelsDecodingEncodingAndAttachmentURLResolution() throws {
        let itemJSON = """
        {
          "code": 0,
          "message": "ok",
          "data": {
            "items": [
              {
                "id": 102,
                "category": "bug",
                "content": "深色模式下行情刷新偶发闪烁",
                "contact": "wx_gold_100",
                "attachments": [
                  {
                    "object_key": "feedback/20261123/abc123.jpg",
                    "url": "/api/v1/app/feedback/attachments/20261123/abc123.jpg"
                  }
                ],
                "status": "resolved",
                "admin_reply": "感谢反馈！已在 1.0.6 版本修复渲染闪烁问题。",
                "replied_at": "2026-11-23T16:10:00Z",
                "created_at": "2026-11-23T15:48:19Z",
                "updated_at": "2026-11-23T16:10:00Z"
              },
              {
                "id": 101,
                "category": "future_category",
                "content": "缺省字段容错测试",
                "status": "future_status",
                "attachments": null,
                "admin_reply": "",
                "replied_at": null,
                "created_at": "2026-11-22T08:00:00.123Z"
              }
            ]
          }
        }
        """

        let list = try BackendFeedbackService.decodeEnvelope(
            FeedbackListResponse.self,
            from: Data(itemJSON.utf8),
            statusCode: 200
        )
        #expect(list.items.count == 2)

        let first = list.items[0]
        #expect(first.id == 102)
        #expect(first.category == .bug)
        #expect(first.status == .resolved)
        #expect(first.hasDeveloperReply == true)
        #expect(first.adminReply.contains("1.0.6"))
        #expect(first.attachments.count == 1)

        // 相对附件 URL 在生产反代路径与本地端口路径下均正确拼接
        let prodBase = URL(string: "https://oryjk.cn/sumly/api/v1")!
        let localBase = URL(string: "http://127.0.0.1:18090/api/v1/")!
        #expect(
            first.attachments[0].resolvedURL(baseURL: prodBase)?.absoluteString
                == "https://oryjk.cn/sumly/api/v1/app/feedback/attachments/20261123/abc123.jpg"
        )
        #expect(
            first.attachments[0].resolvedURL(baseURL: localBase)?.absoluteString
                == "http://127.0.0.1:18090/api/v1/app/feedback/attachments/20261123/abc123.jpg"
        )

        let absoluteAttachment = FeedbackAttachment(
            objectKey: "feedback/20261123/full.jpg",
            url: "https://cdn.oryjk.cn/sumly/feedback/20261123/full.jpg"
        )
        #expect(
            absoluteAttachment.resolvedURL(baseURL: prodBase)?.absoluteString
                == "https://cdn.oryjk.cn/sumly/feedback/20261123/full.jpg"
        )

        let productionBase = URL(string: "https://oryjk.cn:18443/sumly/api/v1")!
        #expect(
            first.attachments[0].productionImageURL(baseURL: productionBase)?.absoluteString
                == "https://oryjk.cn:18443/sumly/api/v1/app/feedback/attachments/20261123/abc123.jpg"
        )
        #expect(first.attachments[0].productionImageURL(baseURL: localBase) == nil)
        #expect(absoluteAttachment.productionImageURL(baseURL: productionBase) == nil)
        let invalidAttachment = FeedbackAttachment(objectKey: "bad", url: "/api/v1/app/feedback/attachments/../mine")
        #expect(invalidAttachment.productionImageURL(baseURL: productionBase) == nil)

        // 未知枚举值与 null 字段安全回退
        let second = list.items[1]
        #expect(second.category == .other)
        #expect(second.status == .new)
        #expect(second.attachments.isEmpty)
        #expect(second.hasDeveloperReply == false)

        // 提交 Payload JSON 字段键名精确匹配后端契约
        let payload = FeedbackSubmitPayload(
            deviceHash: "device-hash-001",
            category: .data,
            content: "核对国内金价收盘价换算",
            contact: "test@oryjk.cn",
            attachments: [FeedbackAttachment(objectKey: "k1", url: "/api/v1/app/feedback/attachments/20261123/k1.jpg")],
            appVersion: "1.0.5",
            buildNumber: "60",
            iosVersion: "iOS 18.4",
            deviceModel: "iPhone17,1",
            marketMode: "domestic",
            cloudSyncEnabled: false
        )
        let encoded = try JSONEncoder().encode(payload)
        let jsonObject = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(jsonObject["device_hash"] as? String == "device-hash-001")
        #expect(jsonObject["category"] as? String == "data")
        #expect(jsonObject["content"] as? String == "核对国内金价收盘价换算")
        #expect(jsonObject["contact"] as? String == "test@oryjk.cn")
        #expect(jsonObject["app_version"] as? String == "1.0.5")
        #expect(jsonObject["build_number"] as? String == "60")
        #expect(jsonObject["ios_version"] as? String == "iOS 18.4")
        #expect(jsonObject["device_model"] as? String == "iPhone17,1")
        #expect(jsonObject["market_mode"] as? String == "domestic")
        #expect(jsonObject["cloud_sync_enabled"] as? Bool == false)
        // 绝不附带任何持仓/金额隐私字段
        #expect(jsonObject["grams"] == nil)
        #expect(jsonObject["holdings"] == nil)
        #expect(jsonObject["amount"] == nil)
    }

    // MARK: - 2. 字数与表单校验

    @Test("反馈正文与联系方式字数边界及附件数量校验")
    func formValidationBoundaries() {
        #expect(FeedbackValidation.validate(content: "   ", contact: "", attachmentCount: 0) == .tooShort(remaining: 5))
        #expect(FeedbackValidation.validate(content: " 1234 ", contact: "", attachmentCount: 0) == .tooShort(remaining: 1))
        #expect(FeedbackValidation.validate(content: "12345", contact: "", attachmentCount: 0) == .valid)

        let exact1000 = String(repeating: "金", count: 1000)
        #expect(FeedbackValidation.validate(content: exact1000, contact: "", attachmentCount: 3) == .valid)

        let over1000 = String(repeating: "金", count: 1003)
        #expect(FeedbackValidation.validate(content: over1000, contact: "", attachmentCount: 0) == .tooLong(excess: 3))
        #expect(FeedbackValidation.clampContent(over1000).count == 1000)

        let overContact = String(repeating: "a", count: 125)
        #expect(FeedbackValidation.validate(content: "合法描述内容", contact: overContact, attachmentCount: 0) == .contactTooLong(excess: 5))
        #expect(FeedbackValidation.clampContact(overContact).count == 120)

        #expect(FeedbackValidation.validate(content: "合法描述内容", contact: "", attachmentCount: 4) == .tooManyAttachments)
    }

    // MARK: - 3. deviceHash 稳定持久化

    @Test("deviceHash 首次生成并持久化，重复读取保持一致且不合法值自动重建")
    func stableDeviceHashPersistence() {
        let (defaults, suiteName) = makeIsolatedFeedbackDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = FeedbackDeviceIdentity.stableDeviceHash(userDefaults: defaults)
        #expect((8...128).contains(first.count))
        #expect(first == first.lowercased())

        let second = FeedbackDeviceIdentity.stableDeviceHash(userDefaults: defaults)
        #expect(first == second)

        // 若旧值被污染为过短字符串，自动重建合法 UUID
        defaults.set("short", forKey: FeedbackDeviceIdentity.defaultStorageKey)
        let regenerated = FeedbackDeviceIdentity.stableDeviceHash(userDefaults: defaults)
        #expect(regenerated != "short")
        #expect((8...128).contains(regenerated.count))
        #expect(FeedbackDeviceIdentity.stableDeviceHash(userDefaults: defaults) == regenerated)
    }

    // MARK: - 4. 图片缩放与 JPEG 压缩

    @Test("截图缩放限制长边 <= 1600px 且不放大小图，压缩输出合法 JPEG 且远小于 3MB")
    func imageResizeAndCompression() throws {
        #expect(FeedbackImageProcessor.targetPixelSize(for: CGSize(width: 3200, height: 1600)) == CGSize(width: 1600, height: 800))
        #expect(FeedbackImageProcessor.targetPixelSize(for: CGSize(width: 1200, height: 2400)) == CGSize(width: 800, height: 1600))
        #expect(FeedbackImageProcessor.targetPixelSize(for: CGSize(width: 900, height: 600)) == CGSize(width: 900, height: 600))

        let largeImage = makeSolidUIImage(width: 2400, height: 1800, color: .darkGray)
        let jpegData = try FeedbackImageProcessor.compressToJPEG(image: largeImage)
        #expect(jpegData.count > 100)
        #expect(jpegData.count < FeedbackValidation.maxAttachmentBytes)
        // JPEG SOI 魔数 FF D8 FF
        #expect(jpegData[0] == 0xFF && jpegData[1] == 0xD8 && jpegData[2] == 0xFF)

        let decoded = try #require(UIImage(data: jpegData))
        let longEdge = max(decoded.size.width * decoded.scale, decoded.size.height * decoded.scale)
        #expect(longEdge <= 1600)
    }

    // MARK: - 5. Multipart 构建与 Request 构造

    @Test("Multipart 表单结构、X-Device-ID 与可选 Authorization 头正确构建")
    func multipartAndRequestBuilders() throws {
        let sampleBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let boundary = "TestBoundary123"
        let multipart = FeedbackMultipartBuilder.build(
            boundary: boundary,
            fieldName: "file",
            filename: "screen\"1.jpg",
            mimeType: "image/jpeg",
            fileData: sampleBytes
        )
        let text = try #require(String(data: multipart, encoding: .isoLatin1))
        #expect(text.hasPrefix("--TestBoundary123\r\n"))
        #expect(text.contains("Content-Disposition: form-data; name=\"file\"; filename=\"screen1.jpg\"\r\n"))
        #expect(text.contains("Content-Type: image/jpeg\r\n\r\n"))
        #expect(text.hasSuffix("\r\n--TestBoundary123--\r\n"))

        let baseURL = URL(string: "https://oryjk.cn/sumly/api/v1")!
        let uploadReq = try BackendFeedbackService.makeUploadAttachmentRequest(
            baseURL: baseURL,
            jpegData: sampleBytes,
            filename: "shot.jpg",
            deviceHash: "dev-hash-888",
            boundary: boundary
        )
        #expect(uploadReq.httpMethod == "POST")
        #expect(uploadReq.url?.absoluteString == "https://oryjk.cn/sumly/api/v1/app/feedback/attachments")
        #expect(uploadReq.value(forHTTPHeaderField: "X-Device-ID") == "dev-hash-888")
        #expect(uploadReq.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=TestBoundary123")

        // 超过 3MB 提前拒绝
        let oversized = Data(repeating: 0x01, count: FeedbackValidation.maxAttachmentBytes + 1)
        #expect(throws: FeedbackServiceError.attachmentTooLarge) {
            _ = try BackendFeedbackService.makeUploadAttachmentRequest(
                baseURL: baseURL,
                jpegData: oversized,
                filename: "huge.jpg",
                deviceHash: "dev-hash-888"
            )
        }

        // 游客提交不带 Authorization，登录态带 Bearer Token
        let payload = FeedbackSubmitPayload(
            deviceHash: "dev-hash-888",
            category: .suggestion,
            content: "希望支持导出年度攒金总结",
            contact: "",
            attachments: [],
            appVersion: "1.0.5",
            buildNumber: "60",
            iosVersion: "iOS 18.4",
            deviceModel: "iPhone17,1",
            marketMode: "domestic",
            cloudSyncEnabled: false
        )
        let guestReq = try BackendFeedbackService.makeSubmitFeedbackRequest(baseURL: baseURL, payload: payload, bearerToken: nil)
        #expect(guestReq.value(forHTTPHeaderField: "Authorization") == nil)
        let authReq = try BackendFeedbackService.makeSubmitFeedbackRequest(baseURL: baseURL, payload: payload, bearerToken: "jwt-token-xyz")
        #expect(authReq.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-token-xyz")

        // 我的记录 query 参数拼接
        let mineReq = BackendFeedbackService.makeMyFeedbacksRequest(
            baseURL: baseURL,
            deviceHash: "dev-hash-888",
            limit: 50,
            bearerToken: "jwt-token-xyz"
        )
        #expect(mineReq.httpMethod == "GET")
        #expect(mineReq.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-token-xyz")
        let mineURL = try #require(mineReq.url)
        let components = try #require(URLComponents(url: mineURL, resolvingAgainstBaseURL: false))
        #expect(components.path == "/sumly/api/v1/app/feedback/mine")
        #expect(components.queryItems == [
            URLQueryItem(name: "device_hash", value: "dev-hash-888"),
            URLQueryItem(name: "limit", value: "50")
        ])
    }

    // MARK: - 6. Mock URLSession 全链路（上传附件 + 免登录提交 + 我的记录 + 错误码映射）

    @Test("BackendFeedbackService 通过 Mock URLSession 完成上传、免登录提交、我的记录查询与错误映射")
    func backendServiceEndToEndWithMockURLSession() async throws {
        let host = "feedback-mock-\(UUID().uuidString.prefix(8).lowercased()).invalid"
        let baseURL = URL(string: "https://\(host)/sumly/api/v1")!
        let recorder = RecordedRequestsBox()

        FeedbackMockURLProtocol.register(host: host) { request in
            let url = request.url!
            let body = readBodyData(from: request)
            let entry = RecordedRequestsBox.Entry(
                method: request.httpMethod ?? "",
                url: url.absoluteString,
                authorization: request.value(forHTTPHeaderField: "Authorization"),
                deviceID: request.value(forHTTPHeaderField: "X-Device-ID"),
                contentType: request.value(forHTTPHeaderField: "Content-Type"),
                body: body
            )
            Task { await recorder.append(entry) }

            let path = url.path
            if path.hasSuffix("/app/feedback/attachments") {
                let json = """
                {"code":0,"message":"ok","data":{"object_key":"feedback/20261123/img1.jpg","url":"/api/v1/app/feedback/attachments/20261123/img1.jpg","content_type":"image/jpeg","size_bytes":42}}
                """
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(json.utf8))
            }
            if path.hasSuffix("/app/feedback") {
                let json = """
                {"code":0,"message":"ok","data":{"id":77,"category":"suggestion","content":"游客也能顺利提交反馈","contact":"guest@example.com","attachments":[{"object_key":"feedback/20261123/img1.jpg","url":"/api/v1/app/feedback/attachments/20261123/img1.jpg"}],"status":"new","admin_reply":"","replied_at":null,"created_at":"2026-11-23T15:50:00Z","updated_at":"2026-11-23T15:50:00Z"}}
                """
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(json.utf8))
            }
            if path.hasSuffix("/app/feedback/mine") {
                if url.query?.contains("rate-limit") == true {
                    let resp = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: nil)!
                    return (resp, Data(#"{"code":429,"message":"提交太频繁，请稍后重试"}"#.utf8))
                }
                let json = """
                {"code":0,"message":"ok","data":{"items":[{"id":77,"category":"suggestion","content":"游客也能顺利提交反馈","contact":"guest@example.com","attachments":[],"status":"in_progress","admin_reply":"我们已列入下版本计划","replied_at":"2026-11-23T16:00:00Z","created_at":"2026-11-23T15:50:00Z","updated_at":"2026-11-23T16:00:00Z"}]}}
                """
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, Data(json.utf8))
            }
            let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"code":404,"message":"not found"}"#.utf8))
        }
        defer { FeedbackMockURLProtocol.unregister(host: host) }

        let service = BackendFeedbackService(baseURL: baseURL, session: makeMockURLSession())

        let uploaded = try await service.uploadAttachment(
            jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            filename: "shot.jpg",
            deviceHash: "guest-device-hash-01"
        )
        #expect(uploaded.objectKey == "feedback/20261123/img1.jpg")
        #expect(uploaded.sizeBytes == 42)

        let payload = FeedbackSubmitPayload(
            deviceHash: "guest-device-hash-01",
            category: .suggestion,
            content: "游客也能顺利提交反馈",
            contact: "guest@example.com",
            attachments: [uploaded.attachment],
            appVersion: "1.0.5",
            buildNumber: "60",
            iosVersion: "iOS 18.4",
            deviceModel: "iPhone17,1",
            marketMode: "domestic",
            cloudSyncEnabled: false
        )
        let created = try await service.submitFeedback(payload, bearerToken: nil)
        #expect(created.id == 77)
        #expect(created.status == .new)
        #expect(created.attachments.count == 1)

        let mine = try await service.fetchMyFeedbacks(deviceHash: "guest-device-hash-01", limit: 50, bearerToken: "member-jwt")
        #expect(mine.count == 1)
        #expect(mine[0].status == .inProgress)
        #expect(mine[0].hasDeveloperReply == true)

        await #expect(throws: FeedbackServiceError.rateLimited("提交太频繁，请稍后重试")) {
            _ = try await service.fetchMyFeedbacks(deviceHash: "rate-limit-device", limit: 50, bearerToken: nil)
        }

        // 等待异步记录落齐并核验请求头细节
        try await Task.sleep(for: .milliseconds(50))
        let entries = await recorder.entries
        #expect(entries.count == 4)
        #expect(entries[0].deviceID == "guest-device-hash-01")
        #expect(entries[0].contentType?.hasPrefix("multipart/form-data; boundary=") == true)
        #expect(entries[1].authorization == nil)
        #expect(entries[2].authorization == "Bearer member-jwt")
    }

    // MARK: - 7. ViewModel 提交流程、截图失败重试复用与 Tab 自动切换

    @MainActor
    @Test("FeedbackCenterViewModel 支持截图失败重试不重复上传、提交成功后清空表单并切到我的记录")
    func viewModelSubmitRetryAndTabTransition() async {
        let createdItem = FeedbackItem(
            id: 501,
            category: .bug,
            content: "导出图表时偶发卡顿，附两张截图",
            contact: "wx_test",
            attachments: [
                FeedbackAttachment(objectKey: "k1", url: "/api/v1/app/feedback/attachments/20261123/k1.jpg"),
                FeedbackAttachment(objectKey: "k2", url: "/api/v1/app/feedback/attachments/20261123/k2.jpg")
            ],
            status: .new,
            createdAt: "2026-11-23T16:20:00Z"
        )
        let mock = MockFeedbackService(
            uploadResults: [
                .success(FeedbackUploadedAttachment(objectKey: "k1", url: "/api/v1/app/feedback/attachments/20261123/k1.jpg", contentType: "image/jpeg", sizeBytes: 10)),
                .failure(FeedbackServiceError.serviceUnavailable("MinIO 临时抖动"))
            ],
            submitResult: .success(createdItem),
            mineResult: .success([createdItem])
        )

        let vm = FeedbackCenterViewModel(
            service: mock,
            deviceHash: "vm-device-hash-99",
            tokenProvider: { nil },
            contextProvider: {
                FeedbackDiagnosticContext(
                    appVersion: "1.0.5",
                    buildNumber: "60",
                    iosVersion: "iOS 18.4",
                    deviceModel: "iPhone17,1",
                    marketMode: "domestic",
                    cloudSyncEnabled: false
                )
            }
        )

        vm.category = .bug
        vm.updateContent("短")
        #expect(vm.canSubmit == false)

        vm.updateContent("导出图表时偶发卡顿，附两张截图")
        vm.updateContact("wx_test")
        vm.addPreparedDraft(FeedbackDraftAttachment(filename: "a.jpg", jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9])))
        vm.addPreparedDraft(FeedbackDraftAttachment(filename: "b.jpg", jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9])))
        #expect(vm.canSubmit == true)

        // 第一次提交：第 1 张上传成功，第 2 张失败
        let firstAttempt = await vm.submit()
        #expect(firstAttempt == false)
        #expect(vm.selectedTab == .submit)
        #expect(vm.formError?.contains("MinIO 临时抖动") == true)
        #expect(vm.draftAttachments[0].uploadState.uploadedAttachment?.objectKey == "k1")
        #expect(vm.draftAttachments[1].uploadState.failureMessage != nil)
        #expect(await mock.uploadCallCount == 2)

        // 第二次重试：第 1 张直接复用，仅上传第 2 张，并成功提交
        await mock.setUploadResults([
            .success(FeedbackUploadedAttachment(objectKey: "k2", url: "/api/v1/app/feedback/attachments/20261123/k2.jpg", contentType: "image/jpeg", sizeBytes: 12))
        ])
        let secondAttempt = await vm.submit()
        #expect(secondAttempt == true)
        #expect(await mock.uploadCallCount == 3)
        #expect(vm.content.isEmpty)
        #expect(vm.contact.isEmpty)
        #expect(vm.draftAttachments.isEmpty)
        #expect(vm.selectedTab == .history)
        #expect(vm.successBanner == FeedbackCopy.submitSuccessMessage)
        #expect(vm.items.first?.id == 501)

        let submitted = await mock.submittedPayloads
        #expect(submitted.count == 1)
        #expect(submitted[0].0.attachments.map(\.objectKey) == ["k1", "k2"])
        #expect(submitted[0].0.deviceHash == "vm-device-hash-99")
        #expect(submitted[0].1 == nil)
    }

    // MARK: - 8. 零投资建议合规文案与隐私声明静态断言

    @Test("意见与反馈全部文案遵守零投资建议红线且明示隐私保护")
    func feedbackCopyCompliance() {
        let forbiddenTerms: [String] = [
            "建议买入", "建议卖出", "抄底", "逃顶", "加仓", "减仓",
            "荐股", "稳赚", "保本收益", "理财推荐", "收益预测",
            "买点", "卖点", "喊单", "牛市", "熊市", "投资建议"
        ]
        for text in FeedbackCopy.allUICopy {
            for forbidden in forbiddenTerms {
                #expect(!text.contains(forbidden), "反馈文案「\(text)」不应包含合规禁用词「\(forbidden)」")
            }
        }
        #expect(FeedbackCopy.diagnosticPrivacyNotice.contains("绝不上报"))
        #expect(FeedbackCopy.diagnosticPrivacyNotice.contains("持仓"))
    }

    // MARK: - 9. 键盘合规验证（禁用 iOS 26 .keyboard Toolbar）与视觉渲染截图

    @MainActor
    @Test("FeedbackCenterView 禁用 .keyboard 工具栏并完成双 Tab 与设置入口暗黑金视觉渲染")
    func feedbackViewsAvoidKeyboardToolbarAndRenderForVisualReview() async throws {
        let sampleItems: [FeedbackItem] = [
            FeedbackItem(
                id: 201,
                category: .suggestion,
                content: "希望在持仓日历里可以按季度查看累计购入克重变化，目前按月看已经很顺手了！",
                contact: "gold_lover@oryjk.cn",
                attachments: [],
                status: .resolved,
                adminReply: "非常棒的建议！我们已经在规划季度与年度维度聚合视图，上线后第一时间为您开放。",
                repliedAt: "2026-11-23T14:30:00Z",
                createdAt: "2026-11-22T09:15:00Z"
            ),
            FeedbackItem(
                id: 200,
                category: .bug,
                content: "切换国际金价与国内金价后，首页折线图偶发延迟 1 秒才刷新标题。",
                contact: "",
                attachments: [],
                status: .inProgress,
                adminReply: "",
                repliedAt: nil,
                createdAt: "2026-11-23T11:20:00Z"
            )
        ]

        let mock = MockFeedbackService(
            submitResult: .success(sampleItems[0]),
            mineResult: .success(sampleItems)
        )
        let context = FeedbackDiagnosticContext(
            appVersion: "1.0.5",
            buildNumber: "60",
            iosVersion: "iOS 18.4",
            deviceModel: "iPhone17,1",
            marketMode: "domestic",
            cloudSyncEnabled: false
        )

        // Tab 1: 提交反馈渲染与键盘 toolbar 零挂载校验
        let submitVM = FeedbackCenterViewModel(
            service: mock,
            deviceHash: "render-device-hash",
            tokenProvider: { nil },
            contextProvider: { context }
        )
        submitVM.category = .suggestion
        submitVM.updateContent("希望支持按季度统计攒金克重趋势，页面整体暗黑金质感非常喜欢。")
        submitVM.updateContact("sumly_user@example.com")
        let thumbJPEG = try FeedbackImageProcessor.compressToJPEG(
            image: makeSolidUIImage(width: 240, height: 240, color: UIColor(red: 0.95, green: 0.77, blue: 0.07, alpha: 1))
        )
        submitVM.addPreparedDraft(FeedbackDraftAttachment(filename: "preview.jpg", jpegData: thumbJPEG))

        // 挂载到非 Key 的后台 UIWindow（不调用 makeKeyAndVisible），既保证 NavigationStack/PhotosPicker
        // 具备完整 UIWindowScene 渲染管线，又绝不抢占并发键盘测试的 isKeyWindow 焦点。
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .normal - 1
        window.overrideUserInterfaceStyle = .dark
        let submitController = UIHostingController(
            rootView: NavigationStack {
                FeedbackCenterView(model: submitVM)
            }
            .preferredColorScheme(.dark)
            .tint(GoldTheme.gold)
        )
        window.rootViewController = submitController
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await Task.sleep(for: .milliseconds(350))
        submitController.view.setNeedsLayout()
        submitController.view.layoutIfNeeded()

        // 验证无 .keyboard UIToolbar 挂载
        for field in Self.findTextInputs(in: submitController.view) {
            #expect((field.inputAccessoryView?.bounds.height ?? 0) == 0)
            #expect(Self.containsToolbar(in: field.inputAccessoryView) == false)
        }

        let artifactDir = FileManager.default.temporaryDirectory.appendingPathComponent("sumly-feedback-ui-review", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)

        let submitImage = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let submitPNG = try #require(submitImage.pngData())
        #expect(submitPNG.count > 10_000)
        let submitURL = artifactDir.appendingPathComponent("feedback-submit.png")
        try submitPNG.write(to: submitURL, options: .atomic)
        print("FEEDBACK_RENDER_ARTIFACT: \(submitURL.path)")

        // Tab 2: 我的记录（含开发者回复）
        let historyVM = FeedbackCenterViewModel(
            service: mock,
            deviceHash: "render-device-hash",
            tokenProvider: { nil },
            contextProvider: { context }
        )
        historyVM.selectedTab = .history
        await historyVM.loadHistory()

        let historyController = UIHostingController(
            rootView: NavigationStack {
                FeedbackCenterView(model: historyVM)
            }
            .preferredColorScheme(.dark)
            .tint(GoldTheme.gold)
        )
        window.rootViewController = historyController
        try await Task.sleep(for: .milliseconds(350))
        historyController.view.setNeedsLayout()
        historyController.view.layoutIfNeeded()

        let historyImage = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let historyPNG = try #require(historyImage.pngData())
        #expect(historyPNG.count > 10_000)
        let historyURL = artifactDir.appendingPathComponent("feedback-history.png")
        try historyPNG.write(to: historyURL, options: .atomic)
        print("FEEDBACK_RENDER_ARTIFACT: \(historyURL.path)")
    }

    @MainActor
    private static func findTextInputs(in root: UIView) -> [UIView] {
        var found: [UIView] = []
        if root is UITextField || root is UITextView {
            found.append(root)
        }
        for subview in root.subviews {
            found.append(contentsOf: findTextInputs(in: subview))
        }
        return found
    }

    @MainActor
    private static func containsToolbar(in root: UIView?) -> Bool {
        guard let root else { return false }
        if root is UIToolbar { return true }
        return root.subviews.contains { containsToolbar(in: $0) }
    }
}
