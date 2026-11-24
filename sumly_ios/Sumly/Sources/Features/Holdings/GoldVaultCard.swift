import SwiftUI

// MARK: - 纯逻辑模型（Sendable，独立可测）

/// 攒金盒轻量化持仓输入项，便于脱离 SwiftData 单独测试。
struct GoldVaultEntry: Equatable, Sendable {
    let assetType: String
    let grams: Double
    let disposition: String

    init(assetType: String, grams: Double, disposition: String = "holding") {
        self.assetType = assetType
        self.grams = grams
        self.disposition = disposition
    }
}

extension HoldingRecord {
    var vaultEntry: GoldVaultEntry {
        GoldVaultEntry(assetType: assetType, grams: grams, disposition: disposition)
    }
}

/// 攒金阶梯里程碑定义（6 档）。
struct GoldMilestone: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let targetGrams: Double
    let shortLabel: String
    let title: String

    static var ladder: [GoldMilestone] {
        [
            GoldMilestone(id: "1g", targetGrams: 1, shortLabel: L10n.tr("首克"), title: L10n.tr("首克 1g")),
            GoldMilestone(id: "10g", targetGrams: 10, shortLabel: "10g", title: L10n.tr("10g 初成")),
            GoldMilestone(id: "50g", targetGrams: 50, shortLabel: "50g", title: L10n.tr("50g 筑底")),
            GoldMilestone(id: "100g", targetGrams: 100, shortLabel: "100g", title: L10n.tr("100g 小金砖")),
            GoldMilestone(id: "500g", targetGrams: 500, shortLabel: "500g", title: L10n.tr("500g 金库")),
            GoldMilestone(id: "1kg", targetGrams: 1000, shortLabel: "1kg", title: L10n.tr("1kg 典藏"))
        ]
    }
}

/// 里程碑解锁状态与进度模型。
struct GoldMilestoneProgress: Equatable, Sendable {
    let totalGrams: Double
    let unlocked: [GoldMilestone]
    let current: GoldMilestone?
    let next: GoldMilestone?
    let remainingToNext: Double
    let progressRatio: Double

    static func evaluate(totalGrams: Double) -> GoldMilestoneProgress {
        let safeGrams = totalGrams.isFinite ? max(0, totalGrams) : 0
        let unlocked = GoldMilestone.ladder.filter { safeGrams >= $0.targetGrams }
        let next = GoldMilestone.ladder.first { safeGrams < $0.targetGrams }
        let remaining = next.map { max(0, $0.targetGrams - safeGrams) } ?? 0
        let ratio: Double = {
            guard let next, next.targetGrams > 0 else { return 1.0 }
            return min(1.0, max(0.0, safeGrams / next.targetGrams))
        }()
        return GoldMilestoneProgress(
            totalGrams: safeGrams,
            unlocked: unlocked,
            current: unlocked.last,
            next: next,
            remainingToNext: remaining,
            progressRatio: ratio
        )
    }

    func isUnlocked(_ milestone: GoldMilestone) -> Bool {
        totalGrams >= milestone.targetGrams
    }

    /// 计算本次入库后是否刚刚跨越新的里程碑，返回跨越的最高档位。
    static func newlyUnlocked(previousGrams: Double, currentGrams: Double) -> GoldMilestone? {
        let prev = previousGrams.isFinite ? max(0, previousGrams) : 0
        let curr = currentGrams.isFinite ? max(0, currentGrams) : 0
        guard curr > prev else { return nil }
        return GoldMilestone.ladder.last { prev < $0.targetGrams && curr >= $0.targetGrams }
    }
}

/// 攒金盒展示盒内的单个可视化陈列元素。
struct GoldVaultTrayToken: Identifiable, Equatable, Sendable {
    let id: String
    let type: GoldAssetType
}

/// 攒金盒下方分类摘要胶囊。
struct GoldVaultCategoryBadge: Identifiable, Equatable, Sendable {
    let type: GoldAssetType
    let text: String
    var id: String { type.id }
}

/// 「我的攒金盒」纯聚合模型：汇总有效持仓、生成金属陈列元素与里程碑进度。
struct GoldVaultSummary: Equatable, Sendable {
    let totalGrams: Double
    let recordCount: Int

    let barCount: Int
    let barGrams: Double

    let beanCount: Int
    let beanRecordCount: Int
    let beanGrams: Double

