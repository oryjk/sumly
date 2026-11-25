import Foundation
import ImageIO
import SwiftUI
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Sumly

// MARK: - 测试用轻量 Mock StoreKit 2 客户端（Actor 隔离，Swift 6 并发安全）

private actor MockMembershipStoreKitClient: MembershipStoreKitClient {
    var productsResult: Result<[MembershipProductInfo], any Error> = .success([
        MembershipProductInfo(plan: .yearly),
        MembershipProductInfo(plan: .monthly)
    ])
    var entitlements: [MembershipTransactionRecord] = []
    var purchaseHandler: @Sendable (String) async throws -> MembershipPurchaseOutcome = { _ in .userCancelled }
    var syncError: (any Error)?
    private(set) var syncCallCount = 0
    private(set) var loadProductsCallCount = 0
    private(set) var purchasedProductIDs: [String] = []
    private var updateContinuation: AsyncStream<MembershipTransactionRecord>.Continuation?

    func setProductsResult(_ result: Result<[MembershipProductInfo], any Error>) {
        productsResult = result
    }

    func setEntitlements(_ records: [MembershipTransactionRecord]) {
        entitlements = records
    }

    func setPurchaseHandler(_ handler: @escaping @Sendable (String) async throws -> MembershipPurchaseOutcome) {
        purchaseHandler = handler
    }

    func setSyncError(_ error: (any Error)?) {
        syncError = error
    }

    func emitTransactionUpdate(_ record: MembershipTransactionRecord) {
        updateContinuation?.yield(record)
    }

    func finishUpdates() {
        updateContinuation?.finish()
    }

    func loadProducts(for productIDs: [String]) async throws -> [MembershipProductInfo] {
        loadProductsCallCount += 1
        return try productsResult.get().filter { productIDs.contains($0.id) }
    }

    func currentEntitlements() async -> [MembershipTransactionRecord] {
        entitlements
    }

    func purchase(productID: String) async throws -> MembershipPurchaseOutcome {
        purchasedProductIDs.append(productID)
        return try await purchaseHandler(productID)
    }

    func syncAppStore() async throws {
        syncCallCount += 1
        if let syncError {
            throw syncError
        }
    }

    nonisolated func observeTransactionUpdates() -> AsyncStream<MembershipTransactionRecord> {
        AsyncStream { continuation in
            Task { await self.registerUpdateContinuation(continuation) }
        }
    }

    private func registerUpdateContinuation(_ continuation: AsyncStream<MembershipTransactionRecord>.Continuation) {
        updateContinuation = continuation
    }
}

private struct MockAccountRenderAuth: AuthServicing {
    func execute(_ request: AuthRequest) async throws -> Data {
        throw AuthError.unavailable
    }
}

@MainActor
private final class MockAccountRenderStore: CredentialStoring {
    func load() throws -> StoredSession? { nil }
    func save(_ session: StoredSession) throws {}
    func clear() throws {}
}

// MARK: - 1. 商品目录、折合月价与年卡省钱比例计算

