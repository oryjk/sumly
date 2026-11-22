import Foundation
import OSLog
import StoreKit

private let membershipLogger = Logger(subsystem: "com.oryjk.sumly", category: "Membership")

// MARK: - 1. 订阅错误与诊断状态定义

enum MembershipProductsLoadFailureReason: Equatable, Sendable {
    case emptyCatalog
    case networkOrStoreError(String)
}

enum MembershipStoreError: LocalizedError, Equatable, Sendable {
    case productUnavailable
    case verificationFailed(String)
    case networkFailure(String)

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            "App Store 暂未返回订阅商品，请稍后重试。"
        case .verificationFailed(let detail):
            detail.isEmpty ? "无法验证本次购买凭证，请稍后重试或点击恢复购买。" : detail
        case .networkFailure(let detail):
            detail.isEmpty ? "连接 App Store 失败，请检查网络连接后重试。" : detail
        }
    }
}

// MARK: - 2. 可注入的轻量 StoreKit 2 服务协议（便于离线单测全覆盖）

protocol MembershipStoreKitClient: Sendable {
    func loadProducts(for productIDs: [String]) async throws -> [MembershipProductInfo]
    func currentEntitlements() async -> [MembershipTransactionRecord]
    func purchase(productID: String) async throws -> MembershipPurchaseOutcome
    func syncAppStore() async throws
    func observeTransactionUpdates() -> AsyncStream<MembershipTransactionRecord>
}

// MARK: - 3. 真实 StoreKit 2 客户端实现（Swift 6 严格并发安全）

private actor StoreKitProductCache {
    private var storage: [String: Product] = [:]

    func store(_ products: [Product]) {
        for product in products {
            storage[product.id] = product
        }
    }

    func product(for id: String) -> Product? {
        storage[id]
    }
}

final class LiveStoreKitMembershipClient: MembershipStoreKitClient, Sendable {
    private let cache = StoreKitProductCache()

