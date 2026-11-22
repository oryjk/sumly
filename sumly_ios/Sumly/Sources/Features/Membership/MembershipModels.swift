import Foundation

// MARK: - 1. 订阅方案定义（严格对齐 App Store Connect 商品 ID）

enum MembershipPlan: String, CaseIterable, Identifiable, Codable, Sendable {
    case yearly = "com.oryjk.sumly.membership.yearly"
    case monthly = "com.oryjk.sumly.membership.monthly"

    var id: String { rawValue }

    static let defaultSelection: MembershipPlan = .yearly

    static var productIDs: [String] {
        allCases.map(\.rawValue)
    }

    /// 方案优先级：同时存在有效年卡与月卡时优先展示更高级方案。
    var tierRank: Int {
        switch self {
        case .yearly: 2
        case .monthly: 1
        }
    }

    var title: String {
        switch self {
        case .yearly: "年度会员"
        case .monthly: "月度会员"
        }
    }

    var shortTitle: String {
        switch self {
        case .yearly: "年卡"
        case .monthly: "月卡"
        }
    }

    var periodLabel: String {
        switch self {
        case .yearly: "1 年"
        case .monthly: "1 个月"
        }
    }

    var billingUnit: String {
        switch self {
        case .yearly: "年"
        case .monthly: "月"
        }
    }

    var subtitle: String {
        switch self {
        case .yearly: "一次订阅全年畅享，性价比之选"
        case .monthly: "按月灵活订阅，随时可取消"
        }
    }

    /// App Store 价格尚未返回时的默认参考价（CNY）。
    var fallbackPrice: Decimal {
        switch self {
        case .yearly: Decimal(99)
        case .monthly: Decimal(39)
        }
    }

    var fallbackDisplayPrice: String {
        switch self {
        case .yearly: "¥99"
        case .monthly: "¥39"
        }
    }

    var fallbackMonthlyEquivalentText: String? {
        switch self {
        case .yearly: "折合 ¥8.25/月"
        case .monthly: nil
        }
    }

    /// 默认年卡相比 12 个月月卡的省钱百分比（(39 * 12 - 99) / (39 * 12) = 78.85% -> 79%）。
    static let defaultYearlySavingsPercent = 79
}

// MARK: - 2. 价格与省钱比例纯逻辑

enum MembershipPricing {
    /// 计算年卡相比 12 个月月卡节省的整数百分比（四舍五入，范围 0...99）。
    static func yearlySavingsPercent(yearlyPrice: Decimal, monthlyPrice: Decimal) -> Int {
        let yearlyDouble = NSDecimalNumber(decimal: yearlyPrice).doubleValue
        let monthlyDouble = NSDecimalNumber(decimal: monthlyPrice).doubleValue
        guard yearlyDouble.isFinite, monthlyDouble.isFinite, yearlyDouble > 0, monthlyDouble > 0 else {
            return MembershipPlan.defaultYearlySavingsPercent
        }
        let twelveMonths = monthlyDouble * 12.0
        guard twelveMonths > yearlyDouble else { return 0 }
        let ratio = (twelveMonths - yearlyDouble) / twelveMonths * 100.0
        return min(99, max(0, Int(ratio.rounded())))
    }

    /// 将年卡价格折算为月均展示文案（如 `"折合 ¥8.25/月"`）。
    static func monthlyEquivalentText(
        yearlyPrice: Decimal,
        currencyCode: String? = "CNY",
        locale: Locale = Locale(identifier: "zh_CN")
    ) -> String {
        let yearlyDouble = NSDecimalNumber(decimal: yearlyPrice).doubleValue
        guard yearlyDouble.isFinite, yearlyDouble > 0 else {
            return MembershipPlan.yearly.fallbackMonthlyEquivalentText ?? "折合 ¥8.25/月"
        }
        let monthly = yearlyDouble / 12.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currencyCode ?? "CNY"
        if (currencyCode ?? "CNY").uppercased() == "CNY" {
            formatter.currencySymbol = "¥"
        }
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: NSNumber(value: monthly))
            ?? String(format: "¥%.2f", monthly)
        return "折合 \(formatted)/月"
    }

    /// 推荐徽章文案（如 `"推荐 · 省 79%"`）。
    static func yearlyBadgeText(savingsPercent: Int) -> String {
        if savingsPercent > 0 {
            return "推荐 · 省 \(savingsPercent)%"
        }
        return "推荐方案"
    }
}