@Test func membershipCatalogIdentifiersAndYearlySavingsCalculation() {
    #expect(MembershipPlan.yearly.rawValue == "com.oryjk.sumly.membership.yearly")
    #expect(MembershipPlan.monthly.rawValue == "com.oryjk.sumly.membership.monthly")
    #expect(MembershipPlan.productIDs == [
        "com.oryjk.sumly.membership.yearly",
        "com.oryjk.sumly.membership.monthly"
    ])
    #expect(MembershipPlan.defaultSelection == .yearly)
    #expect(MembershipPlan.yearly.fallbackDisplayPrice == "¥99")
    #expect(MembershipPlan.yearly.periodLabel == "1 年")
    #expect(MembershipPlan.yearly.fallbackMonthlyEquivalentText == "折合 ¥8.25/月")
    #expect(MembershipPlan.monthly.fallbackDisplayPrice == "¥39")
    #expect(MembershipPlan.monthly.periodLabel == "1 个月")

    // (39 * 12 - 99) / (39 * 12) = 369 / 468 = 78.846% -> 79%
    let defaultSavings = MembershipPricing.yearlySavingsPercent(
        yearlyPrice: MembershipPlan.yearly.fallbackPrice,
        monthlyPrice: MembershipPlan.monthly.fallbackPrice
    )
    #expect(defaultSavings == 79)
    #expect(MembershipPricing.yearlyBadgeText(savingsPercent: defaultSavings) == "推荐 · 省 79%")
    #expect(MembershipPricing.monthlyEquivalentText(yearlyPrice: Decimal(99)) == "折合 ¥8.25/月")

    // 动态价格场景（如促销价 ¥88 / 月卡 ¥29）
    #expect(MembershipPricing.yearlySavingsPercent(yearlyPrice: Decimal(88), monthlyPrice: Decimal(29)) == 75)
    // 年卡高于 12 个月总价时省钱比例为 0，徽章退化为「推荐方案」
    #expect(MembershipPricing.yearlySavingsPercent(yearlyPrice: Decimal(500), monthlyPrice: Decimal(30)) == 0)
    #expect(MembershipPricing.yearlyBadgeText(savingsPercent: 0) == "推荐方案")
    // 非法价格回退默认值
    #expect(MembershipPricing.yearlySavingsPercent(yearlyPrice: Decimal(0), monthlyPrice: Decimal(39)) == 79)
}

// MARK: - 2. 未订阅拦截禅观与 Guideline 5.1.1(v) 游客可先购

@Test func chanlunGateRequiresMembershipBeforeLoginAndAllowsGuestPurchase() {
    // 游客未订阅：直接弹 Paywall（允许不注册先订阅，符合 Guideline 5.1.1(v)）
    #expect(
        MembershipGate.evaluateChanlunAccess(
            hasChanlunConfig: true,
            isMemberActive: false,
            isSignedIn: false
        ) == .openPaywall
    )

    // 已登录但未订阅：拦截并弹 Paywall
    #expect(
        MembershipGate.evaluateChanlunAccess(
            hasChanlunConfig: true,
            isMemberActive: false,
            isSignedIn: true
        ) == .openPaywall
    )

    // 游客购买解锁后：按既有逻辑先弹登录会话
    #expect(
        MembershipGate.evaluateChanlunAccess(
            hasChanlunConfig: true,
            isMemberActive: true,
            isSignedIn: false
        ) == .openLogin
    )

    // 已订阅且已登录：直接进入禅观
    #expect(
        MembershipGate.evaluateChanlunAccess(
            hasChanlunConfig: true,
            isMemberActive: true,
            isSignedIn: true
        ) == .openChanlun
    )

    // 配置不可用时安全跳过
    #expect(
        MembershipGate.evaluateChanlunAccess(
            hasChanlunConfig: false,
            isMemberActive: true,
            isSignedIn: true
        ) == .unavailable
    )
}

// MARK: - 3. 购买成功解锁并自动衔接禅观