    let jewelryCount: Int
    let jewelryGrams: Double

    let accumulationCount: Int
    let accumulationGrams: Double

    let otherCount: Int
    let otherGrams: Double

    let milestone: GoldMilestoneProgress

    var isEmpty: Bool { recordCount == 0 || totalGrams <= 0 }

    /// 展示盒内的总陈列件数（金条根数 + 金豆颗数 + 金饰件数 + 积存金卡(0或1) + 其他件数）。
    var totalDisplayPieces: Int {
        barCount + beanCount + jewelryCount + (accumulationGrams > 0 ? 1 : 0) + otherCount
    }

    init(entries: [GoldVaultEntry]) {
        let active = entries.filter { $0.disposition == "holding" && $0.grams.isFinite && $0.grams > 0 }
        var total = 0.0
        var bars = 0, barG = 0.0
        var beanRecords = 0, beanG = 0.0
        var jewelries = 0, jewelryG = 0.0
        var accs = 0, accG = 0.0
        var others = 0, otherG = 0.0

        for entry in active {
            total += entry.grams
            switch GoldAssetType(rawValue: entry.assetType) ?? .other {
            case .bar:
                bars += 1
                barG += entry.grams
            case .bean:
                beanRecords += 1
                beanG += entry.grams
            case .jewelry:
                jewelries += 1
                jewelryG += entry.grams
            case .accumulation:
                accs += 1
                accG += entry.grams
            case .other:
                others += 1
                otherG += entry.grams
            }
        }

        // 金豆常按克攒买（例如一笔 3g 代表 3 颗 1g 金豆），按向下取整与笔数较大值陈列颗数。
        let displayBeans = beanRecords == 0 ? 0 : max(beanRecords, Int(beanG.rounded(.down)))

        self.totalGrams = total
        self.recordCount = active.count
        self.barCount = bars
        self.barGrams = barG
        self.beanCount = displayBeans
        self.beanRecordCount = beanRecords
        self.beanGrams = beanG
        self.jewelryCount = jewelries
        self.jewelryGrams = jewelryG
        self.accumulationCount = accs
        self.accumulationGrams = accG
        self.otherCount = others
        self.otherGrams = otherG
        self.milestone = GoldMilestoneProgress.evaluate(totalGrams: total)
    }

    @MainActor init(records: [HoldingRecord]) {
        self.init(entries: records.map(\.vaultEntry))
    }

    /// 生成展示盒可见陈列元素列表；数量超过上限时优先保留各已持有品类代表，再展示 `+N` 折叠角标。
    func visibleTrayTokens(limit: Int = 9) -> (tokens: [GoldVaultTrayToken], overflowCount: Int) {
        let cap = max(1, limit)
        let groups: [(GoldAssetType, Int)] = [
            (.bar, barCount),
            (.bean, beanCount),
            (.jewelry, jewelryCount),
            (.accumulation, accumulationGrams > 0 ? 1 : 0),
            (.other, otherCount)
        ].filter { $0.1 > 0 }

        let totalPieces = groups.reduce(0) { $0 + $1.1 }
        guard totalPieces > 0 else { return ([], 0) }

        if totalPieces <= cap {
            var tokens: [GoldVaultTrayToken] = []
            for (type, count) in groups {
                for index in 0..<count {
                    tokens.append(GoldVaultTrayToken(id: "\(type.rawValue)-\(index)", type: type))
                }
            }
            return (tokens, 0)
        }

        // 超过上限：先为每个非空品类分配 1 个展位，再按顺序填充剩余展位。
        var allocations: [GoldAssetType: Int] = [:]
        var remaining = cap
        for (type, _) in groups {
            guard remaining > 0 else { break }
            allocations[type] = 1
            remaining -= 1
        }
        for (type, count) in groups {
            guard remaining > 0 else { break }
            let extra = min(count - (allocations[type] ?? 0), remaining)
            if extra > 0 {
                allocations[type, default: 0] += extra
                remaining -= extra
            }
        }

        var tokens: [GoldVaultTrayToken] = []
        for (type, _) in groups {
            let count = allocations[type] ?? 0
            for index in 0..<count {
                tokens.append(GoldVaultTrayToken(id: "\(type.rawValue)-\(index)", type: type))
            }
        }
        return (tokens, max(0, totalPieces - tokens.count))
    }

