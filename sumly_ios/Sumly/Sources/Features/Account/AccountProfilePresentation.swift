import Foundation

// MARK: - 账户页静态文案与合规声明（单一数据源，供视图与合规单测共用）

enum AccountProfileCopy {
    static var pageTitle: String { L10n.tr("我的") }
    static var pageSubtitle: String { L10n.tr("记下每一克，积累每一天") }

    static var guestHeadline: String { L10n.tr("让积累，有自己的名字") }
    static var guestModeLabel: String { L10n.tr("本机游客模式") }
    static var guestSubtitle: String { L10n.tr("本机离线即可记录，随时登录开启多端同步") }
    static var guestValueTags: [String] {
        [
            L10n.tr("多端云同步"),
            L10n.tr("离线可用"),
            L10n.tr("游客数据独立")
        ]
    }
    static var loginActionTitle: String { L10n.tr("登录 / 注册") }

    static var profileSectionTitle: String { L10n.tr("我的攒金档案") }
    static var activeGramsLabel: String { L10n.tr("当前持有") }
    static var activeCountLabel: String { L10n.tr("持仓笔数") }
    static var companionDaysLabel: String { L10n.tr("攒金陪伴") }

    static var preferencesSectionTitle: String { L10n.tr("偏好与工具") }
    static var membershipTitle: String { MembershipCopy.title }
    static var membershipSubtitle: String { MembershipCopy.accountInactiveSubtitle }
    static var chanlunMemberBadge: String { MembershipCopy.chanlunMemberBadge }
    static var privacyMaskTitle: String { L10n.tr("隐私遮罩") }
    static var privacyMaskSubtitle: String { L10n.tr("隐藏全应用金额与持仓克重") }
    static var chanlunTitle: String { L10n.tr("禅观") }
    static var chanlunSubtitle: String { L10n.tr("查看行情走势与复盘") }
    static var onboardingTitle: String { L10n.tr("新手引导") }
    static var onboardingSubtitle: String { L10n.tr("快速了解记金核心功能") }
    static var cloudSettingsTitle: String { L10n.tr("云同步与系统设置") }
    static var cloudSettingsSubtitle: String { L10n.tr("同步、跨设备登录与缓存管理") }

    static var supportSectionTitle: String { L10n.tr("支持与合规") }
    static var privacyPolicyTitle: String { L10n.tr("隐私政策") }
    static var privacyPolicySubtitle: String { L10n.tr("了解数据存储与隐私保护说明") }
    static var supportTitle: String { L10n.tr("联系支持") }
    static let supportSubtitle = "oryjk@qq.com"
    static var icpTitle: String { L10n.tr("App 备案号") }
    static let icpNumber = "蜀ICP备2020035100号-3A"

    static var securitySectionTitle: String { L10n.tr("账户安全") }
    static var logoutTitle: String { L10n.tr("退出登录") }
    static var logoutSubtitle: String { L10n.tr("本机缓存保留，退出后切换回游客视图") }
    static var deleteAccountTitle: String { L10n.tr("注销账户") }
    static var deleteAccountSubtitle: String { L10n.tr("永久删除账户与云端持仓，需 5 分钟内重验") }

    static var disclaimer: String { L10n.tr("记金用于个人记录与回收估算，不提供黄金交易或投资建议。") }

    static var allPromotionalAndUICopy: [String] {
        [
            pageTitle,
            pageSubtitle,
            guestHeadline,
            guestModeLabel,
            guestSubtitle,
            loginActionTitle,
            profileSectionTitle,
            activeGramsLabel,
            activeCountLabel,
            companionDaysLabel,
            preferencesSectionTitle,
            membershipTitle,
            membershipSubtitle,
            chanlunMemberBadge,
            privacyMaskTitle,
            privacyMaskSubtitle,
            chanlunTitle,
            chanlunSubtitle,
            onboardingTitle,
            onboardingSubtitle,
            cloudSettingsTitle,
            cloudSettingsSubtitle,
            supportSectionTitle,
            privacyPolicyTitle,
            privacyPolicySubtitle,
            supportTitle,
            supportSubtitle,
            icpTitle,
            icpNumber,
            securitySectionTitle,
            logoutTitle,
            logoutSubtitle,
            deleteAccountTitle,
            deleteAccountSubtitle
        ] + guestValueTags
    }
}