@MainActor
@Test func purchaseYearlyUnlocksEntitlementAndAdvancesChanlunGate() async throws {
    let now = Date(timeIntervalSince1970: 1_795_334_400) // 2026-11-22
    let expiration = now.addingTimeInterval(365 * 24 * 3600)
    let client = MockMembershipStoreKitClient()

    let purchasedRecord = MembershipTransactionRecord(
        transactionID: 1001,
        productID: MembershipPlan.yearly.rawValue,
        purchaseDate: now,
        expirationDate: expiration,
        willAutoRenew: true,
        isSandbox: true
    )

    await client.setPurchaseHandler { productID in
        #expect(productID == MembershipPlan.yearly.rawValue)
        await client.setEntitlements([purchasedRecord])
        return .purchased(purchasedRecord)
    }

    let store = MembershipStore(client: client, now: { now })
    await store.loadProducts()
    #expect(!store.isActive)
    #expect(
        MembershipGate.evaluateChanlunAccess(
            hasChanlunConfig: true,
            isMemberActive: store.isActive,
            isSignedIn: true
        ) == .openPaywall
    )
    #expect(store.ctaTitle(for: .yearly) == "立即订阅 · ¥99/年")

    let unlocked = await store.purchase(plan: .yearly)
    #expect(unlocked)
    #expect(store.isActive)
    #expect(store.entitlement.activeProductID == MembershipPlan.yearly.rawValue)
    #expect(store.entitlement.planTitle == "年度会员")
    #expect(store.entitlement.expirationDate == expiration)
    #expect(store.entitlement.willAutoRenew)
    #expect(store.entitlement.isSandbox)
    #expect(store.errorMessage == nil)
    #expect(store.statusMessage == MembershipCopy.purchaseSucceededNotice)

    // 订阅成功后，门禁自动从 openPaywall 切换为 openChanlun（已登录）或 openLogin（游客）
    #expect(
        MembershipGate.evaluateChanlunAccess(
            hasChanlunConfig: true,
            isMemberActive: store.isActive,
            isSignedIn: true
        ) == .openChanlun
    )
    #expect(
        MembershipGate.evaluateChanlunAccess(
            hasChanlunConfig: true,
            isMemberActive: store.isActive,
            isSignedIn: false
        ) == .openLogin
    )
}

// MARK: - 4. 用户取消、待家长批准、未验证与网络异常处理

@MainActor
@Test func purchaseHandlesCancellationPendingUnverifiedAndNetworkFailure() async {
    let client = MockMembershipStoreKitClient()
    let store = MembershipStore(client: client)

    // 4.1 用户取消：不报错、不激活
    await client.setPurchaseHandler { _ in .userCancelled }
    let cancelled = await store.purchase(plan: .yearly)
    #expect(!cancelled)
    #expect(!store.isActive)
    #expect(!store.isPurchasing)
    #expect(store.errorMessage == nil)
    #expect(store.statusMessage == nil)

    // 4.2 家长批准（pending）：给出明确提示、不激活
    await client.setPurchaseHandler { _ in .pending }
    let pending = await store.purchase(plan: .monthly)
    #expect(!pending)
    #expect(!store.isActive)
    #expect(store.statusMessage == MembershipCopy.pendingPurchaseNotice)
    #expect(store.errorMessage == nil)

    // 4.3 交易凭证未通过验证：拒绝激活并展示错误
    await client.setPurchaseHandler { _ in .unverified("签名校验未通过") }
    let unverified = await store.purchase(plan: .yearly)
    #expect(!unverified)
    #expect(!store.isActive)
    #expect(store.errorMessage == "签名校验未通过")

    // 4.4 网络异常：展示可读提示、状态复位
    await client.setPurchaseHandler { _ in
        throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
    }
    let failed = await store.purchase(plan: .yearly)
    #expect(!failed)
    #expect(!store.isActive)
    #expect(!store.isPurchasing)
    #expect(store.errorMessage?.contains("网络") == true)
}

// MARK: - 5. 恢复购买（成功、无订阅、网络失败）与商品加载降级

