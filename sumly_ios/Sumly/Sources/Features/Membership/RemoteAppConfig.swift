import Foundation
import OSLog

private let remoteConfigLogger = Logger(subsystem: "com.oryjk.sumly", category: "RemoteConfig")

// MARK: - 1. 远程应用配置纯模型（Sendable）

struct MembershipPaywallConfig: Codable, Equatable, Sendable {
    var chanlunRequiresMembership: Bool
    var membershipEntryVisible: Bool
    var freeAccessNotice: String

    /// 安全默认配置：默认收费、展示会员入口、无免费公告。
    static let `default` = MembershipPaywallConfig(
        chanlunRequiresMembership: true,
        membershipEntryVisible: true,
        freeAccessNotice: ""
    )

    init(
        chanlunRequiresMembership: Bool = true,
        membershipEntryVisible: Bool = true,
        freeAccessNotice: String = ""
    ) {
        self.chanlunRequiresMembership = chanlunRequiresMembership
        self.membershipEntryVisible = membershipEntryVisible
        self.freeAccessNotice = freeAccessNotice.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CodingKeys: String, CodingKey {
        case chanlunRequiresMembership = "chanlun_requires_membership"
        case membershipEntryVisible = "membership_entry_visible"
        case freeAccessNotice = "free_access_notice"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.chanlunRequiresMembership = try container.decodeIfPresent(Bool.self, forKey: .chanlunRequiresMembership) ?? true
        self.membershipEntryVisible = try container.decodeIfPresent(Bool.self, forKey: .membershipEntryVisible) ?? true
        let rawNotice = try container.decodeIfPresent(String.self, forKey: .freeAccessNotice) ?? ""
        self.freeAccessNotice = rawNotice.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct RemoteAppConfig: Codable, Equatable, Sendable {
    var membershipPaywall: MembershipPaywallConfig
    var updatedAt: String?

    /// 安全默认配置：从未拉取过或缺少字段时保持收费门禁。
    static let `default` = RemoteAppConfig(
        membershipPaywall: .default,
        updatedAt: nil
    )

    init(
        membershipPaywall: MembershipPaywallConfig = .default,
        updatedAt: String? = nil
    ) {
        self.membershipPaywall = membershipPaywall
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case membershipPaywall = "membership_paywall"
        case updatedAt = "updated_at"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.membershipPaywall = try container.decodeIfPresent(MembershipPaywallConfig.self, forKey: .membershipPaywall) ?? .default
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

// MARK: - 2. 远程配置网络服务协议与后端实现

protocol RemoteAppConfigServicing: Sendable {
    func fetchConfig() async throws -> RemoteAppConfig
}

struct BackendRemoteAppConfigService: RemoteAppConfigServicing, Sendable {
    static let endpointPath = "app/config"
    static let requestTimeout: TimeInterval = 8

    var baseURL: URL = BackendGoldPriceService.defaultBaseURL
    var session: URLSession = .shared

    enum ServiceError: Error, Equatable, Sendable {
        case badResponse
        case httpStatus(Int)
        case envelope(Int, String)
        case emptyData
    }

    private struct Envelope<T: Decodable>: Decodable {
        let code: Int
        let message: String?
        let data: T?
    }

    static func makeRequest(baseURL: URL) -> URLRequest {
        let url = BackendGoldPriceService.requestURL(baseURL: baseURL, path: endpointPath)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = requestTimeout
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    static func decodeEnvelope(_ data: Data) throws -> RemoteAppConfig {
        let envelope = try JSONDecoder().decode(Envelope<RemoteAppConfig>.self, from: data)
        guard envelope.code == 0 else {
            throw ServiceError.envelope(envelope.code, envelope.message ?? "")
        }
        guard let payload = envelope.data else {
            throw ServiceError.emptyData
        }
        return payload
    }

    func fetchConfig() async throws -> RemoteAppConfig {
        let request = Self.makeRequest(baseURL: baseURL)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ServiceError.httpStatus(http.statusCode)
        }
        return try Self.decodeEnvelope(data)
    }
}

// MARK: - 3. 远程配置状态容器（@MainActor @Observable + UserDefaults 持久化）

@MainActor
@Observable
final class RemoteAppConfigStore {
    static let defaultStorageKey = "sumly.remote_app_config.snapshot.v1"

    @ObservationIgnored private let service: any RemoteAppConfigServicing
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let storageKey: String

    private(set) var config: RemoteAppConfig
    private(set) var isRefreshing = false
    private(set) var lastSyncedAt: Date?

    init(
        service: any RemoteAppConfigServicing = BackendRemoteAppConfigService(),
        userDefaults: UserDefaults = .standard,
        storageKey: String = RemoteAppConfigStore.defaultStorageKey,
        initialConfig: RemoteAppConfig? = nil
    ) {
        self.service = service
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        if let initialConfig {
            self.config = initialConfig
        } else if let cached = Self.loadSnapshot(from: userDefaults, key: storageKey) {
            self.config = cached
        } else {
            self.config = .default
        }
    }

    var membershipPaywall: MembershipPaywallConfig {
        config.membershipPaywall
    }

    var chanlunRequiresMembership: Bool {
        config.membershipPaywall.chanlunRequiresMembership
    }

    var membershipEntryVisible: Bool {
        config.membershipPaywall.membershipEntryVisible
    }

    var freeAccessNotice: String {
        config.membershipPaywall.freeAccessNotice
    }

    /// 拉取最新远程配置并落盘；网络或服务端异常时静默保留上次有效缓存，绝不降级把收费误切免费。
    @discardableResult
    func refresh() async -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let latest = try await service.fetchConfig()
            config = latest
            lastSyncedAt = .now
            Self.saveSnapshot(latest, to: userDefaults, key: storageKey)
            remoteConfigLogger.info(
                "RemoteAppConfig refreshed: chanlunRequiresMembership=\(latest.membershipPaywall.chanlunRequiresMembership, privacy: .public), membershipEntryVisible=\(latest.membershipPaywall.membershipEntryVisible, privacy: .public)"
            )
            return true
        } catch {
            remoteConfigLogger.warning(
                "RemoteAppConfig refresh failed; keeping cached snapshot (chanlunRequiresMembership=\(self.config.membershipPaywall.chanlunRequiresMembership, privacy: .public)): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    // MARK: - Persistence Helpers

    static func loadSnapshot(from userDefaults: UserDefaults, key: String) -> RemoteAppConfig? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RemoteAppConfig.self, from: data)
    }

    static func saveSnapshot(_ config: RemoteAppConfig, to userDefaults: UserDefaults, key: String) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        userDefaults.set(data, forKey: key)
    }
}
