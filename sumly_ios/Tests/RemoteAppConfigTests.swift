import Foundation
import Testing
@testable import Sumly

// MARK: - 测试用 Mock RemoteAppConfigServicing（Actor 隔离，Swift 6 并发安全）

private actor MockRemoteAppConfigService: RemoteAppConfigServicing {
    var result: Result<RemoteAppConfig, any Error>
    private(set) var fetchCount = 0

    init(result: Result<RemoteAppConfig, any Error>) {
        self.result = result
    }

    func setResult(_ next: Result<RemoteAppConfig, any Error>) {
        result = next
    }

    func fetchConfig() async throws -> RemoteAppConfig {
        fetchCount += 1
        return try result.get()
    }
}

private func makeIsolatedDefaults() -> (UserDefaults, String) {
    let suiteName = "com.oryjk.sumly.tests.remote-config.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}

// MARK: - 1. GET /api/v1/app/config 请求构造与 JSON Envelope 解码

@Test func remoteAppConfigRequestAndEnvelopeDecoding() throws {
    let baseNoSlash = URL(string: "https://oryjk.cn/sumly/api/v1")!
    let request = BackendRemoteAppConfigService.makeRequest(baseURL: baseNoSlash)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.absoluteString == "https://oryjk.cn/sumly/api/v1/app/config")
    #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    #expect(request.timeoutInterval == 8)

    let baseWithSlash = URL(string: "https://oryjk.cn/sumly/api/v1/")!
    let request2 = BackendRemoteAppConfigService.makeRequest(baseURL: baseWithSlash)
    #expect(request2.url?.absoluteString == "https://oryjk.cn/sumly/api/v1/app/config")

    // 标准响应（不带 message 字段）
    let payloadJSON = """
    {
      "code": 0,
      "data": {
        "membership_paywall": {
          "chanlun_requires_membership": false,
          "membership_entry_visible": false,
          "free_access_notice": "  限时免费  "
        },
        "updated_at": "2026-11-22T10:35:00Z"
      }
    }
    """
    let decoded = try BackendRemoteAppConfigService.decodeEnvelope(Data(payloadJSON.utf8))
    #expect(decoded.membershipPaywall.chanlunRequiresMembership == false)
    #expect(decoded.membershipPaywall.membershipEntryVisible == false)
    #expect(decoded.membershipPaywall.freeAccessNotice == "限时免费")
    #expect(decoded.updatedAt == "2026-11-22T10:35:00Z")

    // 字段缺失时安全默认值兜底（chanlun_requires_membership 必须默认 true）
    let partialJSON = """
    {
      "code": 0,
      "message": "ok",
      "data": {
        "membership_paywall": {}
      }
    }
    """
    let partialDecoded = try BackendRemoteAppConfigService.decodeEnvelope(Data(partialJSON.utf8))
    #expect(partialDecoded.membershipPaywall.chanlunRequiresMembership == true)
    #expect(partialDecoded.membershipPaywall.membershipEntryVisible == true)
    #expect(partialDecoded.membershipPaywall.freeAccessNotice == "")

    // 业务错误码抛出 envelope 错误
    let errorJSON = #"{"code": 50001, "message": "internal error"}"#
    #expect(throws: BackendRemoteAppConfigService.ServiceError.envelope(50001, "internal error")) {
        try BackendRemoteAppConfigService.decodeEnvelope(Data(errorJSON.utf8))
    }

    // code == 0 但缺 data 抛出 emptyData
    let emptyDataJSON = #"{"code": 0}"#
    #expect(throws: BackendRemoteAppConfigService.ServiceError.emptyData) {
        try BackendRemoteAppConfigService.decodeEnvelope(Data(emptyDataJSON.utf8))
    }
}

// MARK: - 2. 安全默认兜底与冷启动快照恢复

