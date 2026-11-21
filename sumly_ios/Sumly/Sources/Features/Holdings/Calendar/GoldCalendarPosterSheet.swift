import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - 海报数据快照（Sendable）

enum GoldCalendarPosterMode: String, CaseIterable, Identifiable, Sendable {
    case monthly = "月度日历"
    case yearly = "年度热力"

    var id: String { rawValue }
}

struct GoldCalendarPosterSnapshot: Equatable, Sendable {
    let year: Int
    let month: Int
    let monthSummary: GoldCalendarMonthSummary
    let yearSnapshot: GoldCalendarYearSnapshot
    let companion: GoldCalendarCompanionStats
    let basis: GoldMarketBasis
    let layer: GoldCalendarLayer
    let maskSensitiveAmounts: Bool

    var hasHoldings: Bool {
        companion.hasAnyRecords
    }

    var isPnLView: Bool {
        hasHoldings && layer == .pnl
    }

    var monthlyBuySubtitle: String? {
        guard isPnLView, !maskSensitiveAmounts, monthSummary.newBuyGrams > 1e-9 else { return nil }
        return "本月新攒 +\(GoldVaultSummary.formatGrams(monthSummary.newBuyGrams))g"
    }

    var yearlyBuySubtitle: String? {
        guard hasHoldings, !maskSensitiveAmounts, yearSnapshot.totalBuyGrams > 1e-9 else { return nil }
        return "新攒 +\(GoldVaultSummary.formatGrams(yearSnapshot.totalBuyGrams))g · \(yearSnapshot.totalBuyCount)笔"
    }
}

struct GoldCalendarShareImage: Transferable, Sendable {
    let pngData: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.pngData
        }
    }
}

enum GoldCalendarPosterRenderer {
    @MainActor
    static func renderImage(
        snapshot: GoldCalendarPosterSnapshot,
        mode: GoldCalendarPosterMode,
        width: CGFloat = 340,
        scale: CGFloat = 3.0
    ) -> UIImage? {
        let card = GoldCalendarPosterCardView(snapshot: snapshot, mode: mode)
            .frame(width: width)
            .padding(18)
            .background(GoldTheme.background)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: card)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }

    @MainActor
    static func renderShareImage(
        snapshot: GoldCalendarPosterSnapshot,
        mode: GoldCalendarPosterMode,
        width: CGFloat = 340,
        scale: CGFloat = 3.0
    ) -> GoldCalendarShareImage? {
        guard let image = renderImage(snapshot: snapshot, mode: mode, width: width, scale: scale),
              let data = image.pngData() else { return nil }
        return GoldCalendarShareImage(pngData: data)
    }
}

// MARK: - 暗黑金日历海报主体（同时用于弹窗预览与高清图导出）

struct GoldCalendarPosterCardView: View {
    let snapshot: GoldCalendarPosterSnapshot
    let mode: GoldCalendarPosterMode

    private var hideAmounts: Bool { snapshot.maskSensitiveAmounts }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            posterHeader
            if mode == .monthly {
                monthlyHeroSection
                monthlyMiniCalendar
            } else {
                yearlyHeroSection
                yearlyCompactHeatmap
            }
            posterDivider
            posterFooter
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [GoldTheme.card, GoldTheme.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: GoldTheme.cardShape
        )
        .overlay(
            GoldTheme.cardShape.strokeBorder(
                LinearGradient(
                    colors: [GoldTheme.goldSoft.opacity(0.65), GoldTheme.gold.opacity(0.26), GoldTheme.cardStroke],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.2
            )
        )
    }

