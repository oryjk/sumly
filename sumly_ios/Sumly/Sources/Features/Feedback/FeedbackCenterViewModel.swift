import Foundation
import Observation
import UIKit

// MARK: - 1. 反馈中心 Tab 与草稿附件状态

enum FeedbackCenterTab: String, CaseIterable, Identifiable, Sendable {
    case submit
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .submit: FeedbackCopy.submitTabTitle
        case .history: FeedbackCopy.historyTabTitle
        }
    }
}

struct FeedbackDraftAttachment: Identifiable, Equatable, Sendable {
    enum UploadState: Equatable, Sendable {
        case pending
        case uploading
        case uploaded(FeedbackAttachment)
        case failed(String)

        var isUploading: Bool {
            self == .uploading
        }

        var uploadedAttachment: FeedbackAttachment? {
            if case .uploaded(let attachment) = self {
                return attachment
            }
            return nil
        }

        var failureMessage: String? {
            if case .failed(let message) = self {
                return message
            }
            return nil
        }
    }

    let id: UUID
    let filename: String
    let jpegData: Data
    var uploadState: UploadState

    init(
        id: UUID = UUID(),
        filename: String = "screenshot.jpg",
        jpegData: Data,
        uploadState: UploadState = .pending
    ) {
        self.id = id
        self.filename = filename
        self.jpegData = jpegData
        self.uploadState = uploadState
    }
}

// MARK: - 2. 可选 Bearer Token 解析器（游客免登录照常放行）

@MainActor
enum FeedbackAuthTokenProvider {
    static func resolveOptionalToken(from session: AuthSession) async -> String? {
        guard let current = session.stored else { return nil }
        if current.expiresAt <= Date().addingTimeInterval(15) {
            try? await session.refresh()
        }
        guard let latest = session.stored, latest.expiresAt > Date() else {
            return nil
        }
        let token = latest.result.token.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}

// MARK: - 3. FeedbackCenterViewModel（@MainActor @Observable）

@MainActor
@Observable
final class FeedbackCenterViewModel {
    enum HistoryState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    // Tab 状态
    var selectedTab: FeedbackCenterTab = .submit

    // 表单字段
    var category: FeedbackCategory = .suggestion
    var content: String = ""
    var contact: String = ""
    var draftAttachments: [FeedbackDraftAttachment] = []
    var isProcessingPhotos: Bool = false

    // 提交状态
    private(set) var isSubmitting: Bool = false
    private(set) var submissionStatusText: String = FeedbackCopy.submitButtonTitle
    var formError: String?
    var successBanner: String?

    // 历史记录状态
    private(set) var items: [FeedbackItem] = []
    private(set) var historyState: HistoryState = .idle
    private(set) var isRefreshingHistory: Bool = false

    // 依赖（不触发 SwiftUI 无关重绘）
    @ObservationIgnored let service: any FeedbackServicing
    @ObservationIgnored let deviceHash: String
    @ObservationIgnored private let tokenProvider: @MainActor () async -> String?
    @ObservationIgnored private let contextProvider: @MainActor () -> FeedbackDiagnosticContext

    init(
        service: any FeedbackServicing = BackendFeedbackService(),
        deviceHash: String = FeedbackDeviceIdentity.stableDeviceHash(),
        tokenProvider: @escaping @MainActor () async -> String? = { nil },
        contextProvider: @escaping @MainActor () -> FeedbackDiagnosticContext
    ) {
        self.service = service
        self.deviceHash = deviceHash
        self.tokenProvider = tokenProvider
        self.contextProvider = contextProvider
    }

    convenience init(
        session: AuthSession,
        marketBasis: GoldMarketBasis,
        service: any FeedbackServicing = BackendFeedbackService(),
        userDefaults: UserDefaults = .standard
    ) {
        self.init(
            service: service,
            deviceHash: FeedbackDeviceIdentity.stableDeviceHash(userDefaults: userDefaults),
            tokenProvider: {
                await FeedbackAuthTokenProvider.resolveOptionalToken(from: session)
            },
            contextProvider: {
                FeedbackDiagnosticContext.current(
                    marketBasis: marketBasis,
                    cloudSyncEnabled: session.user != nil
                )
            }
        )
    }