@MainActor
@Test func remoteAppConfigDefaultsSafeWhenNeverFetched() async {
    let (defaults, suiteName) = makeIsolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let service = MockRemoteAppConfigService(
        result: .failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
    )
    let store = RemoteAppConfigStore(service: service, userDefaults: defaults)

    // 从未拉取过：安全默认收费，入口显示，无免费公告
    #expect(store.chanlunRequiresMembership == true)
    #expect(store.membershipEntryVisible == true)
    #expect(store.freeAccessNotice == "")
    #expect(store.lastSyncedAt == nil)

    // 首次拉取即断网：不得因断网把收费切免费
    let ok = await store.refresh()
    #expect(!ok)
    #expect(store.chanlunRequiresMembership == true)
    #expect(store.membershipEntryVisible == true)
    #expect(store.lastSyncedAt == nil)
}

// MARK: - 3. 远程热切换免费与切回收费（门禁放行 + 皇冠标联动）

@MainActor
@Test func remoteConfigHotToggleBetweenFreeAndPaidControlsChanlunGateAndBadge() async {
    let (defaults, suiteName) = makeIsolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let freeConfig = RemoteAppConfig(
        membershipPaywall: MembershipPaywallConfig(
            chanlunRequiresMembership: false,
            membershipEntryVisible: true,
            freeAccessNotice: "限时免费"
        ),
        updatedAt: "2026-11-22T11:00:00Z"
    )
    let paidConfig = RemoteAppConfig(
        membershipPaywall: MembershipPaywallConfig(
            chanlunRequiresMembership: true,
            membershipEntryVisible: true,
            freeAccessNotice: ""
        ),
        updatedAt: "2026-11-22T12:00:00Z"
    )

    let service = MockRemoteAppConfigService(result: .success(freeConfig))
    let store = RemoteAppConfigStore(service: service, userDefaults: defaults)

    // 初始安全默认：拦截未订阅用户并显示皇冠标
    #expect(
        MembershipGate.evaluateChanlunAccess(
            hasChanlunConfig: true,
            isMemberActive: false,
            isSignedIn: true,
            requiresMembership: store.chanlunRequiresMembership
        ) == .openPaywall
    )
    #expect(
        MembershipGate.shouldShowChanlunLockBadge(
            requiresMembership: store.chanlunRequiresMembership,
            isMemberActive: false
        ) == true
    )

    // 1) 后台切换为免费（chanlun_requires_membership = false）：立即放行禅观且隐藏皇冠标
    let switchedFree = await store.refresh()
    #expect(switchedFree)
    #expect(store.chanlunRequiresMembership == false)
    #expect(store.freeAccessNotice == "限时免费")
    #expect(store.lastSyncedAt != nil)

    #expect(
        MembershipGate.evaluateChanlunAccess(
            hasChanlunConfig: true,
            isMemberActive: false,
            isSignedIn: true,
            requiresMembership: store.chanlunRequiresMembership
        ) == .openChanlun
    )
    #expect(
        MembershipGate.evaluateChanlunAccess(
            hasChanlunConfig: true,
            isMemberActive: false,
            isSignedIn: false,
            requiresMembership: store.chanlunRequiresMembership
        ) == .openLogin
    )
    #expect(
        MembershipGate.shouldShowChanlunLockBadge(
            requiresMembership: store.chanlunRequiresMembership,
            isMemberActive: false
        ) == false
    )

    // 2) 后台切回收费（chanlun_requires_membership = true）：立即恢复拦截与皇冠标
    await service.setResult(.success(paidConfig))
    let switchedPaid = await store.refresh()
    #expect(switchedPaid)
    #expect(store.chanlunRequiresMembership == true)
    #expect(store.freeAccessNotice == "")

    #expect(
        MembershipGate.evaluateChanlunAccess(
            hasChanlunConfig: true,
            isMemberActive: false,
            isSignedIn: true,
            requiresMembership: store.chanlunRequiresMembership
        ) == .openPaywall
    )
    #expect(
        MembershipGate.shouldShowChanlunLockBadge(
            requiresMembership: store.chanlunRequiresMembership,
            isMemberActive: false
        ) == true
    )
    // 已订阅老会员始终放行且不显示皇冠锁标
    #expect(
        MembershipGate.evaluateChanlunAccess(
            hasChanlunConfig: true,
            isMemberActive: true,
            isSignedIn: true,
            requiresMembership: store.chanlunRequiresMembership
        ) == .openChanlun
    )
    #expect(
        MembershipGate.shouldShowChanlunLockBadge(
            requiresMembership: store.chanlunRequiresMembership,
            isMemberActive: true
        ) == false
    )
}