// MARK: - 3. StoreKit 商品与交易快照模型（解耦 StoreKit 原生类型，便于离线单测）

struct MembershipProductInfo: Equatable, Sendable {
    let id: String
    let plan: MembershipPlan
    let displayName: String
    let description: String
    let price: Decimal
    let displayPrice: String
    let currencyCode: String?
    let subscriptionPeriodDescription: String

    init(
        plan: MembershipPlan,
        displayName: String? = nil,
        description: String? = nil,
        price: Decimal? = nil,
        displayPrice: String? = nil,
        currencyCode: String? = "CNY",
        subscriptionPeriodDescription: String? = nil
    ) {
        self.id = plan.rawValue
        self.plan = plan
        self.displayName = displayName ?? plan.title
        self.description = description ?? plan.subtitle
        self.price = price ?? plan.fallbackPrice
        self.displayPrice = displayPrice ?? plan.fallbackDisplayPrice
        self.currencyCode = currencyCode
        self.subscriptionPeriodDescription = subscriptionPeriodDescription ?? plan.periodLabel
    }
}

struct MembershipTransactionRecord: Equatable, Sendable {
    let transactionID: UInt64
    let originalTransactionID: UInt64
    let productID: String
    let purchaseDate: Date
    let expirationDate: Date?
    let revocationDate: Date?
    let isUpgraded: Bool
    let willAutoRenew: Bool
    let isSandbox: Bool

    init(
        transactionID: UInt64,
        originalTransactionID: UInt64? = nil,
        productID: String,
        purchaseDate: Date,
        expirationDate: Date?,
        revocationDate: Date? = nil,
        isUpgraded: Bool = false,
        willAutoRenew: Bool = true,
        isSandbox: Bool = false
    ) {
        self.transactionID = transactionID
        self.originalTransactionID = originalTransactionID ?? transactionID
        self.productID = productID
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.isUpgraded = isUpgraded
        self.willAutoRenew = willAutoRenew
        self.isSandbox = isSandbox
    }

    var plan: MembershipPlan? {
        MembershipPlan(rawValue: productID)
    }

    func isValid(at now: Date) -> Bool {
        guard plan != nil else { return false }
        guard revocationDate == nil, !isUpgraded else { return false }
        if let expirationDate, expirationDate <= now {
            return false
        }
        return true
    }
}

enum MembershipPurchaseOutcome: Equatable, Sendable {
    case purchased(MembershipTransactionRecord)
    case userCancelled
    case pending
    case unverified(String)
}

// MARK: - 4. 当前有效会员权益状态

struct MembershipEntitlement: Equatable, Sendable {
    let isActive: Bool
    let activeProductID: String?
    let planTitle: String?
    let expirationDate: Date?
    let willAutoRenew: Bool
    let isSandbox: Bool

    static let inactive = MembershipEntitlement(
        isActive: false,
        activeProductID: nil,
        planTitle: nil,
        expirationDate: nil,
        willAutoRenew: false,
        isSandbox: false
    )

    var activePlan: MembershipPlan? {
        activeProductID.flatMap(MembershipPlan.init(rawValue:))
    }