    func formattedTotalGrams(hideAmounts: Bool) -> String {
        if hideAmounts { return "•••• g" }
        return "\(Self.formatGrams(totalGrams)) g"
    }

    func milestoneHeadline(hideAmounts: Bool) -> String {
        if hideAmounts {
            return L10n.tr("里程碑进度已隐藏")
        }
        if let next = milestone.next {
            return L10n.fmt("距「%@」还差 %@ g", next.title, Self.formatGrams(milestone.remainingToNext))
        }
        return L10n.tr("已点亮全部 6 档里程碑")
    }

    func progressPercentText(hideAmounts: Bool) -> String {
        if hideAmounts { return "••%" }
        return "\(Int((milestone.progressRatio * 100).rounded()))%"
    }

    func categoryBadges(hideAmounts: Bool) -> [GoldVaultCategoryBadge] {
        var badges: [GoldVaultCategoryBadge] = []
        if barCount > 0 {
            let text = hideAmounts ? L10n.tr("金条 ••••") : L10n.fmt("金条 %lld根 · %@g", Int64(barCount), Self.formatGrams(barGrams))
            badges.append(GoldVaultCategoryBadge(type: .bar, text: text))
        }
        if beanCount > 0 {
            let text = hideAmounts ? L10n.tr("金豆 ••••") : L10n.fmt("金豆 %lld颗 · %@g", Int64(beanCount), Self.formatGrams(beanGrams))
            badges.append(GoldVaultCategoryBadge(type: .bean, text: text))
        }
        if jewelryCount > 0 {
            let text = hideAmounts ? L10n.tr("金饰 ••••") : L10n.fmt("金饰 %lld件 · %@g", Int64(jewelryCount), Self.formatGrams(jewelryGrams))
            badges.append(GoldVaultCategoryBadge(type: .jewelry, text: text))
        }
        if accumulationGrams > 0 {
            let text = hideAmounts ? L10n.tr("积存金 ••••") : L10n.fmt("积存金 %@g", Self.formatGrams(accumulationGrams))
            badges.append(GoldVaultCategoryBadge(type: .accumulation, text: text))
        }
        if otherCount > 0 {
            let text = hideAmounts ? L10n.tr("其他 ••••") : L10n.fmt("其他 %lld笔 · %@g", Int64(otherCount), Self.formatGrams(otherGrams))
            badges.append(GoldVaultCategoryBadge(type: .other, text: text))
        }
        return badges
    }

    static func formatGrams(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.005 {
            return String(Int(value.rounded()))
        }
        return value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }
}

// MARK: - 视图组件：「我的攒金盒 + 里程碑」卡片

