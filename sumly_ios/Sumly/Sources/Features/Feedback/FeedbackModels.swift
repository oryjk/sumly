import Foundation
import UIKit

// MARK: - 1. 反馈分类与状态模型（Sendable）

enum FeedbackCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case suggestion
    case bug
    case data
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .suggestion: L10n.tr("功能建议")
        case .bug: L10n.tr("问题报错")
        case .data: L10n.tr("数据核对")
        case .other: L10n.tr("其他")
        }
    }

    /// 100% 兼容 iOS 17.0+ 的 SF Symbol。
    var symbolName: String {
        switch self {
        case .suggestion: "lightbulb.fill"
        case .bug: "ladybug.fill"
        case .data: "doc.text.magnifyingglass"
        case .other: "ellipsis.bubble.fill"
        }
    }

    var placeholder: String {
        switch self {
        case .suggestion:
            L10n.tr("说说您希望增加的新功能、交互优化或使用场景…")
        case .bug:
            L10n.tr("请描述遇到的问题、出现页面和复现步骤，附截图更有助于排查…")
        case .data:
            L10n.tr("请说明行情报价、涨跌幅或单位换算中的疑问（无需填写您的持仓金额）…")
        case .other:
            L10n.tr("欢迎留下任何关于记金的想法、使用体验或疑问…")
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self = FeedbackCategory(rawValue: raw) ?? .other
    }
}

enum FeedbackStatus: String, CaseIterable, Codable, Sendable {
    case new
    case inProgress = "in_progress"
    case resolved
    case archived

    var title: String {
        switch self {
        case .new: L10n.tr("待处理")
        case .inProgress: L10n.tr("处理中")
        case .resolved: L10n.tr("已解决")
        case .archived: L10n.tr("已归档")
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self = FeedbackStatus(rawValue: raw) ?? .new
    }
}

// MARK: - 2. 附件与反馈实体模型

struct FeedbackAttachment: Codable, Equatable, Hashable, Identifiable, Sendable {
    let objectKey: String
    let url: String

    var id: String { objectKey.isEmpty ? url : objectKey }

    enum CodingKeys: String, CodingKey {
        case objectKey = "object_key"
        case url
    }

    init(objectKey: String, url: String) {
        self.objectKey = objectKey
        self.url = url
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.objectKey = try container.decodeIfPresent(String.self, forKey: .objectKey) ?? ""
        self.url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
    }

    /// 解析完整图片访问地址：兼容后端返回绝对 URL 或 `/api/v1/...` 相对路径。
    func resolvedURL(baseURL: URL = BackendGoldPriceService.defaultBaseURL) -> URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") {
            return URL(string: trimmed)
        }
        if trimmed.hasPrefix("/") {
            let siteBase = Self.siteRootURL(from: baseURL)
            let joined = siteBase.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + trimmed
            return URL(string: joined)
        }
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    }

    func productionImageURL(baseURL: URL) -> URL? {
        let prefix = "/api/v1/app/feedback/attachments/"
        let raw = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard baseURL == SumlyProductionEndpoints.apiBaseURL, raw.hasPrefix(prefix),
              let components = URLComponents(string: raw), components.query == nil, components.fragment == nil else {
            return nil
        }
        let path = components.path.dropFirst(prefix.count)
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        return resolvedURL(baseURL: baseURL)
    }

    /// 从 API Base URL（如 `https://oryjk.cn/sumly/api/v1`）提取站点根前缀（`https://oryjk.cn/sumly`）。
    static func siteRootURL(from apiBaseURL: URL) -> URL {
        var raw = apiBaseURL.absoluteString
        while raw.hasSuffix("/") {
            raw.removeLast()
        }
        if raw.hasSuffix("/api/v1") {
            raw.removeLast("/api/v1".count)
        }
        return URL(string: raw) ?? apiBaseURL
    }
}

struct FeedbackUploadedAttachment: Codable, Equatable, Sendable {
    let objectKey: String
    let url: String
    let contentType: String
    let sizeBytes: Int

    var attachment: FeedbackAttachment {
        FeedbackAttachment(objectKey: objectKey, url: url)
    }

    enum CodingKeys: String, CodingKey {
        case objectKey = "object_key"
        case url
        case contentType = "content_type"
        case sizeBytes = "size_bytes"
    }

    init(objectKey: String, url: String, contentType: String, sizeBytes: Int) {
        self.objectKey = objectKey
        self.url = url
        self.contentType = contentType
        self.sizeBytes = sizeBytes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.objectKey = try container.decode(String.self, forKey: .objectKey)
        self.url = try container.decode(String.self, forKey: .url)
        self.contentType = try container.decodeIfPresent(String.self, forKey: .contentType) ?? "image/jpeg"
        self.sizeBytes = try container.decodeIfPresent(Int.self, forKey: .sizeBytes) ?? 0
    }
}

struct FeedbackItem: Codable, Equatable, Identifiable, Sendable {
    let id: Int64
    let category: FeedbackCategory
    let content: String
    let contact: String
    let attachments: [FeedbackAttachment]
    let status: FeedbackStatus
    let adminReply: String
    let repliedAt: String?
    let createdAt: String
    let updatedAt: String