@MainActor
@Test func restorePurchasesSyncsAndHandlesEmptyAndErrors() async {
    let now = Date(timeIntervalSince1970: 1_795_334_400)
    let client = MockMembershipStoreKitClient()
    let store = MembershipStore(client: client, now: { now })

    // 5.1 商品加载失败时平滑回退参考价并标记 productsLoadFailed
    await client.setProductsResult(.failure(MembershipStoreError.networkFailure("超时")))
    await store.loadProducts()
    #expect(store.productsLoadFailed)
    #expect(store.displayPrice(for: .yearly) == "¥99")
    #expect(store.displayPrice(for: .monthly) == "¥39")

    // 5.2 无有效订阅时恢复：给出清晰提示
    let emptyRestore = await store.restorePurchases()
    #expect(!emptyRestore)
    #expect(!store.isActive)
    #expect(store.statusMessage == MembershipCopy.restoreNotFoundNotice)
    #expect(await client.syncCallCount == 1)

    // 5.3 App Store 存在有效月卡时恢复：成功解锁
    let monthlyRecord = MembershipTransactionRecord(
        transactionID: 2001,
        productID: MembershipPlan.monthly.rawValue,
        purchaseDate: now.addingTimeInterval(-3600),
        expirationDate: now.addingTimeInterval(29 * 24 * 3600),
        willAutoRenew: true,
        isSandbox: false
    )
    await client.setEntitlements([monthlyRecord])
    let restored = await store.restorePurchases()
    #expect(restored)
    #expect(store.isActive)
    #expect(store.entitlement.activeProductID == MembershipPlan.monthly.rawValue)
    #expect(store.entitlement.planTitle == "月度会员")
    #expect(store.statusMessage == MembershipCopy.restoreSucceededNotice)

    // 5.4 syncAppStore 异常时给出可读错误
    await client.setSyncError(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
    let erroredRestore = await store.restorePurchases()
    #expect(!erroredRestore)
    #expect(!store.isRestoring)
    #expect(store.errorMessage?.contains("网络") == true)
}

// MARK: - 5.5 StoreKit 空商品目录 vs 真实网络/StoreKit 异常区分与前台 refresh 补拉

@MainActor
@Test func storeKitEmptyCatalogIsDistinguishedFromNetworkErrors() async {
    let client = MockMembershipStoreKitClient()
    let store = MembershipStore(client: client)

    // 1) Product.products(for:) 正常返回空数组 []：不得误报「请检查网络」
    await client.setProductsResult(.success([]))
    await store.loadProducts()
    #expect(store.productsLoadFailed)
    #expect(store.productsLoadFailureReason == .emptyCatalog)
    #expect(store.productsLoadNotice == "App Store 暂未返回订阅商品，请稍后重试。")
    #expect(store.productsLoadNotice?.contains("网络") == false)

    // 购买时因商品目录为空抛出 productUnavailable：同样明确提示，不误报网络
    await client.setPurchaseHandler { _ in
        throw MembershipStoreError.productUnavailable
    }
    let unavailablePurchase = await store.purchase(plan: .yearly)
    #expect(!unavailablePurchase)
    #expect(store.errorMessage == "App Store 暂未返回订阅商品，请稍后重试。")
    #expect(store.errorMessage?.contains("网络") == false)

    // 2) 真实网络异常：明确标记为 networkOrStoreError 并提示网络问题
    await client.setProductsResult(.failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)))
    await store.loadProducts()
    #expect(store.productsLoadFailed)
    if case .networkOrStoreError(let message) = store.productsLoadFailureReason {
        #expect(message.contains("网络"))
    } else {
        Issue.record("预期为 .networkOrStoreError，实际为 \(String(describing: store.productsLoadFailureReason))")
    }
    #expect(store.productsLoadNotice?.contains("网络") == true)

    // 3) 前台 refresh() 在商品为空时自动补拉；成功后清除失败原因；之后再次 refresh 不重复拉取商品
    let callsBeforeRecovery = await client.loadProductsCallCount
    await client.setProductsResult(.success([
        MembershipProductInfo(plan: .yearly),
        MembershipProductInfo(plan: .monthly)
    ]))
    await store.refresh()
    #expect(!store.productsLoadFailed)
    #expect(store.productsLoadFailureReason == nil)
    #expect(store.productsLoadNotice == nil)
    #expect(store.products.count == 2)
    #expect(await client.loadProductsCallCount == callsBeforeRecovery + 1)

    await store.refresh()
    #expect(await client.loadProductsCallCount == callsBeforeRecovery + 1)
}

// MARK: - 6. 过期、撤销交易自动降级与多订阅优先级裁决