    // MARK: - 派生属性

    var diagnosticContext: FeedbackDiagnosticContext {
        contextProvider()
    }

    var contentCharacterCount: Int {
        content.count
    }

    var remainingAttachmentSlots: Int {
        max(0, FeedbackValidation.maxAttachmentCount - draftAttachments.count)
    }

    var validationResult: FeedbackValidation.Result {
        FeedbackValidation.validate(
            content: content,
            contact: contact,
            attachmentCount: draftAttachments.count
        )
    }

    var canSubmit: Bool {
        validationResult.isValid && !isSubmitting && !isProcessingPhotos
    }

    var contentHintText: String {
        switch validationResult {
        case .tooShort(let remaining):
            if FeedbackValidation.trimmedContent(content).isEmpty {
                return "至少输入 \(FeedbackValidation.minContentLength) 个字"
            }
            return "再输入 \(remaining) 个字即可提交"
        case .tooLong(let excess):
            return "已超出 \(excess) 字，请精简至 \(FeedbackValidation.maxContentLength) 字以内"
        case .contactTooLong:
            return "联系方式过长，请控制在 \(FeedbackValidation.maxContactLength) 字以内"
        case .tooManyAttachments:
            return "最多上传 \(FeedbackValidation.maxAttachmentCount) 张截图"
        case .valid:
            return "描述越清晰，越方便我们快速定位"
        }
    }

    var hasAnyDeveloperReply: Bool {
        items.contains(where: \.hasDeveloperReply)
    }

    // MARK: - 输入与附件管理

    func updateContent(_ newValue: String) {
        let clamped = FeedbackValidation.clampContent(newValue)
        if content != clamped {
            content = clamped
        }
        if formError != nil {
            formError = nil
        }
    }

    func updateContact(_ newValue: String) {
        let clamped = FeedbackValidation.clampContact(newValue)
        if contact != clamped {
            contact = clamped
        }
        if formError != nil {
            formError = nil
        }
    }

    func appendCompressedImages(rawDatas: [Data]) async {
        guard !rawDatas.isEmpty, remainingAttachmentSlots > 0 else { return }
        isProcessingPhotos = true
        formError = nil
        defer { isProcessingPhotos = false }

        let slots = remainingAttachmentSlots
        let candidates = Array(rawDatas.prefix(slots))
        var failures = 0

        for rawData in candidates {
            do {
                let jpegData = try await Task.detached(priority: .userInitiated) {
                    try FeedbackImageProcessor.compressToJPEG(rawData: rawData)
                }.value
                let draft = FeedbackDraftAttachment(
                    filename: "feedback-\(UUID().uuidString.prefix(8).lowercased()).jpg",
                    jpegData: jpegData,
                    uploadState: .pending
                )
                if draftAttachments.count < FeedbackValidation.maxAttachmentCount {
                    draftAttachments.append(draft)
                }
            } catch {
                failures += 1
            }
        }

        if failures > 0 {
            formError = "有 \(failures) 张图片读取或压缩失败，已跳过。"
        }
    }

    func addPreparedDraft(_ draft: FeedbackDraftAttachment) {
        guard draftAttachments.count < FeedbackValidation.maxAttachmentCount else { return }
        draftAttachments.append(draft)
        formError = nil
    }

    func removeAttachment(id: UUID) {
        guard !isSubmitting else { return }
        draftAttachments.removeAll { $0.id == id }
        formError = nil
    }

    func dismissSuccessBanner() {
        successBanner = nil
    }

    // MARK: - 提交反馈（顺序上传截图 + 提交主表单）