    var hasDeveloperReply: Bool {
        !adminReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var trimmedContact: String {
        contact.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case content
        case contact
        case attachments
        case status
        case adminReply = "admin_reply"
        case repliedAt = "replied_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: Int64,
        category: FeedbackCategory,
        content: String,
        contact: String = "",
        attachments: [FeedbackAttachment] = [],
        status: FeedbackStatus = .new,
        adminReply: String = "",
        repliedAt: String? = nil,
        createdAt: String,
        updatedAt: String = ""
    ) {
        self.id = id
        self.category = category
        self.content = content
        self.contact = contact
        self.attachments = attachments
        self.status = status
        self.adminReply = adminReply
        self.repliedAt = repliedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int64.self, forKey: .id)
        self.category = try container.decodeIfPresent(FeedbackCategory.self, forKey: .category) ?? .other
        self.content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.contact = try container.decodeIfPresent(String.self, forKey: .contact) ?? ""
        self.attachments = try container.decodeIfPresent([FeedbackAttachment].self, forKey: .attachments) ?? []
        self.status = try container.decodeIfPresent(FeedbackStatus.self, forKey: .status) ?? .new
        self.adminReply = try container.decodeIfPresent(String.self, forKey: .adminReply) ?? ""
        self.repliedAt = try container.decodeIfPresent(String.self, forKey: .repliedAt)
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }
}

struct FeedbackListResponse: Codable, Equatable, Sendable {
    let items: [FeedbackItem]

    init(items: [FeedbackItem]) {
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case items
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.items = try container.decodeIfPresent([FeedbackItem].self, forKey: .items) ?? []
    }
}

struct FeedbackSubmitPayload: Codable, Equatable, Sendable {
    let deviceHash: String
    let category: FeedbackCategory
    let content: String
    let contact: String
    let attachments: [FeedbackAttachment]
    let appVersion: String
    let buildNumber: String
    let iosVersion: String
    let deviceModel: String
    let marketMode: String
    let cloudSyncEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case deviceHash = "device_hash"
        case category
        case content
        case contact
        case attachments
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case iosVersion = "ios_version"
        case deviceModel = "device_model"
        case marketMode = "market_mode"
        case cloudSyncEnabled = "cloud_sync_enabled"
    }
}

// MARK: - 3. 稳定设备哈希与透明排障环境上下文（绝不含任何持仓/金额隐私）

enum FeedbackDeviceIdentity {
    static let defaultStorageKey = "sumly.feedback.device_hash.v1"

    /// 返回当前设备稳定的匿名反馈标识，持久化在 `UserDefaults.standard`（不随账号登录/退出重置）。
    static func stableDeviceHash(
        userDefaults: UserDefaults = .standard,
        key: String = defaultStorageKey
    ) -> String {
        if let existing = userDefaults.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           (8...128).contains(existing.count) {
            return existing
        }
        let generated = UUID().uuidString.lowercased()
        userDefaults.set(generated, forKey: key)
        return generated
    }
}

struct FeedbackDiagnosticContext: Equatable, Sendable {
    let appVersion: String
    let buildNumber: String
    let iosVersion: String
    let deviceModel: String
    let marketMode: String
    let cloudSyncEnabled: Bool

    var summaryLine: String {
        var segments: [String] = []
        if !appVersion.isEmpty {
            if !buildNumber.isEmpty {
                segments.append("App v\(appVersion) (\(buildNumber))")
            } else {
                segments.append("App v\(appVersion)")
            }
        }
        if !iosVersion.isEmpty {
            segments.append(iosVersion)
        }
        if !deviceModel.isEmpty {
            segments.append(deviceModel)
        }
        return segments.joined(separator: " · ")
    }

    var marketModeDisplayTitle: String {
        switch marketMode {
        case GoldMarketBasis.domestic.rawValue: L10n.tr("国内金价")
        case GoldMarketBasis.international.rawValue: L10n.tr("国际金价")
        default: marketMode
        }
    }

    var cloudSyncDisplayTitle: String {
        cloudSyncEnabled ? L10n.tr("已登录云同步") : L10n.tr("游客离线模式")
    }

    @MainActor
    static func current(
        marketBasis: GoldMarketBasis,
        cloudSyncEnabled: Bool,
        bundle: Bundle = .main
    ) -> FeedbackDiagnosticContext {
        let appVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let buildNumber = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let osVersion = UIDevice.current.systemVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let iosVersion = osVersion.isEmpty ? "iOS" : "iOS \(osVersion)"
        return FeedbackDiagnosticContext(
            appVersion: appVersion,
            buildNumber: buildNumber,
            iosVersion: iosVersion,
            deviceModel: hardwareModelIdentifier(),
            marketMode: marketBasis.rawValue,
            cloudSyncEnabled: cloudSyncEnabled
        )
    }

    static func hardwareModelIdentifier() -> String {
        #if targetEnvironment(simulator)
        if let simModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !simModel.isEmpty {
            return simModel
        }
        #endif
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            partial.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? "iPhone" : identifier
    }
}