    /// 格式化到期日期（中文年月日，例如 `2027年11月22日`）。
    func formattedExpirationDate(
        locale: Locale = Locale(identifier: "zh_CN"),
        timeZone: TimeZone = .current
    ) -> String? {
        guard let expirationDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: expirationDate)
    }

    /// 供「我的」行副标题与管理页展示的简洁状态摘要。
    func statusSummary(
        locale: Locale = Locale(identifier: "zh_CN"),
        timeZone: TimeZone = .current
    ) -> String {
        guard isActive else {
            return MembershipCopy.accountInactiveSubtitle
        }
        let title = planTitle ?? MembershipCopy.title
        if let dateText = formattedExpirationDate(locale: locale, timeZone: timeZone) {
            return "\(title) · 有效期至 \(dateText)"
        }
        return "\(title) · 已生效"
    }

    var renewalStatusDescription: String {
        guard isActive else { return "尚未开通自动续期订阅" }
        return willAutoRenew ? "到期将自动续费，可在系统订阅设置中随时取消" : "已关闭自动续费，到期后自动失效"
    }

    /// 从一组 StoreKit 2 交易快照中实时计算当前有效会员权益：
    /// - 过滤未知商品、已撤销、已升级替代、已过期的交易；
    /// - 若同时存在有效年卡与月卡，优先取更高级方案（年卡 > 月卡），同级优先取较晚过期时间。
    static func resolve(
        from records: [MembershipTransactionRecord],
        now: Date = .now
    ) -> MembershipEntitlement {
        let validRecords = records.filter { $0.isValid(at: now) }
        guard let best = validRecords.max(by: { lhs, rhs in
            let lhsRank = lhs.plan?.tierRank ?? 0
            let rhsRank = rhs.plan?.tierRank ?? 0
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            let lhsExp = lhs.expirationDate ?? .distantFuture
            let rhsExp = rhs.expirationDate ?? .distantFuture
            if lhsExp != rhsExp {
                return lhsExp < rhsExp
            }
            return lhs.purchaseDate < rhs.purchaseDate
        }), let plan = best.plan else {
            return .inactive
        }

        return MembershipEntitlement(
            isActive: true,
            activeProductID: best.productID,
            planTitle: plan.title,
            expirationDate: best.expirationDate,
            willAutoRenew: best.willAutoRenew,
            isSandbox: best.isSandbox
        )
    }
}

// MARK: - 5. 「禅观」权限门禁纯逻辑（遵循 Guideline 5.1.1(v)）

enum MembershipGateDecision: Equatable, Sendable {
    case unavailable
    case openPaywall
    case openLogin
    case openChanlun
}

enum MembershipGate {
    /// 评估点击「禅观」时的下一步跳转：
    /// 1. 禅观配置缺失 -> unavailable；
    /// 2. 远程开关要求会员订阅且未开通会员 -> 直接弹出 Paywall（允许游客无需注册先完成 StoreKit 2 订阅或恢复，符合 5.1.1(v)）；
    /// 3. 已放行（后台关闭付费门槛或已开通会员）但未登录 -> 按既有逻辑弹出登录页；
    /// 4. 已放行且已登录 -> 直接打开禅观页面。
    static func evaluateChanlunAccess(
        hasChanlunConfig: Bool,
        isMemberActive: Bool,
        isSignedIn: Bool,
        requiresMembership: Bool = true
    ) -> MembershipGateDecision {
        guard hasChanlunConfig else { return .unavailable }
        if requiresMembership && !isMemberActive {
            return .openPaywall
        }
        return isSignedIn ? .openChanlun : .openLogin
    }

    /// 首页胶囊皇冠标与「我的」页「会员专属」徽标仅在需要会员且当前未开通时显示。
    static func shouldShowChanlunLockBadge(
        requiresMembership: Bool,
        isMemberActive: Bool
    ) -> Bool {
        requiresMembership && !isMemberActive
    }

    /// 「我的」页「记金会员」入口：后台开启入口或用户已是有效会员时显示（确保老会员始终可查看有效期与管理订阅）。
    static func shouldShowMembershipEntry(
        entryVisible: Bool,
        isMemberActive: Bool
    ) -> Bool {
        entryVisible || isMemberActive
    }
}

// MARK: - 6. 客观合规文案与审核必备链接（单一数据源，供视图与合规测试共用）

struct MembershipBenefit: Identifiable, Equatable, Sendable {
    let id: String
    let iconSystemName: String
    let title: String
    let detail: String
}