@MainActor
@Test func entitlementResolutionDowngradesExpiredRevokedAndPrefersHigherTier() async {
    let now = Date(timeIntervalSince1970: 1_795_334_400)

    // 6.1 已过期交易不得生效
    let expiredYearly = MembershipTransactionRecord(
        transactionID: 1,
        productID: MembershipPlan.yearly.rawValue,
        purchaseDate: now.addingTimeInterval(-400 * 86_400),
        expirationDate: now.addingTimeInterval(-10)
    )
    #expect(!MembershipEntitlement.resolve(from: [expiredYearly], now: now).isActive)

    // 6.2 已撤销交易不得生效
    let revokedYearly = MembershipTransactionRecord(
        transactionID: 2,
        productID: MembershipPlan.yearly.rawValue,
        purchaseDate: now.addingTimeInterval(-86_400),
        expirationDate: now.addingTimeInterval(300 * 86_400),
        revocationDate: now.addingTimeInterval(-60)
    )
    #expect(!MembershipEntitlement.resolve(from: [revokedYearly], now: now).isActive)

    // 6.3 已升级替代的旧月卡不得生效
    let upgradedMonthly = MembershipTransactionRecord(
        transactionID: 3,
        productID: MembershipPlan.monthly.rawValue,
        purchaseDate: now.addingTimeInterval(-10 * 86_400),
        expirationDate: now.addingTimeInterval(20 * 86_400),
        isUpgraded: true
    )
    #expect(!MembershipEntitlement.resolve(from: [upgradedMonthly], now: now).isActive)

    // 6.4 同时存在有效月卡与年卡：优先取更高级方案（年卡）
    let activeMonthly = MembershipTransactionRecord(
        transactionID: 4,
        productID: MembershipPlan.monthly.rawValue,
        purchaseDate: now,
        expirationDate: now.addingTimeInterval(30 * 86_400)
    )
    let activeYearly = MembershipTransactionRecord(
        transactionID: 5,
        productID: MembershipPlan.yearly.rawValue,
        purchaseDate: now.addingTimeInterval(-5 * 86_400),
        expirationDate: now.addingTimeInterval(360 * 86_400),
        willAutoRenew: false
    )
    let resolved = MembershipEntitlement.resolve(from: [activeMonthly, activeYearly], now: now)
    #expect(resolved.isActive)
    #expect(resolved.activeProductID == MembershipPlan.yearly.rawValue)
    #expect(resolved.planTitle == "年度会员")
    #expect(!resolved.willAutoRenew)

    // 6.5 同为年卡存在两条记录时取较晚过期时间
    let laterYearly = MembershipTransactionRecord(
        transactionID: 6,
        productID: MembershipPlan.yearly.rawValue,
        purchaseDate: now,
        expirationDate: now.addingTimeInterval(720 * 86_400)
    )
    let resolvedLater = MembershipEntitlement.resolve(from: [activeYearly, laterYearly], now: now)
    #expect(resolvedLater.expirationDate == laterYearly.expirationDate)

    // 6.6 监听 Transaction.updates 收到撤销交易后实时自动降级为非激活态
    let client = MockMembershipStoreKitClient()
    await client.setEntitlements([activeYearly])
    let store = MembershipStore(client: client, now: { now })
    await store.start()
    #expect(store.isActive)

    let revokedUpdate = MembershipTransactionRecord(
        transactionID: activeYearly.transactionID,
        productID: activeYearly.productID,
        purchaseDate: activeYearly.purchaseDate,
        expirationDate: activeYearly.expirationDate,
        revocationDate: now
    )
    await client.setEntitlements([])
    await client.emitTransactionUpdate(revokedUpdate)
    for _ in 0..<20 where store.isActive {
        try? await Task.sleep(for: .milliseconds(25))
    }
    #expect(!store.isActive)
    await client.finishUpdates()
    store.stopObservingUpdates()
}

// MARK: - 7. Apple 3.1.2 合规链接、中性功能表述与零投资建议静态断言