struct GoldVaultCard: View {
    let summary: GoldVaultSummary
    let hideAmounts: Bool
    var onAddTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            showcaseTray
            if !summary.isEmpty {
                categoryStrip
            }
            milestoneSection
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [GoldTheme.card, GoldTheme.card, GoldTheme.background.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: GoldTheme.holdingsCardShape
        )
        .overlay(
            GoldTheme.holdingsCardShape.strokeBorder(
                LinearGradient(
                    colors: [GoldTheme.gold.opacity(0.32), GoldTheme.cardStroke, GoldTheme.cardStroke],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        )
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GoldTheme.gold)
                Text(L10n.tr("我的攒金盒"))
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.text)
            }
            if let unlocked = summary.milestone.current, !hideAmounts {
                Text(unlocked.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(GoldTheme.onGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(GoldTheme.goldSoft, in: GoldTheme.capsuleShape)
            } else if hideAmounts, !summary.isEmpty {
                Text(L10n.tr("隐私保护"))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(GoldTheme.goldSoft)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(GoldTheme.calendarCell, in: GoldTheme.capsuleShape)
                    .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
            }
            Spacer(minLength: 4)
            Text(summary.formattedTotalGrams(hideAmounts: hideAmounts))
                .font(.system(.subheadline, design: .rounded).bold())
                .monospacedDigit()
                .foregroundStyle(GoldTheme.gold)
        }
    }

    private var showcaseTray: some View {
        let tray = summary.visibleTrayTokens(limit: 7)
        return ZStack {
            // 暗黑金绒面展示盒背景
            GoldTheme.subCardShape
                .fill(GoldTheme.background)
                .overlay(
                    RadialGradient(
                        colors: [GoldTheme.gold.opacity(0.11), .clear],
                        center: .top,
                        startRadius: 4,
                        endRadius: 140
                    )
                    .clipShape(GoldTheme.subCardShape)
                )
                .overlay(
                    GoldTheme.subCardShape.strokeBorder(
                        LinearGradient(
                            colors: [GoldTheme.gold.opacity(0.24), GoldTheme.cardStroke],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                )

            if summary.isEmpty {
                emptyTrayContent
            } else if hideAmounts {
                privacyTrayContent
            } else {
                HStack(spacing: 7) {
                    ForEach(tray.tokens) { token in
                        GoldAssetGlyph(type: token.type, size: 28, emphasized: true)
                    }
                    if tray.overflowCount > 0 {
                        Text("+\(tray.overflowCount)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(GoldTheme.goldSoft)
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(GoldTheme.card, in: GoldTheme.capsuleShape)
                            .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.45), lineWidth: 1))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58)
    }

    private var emptyTrayContent: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                GoldAssetGlyph(type: .bean, size: 24, emphasized: false).opacity(0.55)
                GoldAssetGlyph(type: .bar, size: 24, emphasized: false).opacity(0.55)
            }
            Text(L10n.tr("存入第一颗金豆或金条，点亮专属攒金盒"))
                .font(.caption)
                .foregroundStyle(GoldTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            if let onAddTap {
                Button(L10n.tr("去入库"), action: onAddTap)
                    .font(.caption2.bold())
                    .foregroundStyle(GoldTheme.onGold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(GoldTheme.gold, in: GoldTheme.capsuleShape)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var privacyTrayContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(GoldTheme.goldSoft)
            Text(L10n.tr("隐私模式已开启 · 已隐藏藏品数量与克重"))
                .font(.caption)
                .foregroundStyle(GoldTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(summary.categoryBadges(hideAmounts: hideAmounts)) { badge in
                    HStack(spacing: 5) {
                        GoldAssetGlyph(type: badge.type, size: 15, emphasized: true)
                        Text(badge.text)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.text)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(GoldTheme.calendarCell, in: GoldTheme.capsuleShape)
                    .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
                }
            }
        }
    }

    private var milestoneSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(summary.milestoneHeadline(hideAmounts: hideAmounts))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(GoldTheme.goldSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(summary.progressPercentText(hideAmounts: hideAmounts))
                    .font(.system(.caption, design: .rounded).bold())
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.gold)
            }

            GeometryReader { geo in
                let ratio = hideAmounts ? 0.0 : summary.milestone.progressRatio
                ZStack(alignment: .leading) {
                    GoldTheme.capsuleShape
                        .fill(GoldTheme.background)
                    if ratio > 0 {
                        GoldTheme.capsuleShape
                            .fill(
                                LinearGradient(
                                    colors: [GoldTheme.tempWarm, GoldTheme.gold, GoldTheme.goldSoft],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * ratio))
                    }
                }
            }
            .frame(height: 7)
            .animation(.easeOut(duration: 0.25), value: summary.milestone.progressRatio)

            // 6 档里程碑徽章条
            HStack(spacing: 5) {
                ForEach(GoldMilestone.ladder) { tier in
                    let unlocked = !hideAmounts && summary.milestone.isUnlocked(tier)
                    let isNext = !hideAmounts && summary.milestone.next?.id == tier.id
                    HStack(spacing: 3) {
                        if unlocked {
                            Image(systemName: "sparkles")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(GoldTheme.gold)
                        }
                        Text(tier.shortLabel)
                            .font(.system(size: 10, weight: unlocked ? .bold : .medium, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(
                        unlocked ? GoldTheme.goldSoft :
                        isNext ? GoldTheme.text :
                        GoldTheme.textFaint
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        unlocked ? GoldTheme.gold.opacity(0.16) : GoldTheme.background,
                        in: GoldTheme.rangeShape
                    )
                    .overlay(
                        GoldTheme.rangeShape.strokeBorder(
                            unlocked ? GoldTheme.gold.opacity(0.55) :
                            isNext ? GoldTheme.goldSoft.opacity(0.32) :
                            GoldTheme.cardStroke,
                            lineWidth: unlocked ? 1 : 0.8
                        )
                    )
                }
            }
        }
    }
}