// MARK: - 4. Apple 合规：后台隐藏新客入口时，已购老会员仍可见入口管理订阅

@Test func hiddenMembershipEntryRemainsVisibleForActiveSubscribers() {
    // 后台关闭新客入口：未订阅用户隐藏，已订阅老会员必须可见
    #expect(
        MembershipGate.shouldShowMembershipEntry(
            entryVisible: false,
            isMemberActive: false
        ) == false
    )
    #expect(
        MembershipGate.shouldShowMembershipEntry(
            entryVisible: false,
            isMemberActive: true
        ) == true
    )

    // 后台开启入口：所有用户均可见
    #expect(
        MembershipGate.shouldShowMembershipEntry(
            entryVisible: true,
            isMemberActive: false
        ) == true
    )
    #expect(
        MembershipGate.shouldShowMembershipEntry(
            entryVisible: true,
            isMemberActive: true
        ) == true
    )
}

// MARK: - 5. 断网静默保留上次有效缓存，绝不降级或崩溃

@MainActor
@Test func offlineRefreshPreservesLastValidPersistedSnapshotWithoutDowngrading() async {
    let (defaults, suiteName) = makeIsolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    // 5.1 先成功拉取收费态配置并落盘
    let paidSnapshot = RemoteAppConfig(
        membershipPaywall: MembershipPaywallConfig(
            chanlunRequiresMembership: true,
            membershipEntryVisible: true,
            freeAccessNotice: ""
        ),
        updatedAt: "2026-11-22T10:00:00Z"
    )
    let service = MockRemoteAppConfigService(result: .success(paidSnapshot))
    let firstStore = RemoteAppConfigStore(service: service, userDefaults: defaults)
    #expect(await firstStore.refresh())

    // 断网刷新失败：保留收费态，绝不降级为免费
    await service.setResult(.failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)))
    #expect(!(await firstStore.refresh()))
    #expect(firstStore.chanlunRequiresMembership == true)

    // 5.2 拉取限时免费配置并落盘，随后重启 App（新建 Store 实例）且处于断网状态
    let freeSnapshot = RemoteAppConfig(
        membershipPaywall: MembershipPaywallConfig(
            chanlunRequiresMembership: false,
            membershipEntryVisible: false,
            freeAccessNotice: "限时免费"
        ),
        updatedAt: "2026-11-22T10:30:00Z"
    )
    await service.setResult(.success(freeSnapshot))
    #expect(await firstStore.refresh())

    let offlineService = MockRemoteAppConfigService(
        result: .failure(BackendRemoteAppConfigService.ServiceError.httpStatus(503))
    )
    let relaunchedStore = RemoteAppConfigStore(service: offlineService, userDefaults: defaults)
    // 冷启动直接命中本地持久化快照
    #expect(relaunchedStore.chanlunRequiresMembership == false)
    #expect(relaunchedStore.membershipEntryVisible == false)
    #expect(relaunchedStore.freeAccessNotice == "限时免费")

    // 服务端 503 失败：静默保留上次有效缓存
    #expect(!(await relaunchedStore.refresh()))
    #expect(relaunchedStore.chanlunRequiresMembership == false)
    #expect(relaunchedStore.membershipEntryVisible == false)
    #expect(relaunchedStore.freeAccessNotice == "限时免费")
}