@Test func membershipCopyContainsZeroInvestmentAdviceAndNeutralFeatureWording() {
    let forbiddenTerms: [String] = [
        "建议买入",
        "建议卖出",
        "抄底",
        "逃顶",
        "加仓",
        "减仓",
        "荐股",
        "稳赚",
        "保本收益",
        "理财推荐",
        "收益预测",
        "买点",
        "卖点",
        "喊单",
        "牛市",
        "熊市",
        "投资建议",
        "交易信号",
        "包赚",
        "高胜率"
    ]

    for text in MembershipCopy.allPromotionalAndUICopy {
        for forbidden in forbiddenTerms {
            #expect(!text.contains(forbidden), "会员文案「\(text)」不应包含合规禁用词「\(forbidden)」")
        }
    }

    // 所有会员/订阅对外文案必须采用中性功能表述，不含「禅观」或「Chanlun」
    let allMembershipPublicCopy = MembershipCopy.allPromotionalAndUICopy + [
        MembershipCopy.complianceDisclaimer,
        AccountProfileCopy.membershipTitle,
        AccountProfileCopy.membershipSubtitle,
        MembershipEntitlement.inactive.statusSummary(),
        MembershipEntitlement.inactive.renewalStatusDescription
    ]
    for text in allMembershipPublicCopy {
        #expect(!text.contains("禅观"), "会员对外文案「\(text)」不应包含「禅观」")
        #expect(!text.lowercased().contains("chanlun"), "会员对外文案「\(text)」不应包含「Chanlun」")
    }

    // Apple 3.1.2 必填审核链接与自动续期说明校验
    #expect(MembershipCopy.privacyPolicyURL.absoluteString == "https://oryjk.cn/sumly/privacy")
    #expect(MembershipCopy.termsOfUseURL.absoluteString == "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    #expect(MembershipCopy.autoRenewalDisclosure.contains("24 小时"))
    #expect(MembershipCopy.autoRenewalDisclosure.contains("Apple ID"))
    #expect(MembershipCopy.autoRenewalDisclosure.contains("订阅"))
    #expect(MembershipCopy.complianceDisclaimer.contains("不构成任何交易或投资建议"))
}

// MARK: - 8. 多态视觉核验渲染导出（未订阅 Paywall / 已订阅管理态 / 「我的」会员入口与禅观标）