// MARK: - 4. 表单与字数校验（纯函数）

enum FeedbackValidation {
    static let minContentLength = 5
    static let maxContentLength = 1000
    static let maxContactLength = 120
    static let maxAttachmentCount = 3
    static let maxAttachmentBytes = 3 * 1024 * 1024

    enum Result: Equatable, Sendable {
        case valid
        case tooShort(remaining: Int)
        case tooLong(excess: Int)
        case contactTooLong(excess: Int)
        case tooManyAttachments

        var isValid: Bool {
            self == .valid
        }
    }

    static func trimmedContent(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func trimmedContact(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func clampContent(_ text: String) -> String {
        guard text.count > maxContentLength else { return text }
        return String(text.prefix(maxContentLength))
    }

    static func clampContact(_ text: String) -> String {
        guard text.count > maxContactLength else { return text }
        return String(text.prefix(maxContactLength))
    }

    static func validate(content: String, contact: String, attachmentCount: Int) -> Result {
        let trimmed = trimmedContent(content)
        if trimmed.count < minContentLength {
            return .tooShort(remaining: minContentLength - trimmed.count)
        }
        if trimmed.count > maxContentLength {
            return .tooLong(excess: trimmed.count - maxContentLength)
        }
        let cleanContact = trimmedContact(contact)
        if cleanContact.count > maxContactLength {
            return .contactTooLong(excess: cleanContact.count - maxContactLength)
        }
        if attachmentCount > maxAttachmentCount {
            return .tooManyAttachments
        }
        return .valid
    }
}

// MARK: - 5. 时间解析与展示格式化

enum FeedbackDateFormatter {
    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: trimmed)
    }

    static func formatDisplay(
        _ raw: String?,
        now: Date = .now,
        timeZone: TimeZone = .current
    ) -> String {
        guard let date = parse(raw) else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.dateFormat = sameYear ? "MM-dd HH:mm" : "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 6. 静态文案（单一数据源，便于零投资建议合规测试）

enum FeedbackCopy {
    static var pageTitle: String { L10n.tr("意见与反馈") }
    static var entryTitle: String { L10n.tr("意见与反馈") }
    static var entrySubtitle: String { L10n.tr("提交建议、反馈问题或查看回复") }

    static var submitTabTitle: String { L10n.tr("提交反馈") }
    static var historyTabTitle: String { L10n.tr("我的记录") }

    static var categorySectionTitle: String { L10n.tr("反馈类型") }
    static var contentSectionTitle: String { L10n.tr("详细描述") }
    static var attachmentsSectionTitle: String { L10n.tr("截图附件") }
    static var attachmentsOptionalHint: String { L10n.tr("选填，最多 3 张") }
    static var attachmentsFootnote: String { L10n.tr("图片会自动压缩上传，仅用于辅助定位问题。") }
    static var contactSectionTitle: String { L10n.tr("联系方式") }
    static var contactOptionalHint: String { L10n.tr("选填") }
    static var contactPlaceholder: String { L10n.tr("微信号或邮箱，方便一对一回复") }

    static var diagnosticTitle: String { L10n.tr("随附排障环境信息") }
    static var diagnosticPrivacyNotice: String { L10n.tr("仅用于排查问题，绝不上报您的克重、金额或任何持仓记录") }

    static var submitButtonTitle: String { L10n.tr("提交反馈") }
    static var submittingFeedbackText: String { L10n.tr("正在提交反馈…") }
    static var submitSuccessMessage: String { L10n.tr("感谢反馈，已收到您的消息。开发者回复后可在此查看。") }

    static var developerReplyTitle: String { L10n.tr("开发者回复") }
    static var emptyHistoryTitle: String { L10n.tr("还没有提交过反馈") }
    static var emptyHistorySubtitle: String { L10n.tr("无论是新功能想法还是使用中的小问题，都很欢迎随时告诉我们。") }
    static var emptyHistoryAction: String { L10n.tr("去写一条反馈") }
    static var loadingHistoryText: String { L10n.tr("正在加载反馈记录…") }
    static var retryActionTitle: String { L10n.tr("重新加载") }

    static var allUICopy: [String] {
        [
            pageTitle,
            entryTitle,
            entrySubtitle,
            submitTabTitle,
            historyTabTitle,
            categorySectionTitle,
            contentSectionTitle,
            attachmentsSectionTitle,
            attachmentsOptionalHint,
            attachmentsFootnote,
            contactSectionTitle,
            contactOptionalHint,
            contactPlaceholder,
            diagnosticTitle,
            diagnosticPrivacyNotice,
            submitButtonTitle,
            submittingFeedbackText,
            submitSuccessMessage,
            developerReplyTitle,
            emptyHistoryTitle,
            emptyHistorySubtitle,
            emptyHistoryAction,
            loadingHistoryText,
            retryActionTitle
        ] + FeedbackCategory.allCases.flatMap { [$0.title, $0.placeholder] }
          + FeedbackStatus.allCases.map(\.title)
    }
}