    private var posterHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GoldTheme.gold)
                Text("记金 · 攒金陪伴日历")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.goldSoft)
            }

            Spacer(minLength: 4)

            Text(GoldCalendarFormat.headerCompanionBadge(companionDays: snapshot.companion.companionDays, hasRecords: snapshot.hasHoldings))
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(GoldTheme.onGold)
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(
                    LinearGradient(
                        colors: [GoldTheme.goldSoft, GoldTheme.gold],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: GoldTheme.capsuleShape
                )
        }
    }

    // MARK: 月度海报区块

    private var monthlyHeroSection: some View {
        let m = snapshot.monthSummary
        let isPnL = snapshot.isPnLView
        let redDays = isPnL ? m.pnlRedDays : m.marketRedDays
        let greenDays = isPnL ? m.pnlGreenDays : m.marketGreenDays

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(String(snapshot.year))年\(snapshot.month)月 战报")
                    .font(.system(.headline, design: .rounded).bold())
                    .foregroundStyle(GoldTheme.text)
                Spacer()
                if hideAmounts && isPnL {
                    Text("隐私脱敏版")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(GoldTheme.goldSoft)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(GoldTheme.calendarCell, in: GoldTheme.capsuleShape)
                }
            }

            if isPnL && hideAmounts {
                // 隐私开启时：以红绿天数战绩作为核心视觉，大方高级不堆砌遮罩符。
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    HStack(spacing: 3) {
                        Text("红")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(GoldTheme.textSecondary)
                        Text("\(redDays)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.up)
                        Text("天")
                            .font(.caption)
                            .foregroundStyle(GoldTheme.textSecondary)
                    }

                    Text("·")
                        .font(.title3.bold())
                        .foregroundStyle(GoldTheme.textFaint)

                    HStack(spacing: 3) {
                        Text("绿")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(GoldTheme.textSecondary)
                        Text("\(greenDays)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.down)
                        Text("天")
                            .font(.caption)
                            .foregroundStyle(GoldTheme.textSecondary)
                    }

                    Spacer()
                }
            } else {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isPnL ? "本月预估盈亏" : "本月金价涨跌")
                            .font(.caption2)
                            .foregroundStyle(GoldTheme.textSecondary)
                        let dir = isPnL
                            ? GoldCalendarDirection.from(m.totalPnL)
                            : GoldCalendarDirection.from(m.marketMonthChangePercent)
                        let color: Color = dir == .up ? GoldTheme.up : dir == .down ? GoldTheme.down : GoldTheme.text
                        Text(
                            isPnL
                                ? GoldCalendarFormat.signedCurrency(m.totalPnL, hideAmounts: false)
                                : GoldCalendarFormat.signedPercent(m.marketMonthChangePercent)
                        )
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 5) {
                            Text("红 \(redDays)天").foregroundStyle(GoldTheme.up).fontWeight(.bold)
                            Text("·").foregroundStyle(GoldTheme.textFaint)
                            Text("绿 \(greenDays)天").foregroundStyle(GoldTheme.down).fontWeight(.bold)
                        }
                        .font(.system(size: 11.5, design: .rounded))
                        .monospacedDigit()

                        if let buySubtitle = snapshot.monthlyBuySubtitle {
                            Text(buySubtitle)
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .foregroundStyle(GoldTheme.goldSoft)
                        }
                    }
                }
            }

            GoldCalendarRatioBar(redCount: redDays, greenCount: greenDays)
                .frame(height: 6)
        }
        .padding(12)
        .background(GoldTheme.background.opacity(0.85), in: GoldTheme.subCardShape)
        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    private var monthlyMiniCalendar: some View {
        let monthDate = CalendarDayKey(year: snapshot.year, month: snapshot.month, day: 1).noonDate()
        let rawDays = HoldingCalendarLogic.days(in: monthDate)
        let gridDays: [Date] = {
            guard rawDays.count == 42 else { return rawDays }
            let hasSixth = rawDays[35..<42].contains { d in
                let k = CalendarDayKey(date: d)
                return k.year == snapshot.year && k.month == snapshot.month
            }
            return hasSixth ? rawDays : Array(rawDays[0..<35])
        }()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(GoldTheme.textFaint)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(gridDays, id: \.self) { day in
                    let key = CalendarDayKey(date: day)
                    let inMonth = (key.year == snapshot.year && key.month == snapshot.month)
                    let daySnap = inMonth ? snapshot.yearSnapshot.daysByKey[key] : nil
                    posterDayCell(dayKey: key, inMonth: inMonth, snap: daySnap)
                }
            }
        }
        .padding(10)
        .background(GoldTheme.background.opacity(0.7), in: GoldTheme.subCardShape)
        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    private func posterDayCell(dayKey: CalendarDayKey, inMonth: Bool, snap: GoldCalendarDaySnapshot?) -> some View {
        let isPnL = snapshot.isPnLView
        let heatColor: Color = {
            guard inMonth, let snap, snap.status == .trading else { return .clear }
            if isPnL {
                guard let pnl = snap.dailyPnL else { return .clear }
                let dir = GoldCalendarDirection.from(pnl)
                guard dir != .flat else { return .clear }
                let base = dir == .up ? GoldTheme.up : GoldTheme.down
                if hideAmounts { return base.opacity(0.16) }
                let level = snap.pnlHeatLevel == .none ? .mild : snap.pnlHeatLevel
                return base.opacity(level.fillOpacity + 0.04)
            } else {
                guard let pct = snap.marketChangePercent else { return .clear }
                let dir = GoldCalendarDirection.from(pct)
                guard dir != .flat else { return .clear }
                let base = dir == .up ? GoldTheme.up : GoldTheme.down
                let level = snap.marketHeatLevel == .none ? .mild : snap.marketHeatLevel
                return base.opacity(level.fillOpacity + 0.04)
            }
        }()

        let subLabel: String = {
            guard inMonth, let snap, snap.status == .trading else { return "" }
            if isPnL {
                return GoldCalendarFormat.compactCellPnL(snap.dailyPnL, hideAmounts: hideAmounts)
            }
            return GoldCalendarFormat.compactCellPercent(snap.marketChangePercent)
        }()

        let subColor: Color = {
            guard inMonth, let snap, snap.status == .trading else { return GoldTheme.textFaint }
            let dir = isPnL ? snap.pnlDirection : snap.marketDirection
            switch dir {
            case .up: return GoldTheme.up
            case .down: return GoldTheme.down
            case .flat: return GoldTheme.textSecondary
            }
        }()

        return VStack(spacing: 1.5) {
            HStack(spacing: 1) {
                Text(inMonth ? "\(dayKey.day)" : "")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(inMonth ? (snap?.status == .future ? GoldTheme.textFaint.opacity(0.45) : GoldTheme.text) : .clear)
                Spacer(minLength: 0)
                if inMonth, let snap {
                    if snap.hasMilestone && !hideAmounts {
                        Image(systemName: "sparkles")
                            .font(.system(size: 6.5, weight: .bold))
                            .foregroundStyle(GoldTheme.goldSoft)
                    } else if snap.hasBuy {
                        GoldTheme.circleShape.fill(GoldTheme.gold).frame(width: 4, height: 4)
                    }
                }
            }
            .padding(.horizontal, 3)

            Text(subLabel)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(subColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(
            ZStack {
                GoldTheme.rangeShape.fill(inMonth ? GoldTheme.calendarCell.opacity(0.75) : GoldTheme.background.opacity(0.3))
                GoldTheme.rangeShape.fill(heatColor)
            }
        )
    }

    // MARK: 年度海报区块

    private var yearlyHeroSection: some View {
        let y = snapshot.yearSnapshot
        let isPnL = snapshot.hasHoldings && y.totalPnL != nil
        let redDays = isPnL ? y.pnlRedDays : y.marketRedDays
        let greenDays = isPnL ? y.pnlGreenDays : y.marketGreenDays

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(String(y.year))年 攒金足迹")
                    .font(.system(.headline, design: .rounded).bold())
                    .foregroundStyle(GoldTheme.text)
                Spacer()
                if hideAmounts && isPnL {
                    Text("隐私脱敏版")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(GoldTheme.goldSoft)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(GoldTheme.calendarCell, in: GoldTheme.capsuleShape)
                }
            }

            if isPnL && hideAmounts {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text("红 \(redDays)天")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(GoldTheme.up)
                    Text("·")
                        .font(.title3.bold())
                        .foregroundStyle(GoldTheme.textFaint)
                    Text("绿 \(greenDays)天")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(GoldTheme.down)
                    Spacer()
                }
                .monospacedDigit()
            } else {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isPnL ? "年度预估盈亏" : "年度金价涨跌")
                            .font(.caption2)
                            .foregroundStyle(GoldTheme.textSecondary)
                        let dir = isPnL
                            ? GoldCalendarDirection.from(y.totalPnL)
                            : GoldCalendarDirection.from(y.marketYearChangePercent)
                        let color: Color = dir == .up ? GoldTheme.up : dir == .down ? GoldTheme.down : GoldTheme.text
                        Text(
                            isPnL
                                ? GoldCalendarFormat.signedCurrency(y.totalPnL, hideAmounts: false)
                                : GoldCalendarFormat.signedPercent(y.marketYearChangePercent)
                        )
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("红 \(redDays)天 · 绿 \(greenDays)天")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.textSecondary)
                        if let buySubtitle = snapshot.yearlyBuySubtitle {
                            Text(buySubtitle)
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(GoldTheme.goldSoft)
                        }
                    }
                }
            }

            GoldCalendarRatioBar(redCount: redDays, greenCount: greenDays)
                .frame(height: 6)
        }
        .padding(12)
        .background(GoldTheme.background.opacity(0.85), in: GoldTheme.subCardShape)
        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    private var yearlyCompactHeatmap: some View {
        let weeks = snapshot.yearSnapshot.weeks
        return VStack(alignment: .leading, spacing: 8) {
            Text("52 周红绿热力足迹")
                .font(.caption2.weight(.medium))
                .foregroundStyle(GoldTheme.textSecondary)

            // 将 53 周紧凑排版在海报宽度内，无需横向裁剪。
            HStack(spacing: 1.5) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 1.5) {
                        ForEach(week) { cell in
                            GoldTheme.rangeShape
                                .fill(posterYearCellColor(cell))
                                .frame(height: 4.5)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // 12 个月极简红绿条带
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                ForEach(snapshot.yearSnapshot.monthSummaries) { m in
                    let usePnL = snapshot.hasHoldings && m.totalPnL != nil
                    let dir = usePnL ? GoldCalendarDirection.from(m.totalPnL) : GoldCalendarDirection.from(m.marketMonthChangePercent)
                    let dotColor: Color = dir == .up ? GoldTheme.up : dir == .down ? GoldTheme.down : GoldTheme.textFaint
                    HStack(spacing: 3) {
                        GoldTheme.circleShape.fill(dotColor).frame(width: 5, height: 5)
                        Text("\(m.month)月")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(GoldTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(GoldTheme.calendarCell.opacity(0.6), in: GoldTheme.rangeShape)
                }
            }
        }
        .padding(10)
        .background(GoldTheme.background.opacity(0.75), in: GoldTheme.subCardShape)
        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    private func posterYearCellColor(_ cell: GoldCalendarYearHeatCell) -> Color {
        guard cell.inTargetYear, let snap = cell.snapshot else { return .clear }
        if snap.status == .future { return GoldTheme.background.opacity(0.35) }
        guard snap.status == .trading else { return GoldTheme.calendarCell.opacity(0.55) }
        if snapshot.hasHoldings {
            guard let pnl = snap.dailyPnL else { return GoldTheme.calendarCell.opacity(0.7) }
            let dir = GoldCalendarDirection.from(pnl)
            guard dir != .flat else { return GoldTheme.calendarCell.opacity(0.8) }
            let base = dir == .up ? GoldTheme.up : GoldTheme.down
            if hideAmounts { return base.opacity(0.45) }
            switch snap.pnlHeatLevel {
            case .none, .mild: return base.opacity(0.38)
            case .medium: return base.opacity(0.65)
            case .strong: return base.opacity(0.95)
            }
        } else {
            guard let pct = snap.marketChangePercent else { return GoldTheme.calendarCell.opacity(0.7) }
            let dir = GoldCalendarDirection.from(pct)
            guard dir != .flat else { return GoldTheme.calendarCell.opacity(0.8) }
            let base = dir == .up ? GoldTheme.up : GoldTheme.down
            switch snap.marketHeatLevel {
            case .none, .mild: return base.opacity(0.38)
            case .medium: return base.opacity(0.65)
            case .strong: return base.opacity(0.95)
            }
        }
    }

    private var posterDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, GoldTheme.gold.opacity(0.35), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    private var posterFooter: some View {
        HStack {
            Text(snapshot.basis == .international ? "慢慢攒金，稳稳发光 · 国际口径按当前汇率折算参考" : "慢慢攒金，稳稳发光 · 预估盈亏仅作客观记录参考")
                .font(.system(size: 8.5))
                .foregroundStyle(GoldTheme.textFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Text("Sumly")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(GoldTheme.gold.opacity(0.8))
        }
    }
}

// MARK: - 分享海报弹窗（默认开启隐私脱敏开关）

struct GoldCalendarPosterSheet: View {
    let baseSnapshot: GoldCalendarPosterSnapshot
    let initialMode: GoldCalendarPosterMode

    @Environment(\.dismiss) private var dismiss
    @State private var mode: GoldCalendarPosterMode
    /// 分享海报默认开启脱敏，防止误晒具体金额与克重。
    @State private var maskSensitiveAmounts = true
    @State private var shareItem: GoldCalendarShareImage?
    @State private var previewImage: UIImage?
    @State private var sharePulse = 0

    init(snapshot: GoldCalendarPosterSnapshot, initialMode: GoldCalendarPosterMode = .monthly) {
        self.baseSnapshot = snapshot
        self.initialMode = initialMode
        _mode = State(initialValue: initialMode)
        _maskSensitiveAmounts = State(initialValue: true)
    }

    private var effectiveSnapshot: GoldCalendarPosterSnapshot {
        GoldCalendarPosterSnapshot(
            year: baseSnapshot.year,
            month: baseSnapshot.month,
            monthSummary: baseSnapshot.monthSummary,
            yearSnapshot: baseSnapshot.yearSnapshot,
            companion: baseSnapshot.companion,
            basis: baseSnapshot.basis,
            layer: baseSnapshot.layer,
            maskSensitiveAmounts: maskSensitiveAmounts
        )
    }

    private var renderTaskID: String {
        "\(mode.rawValue)-\(maskSensitiveAmounts)-\(baseSnapshot.year)-\(baseSnapshot.month)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 模式切换：月度 / 年度
                    HStack(spacing: 4) {
                        ForEach(GoldCalendarPosterMode.allCases) { item in
                            let selected = (mode == item)
                            Button {
                                mode = item
                            } label: {
                                Text(item.rawValue + "海报")
                                    .font(.system(.subheadline, design: .rounded).weight(selected ? .bold : .medium))
                                    .foregroundStyle(selected ? GoldTheme.onGold : GoldTheme.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(selected ? GoldTheme.gold : Color.clear, in: GoldTheme.capsuleShape)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(GoldTheme.card, in: GoldTheme.capsuleShape)
                    .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))

                    // 默认开启的隐私脱敏开关
                    Toggle(isOn: $maskSensitiveAmounts) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("隐藏具体金额与克重")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(GoldTheme.text)
                            Text("仅晒红绿战绩、热力分布与陪伴天数")
                                .font(.caption2)
                                .foregroundStyle(GoldTheme.textSecondary)
                        }
                    }
                    .tint(GoldTheme.gold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(GoldTheme.card, in: GoldTheme.subCardShape)
                    .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))

                    // 海报实时预览
                    GoldCalendarPosterCardView(snapshot: effectiveSnapshot, mode: mode)
                        .shadow(color: GoldTheme.tabBarShadow, radius: 18, y: 10)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(GoldTheme.background)
            .navigationTitle("日历战报海报")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GoldTheme.textSecondary)
                    }
                    .accessibilityLabel("关闭")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if let shareItem, let previewImage {
                        ShareLink(
                            item: shareItem,
                            preview: SharePreview(
                                "记金 · \(String(baseSnapshot.year))年\(mode == .monthly ? "\(baseSnapshot.month)月" : "")攒金日历",
                                image: Image(uiImage: previewImage)
                            )
                        ) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                Text("分享 / 保存高清海报")
                            }
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(GoldTheme.onGold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(GoldTheme.gold, in: GoldTheme.capsuleShape)
                        }
                        .simultaneousGesture(TapGesture().onEnded { sharePulse += 1 })
                    } else {
                        ProgressView("正在生成海报…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(GoldTheme.card, in: GoldTheme.capsuleShape)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(GoldTheme.background)
            }
        }
        .tint(GoldTheme.gold)
        .presentationBackground(GoldTheme.background)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.impact(weight: .light), trigger: sharePulse)
        .task(id: renderTaskID) {
            let rendered = GoldCalendarPosterRenderer.renderImage(snapshot: effectiveSnapshot, mode: mode)
            previewImage = rendered
            if let data = rendered?.pngData() {
                shareItem = GoldCalendarShareImage(pngData: data)
            }
        }
    }
}
