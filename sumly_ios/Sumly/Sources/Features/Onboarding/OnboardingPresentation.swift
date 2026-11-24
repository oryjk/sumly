import Foundation

/// 新手引导与「3 步开启记金」共用的 AppStorage 键名。
enum OnboardingStorageKey {
    static let completedVersion = "onboarding.completedVersion"
    static let quickStartDismissed = "onboarding.quickStartDismissed"
    static let visitedChartOverlay = "onboarding.visitedChartOverlay"
    static let visitedCalendar = "onboarding.visitedCalendar"
}

/// 新手引导自动触发决策机：绝不打扰已有持仓记录的老用户。
enum OnboardingGate: Sendable {
    static let currentVersion = 1

    enum AutoLaunchDecision: Equatable, Sendable {
        /// 全新零持仓用户：首次进入自动呈现 3 页引导。
        case present
        /// 已有持仓老用户：不弹出打断，静默标记当前版本已完成。
        case markCompletedSilently
        /// 已完成或已跳过：不做任何操作。
        case skip
    }

    /// 仅当尚未完成当前版本且本地尚无任何持仓记录时自动弹出。
    static func shouldAutoPresent(completedVersion: Int, existingHoldingCount: Int) -> Bool {
        completedVersion < currentVersion && max(0, existingHoldingCount) == 0
    }

    /// 老用户已有持仓记录且未标记完成时，应静默置为已完成，不打断使用。
    static func shouldMarkCompletedSilently(completedVersion: Int, existingHoldingCount: Int) -> Bool {
        completedVersion < currentVersion && existingHoldingCount > 0
    }

    static func evaluateLaunch(completedVersion: Int, existingHoldingCount: Int) -> AutoLaunchDecision {
        if shouldAutoPresent(completedVersion: completedVersion, existingHoldingCount: existingHoldingCount) {
            return .present
        }
        if shouldMarkCompletedSilently(completedVersion: completedVersion, existingHoldingCount: existingHoldingCount) {
            return .markCompletedSilently
        }
        return .skip
    }
}

/// 3 页暗黑金新手引导内容模型（100% 客观工具表述，不含任何交易或投资建议）。
struct OnboardingStep: Identifiable, Equatable, Sendable {
    enum Kind: Int, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
        case holdings = 0
        case marketChart = 1
        case calendarVault = 2

        var id: Int { rawValue }
    }

    let kind: Kind
    let badge: String
    let title: String
    let subtitle: String
    let highlights: [String]
    let primaryButtonTitle: String
    let secondaryButtonTitle: String?

    var id: Int { kind.rawValue }
    var isFinalStep: Bool { kind == .calendarVault }

    var allCopyStrings: [String] {
        [badge, title, subtitle, primaryButtonTitle] + highlights + (secondaryButtonTitle.map { [$0] } ?? [])
    }

    static var allSteps: [OnboardingStep] {
        [
            OnboardingStep(
                kind: .holdings,
                badge: L10n.tr("01 · 极简记账"),
                title: L10n.tr("记下每一克，算清真实保本价"),
                subtitle: L10n.tr("支持金豆、金条、金饰与积存金，自动计入工费、纯度与回收扣减，一眼看清真实盈亏与保本金价。"),
                highlights: [
                    L10n.tr("4 种黄金形态预设常见纯度与工费"),
                    L10n.tr("按回收规则实时核算预计到手与保本价")
                ],
                primaryButtonTitle: L10n.tr("下一步"),
                secondaryButtonTitle: nil
            ),
            OnboardingStep(
                kind: .marketChart,
                badge: L10n.tr("02 · 行情对照"),
                title: L10n.tr("看懂大盘与你的买入点位"),
                subtitle: L10n.tr("实时切换国内与国际金价走势，同图叠加黄色保本虚线与红色买入点连线，并附黄金温度与美债压力客观读数。"),
                highlights: [
                    L10n.tr("黄色保本虚线与红色买入点清晰对照"),
                    L10n.tr("黄金温度与美债压力基于历史分位客观展示")
                ],
                primaryButtonTitle: L10n.tr("下一步"),
                secondaryButtonTitle: nil
            ),
            OnboardingStep(
                kind: .calendarVault,
                badge: L10n.tr("03 · 攒金陪伴"),
                title: L10n.tr("攒金陪伴日历，见证每一次积累"),
                subtitle: L10n.tr("日历热力记录每日克重轨迹，攒金盒点亮阶段里程碑。本机游客即可直接使用，随时开启多端云同步。"),
                highlights: [
                    L10n.tr("本机游客免登录即用，记录随时可查"),
                    L10n.tr("登录账户即可按需开启多端云同步")
                ],
                primaryButtonTitle: L10n.tr("立刻记下第一笔黄金"),
                secondaryButtonTitle: L10n.tr("先随便逛逛")
            )
        ]
    }

    static var allCopyStrings: [String] {
        allSteps.flatMap(\.allCopyStrings)
    }
}