    func loadProducts(for productIDs: [String]) async throws -> [MembershipProductInfo] {
        let storefrontCountry = await Storefront.current?.countryCode ?? "unknown"
        let canMakePayments = AppStore.canMakePayments
        let requestedList = productIDs.joined(separator: ",")
        membershipLogger.info(
            "StoreKit loadProducts requested: ids=\(requestedList, privacy: .public), storefront=\(storefrontCountry, privacy: .public), canMakePayments=\(canMakePayments, privacy: .public)"
        )

        do {
            let storeProducts = try await Product.products(for: productIDs)
            await cache.store(storeProducts)
            if storeProducts.isEmpty {
                membershipLogger.warning(
                    "StoreKit loadProducts returned empty catalog: requestedIDs=\(requestedList, privacy: .public), count=0, storefront=\(storefrontCountry, privacy: .public), canMakePayments=\(canMakePayments, privacy: .public)"
                )
            } else {
                let returnedList = storeProducts.map(\.id).joined(separator: ",")
                membershipLogger.info(
                    "StoreKit loadProducts succeeded: count=\(storeProducts.count, privacy: .public), returnedIDs=\(returnedList, privacy: .public), storefront=\(storefrontCountry, privacy: .public), canMakePayments=\(canMakePayments, privacy: .public)"
                )
            }
            return storeProducts
                .compactMap(Self.makeProductInfo(from:))
                .sorted { $0.plan.tierRank > $1.plan.tierRank }
        } catch {
            let nsError = error as NSError
            membershipLogger.error(
                "StoreKit loadProducts failed: requestedIDs=\(requestedList, privacy: .public), storefront=\(storefrontCountry, privacy: .public), canMakePayments=\(canMakePayments, privacy: .public), domain=\(nsError.domain, privacy: .public), code=\(nsError.code, privacy: .public), detail=\(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }

    func currentEntitlements() async -> [MembershipTransactionRecord] {
        var records: [MembershipTransactionRecord] = []
        for await verificationResult in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = verificationResult else { continue }
            guard MembershipPlan(rawValue: transaction.productID) != nil else { continue }
            let record = await Self.makeTransactionRecord(from: transaction)
            records.append(record)
        }
        return records
    }

    func purchase(productID: String) async throws -> MembershipPurchaseOutcome {
        let product: Product
        if let cached = await cache.product(for: productID) {
            product = cached
        } else {
            let storefrontCountry = await Storefront.current?.countryCode ?? "unknown"
            let canMakePayments = AppStore.canMakePayments
            membershipLogger.info(
                "StoreKit purchase cache miss, fetching product: id=\(productID, privacy: .public), storefront=\(storefrontCountry, privacy: .public), canMakePayments=\(canMakePayments, privacy: .public)"
            )
            let fetched: [Product]
            do {
                fetched = try await Product.products(for: [productID])
            } catch {
                let nsError = error as NSError
                membershipLogger.error(
                    "StoreKit purchase product fetch failed: id=\(productID, privacy: .public), storefront=\(storefrontCountry, privacy: .public), canMakePayments=\(canMakePayments, privacy: .public), domain=\(nsError.domain, privacy: .public), code=\(nsError.code, privacy: .public), detail=\(String(describing: error), privacy: .public)"
                )
                throw error
            }
            await cache.store(fetched)
            guard let matched = fetched.first(where: { $0.id == productID }) else {
                membershipLogger.warning(
                    "StoreKit purchase product fetch returned empty/missing product: id=\(productID, privacy: .public), returnedCount=\(fetched.count, privacy: .public), storefront=\(storefrontCountry, privacy: .public), canMakePayments=\(canMakePayments, privacy: .public)"
                )
                throw MembershipStoreError.productUnavailable
            }
            product = matched
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verificationResult):
            switch verificationResult {
            case .verified(let transaction):
                let record = await Self.makeTransactionRecord(from: transaction)
                await transaction.finish()
                return .purchased(record)
            case .unverified(_, let error):
                membershipLogger.error(
                    "StoreKit purchase transaction unverified: id=\(productID, privacy: .public), detail=\(String(describing: error), privacy: .public)"
                )
                return .unverified(error.localizedDescription)
            }
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .unverified("无法识别的购买状态，请稍后重试。")
        }
    }

    func syncAppStore() async throws {
        do {
            try await AppStore.sync()
        } catch {
            let nsError = error as NSError
            let storefrontCountry = await Storefront.current?.countryCode ?? "unknown"
            membershipLogger.error(
                "StoreKit AppStore.sync failed: storefront=\(storefrontCountry, privacy: .public), domain=\(nsError.domain, privacy: .public), code=\(nsError.code, privacy: .public), detail=\(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }

    func observeTransactionUpdates() -> AsyncStream<MembershipTransactionRecord> {
        AsyncStream { continuation in
            let task = Task {
                for await verificationResult in StoreKit.Transaction.updates {
                    guard !Task.isCancelled else { break }
                    guard case .verified(let transaction) = verificationResult else { continue }
                    if MembershipPlan(rawValue: transaction.productID) != nil {
                        let record = await Self.makeTransactionRecord(from: transaction)
                        await transaction.finish()
                        continuation.yield(record)
                    } else {
                        await transaction.finish()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func makeProductInfo(from product: Product) -> MembershipProductInfo? {
        guard let plan = MembershipPlan(rawValue: product.id) else { return nil }
        let periodText: String = {
            guard let period = product.subscription?.subscriptionPeriod else {
                return plan.periodLabel
            }
            switch period.unit {
            case .year:
                return period.value == 1 ? "1 年" : "\(period.value) 年"
            case .month:
                return period.value == 1 ? "1 个月" : "\(period.value) 个月"
            case .week:
                return period.value == 1 ? "1 周" : "\(period.value) 周"
            case .day:
                return period.value == 1 ? "1 天" : "\(period.value) 天"
            @unknown default:
                return plan.periodLabel
            }
        }()

        return MembershipProductInfo(
            plan: plan,
            displayName: product.displayName.isEmpty ? plan.title : product.displayName,
            description: product.description.isEmpty ? plan.subtitle : product.description,
            price: product.price,
            displayPrice: product.displayPrice,
            currencyCode: product.priceFormatStyle.currencyCode,
            subscriptionPeriodDescription: periodText
        )
    }

    private static func makeTransactionRecord(from transaction: StoreKit.Transaction) async -> MembershipTransactionRecord {
        var willAutoRenew = true
        if let status = await transaction.subscriptionStatus,
           case .verified(let renewalInfo) = status.renewalInfo {
            willAutoRenew = renewalInfo.willAutoRenew
        }
        return MembershipTransactionRecord(
            transactionID: transaction.id,
            originalTransactionID: transaction.originalID,
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            isUpgraded: transaction.isUpgraded,
            willAutoRenew: willAutoRenew,
            isSandbox: transaction.environment != .production
        )
    }
}

// MARK: - 4. StoreKit 2 订阅状态容器（@MainActor @Observable）

@MainActor
@Observable
final class MembershipStore {
    private let client: any MembershipStoreKitClient
    private let nowProvider: @Sendable () -> Date

    private(set) var products: [MembershipPlan: MembershipProductInfo] = [:]
    private(set) var entitlement: MembershipEntitlement = .inactive
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var productsLoadFailed = false
    private(set) var productsLoadFailureReason: MembershipProductsLoadFailureReason?

    var statusMessage: String?
    var errorMessage: String?

    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(
        client: any MembershipStoreKitClient = LiveStoreKitMembershipClient(),
        now: @escaping @Sendable () -> Date = { .now },
        initialEntitlement: MembershipEntitlement = .inactive,
        initialProducts: [MembershipPlan: MembershipProductInfo] = [:]
    ) {
        self.client = client
        self.nowProvider = now
        self.entitlement = initialEntitlement
        self.products = initialProducts
    }

    var isActive: Bool {
        entitlement.isActive
    }

    /// 获取方案展示价格，优先读取 App Store 动态价格，未加载完成时平滑回退参考价。
    func displayPrice(for plan: MembershipPlan) -> String {
        products[plan]?.displayPrice ?? plan.fallbackDisplayPrice
    }

    /// 获取方案周期描述。
    func periodLabel(for plan: MembershipPlan) -> String {
        products[plan]?.subscriptionPeriodDescription ?? plan.periodLabel
    }

    /// 年卡相比月卡节省比例（优先基于已加载的 StoreKit 动态价格计算）。
    func yearlySavingsPercent() -> Int {
        let yearlyPrice = products[.yearly]?.price ?? MembershipPlan.yearly.fallbackPrice
        let monthlyPrice = products[.monthly]?.price ?? MembershipPlan.monthly.fallbackPrice
        return MembershipPricing.yearlySavingsPercent(yearlyPrice: yearlyPrice, monthlyPrice: monthlyPrice)
    }

    /// 年卡折合月均文案（月卡返回 nil）。
    func monthlyEquivalentText(for plan: MembershipPlan) -> String? {
        guard plan == .yearly else { return nil }
        if let info = products[.yearly] {
            return MembershipPricing.monthlyEquivalentText(
                yearlyPrice: info.price,
                currencyCode: info.currencyCode
            )
        }
        return plan.fallbackMonthlyEquivalentText
    }

    /// 主 CTA 按钮标题，如 `"立即订阅 · ¥99/年"`。
    func ctaTitle(for plan: MembershipPlan) -> String {
        "立即订阅 · \(displayPrice(for: plan))/\(plan.billingUnit)"
    }

    /// 「我的」入口未开通态胶囊文案，如 `"¥99/年起"`。
    var entryPriceBadgeText: String {
        "\(displayPrice(for: .yearly))/年起"
    }

    /// 商品拉取异常时的面向用户提示（明确区分空目录返回与网络/StoreKit 异常，不含内部敏感信息）。
    var productsLoadNotice: String? {
        guard productsLoadFailed, products.isEmpty else { return nil }
        switch productsLoadFailureReason {
        case .emptyCatalog:
            return MembershipStoreError.productUnavailable.errorDescription
        case .networkOrStoreError(let message):
            return message
        case nil:
            return nil
        }
    }

    /// 启动订阅引擎：监听 Transaction.updates，同时拉取商品并刷新当前有效权益。
    func start() async {
        if !hasStarted {
            hasStarted = true
            startObservingUpdates()
        }
        async let productsTask: Void = loadProducts()
        async let entitlementsTask: Void = refreshEntitlements()
        _ = await (productsTask, entitlementsTask)
    }

    /// 前台激活或手动刷新：刷新有效权益，若尚未拉取到 App Store 商品则一并补拉。
    func refresh() async {
        if products.isEmpty {
            async let productsTask: Void = loadProducts()
            async let entitlementsTask: Void = refreshEntitlements()
            _ = await (productsTask, entitlementsTask)
        } else {
            await refreshEntitlements()
        }
    }

    func stopObservingUpdates() {
        updatesTask?.cancel()
        updatesTask = nil
        hasStarted = false
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let loaded = try await client.loadProducts(for: MembershipPlan.productIDs)
            if loaded.isEmpty {
                let fallbackOnly = products.isEmpty
                productsLoadFailed = fallbackOnly
                productsLoadFailureReason = fallbackOnly ? .emptyCatalog : nil
                membershipLogger.warning(
                    "MembershipStore loadProducts empty: requestedIDs=\(MembershipPlan.productIDs.joined(separator: ","), privacy: .public), fallbackOnly=\(fallbackOnly, privacy: .public)"
                )
            } else {
                var mapped = products
                for item in loaded {
                    mapped[item.plan] = item
                }
                products = mapped
                productsLoadFailed = false
                productsLoadFailureReason = nil
            }
        } catch {
            let readable = Self.readableErrorMessage(for: error)
            let fallbackOnly = products.isEmpty
            productsLoadFailed = fallbackOnly
            productsLoadFailureReason = fallbackOnly ? .networkOrStoreError(readable) : nil
            let nsError = error as NSError
            membershipLogger.error(
                "MembershipStore loadProducts threw error: domain=\(nsError.domain, privacy: .public), code=\(nsError.code, privacy: .public), detail=\(String(describing: error), privacy: .public)"
            )
        }
    }

    func refreshEntitlements() async {
        let records = await client.currentEntitlements()
        entitlement = MembershipEntitlement.resolve(from: records, now: nowProvider())
    }

    /// 发起购买；遵循 Guideline 5.1.1(v)，不要求先注册或登录账号即可直接完成 StoreKit 2 购买。
    @discardableResult
    func purchase(plan: MembershipPlan) async -> Bool {
        guard !isPurchasing, !isRestoring else { return false }
        isPurchasing = true
        statusMessage = nil
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            let outcome = try await client.purchase(productID: plan.rawValue)
            switch outcome {
            case .purchased(let record):
                let currentRecords = await client.currentEntitlements()
                let merged = Self.merge(records: currentRecords, latest: record)
                entitlement = MembershipEntitlement.resolve(from: merged, now: nowProvider())
                if entitlement.isActive {
                    statusMessage = MembershipCopy.purchaseSucceededNotice
                    return true
                } else {
                    errorMessage = "该订阅已失效或被撤销，请确认购买状态后重试。"
                    return false
                }
            case .userCancelled:
                return false
            case .pending:
                statusMessage = MembershipCopy.pendingPurchaseNotice
                return false
            case .unverified(let detail):
                errorMessage = MembershipStoreError.verificationFailed(detail).localizedDescription
                return false
            }
        } catch {
            let nsError = error as NSError
            membershipLogger.error(
                "MembershipStore purchase failed: plan=\(plan.rawValue, privacy: .public), domain=\(nsError.domain, privacy: .public), code=\(nsError.code, privacy: .public), detail=\(String(describing: error), privacy: .public)"
            )
            errorMessage = Self.readableErrorMessage(for: error)
            return false
        }
    }

    /// 恢复历史购买（AppStore.sync + 实时重算有效权益）。
    @discardableResult
    func restorePurchases() async -> Bool {
        guard !isPurchasing, !isRestoring else { return false }
        isRestoring = true
        statusMessage = nil
        errorMessage = nil
        defer { isRestoring = false }

        do {
            try await client.syncAppStore()
            await refreshEntitlements()
            if entitlement.isActive {
                statusMessage = MembershipCopy.restoreSucceededNotice
                return true
            } else {
                statusMessage = MembershipCopy.restoreNotFoundNotice
                return false
            }
        } catch {
            let nsError = error as NSError
            membershipLogger.error(
                "MembershipStore restorePurchases failed: domain=\(nsError.domain, privacy: .public), code=\(nsError.code, privacy: .public), detail=\(String(describing: error), privacy: .public)"
            )
            errorMessage = Self.readableErrorMessage(for: error)
            return false
        }
    }

    func clearFeedback() {
        statusMessage = nil
        errorMessage = nil
    }

    // MARK: - Private Helpers

    private func startObservingUpdates() {
        updatesTask?.cancel()
        let stream = client.observeTransactionUpdates()
        updatesTask = Task { @MainActor [weak self] in
            for await updatedRecord in stream {
                guard !Task.isCancelled, let self else { break }
                let currentRecords = await self.client.currentEntitlements()
                let merged = Self.merge(records: currentRecords, latest: updatedRecord)
                self.entitlement = MembershipEntitlement.resolve(from: merged, now: self.nowProvider())
            }
        }
    }

    private static func merge(
        records: [MembershipTransactionRecord],
        latest: MembershipTransactionRecord
    ) -> [MembershipTransactionRecord] {
        var result = records.filter { $0.transactionID != latest.transactionID }
        result.append(latest)
        return result
    }

    static func readableErrorMessage(for error: any Error) -> String {
        if let storeError = error as? MembershipStoreError, let description = storeError.errorDescription {
            return description
        }
        if let skError = error as? StoreKitError {
            switch skError {
            case .networkError:
                return "网络连接不稳定，暂时无法连接 App Store，请稍后重试。"
            case .notAvailableInStorefront:
                return "当前 App Store 地区暂不支持该订阅商品。"
            default:
                break
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "网络连接不稳定，暂时无法连接 App Store，请稍后重试。"
        }
        let localized = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return localized.isEmpty ? "连接 App Store 失败，请稍后重试。" : localized
    }
}