@MainActor
@Test func renderMembershipPaywallAndAccountEntryVisualShowcase() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let expiration = try #require(calendar.date(from: DateComponents(year: 2027, month: 11, day: 22, hour: 12)))

    let inactiveStore = MembershipStore(
        client: MockMembershipStoreKitClient(),
        initialEntitlement: .inactive,
        initialProducts: [
            .yearly: MembershipProductInfo(plan: .yearly),
            .monthly: MembershipProductInfo(plan: .monthly)
        ]
    )

    let activeEntitlement = MembershipEntitlement(
        isActive: true,
        activeProductID: MembershipPlan.yearly.rawValue,
        planTitle: MembershipPlan.yearly.title,
        expirationDate: expiration,
        willAutoRenew: true,
        isSandbox: false
    )
    let activeStore = MembershipStore(
        client: MockMembershipStoreKitClient(),
        initialEntitlement: activeEntitlement,
        initialProducts: [
            .yearly: MembershipProductInfo(plan: .yearly),
            .monthly: MembershipProductInfo(plan: .monthly)
        ]
    )

    let guestSession = AuthSession(service: MockAccountRenderAuth(), store: MockAccountRenderStore())

    let showcase = VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
            Text("记金会员 StoreKit 2 · 多态视觉核验")
                .font(.title3.bold())
                .foregroundStyle(GoldTheme.text)
            Text("左：未订阅 Paywall（年卡默认选中 + 3.1.2 合规页脚） · 中：已订阅会员管理态 · 右：「我的」会员入口与禅观微标")
                .font(.caption)
                .foregroundStyle(GoldTheme.textSecondary)
        }

        HStack(alignment: .top, spacing: 18) {
            // 1. 未订阅 Paywall 弹窗（年卡选中）
            VStack(alignment: .leading, spacing: 8) {
                Text("1 · 未订阅 Paywall 弹窗（年卡默认选中）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.goldSoft)

                MembershipPaywallContent(
                    membership: inactiveStore,
                    selectedPlan: .constant(.yearly)
                )
                .frame(width: 393, height: 830)
                .clipShape(GoldTheme.cardShape)
                .overlay(
                    GoldTheme.cardShape.strokeBorder(GoldTheme.gold.opacity(0.28), lineWidth: 1)
                )
            }

            // 2. 已订阅会员管理态
            VStack(alignment: .leading, spacing: 8) {
                Text("2 · 已订阅会员管理态（年度会员生效）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.goldSoft)

                MembershipPaywallContent(
                    membership: activeStore,
                    selectedPlan: .constant(.yearly),
                    showsChanlunAction: true
                )
                .frame(width: 393, height: 830)
                .clipShape(GoldTheme.cardShape)
                .overlay(
                    GoldTheme.cardShape.strokeBorder(GoldTheme.gold.opacity(0.28), lineWidth: 1)
                )
            }

            // 3. 「我的」页面会员入口与禅观会员标（上：未开通完整页，下：已开通入口对照）
            VStack(alignment: .leading, spacing: 8) {
                Text("3 · 「我的」会员入口与禅观会员标")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.goldSoft)

                VStack(spacing: 12) {
                    AccountView(
                        session: guestSession,
                        membership: inactiveStore,
                        onOpenMembership: {},
                        onOpenChanlun: {},
                        onOpenOnboarding: {}
                    )
                    .frame(width: 393, height: 690)
                    .clipShape(GoldTheme.cardShape)
                    .overlay(
                        GoldTheme.cardShape.strokeBorder(GoldTheme.gold.opacity(0.28), lineWidth: 1)
                    )

                    // 底部附已开通态入口与首页禅观胶囊微标对比条
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            AccountRowIconBadge(systemName: "crown.fill", style: .gold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(AccountProfileCopy.membershipTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(GoldTheme.goldSoft)
                                Text(activeEntitlement.statusSummary())
                                    .font(.caption)
                                    .foregroundStyle(GoldTheme.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text(MembershipCopy.activeBadgeTitle)
                                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(GoldTheme.down)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(GoldTheme.down.opacity(0.14), in: GoldTheme.capsuleShape)
                            .overlay(
                                GoldTheme.capsuleShape.strokeBorder(GoldTheme.down.opacity(0.38), lineWidth: 0.8)
                            )
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
                        .overlay(
                            GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.gold.opacity(0.28), lineWidth: 1)
                        )

                        HStack(spacing: 8) {
                            Text("首页禅观胶囊")
                                .font(.caption2)
                                .foregroundStyle(GoldTheme.textSecondary)
                                .fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: 4)
                            HStack(spacing: 3.5) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.caption.weight(.semibold))
                                Text("禅观")
                                    .font(.caption.weight(.semibold))
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(GoldTheme.gold)
                            }
                            .foregroundStyle(GoldTheme.goldSoft)
                            .padding(.horizontal, 8.5)
                            .frame(height: 30)
                            .background(GoldTheme.card, in: GoldTheme.capsuleShape)
                            .overlay(
                                GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.32), lineWidth: 1)
                            )
                            .fixedSize(horizontal: true, vertical: false)
                            Text("未开通")
                                .font(.caption2)
                                .foregroundStyle(GoldTheme.textFaint)
                                .fixedSize(horizontal: true, vertical: false)

                            HStack(spacing: 3.5) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.caption.weight(.semibold))
                                Text("禅观")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(GoldTheme.goldSoft)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(GoldTheme.card, in: GoldTheme.capsuleShape)
                            .overlay(
                                GoldTheme.capsuleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1)
                            )
                            .fixedSize(horizontal: true, vertical: false)
                            Text("已开通")
                                .font(.caption2)
                                .foregroundStyle(GoldTheme.textFaint)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(GoldTheme.card, in: GoldTheme.subCardShape)
                        .overlay(
                            GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1)
                        )
                    }
                    .frame(width: 393)
                }
            }
        }
    }
    .padding(20)
    .background(GoldTheme.background)
    .preferredColorScheme(.dark)
    .tint(GoldTheme.gold)

    let controller = UIHostingController(rootView: showcase)
    controller.overrideUserInterfaceStyle = .dark
    let totalWidth: CGFloat = 393 * 3 + 18 * 2 + 20 * 2
    let fittedSize = controller.sizeThatFits(in: CGSize(width: totalWidth, height: CGFloat.greatestFiniteMagnitude))
    controller.view.bounds = CGRect(origin: .zero, size: fittedSize)
    controller.view.backgroundColor = UIColor(GoldTheme.background)
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()

    let format = UIGraphicsImageRendererFormat()
    format.scale = 2.0
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: fittedSize, format: format).image { _ in
        controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
    }

    #expect(image.size.width >= 1200)
    #expect(image.size.height >= 850)
    let data = try #require(image.pngData())
    #expect(data.count > 40_000)

    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sim_membership_paywall.png")
    try data.write(to: tempURL, options: .atomic)
    print("MEMBERSHIP_SHOWCASE_ARTIFACT: \(tempURL.path)")

    if let envPath = ProcessInfo.processInfo.environment["SUMLY_MEMBERSHIP_SHOWCASE_OUT"], !envPath.isEmpty {
        let envURL = URL(fileURLWithPath: envPath)
        try FileManager.default.createDirectory(at: envURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: envURL, options: .atomic)
    }
}