    @discardableResult
    func submit() async -> Bool {
        guard !isSubmitting else { return false }
        formError = nil
        successBanner = nil

        let check = validationResult
        guard check.isValid else {
            formError = contentHintText
            return false
        }

        isSubmitting = true
        defer {
            isSubmitting = false
            submissionStatusText = FeedbackCopy.submitButtonTitle
        }

        // 1. 顺序上传尚未成功的截图，已上传成功的附件重试时自动复用
        let pendingIndices = draftAttachments.indices.filter {
            draftAttachments[$0].uploadState.uploadedAttachment == nil
        }
        let totalToUpload = pendingIndices.count

        for (step, index) in pendingIndices.enumerated() {
            submissionStatusText = "正在上传截图 \(step + 1)/\(totalToUpload)…"
            draftAttachments[index].uploadState = .uploading
            let item = draftAttachments[index]
            do {
                let uploaded = try await service.uploadAttachment(
                    jpegData: item.jpegData,
                    filename: item.filename,
                    deviceHash: deviceHash
                )
                draftAttachments[index].uploadState = .uploaded(uploaded.attachment)
            } catch is CancellationError {
                draftAttachments[index].uploadState = .pending
                return false
            } catch {
                let message = error.localizedDescription
                draftAttachments[index].uploadState = .failed(message)
                formError = "截图上传失败：\(message)"
                return false
            }
        }

        let uploadedAttachments = draftAttachments.compactMap(\.uploadState.uploadedAttachment)

        // 2. 提交反馈主体（登录带 Bearer，游客不带 Header 照常提交）
        submissionStatusText = FeedbackCopy.submittingFeedbackText
        let token = await tokenProvider()
        let context = contextProvider()
        let payload = FeedbackSubmitPayload(
            deviceHash: deviceHash,
            category: category,
            content: FeedbackValidation.trimmedContent(content),
            contact: FeedbackValidation.trimmedContact(contact),
            attachments: uploadedAttachments,
            appVersion: context.appVersion,
            buildNumber: context.buildNumber,
            iosVersion: context.iosVersion,
            deviceModel: context.deviceModel,
            marketMode: context.marketMode,
            cloudSyncEnabled: context.cloudSyncEnabled
        )

        do {
            let created = try await service.submitFeedback(payload, bearerToken: token)
            // 清空表单并立即将新提交插入「我的记录」顶部
            content = ""
            contact = ""
            draftAttachments = []
            formError = nil
            successBanner = FeedbackCopy.submitSuccessMessage
            items.removeAll { $0.id == created.id }
            items.insert(created, at: 0)
            historyState = .loaded
            selectedTab = .history
            await refreshHistory(silent: true)
            return true
        } catch is CancellationError {
            return false
        } catch {
            formError = error.localizedDescription
            return false
        }
    }

    // MARK: - 拉取「我的反馈记录」

    func loadHistoryIfNeeded() async {
        if case .idle = historyState {
            await loadHistory()
        }
    }

    func loadHistory() async {
        guard !isRefreshingHistory else { return }
        isRefreshingHistory = true
        if items.isEmpty {
            historyState = .loading
        }
        defer { isRefreshingHistory = false }

        let token = await tokenProvider()
        do {
            let fetched = try await service.fetchMyFeedbacks(
                deviceHash: deviceHash,
                limit: 50,
                bearerToken: token
            )
            items = fetched
            historyState = .loaded
        } catch is CancellationError {
            if items.isEmpty {
                historyState = .idle
            }
        } catch {
            if items.isEmpty {
                historyState = .failed(error.localizedDescription)
            }
        }
    }

    func refreshHistory(silent: Bool = false) async {
        guard !isRefreshingHistory else { return }
        isRefreshingHistory = true
        if !silent, items.isEmpty {
            historyState = .loading
        }
        defer { isRefreshingHistory = false }

        let token = await tokenProvider()
        do {
            let fetched = try await service.fetchMyFeedbacks(
                deviceHash: deviceHash,
                limit: 50,
                bearerToken: token
            )
            items = fetched
            historyState = .loaded
        } catch is CancellationError {
            return
        } catch {
            if !silent, items.isEmpty {
                historyState = .failed(error.localizedDescription)
            }
        }
    }
}
