import Foundation
import Testing
@testable import Sumly

// MARK: - 1. AccountGoldProfileSummary 持有聚合、陪伴天数、里程碑与隐私脱敏

@Test func profileSummaryAggregatesActiveHoldingsAndExcludesDisposedRecords() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))

    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 12)))
    let tenDaysAgo = try #require(calendar.date(byAdding: .day, value: -10, to: now))
    let thirtyDaysAgo = try #require(calendar.date(byAdding: .day, value: -30, to: now))
    let fortyDaysAgo = try #require(calendar.date(byAdding: .day, value: -40, to: now))

    let entries: [AccountHoldingSnapshot] = [
        AccountHoldingSnapshot(grams: 12.5, timestamp: tenDaysAgo, disposition: "holding"),
        AccountHoldingSnapshot(grams: 40.0, timestamp: thirtyDaysAgo, disposition: "holding"),
        // 已卖出与已赠送不得计入当前持有克重与笔数，但最早购入日仍记录在陪伴天数中
        AccountHoldingSnapshot(grams: 100.0, timestamp: fortyDaysAgo, disposition: "sold"),
        AccountHoldingSnapshot(grams: 5.0, timestamp: tenDaysAgo, disposition: "gift"),
        // 非法或非正克重安全忽略
        AccountHoldingSnapshot(grams: 0, timestamp: fortyDaysAgo, disposition: "holding"),
        AccountHoldingSnapshot(grams: -3, timestamp: fortyDaysAgo, disposition: "holding"),
        AccountHoldingSnapshot(grams: .nan, timestamp: fortyDaysAgo, disposition: "holding"),
        AccountHoldingSnapshot(grams: .infinity, timestamp: fortyDaysAgo, disposition: "holding")
    ]

    let summary = AccountGoldProfileSummary(entries: entries, now: now, calendar: calendar)

    #expect(!summary.isEmpty)
    #expect(abs(summary.activeGrams - 52.5) < 0.0001)
    #expect(summary.activeCount == 2)
    // 40 天前购入至今（含首尾）= 41 天
    #expect(summary.companionDays == 41)
    #expect(summary.hasUnlockedMilestone)
    #expect(summary.milestoneTitle == "50g 筑底")
    #expect(summary.formattedActiveGrams(hideAmounts: false) == "52.5 g")
    #expect(summary.formattedActiveCount(hideAmounts: false) == "2 笔")
    #expect(summary.formattedCompanionDays() == "41 天")
}

@Test func profileSummaryEmptyAndSubOneGramDegradeGracefully() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 12)))

    let empty = AccountGoldProfileSummary(entries: [], now: now, calendar: calendar)
    #expect(empty.isEmpty)
    #expect(empty.activeGrams == 0)
    #expect(empty.activeCount == 0)
    #expect(empty.companionDays == 0)
    #expect(!empty.hasUnlockedMilestone)
    #expect(empty.milestoneTitle == "待启首克")
    #expect(empty.formattedActiveGrams(hideAmounts: false) == "0 g")
    #expect(empty.formattedActiveCount(hideAmounts: false) == "0 笔")
    #expect(empty.formattedCompanionDays() == "0 天")

    // 全部已卖出时当前持仓为 0，里程碑回退待启首克
    let onlyDisposed = AccountGoldProfileSummary(
        entries: [
            AccountHoldingSnapshot(grams: 20, timestamp: now, disposition: "sold"),
            AccountHoldingSnapshot(grams: 5, timestamp: now, disposition: "gift")
        ],
        now: now,
        calendar: calendar
    )
    #expect(onlyDisposed.isEmpty)
    #expect(onlyDisposed.activeGrams == 0)
    #expect(onlyDisposed.activeCount == 0)
    #expect(onlyDisposed.companionDays == 1)
    #expect(onlyDisposed.milestoneTitle == "待启首克")

    // 持有不足 1g 时显示「蓄力首克」，当日购入陪伴 1 天
    let subOneGram = AccountGoldProfileSummary(
        entries: [AccountHoldingSnapshot(grams: 0.5, timestamp: now, disposition: "holding")],
        now: now,
        calendar: calendar
    )
    #expect(!subOneGram.isEmpty)
    #expect(subOneGram.activeCount == 1)
    #expect(subOneGram.companionDays == 1)
    #expect(!subOneGram.hasUnlockedMilestone)
    #expect(subOneGram.milestoneTitle == "蓄力首克")
}