enum MembershipCopy {
    static let title = "记金会员"
    static let subtitle = "解锁高阶多周期走势与复盘工具"
    static let activeMemberSubtitle = "您的会员权益已生效，可随时打开高阶多周期走势与复盘视图"
    static let activeBadgeTitle = "已开通"
    static let chanlunMemberBadge = "会员专属"
    static let accountInactiveSubtitle = "解锁高阶多周期走势与复盘工具"

    static let benefits: [MembershipBenefit] = [
        MembershipBenefit(
            id: "advanced-chart-access",
            iconSystemName: "chart.line.uptrend.xyaxis",
            title: "解锁高阶多周期走势与复盘视图",
            detail: "完整使用高阶走势页面查看行情结构与历史复盘记录"
        ),
        MembershipBenefit(
            id: "multi-timeframe",
            iconSystemName: "clock.arrow.circlepath",
            title: "支持多周期图表查看",
            detail: "自由切换不同时间周期图表，便于日常记录与历史对照"
        ),
        MembershipBenefit(
            id: "future-upgrades",
            iconSystemName: "sparkles",
            title: "持续获享后续会员专属工具升级",
            detail: "后续新增的高阶行情与个人数据整理工具将持续纳入会员权益"
        )
    ]

    static let autoRenewalDisclosure =
        "订阅将在当前周期结束前 24 小时自动续费，费用从您的 Apple ID 账户扣除；您可随时前往系统「设置 → Apple ID → 订阅」管理或取消订阅。"

    static let complianceDisclaimer =
        "会员工具仅提供行情数据查看与个人复盘记录，不构成任何交易或投资建议。"

    static let restoreButtonTitle = "恢复购买"
    static let privacyPolicyTitle = "隐私政策"
    static let termsOfUseTitle = "使用条款"
    static let manageSubscriptionsTitle = "管理订阅"
    static let openChanlunTitle = "打开高阶走势视图"
    static let retryLoadProductsTitle = "当前显示参考价 · 点击重新拉取 App Store 价格"
    static let purchasingStatusTitle = "正在连接 App Store…"
    static let restoringStatusTitle = "正在恢复购买…"
    static let pendingPurchaseNotice = "购买请求已提交，等待家长或家庭组织者批准后将自动生效。"
    static let restoreSucceededNotice = "已恢复您的记金会员权益。"
    static let restoreNotFoundNotice = "未找到可恢复的有效订阅，请确认当前设备已登录购买时使用的 Apple ID。"
    static let purchaseSucceededNotice = "订阅已生效，欢迎成为记金会员。"

    static let privacyPolicyURL = URL(string: "https://oryjk.cn/sumly/privacy")!
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let manageSubscriptionsFallbackURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    /// 面向用户的全部营销与界面文案（不含免责声明中的反向陈述），供零投资建议与中性化合规测试静态断言。
    static var allPromotionalAndUICopy: [String] {
        var items: [String] = [
            title,
            subtitle,
            activeMemberSubtitle,
            activeBadgeTitle,
            chanlunMemberBadge,
            accountInactiveSubtitle,
            autoRenewalDisclosure,
            restoreButtonTitle,
            privacyPolicyTitle,
            termsOfUseTitle,
            manageSubscriptionsTitle,
            openChanlunTitle,
            retryLoadProductsTitle,
            purchasingStatusTitle,
            restoringStatusTitle,
            pendingPurchaseNotice,
            restoreSucceededNotice,
            restoreNotFoundNotice,
            purchaseSucceededNotice
        ]
        for plan in MembershipPlan.allCases {
            items.append(plan.title)
            items.append(plan.shortTitle)
            items.append(plan.periodLabel)
            items.append(plan.subtitle)
            items.append(plan.fallbackDisplayPrice)
            if let monthly = plan.fallbackMonthlyEquivalentText {
                items.append(monthly)
            }
        }
        items.append(MembershipPricing.yearlyBadgeText(savingsPercent: MembershipPlan.defaultYearlySavingsPercent))
        for benefit in benefits {
            items.append(benefit.title)
            items.append(benefit.detail)
        }
        return items
    }
}