// MARK: - 登录方式与头像展示辅助

extension AuthProvider {
    var loginPillTitle: String {
        switch self {
        case .apple: L10n.tr("Apple 登录")
        case .phone: L10n.tr("手机登录")
        case .email: L10n.tr("邮箱登录")
        }
    }
}

enum AccountAvatarPresentation {
    /// 提取用户昵称首字作为暗金头像徽章字符；昵称为空时返回 nil 由视图回退图标。
    static func monogram(for nickname: String) -> String? {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        return String(first).uppercased()
    }
}

// MARK: - 1. 个人攒金档案纯逻辑摘要（Sendable，独立可测）

/// 轻量持仓快照，便于脱离 SwiftData 容器独立验证聚合与脱敏逻辑。
struct AccountHoldingSnapshot: Equatable, Sendable {
    let grams: Double
    let timestamp: Date
    let disposition: String

    init(grams: Double, timestamp: Date, disposition: String = "holding") {
        self.grams = grams
        self.timestamp = timestamp
        self.disposition = disposition
    }
}

extension HoldingRecord {
    var accountSnapshot: AccountHoldingSnapshot {
        AccountHoldingSnapshot(grams: grams, timestamp: timestamp, disposition: disposition)
    }
}

/// 「我的攒金档案」汇总模型：统计当前有效持有克重、笔数、陪伴天数与攒金里程碑。
struct AccountGoldProfileSummary: Equatable, Sendable {
    let activeGrams: Double
    let activeCount: Int
    let companionDays: Int
    let milestoneProgress: GoldMilestoneProgress
    let milestoneTitle: String

    static let empty = AccountGoldProfileSummary(entries: [])

    var isEmpty: Bool {
        activeCount == 0 || activeGrams <= 0
    }

    var hasUnlockedMilestone: Bool {
        milestoneProgress.current != nil
    }

    init(
        entries: [AccountHoldingSnapshot],
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let validEntries = entries.filter { $0.grams.isFinite && $0.grams > 0 }
        let activeEntries = validEntries.filter { $0.disposition == "holding" }

        let totalActiveGrams = activeEntries.reduce(0.0) { $0 + $1.grams }
        let count = activeEntries.count

        let todayStart = calendar.startOfDay(for: now)
        let earliestPurchaseDay = validEntries
            .map { calendar.startOfDay(for: $0.timestamp) }
            .filter { $0 <= todayStart }
            .min()

        let days: Int = {
            guard let earliestPurchaseDay else { return 0 }
            let diff = calendar.dateComponents([.day], from: earliestPurchaseDay, to: todayStart).day ?? 0
            return max(1, diff + 1)
        }()

        let progress = GoldMilestoneProgress.evaluate(totalGrams: totalActiveGrams)
        let resolvedTitle: String = {
            if let current = progress.current {
                return current.title
            }
            if totalActiveGrams > 0 {
                return L10n.tr("蓄力首克")
            }
            return L10n.tr("待启首克")
        }()

        self.activeGrams = totalActiveGrams
        self.activeCount = count
        self.companionDays = days
        self.milestoneProgress = progress
        self.milestoneTitle = resolvedTitle
    }

    @MainActor
    init(
        records: [HoldingRecord],
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        self.init(entries: records.map(\.accountSnapshot), now: now, calendar: calendar)
    }

    func formattedActiveGrams(hideAmounts: Bool) -> String {
        if hideAmounts { return "•••• g" }
        return "\(GoldVaultSummary.formatGrams(activeGrams)) g"
    }

    func formattedActiveCount(hideAmounts: Bool) -> String {
        if hideAmounts { return "••••" }
        return L10n.fmt("%d 笔", activeCount)
    }

    func formattedCompanionDays() -> String {
        L10n.fmt("%d 天", companionDays)
    }
}

// MARK: - 2. 云同步状态胶囊映射（Sendable，独立可测）

struct AccountCloudStatusBadge: Equatable, Sendable {
    enum Tone: Equatable, Sendable {
        case guest
        case synced
        case syncing
        case pending
        case failed
        case conflict
    }