/// 「3 步开启记金」页内任务项动作标识。
enum QuickStartAction: String, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    case recordFirstHolding
    case viewChartOverlay
    case visitCalendar

    var id: String { rawValue }
}

/// 单个新手任务项展示模型。
struct QuickStartTaskItem: Identifiable, Equatable, Sendable {
    let action: QuickStartAction
    let stepNumber: Int
    let title: String
    let subtitle: String
    let iconName: String
    let isCompleted: Bool

    var id: QuickStartAction { action }
}

/// 「3 步开启记金」页内轻量任务引导卡纯状态模型。
struct QuickStartChecklistState: Equatable, Sendable {
    let hasRecordedHolding: Bool
    let hasViewedChartOverlay: Bool
    let hasVisitedCalendar: Bool

    init(
        hasRecordedHolding: Bool = false,
        hasViewedChartOverlay: Bool = false,
        hasVisitedCalendar: Bool = false
    ) {
        self.hasRecordedHolding = hasRecordedHolding
        self.hasViewedChartOverlay = hasViewedChartOverlay
        self.hasVisitedCalendar = hasVisitedCalendar
    }

    var items: [QuickStartTaskItem] {
        [
            QuickStartTaskItem(
                action: .recordFirstHolding,
                stepNumber: 1,
                title: L10n.tr("记下第一笔黄金"),
                subtitle: L10n.tr("3 秒记录克重与金价，算清真实保本价"),
                iconName: "plus.circle.fill",
                isCompleted: hasRecordedHolding
            ),
            QuickStartTaskItem(
                action: .viewChartOverlay,
                stepNumber: 2,
                title: L10n.tr("在走势图点亮持仓红点"),
                subtitle: L10n.tr("前往行情页开启「持仓」，对照保本线与买入点"),
                iconName: "chart.xyaxis.line",
                isCompleted: hasViewedChartOverlay
            ),
            QuickStartTaskItem(
                action: .visitCalendar,
                stepNumber: 3,
                title: L10n.tr("打开攒金陪伴日历"),
                subtitle: L10n.tr("浏览日历热力与每月克重积累轨迹"),
                iconName: "calendar",
                isCompleted: hasVisitedCalendar
            )
        ]
    }

    var totalCount: Int { items.count }

    var completedCount: Int {
        items.reduce(0) { $0 + ($1.isCompleted ? 1 : 0) }
    }

    var isAllCompleted: Bool {
        completedCount >= totalCount
    }

    var progressFraction: Double {
        guard totalCount > 0 else { return 0 }
        return min(1, max(0, Double(completedCount) / Double(totalCount)))
    }

    var progressBadgeText: String {
        "\(completedCount)/\(totalCount)"
    }

    /// 全部完成或用户主动关闭后优雅隐藏。
    func shouldShowCard(dismissed: Bool) -> Bool {
        !dismissed && !isAllCompleted
    }

    static var allCopyStrings: [String] {
        let sample = QuickStartChecklistState()
        return [L10n.tr("3 步开启记金"), L10n.tr("收起"), L10n.tr("已完成")] + sample.items.flatMap { [$0.title, $0.subtitle] }
    }
}