// MARK: - 9. App Store Connect 订阅审核单屏无 Alpha RGB 截图导出（1290×2796）

@MainActor
@Test func renderAppStoreSubscriptionReviewScreenshot() throws {
    let inactiveStore = MembershipStore(
        client: MockMembershipStoreKitClient(),
        initialEntitlement: .inactive,
        initialProducts: [
            .yearly: MembershipProductInfo(plan: .yearly),
            .monthly: MembershipProductInfo(plan: .monthly)
        ]
    )

    let logicalSize = CGSize(width: 430, height: 932)
    let reviewScreen = ZStack {
        GoldTheme.background
        VStack(spacing: 0) {
            Color.clear.frame(height: 54)
            MembershipPaywallContent(
                membership: inactiveStore,
                selectedPlan: .constant(.yearly)
            )
            Color.clear.frame(height: 34)
        }
    }
    .frame(width: logicalSize.width, height: logicalSize.height)
    .background(GoldTheme.background)
    .preferredColorScheme(.dark)
    .tint(GoldTheme.gold)

    let controller = UIHostingController(rootView: reviewScreen)
    controller.overrideUserInterfaceStyle = .dark
    controller.view.bounds = CGRect(origin: .zero, size: logicalSize)
    controller.view.backgroundColor = UIColor(GoldTheme.background)
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()

    let format = UIGraphicsImageRendererFormat()
    format.scale = 3.0
    format.opaque = true
    let rendered = UIGraphicsImageRenderer(size: logicalSize, format: format).image { _ in
        controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
    }

    let cgImage = try #require(rendered.cgImage)
    #expect(cgImage.width == 1290)
    #expect(cgImage.height == 2796)

    // 显式重绘为不带 Alpha 通道的 RGB 位图（noneSkipLast），确保符合 App Store Connect 审核截图无透明通道要求
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
    let rgbContext = try #require(
        CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: cgImage.width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )
    )
    rgbContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    let opaqueCGImage = try #require(rgbContext.makeImage())
    #expect(opaqueCGImage.alphaInfo == .noneSkipLast || opaqueCGImage.alphaInfo == .none)

    let pngData = NSMutableData()
    let destination = try #require(
        CGImageDestinationCreateWithData(pngData as CFMutableData, UTType.png.identifier as CFString, 1, nil)
    )
    CGImageDestinationAddImage(destination, opaqueCGImage, nil)
    #expect(CGImageDestinationFinalize(destination))
    #expect(pngData.length > 50_000)

    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("asc_sub_review_paywall.png")
    try (pngData as Data).write(to: tempURL, options: .atomic)
    print("ASC_SUB_REVIEW_ARTIFACT: \(tempURL.path)")
}