    enum IconAction: Equatable, Sendable {
        case none
        case sync
        case openConflictResolution
    }

    struct AttentionPill: Equatable, Sendable {
        let text: String
        let isUrgent: Bool
    }

    let tone: Tone
    let title: String
    let detail: String
    let guestImportHint: String?
    let canSyncNow: Bool
    let isSyncing: Bool
    let conflictCount: Int
    let guestRecordCount: Int
    let settingsAttention: AttentionPill?

    /// 100% 兼容 iOS 17.0+ 的 SF Symbol 名称（严禁使用 iOS 18+ 专属符号）。
    var iconSystemName: String {
        switch tone {
        case .guest: "icloud.slash"
        case .synced: "checkmark.icloud.fill"
        case .syncing: "arrow.clockwise.icloud"
        case .pending: "icloud.and.arrow.up"
        case .failed: "exclamationmark.icloud"
        case .conflict: "exclamationmark.icloud.fill"
        }
    }

    /// 同步中在 34×34 圆形外圈叠加持续旋转的金色加载弧。
    var showsSyncSpinner: Bool {
        tone == .syncing
    }

    /// 同步失败/待重试态右上角叠加迷你警示点，与本地待上传态区分。
    var showsFailedIndicatorDot: Bool {
        tone == .failed
    }

    /// 多设备冲突态右上角紧凑数字角标（如 "2"、"9+"），其余状态返回 nil。
    var conflictBadgeText: String? {
        guard tone == .conflict, conflictCount > 0 else { return nil }
        return conflictCount > 9 ? "9+" : "\(conflictCount)"
    }

    /// 点击「我的」页用户名行纯图标云同步按钮后应触发的交互动作。
    var iconAction: IconAction {
        switch tone {
        case .synced, .pending, .failed:
            .sync
        case .conflict:
            .openConflictResolution
        case .syncing, .guest:
            .none
        }
    }

    /// 纯图标云同步按钮当前是否可交互（同步中/游客态禁用重复点击）。
    var isIconInteractive: Bool {
        iconAction != .none
    }

    /// VoiceOver 完整可读标签，清晰播报状态与轻点操作。
    var accessibilityLabel: String {
        switch tone {
        case .guest:
            L10n.tr("本机游客模式，未开启云同步")
        case .synced:
            L10n.tr("云端已同步，轻点立即同步")
        case .syncing:
            L10n.tr("正在同步云端数据")
        case .pending:
            L10n.tr("本地有待同步更改，轻点立即同步")
        case .failed:
            L10n.tr("云同步失败待重试，轻点重新同步")
        case .conflict:
            L10n.fmt("有 %d 条同步冲突，轻点前往处理", conflictCount)
        }
    }