@Test func profileSummaryReusesAllSixGoldMilestoneTiers() {
    let cases: [(Double, String)] = [
        (1, "首克 1g"),
        (10, "10g 初成"),
        (50, "50g 筑底"),
        (100, "100g 小金砖"),
        (500, "500g 金库"),
        (1000, "1kg 典藏")
    ]

    for (grams, expectedTitle) in cases {
        let summary = AccountGoldProfileSummary(
            entries: [AccountHoldingSnapshot(grams: grams, timestamp: .now)]
        )
        #expect(summary.hasUnlockedMilestone)
        #expect(summary.milestoneTitle == expectedTitle)
    }
}

@Test func profileSummaryMasksSensitiveAmountsWhenHideAmountsEnabled() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 12)))
    let purchaseDay = try #require(calendar.date(byAdding: .day, value: -99, to: now))

    let summary = AccountGoldProfileSummary(
        entries: [
            AccountHoldingSnapshot(grams: 88.88, timestamp: purchaseDay, disposition: "holding"),
            AccountHoldingSnapshot(grams: 20, timestamp: now, disposition: "holding")
        ],
        now: now,
        calendar: calendar
    )

    let maskedGrams = summary.formattedActiveGrams(hideAmounts: true)
    let maskedCount = summary.formattedActiveCount(hideAmounts: true)

    #expect(maskedGrams == "•••• g")
    #expect(maskedCount == "••••")
    #expect(!maskedGrams.contains("108"))
    #expect(!maskedGrams.contains("88"))
    #expect(!maskedCount.contains("2"))

    // 陪伴天数与陪伴等级在隐私遮罩下仍保留陪伴感
    #expect(summary.formattedCompanionDays() == "100 天")
    #expect(summary.milestoneTitle == "100g 小金砖")
}

// MARK: - 2. AccountCloudStatusBadge 全状态映射

@Test func cloudStatusBadgeMapsGuestSyncedSyncingConflictAndGuestImport() {
    // 1) 未登录：本机游客模式
    let guest = AccountCloudStatusBadge.resolve(isSignedIn: false, guestRecordCount: 4)
    #expect(guest.tone == .guest)
    #expect(guest.title == "本机游客模式")
    #expect(!guest.canSyncNow)
    #expect(guest.guestImportHint == nil)
    #expect(guest.settingsAttention == nil)

    // 2) 登录态正常已同步
    let synced = AccountCloudStatusBadge.resolve(
        isSignedIn: true,
        isSyncing: false,
        conflictCount: 0,
        guestRecordCount: 0,
        hasPendingChanges: false
    )
    #expect(synced.tone == .synced)
    #expect(synced.title == "云端已同步")
    #expect(synced.canSyncNow)
    #expect(synced.guestImportHint == nil)
    #expect(synced.settingsAttention == nil)

    // 3) 登录态同步中
    let syncing = AccountCloudStatusBadge.resolve(
        isSignedIn: true,
        isSyncing: true,
        conflictCount: 0,
        guestRecordCount: 2
    )
    #expect(syncing.tone == .syncing)
    #expect(syncing.title == "同步中…")
    #expect(syncing.isSyncing)
    #expect(!syncing.canSyncNow)
    #expect(syncing.guestImportHint == "可导入 2 条游客记录")
    #expect(syncing.settingsAttention == .init(text: "可导入 2 条", isUrgent: false))

    // 4) 登录态有同步冲突（红标优先于游客导入提示）
    let conflict = AccountCloudStatusBadge.resolve(
        isSignedIn: true,
        isSyncing: false,
        conflictCount: 3,
        guestRecordCount: 5
    )
    #expect(conflict.tone == .conflict)
    #expect(conflict.title == "有 3 条同步冲突")
    #expect(conflict.conflictCount == 3)
    #expect(conflict.guestImportHint == "可导入 5 条游客记录")
    #expect(conflict.settingsAttention == .init(text: "3 条冲突", isUrgent: true))

    // 5) 登录态存在可导入游客记录（无冲突）
    let withGuestImport = AccountCloudStatusBadge.resolve(
        isSignedIn: true,
        isSyncing: false,
        conflictCount: 0,
        guestRecordCount: 3
    )
    #expect(withGuestImport.tone == .synced)
    #expect(withGuestImport.title == "云端已同步")
    #expect(withGuestImport.guestImportHint == "可导入 3 条游客记录")
    #expect(withGuestImport.settingsAttention == .init(text: "可导入 3 条", isUrgent: false))

    // 6) 登录态有未上传本地更改
    let pending = AccountCloudStatusBadge.resolve(
        isSignedIn: true,
        hasPendingChanges: true
    )
    #expect(pending.tone == .pending)
    #expect(pending.title == "待同步更改")
}

