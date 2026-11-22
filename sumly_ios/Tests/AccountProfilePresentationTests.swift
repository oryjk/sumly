import Foundation
import SwiftUI
import Testing
import UIKit
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

// MARK: - 2. AccountCloudStatusBadge 全状态映射与纯图标规范

@Test func cloudStatusBadgeMapsAllFiveSignedInStatesAndGuestIconSpecs() {
    // 1) 未登录：本机游客模式
    let guest = AccountCloudStatusBadge.resolve(isSignedIn: false, guestRecordCount: 4)
    #expect(guest.tone == .guest)
    #expect(guest.title == "本机游客模式")
    #expect(!guest.canSyncNow)
    #expect(!guest.isIconInteractive)
    #expect(guest.iconAction == .none)
    #expect(guest.iconSystemName == "icloud.slash")
    #expect(!guest.showsSyncSpinner)
    #expect(!guest.showsFailedIndicatorDot)
    #expect(guest.conflictBadgeText == nil)
    #expect(guest.accessibilityLabel == "本机游客模式，未开启云同步")
    #expect(guest.guestImportHint == nil)
    #expect(guest.settingsAttention == nil)

    // 2) 登录态：云端已同步 (.synced)
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
    #expect(synced.isIconInteractive)
    #expect(synced.iconAction == .sync)
    #expect(synced.iconSystemName == "checkmark.icloud.fill")
    #expect(!synced.showsSyncSpinner)
    #expect(!synced.showsFailedIndicatorDot)
    #expect(synced.conflictBadgeText == nil)
    #expect(synced.accessibilityLabel == "云端已同步，轻点立即同步")
    #expect(synced.guestImportHint == nil)
    #expect(synced.settingsAttention == nil)

    // 3) 登录态：同步中 (.syncing，禁用重复点击，不叠加冲突角标)
    let syncing = AccountCloudStatusBadge.resolve(
        isSignedIn: true,
        isSyncing: true,
        conflictCount: 2,
        guestRecordCount: 2
    )
    #expect(syncing.tone == .syncing)
    #expect(syncing.title == "同步中…")
    #expect(syncing.isSyncing)
    #expect(!syncing.canSyncNow)
    #expect(!syncing.isIconInteractive)
    #expect(syncing.iconAction == .none)
    #expect(syncing.iconSystemName == "arrow.clockwise.icloud")
    #expect(syncing.showsSyncSpinner)
    #expect(!syncing.showsFailedIndicatorDot)
    #expect(syncing.conflictBadgeText == nil)
    #expect(syncing.accessibilityLabel == "正在同步云端数据")
    #expect(syncing.guestImportHint == "可导入 2 条游客记录")
    #expect(syncing.settingsAttention == .init(text: "2 条冲突", isUrgent: true))

    // 4) 登录态：本地待上传 (.pending)
    let pending = AccountCloudStatusBadge.resolve(
        isSignedIn: true,
        hasPendingChanges: true,
        notice: "   "
    )
    #expect(pending.tone == .pending)
    #expect(pending.title == "待同步更改")
    #expect(pending.canSyncNow)
    #expect(pending.isIconInteractive)
    #expect(pending.iconAction == .sync)
    #expect(pending.iconSystemName == "icloud.and.arrow.up")
    #expect(!pending.showsSyncSpinner)
    #expect(!pending.showsFailedIndicatorDot)
    #expect(pending.conflictBadgeText == nil)
    #expect(pending.accessibilityLabel == "本地有待同步更改，轻点立即同步")

    // 5) 登录态：同步失败/待重试 (.failed，notice 非空且优先于 hasPendingChanges)
    let failed = AccountCloudStatusBadge.resolve(
        isSignedIn: true,
        hasPendingChanges: true,
        notice: "网络连接已中断，稍后重试"
    )
    #expect(failed.tone == .failed)
    #expect(failed.title == "同步待重试")
    #expect(failed.detail == "网络连接已中断，稍后重试")
    #expect(failed.canSyncNow)
    #expect(failed.isIconInteractive)
    #expect(failed.iconAction == .sync)
    #expect(failed.iconSystemName == "exclamationmark.icloud")
    #expect(!failed.showsSyncSpinner)
    #expect(failed.showsFailedIndicatorDot)
    #expect(failed.conflictBadgeText == nil)
    #expect(failed.accessibilityLabel == "云同步失败待重试，轻点重新同步")

    // 6) 登录态：多设备同步冲突 (.conflict，直接跳转设置页处理冲突)
    let conflict = AccountCloudStatusBadge.resolve(
        isSignedIn: true,
        isSyncing: false,
        conflictCount: 3,
        guestRecordCount: 5
    )
    #expect(conflict.tone == .conflict)
    #expect(conflict.title == "有 3 条同步冲突")
    #expect(conflict.conflictCount == 3)
    #expect(conflict.isIconInteractive)
    #expect(conflict.iconAction == .openConflictResolution)
    #expect(conflict.iconSystemName == "exclamationmark.icloud.fill")
    #expect(!conflict.showsSyncSpinner)
    #expect(!conflict.showsFailedIndicatorDot)
    #expect(conflict.conflictBadgeText == "3")
    #expect(conflict.accessibilityLabel == "有 3 条同步冲突，轻点前往处理")
    #expect(conflict.guestImportHint == "可导入 5 条游客记录")
    #expect(conflict.settingsAttention == .init(text: "3 条冲突", isUrgent: true))

    // 冲突数边界：9 显示 "9"，超过 9 压缩为 "9+"
    let nineConflicts = AccountCloudStatusBadge.resolve(isSignedIn: true, conflictCount: 9)
    #expect(nineConflicts.conflictBadgeText == "9")
    let manyConflicts = AccountCloudStatusBadge.resolve(isSignedIn: true, conflictCount: 12)
    #expect(manyConflicts.conflictBadgeText == "9+")
    #expect(manyConflicts.accessibilityLabel == "有 12 条同步冲突，轻点前往处理")

    // 7) 登录态存在可导入游客记录（无冲突）仍保持 .synced 且保留游客导入提示
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

    // 8) 全部 SF Symbol 必须 100% 兼容 iOS 17.0+（禁止 iOS 18+ trianglehead 符号）
    let allBadges = [guest, synced, syncing, pending, failed, conflict]
    let ios17CompatibleSymbols: Set<String> = [
        "icloud.slash",
        "checkmark.icloud.fill",
        "arrow.clockwise.icloud",
        "icloud.and.arrow.up",
        "exclamationmark.icloud",
        "exclamationmark.icloud.fill"
    ]
    for badge in allBadges {
        #expect(ios17CompatibleSymbols.contains(badge.iconSystemName))
        #expect(!badge.iconSystemName.contains("trianglehead"))
        #expect(!badge.accessibilityLabel.isEmpty)
    }
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
        .resolve(isSignedIn: true, hasPendingChanges: true),
        .resolve(isSignedIn: true, notice: "网络不可用，待重试")
    ]

    var candidateStrings = AccountProfileCopy.allPromotionalAndUICopy
    candidateStrings += GoldMilestone.ladder.map(\.title)
    candidateStrings += [AccountGoldProfileSummary.empty.milestoneTitle, "蓄力首克"]
    for badge in allBadgeSamples {
        candidateStrings.append(badge.title)
        candidateStrings.append(badge.detail)
        candidateStrings.append(badge.accessibilityLabel)
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

// MARK: - 5. 登录态 5 种纯图标云同步状态多态视觉渲染验证

@MainActor @Test func renderSignedInCloudIconFiveStatesShowcase() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 12)))
    let startDay = try #require(calendar.date(byAdding: .day, value: -127, to: now))

    let summary = AccountGoldProfileSummary(
        entries: [
            AccountHoldingSnapshot(grams: 35.5, timestamp: startDay, disposition: "holding"),
            AccountHoldingSnapshot(grams: 20.0, timestamp: now, disposition: "holding")
        ],
        now: now,
        calendar: calendar
    )

    let cases: [(label: String, user: NativeUser, badge: AccountCloudStatusBadge)] = [
        (
            "1 · 已同步 (.synced)",
            NativeUser(
                id: 1,
                nickname: "记金用户",
                avatarURL: "",
                email: "gold@oryjk.cn",
                phoneNumber: nil,
                status: "active",
                provider: .apple
            ),
            .resolve(isSignedIn: true)
        ),
        (
            "2 · 同步中 (.syncing)",
            NativeUser(
                id: 2,
                nickname: "Carl 攒金",
                avatarURL: "",
                email: nil,
                phoneNumber: "13800138000",
                status: "active",
                provider: .phone
            ),
            .resolve(isSignedIn: true, isSyncing: true)
        ),
        (
            "3 · 待上传 (.pending) · 长昵称防挤压",
            NativeUser(
                id: 3,
                nickname: "黄金长期主义收藏家超长昵称",
                avatarURL: "",
                email: "collector.longname@example.com",
                phoneNumber: nil,
                status: "active",
                provider: .email
            ),
            .resolve(isSignedIn: true, hasPendingChanges: true)
        ),
        (
            "4 · 失败重试 (.failed) · 含游客导入条",
            NativeUser(
                id: 4,
                nickname: "记金用户",
                avatarURL: "",
                email: "gold@oryjk.cn",
                phoneNumber: nil,
                status: "active",
                provider: .apple
            ),
            .resolve(isSignedIn: true, guestRecordCount: 2, notice: "网络波动，待重试")
        ),
        (
            "5 · 同步冲突 (.conflict)",
            NativeUser(
                id: 5,
                nickname: "记金用户",
                avatarURL: "",
                email: "gold@oryjk.cn",
                phoneNumber: nil,
                status: "active",
                provider: .apple
            ),
            .resolve(isSignedIn: true, conflictCount: 2)
        )
    ]

    let overviewIcons: [(caption: String, badge: AccountCloudStatusBadge)] = [
        ("已同步", .resolve(isSignedIn: true)),
        ("同步中", .resolve(isSignedIn: true, isSyncing: true)),
        ("待上传", .resolve(isSignedIn: true, hasPendingChanges: true)),
        ("失败重试", .resolve(isSignedIn: true, notice: "超时")),
        ("冲突 2", .resolve(isSignedIn: true, conflictCount: 2)),
        ("冲突 9+", .resolve(isSignedIn: true, conflictCount: 12))
    ]

    let showcase = VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 6) {
            Text("「我的」纯图标云同步状态 · 5 态视觉核验")
                .font(.headline.bold())
                .foregroundStyle(GoldTheme.text)
            Text("34×34 视觉圆 · 44×44 热区 · iOS 17+ 符号 · 移除整行横条")
                .font(.caption)
                .foregroundStyle(GoldTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }

        // 顶部 6 枚状态图标横向对照条（含冲突 2 与 9+）
        HStack(spacing: 0) {
            ForEach(Array(overviewIcons.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 4) {
                    AccountCloudSyncIconButton(badge: item.badge, onTap: {})
                    Text(item.caption)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(GoldTheme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))

        // 5 张真实登录态 Hero 卡片
        ForEach(Array(cases.enumerated()), id: \.offset) { _, item in
            VStack(alignment: .leading, spacing: 6) {
                Text(item.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.goldSoft)
                    .padding(.leading, 4)

                AccountHeroCardSurface {
                    AccountSignedInHeroHeader(
                        user: item.user,
                        badge: item.badge,
                        onTapCloudIcon: {}
                    )
                    if let hint = item.badge.guestImportHint {
                        AccountGuestImportCallout(text: hint, action: {})
                    }
                    GoldTheme.cardStroke.frame(height: 1)
                    AccountGoldProfileArchiveStrip(summary: summary, hideAmounts: false)
                }
            }
        }
    }
    .padding(16)
    .frame(width: 393, alignment: .leading)
    .background(GoldTheme.background)
    .preferredColorScheme(.dark)
    .tint(GoldTheme.gold)

    let controller = UIHostingController(rootView: showcase)
    controller.overrideUserInterfaceStyle = .dark
    let fittedSize = controller.sizeThatFits(in: CGSize(width: 393, height: CGFloat.greatestFiniteMagnitude))
    controller.view.bounds = CGRect(origin: .zero, size: fittedSize)
    controller.view.backgroundColor = UIColor(GoldTheme.background)
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()

    let format = UIGraphicsImageRendererFormat()
    format.scale = 3.0
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: fittedSize, format: format).image { _ in
        controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
    }

    #expect(image.size.width >= 390)
    #expect(image.size.height >= 1000)
    let data = try #require(image.pngData())
    #expect(data.count > 20_000)

    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sim_account_cloud_icon_v57.png")
    try data.write(to: outputURL, options: .atomic)
    print("CLOUD_ICON_SHOWCASE_ARTIFACT: \(outputURL.path)")
}