    static func resolve(
        isSignedIn: Bool,
        isSyncing: Bool = false,
        conflictCount: Int = 0,
        guestRecordCount: Int = 0,
        hasPendingChanges: Bool = false,
        lastSyncedAt: Date? = nil,
        notice: String? = nil,
        statusDetail: String? = nil
    ) -> AccountCloudStatusBadge {
        guard isSignedIn else {
            return AccountCloudStatusBadge(
                tone: .guest,
                title: AccountProfileCopy.guestModeLabel,
                detail: statusDetail ?? L10n.tr("游客记录仅保存在此设备，登录后可导入账户。"),
                guestImportHint: nil,
                canSyncNow: false,
                isSyncing: false,
                conflictCount: 0,
                guestRecordCount: max(0, guestRecordCount),
                settingsAttention: nil
            )
        }

        let safeConflicts = max(0, conflictCount)
        let safeGuestRecords = max(0, guestRecordCount)
        let importHint = safeGuestRecords > 0 ? L10n.fmt("可导入 %d 条游客记录", safeGuestRecords) : nil

        let attention: AttentionPill? = {
            if safeConflicts > 0 {
                return AttentionPill(text: L10n.fmt("%d 条冲突", safeConflicts), isUrgent: true)
            }
            if safeGuestRecords > 0 {
                return AttentionPill(text: L10n.fmt("可导入 %d 条", safeGuestRecords), isUrgent: false)
            }
            return nil
        }()

        if isSyncing {
            return AccountCloudStatusBadge(
                tone: .syncing,
                title: L10n.tr("同步中…"),
                detail: statusDetail ?? L10n.tr("正在同步云端持仓与账本…"),
                guestImportHint: importHint,
                canSyncNow: false,
                isSyncing: true,
                conflictCount: safeConflicts,
                guestRecordCount: safeGuestRecords,
                settingsAttention: attention
            )
        }

        if safeConflicts > 0 {
            return AccountCloudStatusBadge(
                tone: .conflict,
                title: L10n.fmt("有 %d 条同步冲突", safeConflicts),
                detail: statusDetail ?? L10n.fmt("%d 条记录在多台设备上均有更改，请选择保留版本。", safeConflicts),
                guestImportHint: importHint,
                canSyncNow: true,
                isSyncing: false,
                conflictCount: safeConflicts,
                guestRecordCount: safeGuestRecords,
                settingsAttention: attention
            )
        }

        if let notice, !notice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AccountCloudStatusBadge(
                tone: .failed,
                title: L10n.tr("同步待重试"),
                detail: statusDetail ?? notice,
                guestImportHint: importHint,
                canSyncNow: true,
                isSyncing: false,
                conflictCount: 0,
                guestRecordCount: safeGuestRecords,
                settingsAttention: attention
            )
        }

        if hasPendingChanges {
            return AccountCloudStatusBadge(
                tone: .pending,
                title: L10n.tr("待同步更改"),
                detail: statusDetail ?? L10n.tr("有更改等待同步，记录已保存在本机。"),
                guestImportHint: importHint,
                canSyncNow: true,
                isSyncing: false,
                conflictCount: 0,
                guestRecordCount: safeGuestRecords,
                settingsAttention: attention
            )
        }

        let syncedDetail = statusDetail ?? lastSyncedAt.map {
            L10n.fmt("已同步 · %@", $0.formatted(date: .omitted, time: .shortened))
        } ?? L10n.tr("已开启云同步，本机缓存支持离线记录。")

        return AccountCloudStatusBadge(
            tone: .synced,
            title: L10n.tr("云端已同步"),
            detail: syncedDetail,
            guestImportHint: importHint,
            canSyncNow: true,
            isSyncing: false,
            conflictCount: 0,
            guestRecordCount: safeGuestRecords,
            settingsAttention: attention
        )
    }

    @MainActor
    static func from(session: AuthSession, cloud: HoldingsCloud?) -> AccountCloudStatusBadge {
        let signedIn = session.user != nil
        guard let cloud else {
            return resolve(isSignedIn: signedIn)
        }
        let hasPending = cloud.userID != nil && ((try? cloud.document()) != cloud.base.document)
        return resolve(
            isSignedIn: signedIn,
            isSyncing: cloud.isSyncing,
            conflictCount: cloud.conflictCount,
            guestRecordCount: cloud.guestRecordCount,
            hasPendingChanges: hasPending,
            lastSyncedAt: cloud.lastSyncedAt,
            notice: cloud.notice,
            statusDetail: cloud.status
        )
    }
}

// MARK: - 3. 版本号安全格式化（Sendable，独立可测）

enum AccountAppVersionFormatter {
    static func format(
        appName: String = L10n.tr("记金"),
        shortVersion: String?,
        buildNumber: String? = nil,
        includeBuild: Bool = false
    ) -> String {
        let trimmedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? L10n.tr("记金") : trimmedName
        let version = shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let build = buildNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !version.isEmpty else {
            if includeBuild, !build.isEmpty {
                return "\(name) (\(build))"
            }
            return name
        }
        if includeBuild, !build.isEmpty {
            return "\(name) v\(version) (\(build))"
        }
        return "\(name) v\(version)"
    }

    static func format(
        bundle: Bundle = .main,
        appName: String = L10n.tr("记金"),
        includeBuild: Bool = false
    ) -> String {
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return format(
            appName: appName,
            shortVersion: shortVersion,
            buildNumber: buildNumber,
            includeBuild: includeBuild
        )
    }
}