// MARK: - 3. 版本格式化、头像首字与登录方式胶囊

@Test func appVersionFormatterAndAvatarPresentationHandleAllEdgeCases() {
    #expect(AccountAppVersionFormatter.format(shortVersion: "1.0.5", buildNumber: "55") == "记金 v1.0.5")
    #expect(AccountAppVersionFormatter.format(shortVersion: "1.0.5", buildNumber: "55", includeBuild: true) == "记金 v1.0.5 (55)")
    #expect(AccountAppVersionFormatter.format(shortVersion: " 1.0.5 ", buildNumber: "  ", includeBuild: true) == "记金 v1.0.5")
    #expect(AccountAppVersionFormatter.format(shortVersion: nil, buildNumber: nil) == "记金")
    #expect(AccountAppVersionFormatter.format(shortVersion: "", buildNumber: "55", includeBuild: true) == "记金 (55)")

    #expect(AccountAvatarPresentation.monogram(for: "记金用户") == "记")
    #expect(AccountAvatarPresentation.monogram(for: "  carl ") == "C")
    #expect(AccountAvatarPresentation.monogram(for: "   ") == nil)

    #expect(AuthProvider.apple.loginPillTitle == "Apple 登录")
    #expect(AuthProvider.phone.loginPillTitle == "手机登录")
    #expect(AuthProvider.email.loginPillTitle == "邮箱登录")
}

// MARK: - 4. 零投资建议与合规词静态断言

@Test func accountCopyContainsZeroInvestmentAdviceOrHypeWords() {
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
        "投资建议"
    ]

    let allBadgeSamples: [AccountCloudStatusBadge] = [
        .resolve(isSignedIn: false),
        .resolve(isSignedIn: true),
        .resolve(isSignedIn: true, isSyncing: true),
        .resolve(isSignedIn: true, conflictCount: 2, guestRecordCount: 3),
        .resolve(isSignedIn: true, hasPendingChanges: true)
    ]

    var candidateStrings = AccountProfileCopy.allPromotionalAndUICopy
    candidateStrings += GoldMilestone.ladder.map(\.title)
    candidateStrings += [AccountGoldProfileSummary.empty.milestoneTitle, "蓄力首克"]
    for badge in allBadgeSamples {
        candidateStrings.append(badge.title)
        candidateStrings.append(badge.detail)
        if let hint = badge.guestImportHint { candidateStrings.append(hint) }
        if let pill = badge.settingsAttention { candidateStrings.append(pill.text) }
    }

    for text in candidateStrings {
        for forbidden in forbiddenTerms {
            #expect(!text.contains(forbidden), "文案「\(text)」不应包含合规禁用词「\(forbidden)」")
        }
    }

    // 合规免责声明必须完整明示非交易、非投资建议定位
    #expect(AccountProfileCopy.disclaimer == "记金用于个人记录与回收估算，不提供黄金交易或投资建议。")
    #expect(AccountProfileCopy.icpNumber == "蜀ICP备2020035100号-3A")
}
