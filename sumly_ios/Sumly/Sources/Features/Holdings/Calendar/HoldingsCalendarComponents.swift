import SwiftUI

// MARK: - 1. 顶部陪伴头与 3 档分段视图栏

struct GoldCalendarHeaderView: View {
    let companionDays: Int
    let hasRecords: Bool
    let showTodayButton: Bool
    let hasActiveFilter: Bool
    let onTodayTap: () -> Void
    let onShareTap: () -> Void
    let onFilterTap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("攒金日历")
                .font(.title3.bold())
                .foregroundStyle(GoldTheme.text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: 4) {
                Image(systemName: hasRecords ? "sparkles" : "waveform.path.ecg")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(GoldTheme.gold)
                Text(GoldCalendarFormat.headerCompanionBadge(companionDays: companionDays, hasRecords: hasRecords))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.goldSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(GoldTheme.card, in: GoldTheme.capsuleShape)
            .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.32), lineWidth: 1))
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                if showTodayButton {
                    Button(action: onTodayTap) {
                        Text("今")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(GoldTheme.gold)
                            .frame(width: 32, height: 32)
                            .background(GoldTheme.card, in: GoldTheme.circleShape)
                            .overlay(GoldTheme.circleShape.strokeBorder(GoldTheme.gold.opacity(0.45), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("回到今天")
                }

                Button(action: onShareTap) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(GoldTheme.goldSoft)
                        .frame(width: 32, height: 32)
                        .background(GoldTheme.card, in: GoldTheme.circleShape)
                        .overlay(GoldTheme.circleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("分享日历海报")

                Button(action: onFilterTap) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(hasActiveFilter ? GoldTheme.gold : GoldTheme.text)
                            .frame(width: 32, height: 32)
                            .background(GoldTheme.card, in: GoldTheme.circleShape)
                            .overlay(
                                GoldTheme.circleShape.strokeBorder(
                                    hasActiveFilter ? GoldTheme.gold.opacity(0.55) : GoldTheme.cardStroke,
                                    lineWidth: 1
                                )
                            )
                        if hasActiveFilter {
                            GoldTheme.circleShape
                                .fill(GoldTheme.gold)
                                .frame(width: 7, height: 7)
                                .offset(x: -1, y: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("筛选记录")
            }
        }
    }
}

struct GoldCalendarSegmentedBar: View {
    @Binding var activeTab: GoldCalendarViewTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(GoldCalendarViewTab.allCases) { tab in
                let selected = (activeTab == tab)
                Button {
                    activeTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(.subheadline, design: .rounded).weight(selected ? .bold : .medium))
                        .foregroundStyle(selected ? GoldTheme.onGold : GoldTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            selected ? GoldTheme.gold : Color.clear,
                            in: GoldTheme.capsuleShape
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(GoldTheme.card, in: GoldTheme.capsuleShape)
        .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }
}

// MARK: - 2. 紧凑「月度战报卡」（~96pt，首屏同屏装下战报 + 完整月历）

struct GoldCalendarMonthReportCard: View {
    let summary: GoldCalendarMonthSummary
    let companion: GoldCalendarCompanionStats
    let layer: GoldCalendarLayer
    let basis: GoldMarketBasis
    let hideAmounts: Bool

    private var isPnLMode: Bool {
        layer == .pnl && companion.hasAnyRecords
    }

    private var redDays: Int {
        isPnLMode ? summary.pnlRedDays : summary.marketRedDays
    }

    private var greenDays: Int {
        isPnLMode ? summary.pnlGreenDays : summary.marketGreenDays
    }

    private var headlineColor: Color {
        if isPnLMode {
            if hideAmounts { return GoldTheme.textSecondary }
            switch GoldCalendarDirection.from(summary.totalPnL) {
            case .up: return GoldTheme.up
            case .down: return GoldTheme.down
            case .flat: return GoldTheme.text
            }
        } else {
            switch GoldCalendarDirection.from(summary.marketMonthChangePercent) {
            case .up: return GoldTheme.up
            case .down: return GoldTheme.down
            case .flat: return GoldTheme.text
            }
        }
    }

    private var subtitleText: String {
        if isPnLMode {
            if summary.newBuyGrams > 1e-9 {
                if hideAmounts {
                    return "本月新攒 •••• · \(summary.newBuyCount)笔"
                }
                return "本月新攒 +\(GoldVaultSummary.formatGrams(summary.newBuyGrams))g · \(summary.newBuyCount)笔"
            }
            if hideAmounts {
                return "在库 •••• · 陪伴第 \(max(1, companion.companionDays)) 天"
            }
            return "在库 \(GoldVaultSummary.formatGrams(summary.endOfMonthHoldingGrams))g · 陪伴第 \(max(1, companion.companionDays)) 天"
        } else {
            if let ref = summary.latestReferencePriceCNY {
                return "\(basis.title)参考价 ¥\(ref.moneyText)/g"
            }
            return "\(basis.title)行情加载中"
        }
    }

    private var bannerText: String? {
        GoldCalendarFormat.monthCompanionBanner(
            monthSummary: summary,
            companion: companion,
            hideAmounts: hideAmounts
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isPnLMode ? "\(summary.month)月预估盈亏" : "\(summary.month)月金价涨跌")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(GoldTheme.textSecondary)

                    Text(
                        isPnLMode
                            ? GoldCalendarFormat.signedCurrency(summary.totalPnL, hideAmounts: hideAmounts)
                            : GoldCalendarFormat.signedPercent(summary.marketMonthChangePercent)
                    )
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(headlineColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                    Text(subtitleText)
                        .font(.caption2)
                        .foregroundStyle(GoldTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 7) {
                    HStack(spacing: 6) {
                        HStack(spacing: 2) {
                            Text(isPnLMode ? "红" : "涨")
                                .foregroundStyle(GoldTheme.textSecondary)
                            Text("\(redDays)天")
                                .foregroundStyle(GoldTheme.up)
                                .fontWeight(.bold)
                        }
                        Text("·")
                            .foregroundStyle(GoldTheme.textFaint)
                        HStack(spacing: 2) {
                            Text(isPnLMode ? "绿" : "跌")
                                .foregroundStyle(GoldTheme.textSecondary)
                            Text("\(greenDays)天")
                                .foregroundStyle(GoldTheme.down)
                                .fontWeight(.bold)
                        }
                    }
                    .font(.system(size: 12, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)

                    GoldCalendarRatioBar(redCount: redDays, greenCount: greenDays)
                        .frame(width: 118, height: 6)

                    Text(isPnLMode ? "持仓红绿战绩" : "大盘收红收绿")
                        .font(.system(size: 10))
                        .foregroundStyle(GoldTheme.textFaint)
                }
            }

            if let bannerText {
                HStack(spacing: 6) {
                    Image(systemName: hideAmounts ? "lock.fill" : "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GoldTheme.gold)
                    Text(bannerText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(GoldTheme.goldSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(GoldTheme.background.opacity(0.75), in: GoldTheme.rangeShape)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
}

struct GoldCalendarRatioBar: View {
    let redCount: Int
    let greenCount: Int

    var body: some View {
        GeometryReader { geo in
            let total = max(0, redCount) + max(0, greenCount)
            ZStack(alignment: .leading) {
                GoldTheme.capsuleShape.fill(GoldTheme.background)
                if total > 0 {
                    let redWidth = geo.size.width * CGFloat(redCount) / CGFloat(total)
                    let greenWidth = geo.size.width * CGFloat(greenCount) / CGFloat(total)
                    HStack(spacing: 1) {
                        if redCount > 0 {
                            GoldTheme.up.frame(width: max(4, redWidth - (greenCount > 0 ? 0.5 : 0)))
                        }
                        if greenCount > 0 {
                            GoldTheme.down.frame(width: max(4, greenWidth - (redCount > 0 ? 0.5 : 0)))
                        }
                    }
                    .clipShape(GoldTheme.capsuleShape)
                }
            }
        }
    }
}

// MARK: - 3. 「红绿热力 × 攒金印记」月历网格卡片（双行顶栏，375pt 零截断）

struct GoldCalendarMonthGridCard: View {
    let year: Int
    let month: Int
    let focusedMonthDate: Date
    let selectedDayKey: CalendarDayKey
    let availableLayers: [GoldCalendarLayer]
    let effectiveLayer: GoldCalendarLayer
    let basis: GoldMarketBasis
    let hideAmounts: Bool
    let snapshotProvider: (Date) -> GoldCalendarDaySnapshot?
    let onSelectLayer: (GoldCalendarLayer) -> Void
    let onShiftMonth: (Int) -> Void
    let onOpenYearMonthPicker: () -> Void
    let onSelectDay: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 10) {
            // 第 1 行：月份导航（< | 2026年11月 | >）
            HStack {
                Button { onShiftMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GoldTheme.text)
                        .frame(width: 36, height: 34)
                        .background(GoldTheme.background.opacity(0.6), in: GoldTheme.circleShape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("上一月")

                Spacer()

                Button(action: onOpenYearMonthPicker) {
                    HStack(spacing: 4) {
                        Text("\(String(year))年\(month)月")
                            .font(.system(.headline, design: .rounded).bold())
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.text)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(GoldTheme.goldSoft)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择年月")

                Spacer()

                Button { onShiftMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GoldTheme.text)
                        .frame(width: 36, height: 34)
                        .background(GoldTheme.background.opacity(0.6), in: GoldTheme.circleShape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("下一月")
            }

            // 第 2 行：紧凑图层切换胶囊（28pt 高）+ 口径单位提示
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(availableLayers) { layer in
                        let selected = (layer == effectiveLayer)
                        Button {
                            onSelectLayer(layer)
                        } label: {
                            Text(layer.rawValue)
                                .font(.system(size: 11, weight: selected ? .bold : .medium, design: .rounded))
                                .foregroundStyle(selected ? GoldTheme.onGold : GoldTheme.textSecondary)
                                .padding(.horizontal, 10)
                                .frame(height: 24)
                                .background(selected ? GoldTheme.gold : Color.clear, in: GoldTheme.capsuleShape)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .frame(height: 28)
                .background(GoldTheme.background, in: GoldTheme.capsuleShape)
                .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))

                Spacer(minLength: 4)

                Text(effectiveLayer.unitHint)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(GoldTheme.textFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            // 星期抬头
            HStack(spacing: 4) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(GoldTheme.textFaint)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 2)

            // 月历热力网格（若第 6 行整行均为下月则自动收起为 5 行，提升首屏空间利用率）
            let rawDays = HoldingCalendarLogic.days(in: focusedMonthDate)
            let visibleDays: [Date] = {
                guard rawDays.count == 42 else { return rawDays }
                let sixthRowHasTargetMonth = rawDays[35..<42].contains { day in
                    let key = CalendarDayKey(date: day)
                    return key.year == year && key.month == month
                }
                return sixthRowHasTargetMonth ? rawDays : Array(rawDays[0..<35])
            }()
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(visibleDays, id: \.self) { day in
                    let dayKey = CalendarDayKey(date: day)
                    let inFocusedMonth = (dayKey.year == year && dayKey.month == month)
                    let snap = snapshotProvider(day)
                    GoldCalendarDayCellView(
                        day: day,
                        dayKey: dayKey,
                        inFocusedMonth: inFocusedMonth,
                        isSelected: dayKey == selectedDayKey,
                        snapshot: snap,
                        layer: effectiveLayer,
                        hideAmounts: hideAmounts,
                        onSelect: { onSelectDay(day) }
                    )
                }
            }

            // 底部单行图例与客观口径脚注
            VStack(alignment: .leading, spacing: 5) {
                legendRow
                Text(GoldCalendarFormat.basisFootnote(basis: basis))
                    .font(.system(size: 10))
                    .foregroundStyle(GoldTheme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        .simultaneousGesture(
            DragGesture(minimumDistance: 36, coordinateSpace: .local)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                    onShiftMonth(value.translation.width < 0 ? 1 : -1)
                }
        )
    }

    private var legendRow: some View {
        HStack(spacing: 6) {
            if effectiveLayer == .temperature {
                HStack(spacing: 3) {
                    Text("冷")
                        .foregroundStyle(GoldTheme.textFaint)
                    ForEach([GoldTheme.tempFreezing, GoldTheme.tempCool, GoldTheme.tempNeutral, GoldTheme.tempWarm, GoldTheme.tempHot], id: \.self) { color in
                        GoldTheme.rangeShape
                            .fill(color.opacity(0.65))
                            .frame(width: 9, height: 9)
                    }
                    Text("热")
                        .foregroundStyle(GoldTheme.textFaint)
                }
            } else {
                HStack(spacing: 3) {
                    Text("跌")
                        .foregroundStyle(GoldTheme.down)
                    ForEach([0.26, 0.16, 0.08], id: \.self) { alpha in
                        GoldTheme.rangeShape
                            .fill(GoldTheme.down.opacity(alpha))
                            .frame(width: 8, height: 8)
                    }
                    ForEach([0.08, 0.16, 0.26], id: \.self) { alpha in
                        GoldTheme.rangeShape
                            .fill(GoldTheme.up.opacity(alpha))
                            .frame(width: 8, height: 8)
                    }
                    Text("涨")
                        .foregroundStyle(GoldTheme.up)
                    Text("· 休市")
                        .foregroundStyle(GoldTheme.textFaint)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    GoldTheme.circleShape.fill(GoldTheme.gold).frame(width: 5, height: 5)
                    Text("记金")
                }
                HStack(spacing: 2) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(GoldTheme.goldSoft)
                    Text("里程碑")
                }
            }
            .foregroundStyle(GoldTheme.textFaint)
        }
        .font(.system(size: 10))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

private struct GoldCalendarDayCellView: View {
    let day: Date
    let dayKey: CalendarDayKey
    let inFocusedMonth: Bool
    let isSelected: Bool
    let snapshot: GoldCalendarDaySnapshot?
    let layer: GoldCalendarLayer
    let hideAmounts: Bool
    let onSelect: () -> Void

    private var status: GoldCalendarDayStatus {
        if let snapshot { return snapshot.status }
        let today = CalendarDayKey(date: .now)
        return dayKey > today ? .future : .noMarketData
    }

    private var isFuture: Bool {
        status == .future
    }

    private var isToday: Bool {
        snapshot?.isToday ?? Calendar.current.isDateInToday(day)
    }

    private var heatTintColor: Color {
        guard inFocusedMonth, status == .trading, let snapshot else { return .clear }
        switch layer {
        case .pnl:
            guard let pnl = snapshot.dailyPnL else { return .clear }
            let dir = GoldCalendarDirection.from(pnl)
            guard dir != .flat else { return .clear }
            let base = (dir == .up) ? GoldTheme.up : GoldTheme.down
            if hideAmounts {
                // 隐私模式：统一单档低饱和方向底色，不按振幅分深浅。
                return base.opacity(0.12)
            }
            let level = snapshot.pnlHeatLevel == .none ? .mild : snapshot.pnlHeatLevel
            return base.opacity(level.fillOpacity)
        case .market:
            guard let pct = snapshot.marketChangePercent else { return .clear }
            let dir = GoldCalendarDirection.from(pct)
            guard dir != .flat else { return .clear }
            let base = (dir == .up) ? GoldTheme.up : GoldTheme.down
            let level = snapshot.marketHeatLevel == .none ? .mild : snapshot.marketHeatLevel
            return base.opacity(level.fillOpacity)
        case .temperature:
            guard let level = snapshot.temperatureLevel else { return .clear }
            return MacroPresentation.temperatureColor(for: level).opacity(0.22)
        }
    }

    private var cellBaseBackground: Color {
        if !inFocusedMonth || isFuture {
            return GoldTheme.background.opacity(0.45)
        }
        if status == .closed || status == .noMarketData {
            return GoldTheme.calendarCell.opacity(0.6)
        }
        return GoldTheme.calendarCell
    }

    private var primaryValueText: String {
        guard inFocusedMonth else { return "" }
        if isFuture {
            return HoldingCalendarLogic.lunar(day)
        }
        guard let snapshot else {
            return HoldingCalendarLogic.lunar(day)
        }
        switch status {
        case .future:
            return HoldingCalendarLogic.lunar(day)
        case .closed:
            return HoldingCalendarLogic.lunar(day)
        case .noMarketData:
            return HoldingCalendarLogic.lunar(day)
        case .trading:
            switch layer {
            case .pnl:
                if snapshot.dailyPnL != nil {
                    return GoldCalendarFormat.compactCellPnL(snapshot.dailyPnL, hideAmounts: hideAmounts)
                }
                return HoldingCalendarLogic.lunar(day)
            case .market:
                if snapshot.marketChangePercent != nil {
                    return GoldCalendarFormat.compactCellPercent(snapshot.marketChangePercent)
                }
                return HoldingCalendarLogic.lunar(day)
            case .temperature:
                if snapshot.temperatureScore != nil {
                    return GoldCalendarFormat.compactCellTemperature(snapshot.temperatureScore)
                }
                return HoldingCalendarLogic.lunar(day)
            }
        }
    }

    private var primaryValueColor: Color {
        guard inFocusedMonth, status == .trading, let snapshot else {
            return GoldTheme.textFaint.opacity(isFuture ? 0.5 : 0.85)
        }
        switch layer {
        case .pnl:
            guard let pnl = snapshot.dailyPnL else { return GoldTheme.textFaint }
            switch GoldCalendarDirection.from(pnl) {
            case .up: return hideAmounts ? GoldTheme.up.opacity(0.75) : GoldTheme.up
            case .down: return hideAmounts ? GoldTheme.down.opacity(0.75) : GoldTheme.down
            case .flat: return GoldTheme.textSecondary
            }
        case .market:
            guard let pct = snapshot.marketChangePercent else { return GoldTheme.textFaint }
            switch GoldCalendarDirection.from(pct) {
            case .up: return GoldTheme.up
            case .down: return GoldTheme.down
            case .flat: return GoldTheme.textSecondary
            }
        case .temperature:
            guard let level = snapshot.temperatureLevel else { return GoldTheme.textFaint }
            return MacroPresentation.temperatureColor(for: level)
        }
    }

    private var dayNumberColor: Color {
        if !inFocusedMonth { return GoldTheme.textFaint.opacity(0.45) }
        if isFuture { return GoldTheme.textFaint.opacity(0.55) }
        if isSelected { return GoldTheme.gold }
        if isToday { return GoldTheme.goldSoft }
        if status == .closed { return GoldTheme.textSecondary }
        return GoldTheme.text
    }

    /// 右上角微标严格上限 2 个，优先级：里程碑星芒 ✦ > 买入小金豆 ● > 卖出/赠送点。
    @ViewBuilder
    private var topRightBadges: some View {
        if inFocusedMonth, let snapshot {
            let showMilestone = snapshot.hasMilestone && !hideAmounts
            let showBuy = snapshot.hasBuy
            let showSold = snapshot.hasSold
            let showGift = snapshot.hasGift
            let badge1IsMilestone = showMilestone
            let remainingSlots = badge1IsMilestone ? 1 : 2

            HStack(spacing: 2) {
                if badge1IsMilestone {
                    Image(systemName: "sparkles")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(GoldTheme.goldSoft)
                }
                if showBuy && remainingSlots >= 1 {
                    GoldTheme.circleShape
                        .fill(GoldTheme.gold)
                        .frame(width: 4.5, height: 4.5)
                }
                let used = (badge1IsMilestone ? 1 : 0) + (showBuy ? 1 : 0)
                if used < 2 {
                    if showSold {
                        GoldTheme.circleShape
                            .fill(GoldTheme.up)
                            .frame(width: 4.5, height: 4.5)
                    } else if showGift {
                        GoldTheme.circleShape
                            .fill(GoldTheme.textSecondary)
                            .frame(width: 4.5, height: 4.5)
                    }
                }
            }
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 3) {
                HStack(alignment: .top, spacing: 1) {
                    Text("\(dayKey.day)")
                        .font(.system(size: 13.5, weight: isSelected || isToday ? .bold : .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(dayNumberColor)
                    Spacer(minLength: 0)
                    topRightBadges
                }
                .padding(.horizontal, 4)

                Spacer(minLength: 0)

                Text(primaryValueText)
                    .font(.system(size: 10, weight: status == .trading ? .semibold : .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(primaryValueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .padding(.horizontal, 2)

                if inFocusedMonth && isToday {
                    GoldTheme.capsuleShape
                        .fill(GoldTheme.gold)
                        .frame(width: 12, height: 2)
                } else if inFocusedMonth && status == .closed {
                    Text("休")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(GoldTheme.textFaint.opacity(0.7))
                        .frame(height: 8)
                } else {
                    Color.clear.frame(height: 4)
                }
            }
            .padding(.top, 5)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                ZStack {
                    GoldTheme.rangeShape.fill(cellBaseBackground)
                    GoldTheme.rangeShape.fill(heatTintColor)
                }
            )
            .overlay {
                if isSelected && inFocusedMonth {
                    GoldTheme.rangeShape.strokeBorder(GoldTheme.gold, lineWidth: 1.5)
                } else if isToday && inFocusedMonth {
                    GoldTheme.rangeShape.strokeBorder(GoldTheme.goldSoft.opacity(0.55), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(HoldingsSelection.dateText(day))
    }
}

// MARK: - 4. 当日黄金手账卡（彻底告别空日冷场）

struct GoldCalendarDayJournalCard: View {
    let snapshot: GoldCalendarDaySnapshot
    let hasHoldingsInScope: Bool
    let basis: GoldMarketBasis
    let hideAmounts: Bool
    let recordLookup: (UUID) -> HoldingRecord?
    let holdingsModel: HoldingsViewModel
    let onAddForDay: () -> Void

    private var hasTemperature: Bool {
        snapshot.temperatureScore != nil && snapshot.temperatureLevel != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 头部：日期 + 农历 + 里程碑徽章 + 补记按钮
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(GoldCalendarFormat.fullChineseDateHeader(snapshot.date))
                        .font(.subheadline.bold())
                        .foregroundStyle(GoldTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    if snapshot.hasMilestone && !hideAmounts {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .bold))
                            Text("点亮里程碑 · \(snapshot.unlockedMilestones.map(\.title).joined(separator: "、"))")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(GoldTheme.goldSoft)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(GoldTheme.gold.opacity(0.16), in: GoldTheme.capsuleShape)
                        .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.45), lineWidth: 1))
                    }
                }

                Spacer(minLength: 4)

                if snapshot.status != .future {
                    Button(action: onAddForDay) {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("补记这天")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(GoldTheme.onGold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(GoldTheme.gold, in: GoldTheme.capsuleShape)
                    }
                    .buttonStyle(.plain)
                }
            }

            // 三联客观指标格（无历史温度数据时自动收起为双栏）
            HStack(spacing: 8) {
                firstMetricTile
                secondMetricTile
                if hasTemperature {
                    thirdMetricTile
                }
            }

            // 当日记账流水或克制单行陪伴语
            if snapshot.events.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: snapshot.endOfDayHoldingGrams > 1e-9 ? "shippingbox.fill" : "calendar")
                        .font(.caption)
                        .foregroundStyle(GoldTheme.goldSoft.opacity(0.85))
                    Text(GoldCalendarFormat.emptyDayJournalNote(snapshot: snapshot, hideAmounts: hideAmounts))
                        .font(.caption)
                        .foregroundStyle(GoldTheme.textSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if snapshot.status != .future {
                        Button("补记一笔", action: onAddForDay)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GoldTheme.gold)
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(GoldTheme.background.opacity(0.75), in: GoldTheme.subCardShape)
                .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
            } else {
                VStack(spacing: 8) {
                    ForEach(snapshot.events) { event in
                        eventRow(event)
                    }
                }
            }
        }
        .padding(14)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    @ViewBuilder
    private var firstMetricTile: some View {
        if hasHoldingsInScope || snapshot.dailyPnL != nil || snapshot.endOfDayHoldingGrams > 1e-9 {
            switch snapshot.status {
            case .trading:
                let pnlColor: Color = {
                    if hideAmounts { return GoldTheme.textSecondary }
                    switch snapshot.pnlDirection {
                    case .up: return GoldTheme.up
                    case .down: return GoldTheme.down
                    case .flat: return GoldTheme.text
                    }
                }()
                metricTile(
                    title: "当日预估盈亏",
                    value: GoldCalendarFormat.signedCurrency(snapshot.dailyPnL, hideAmounts: hideAmounts),
                    subValue: snapshot.dailyPnLRatePercent.map { GoldCalendarFormat.signedPercent($0, hideAmounts: hideAmounts) } ?? "—",
                    valueColor: pnlColor,
                    subColor: pnlColor.opacity(0.9)
                )
            case .closed:
                metricTile(
                    title: "休市 · 参考估值",
                    value: GoldCalendarFormat.currency(snapshot.endOfDayValuationCNY, hideAmounts: hideAmounts),
                    subValue: hideAmounts ? "在库 ••••" : "在库 \(GoldVaultSummary.formatGrams(snapshot.endOfDayHoldingGrams))g",
                    valueColor: GoldTheme.text,
                    subColor: GoldTheme.textSecondary
                )
            case .noMarketData, .future:
                metricTile(
                    title: "当日在库克重",
                    value: hideAmounts ? "•••• g" : "\(GoldVaultSummary.formatGrams(snapshot.endOfDayHoldingGrams))g",
                    subValue: "暂无历史日线",
                    valueColor: GoldTheme.goldSoft,
                    subColor: GoldTheme.textFaint
                )
            }
        } else {
            let marketColor: Color = {
                switch snapshot.marketDirection {
                case .up: return GoldTheme.up
                case .down: return GoldTheme.down
                case .flat: return GoldTheme.textSecondary
                }
            }()
            metricTile(
                title: "当日大盘涨跌",
                value: snapshot.status == .trading ? GoldCalendarFormat.signedPercent(snapshot.marketChangePercent) : "休市",
                subValue: snapshot.status == .trading
                    ? (snapshot.marketChangeCNY.map { ($0 >= 0 ? "+" : "-") + "¥\(abs($0).moneyText)" } ?? "—")
                    : "\(basis.title)口径",
                valueColor: snapshot.status == .trading ? marketColor : GoldTheme.textSecondary,
                subColor: GoldTheme.textSecondary
            )
        }
    }

    private var secondMetricTile: some View {
        let priceTitle = snapshot.isToday ? "最新参考价" : "当日收盘金价"
        let displayPrice: String = {
            if let p = snapshot.referencePriceCNY {
                return "¥\(p.moneyText)"
            }
            if let last = snapshot.lastKnownPriceCNY {
                return "¥\(last.moneyText)"
            }
            return "—"
        }()
        let subText: String = {
            if snapshot.status == .trading {
                return GoldCalendarFormat.signedPercent(snapshot.marketChangePercent)
            }
            if snapshot.status == .closed {
                return "休市 · 前收参考"
            }
            return "\(basis.title) · 元/克"
        }()
        let subColor: Color = {
            guard snapshot.status == .trading else { return GoldTheme.textFaint }
            switch snapshot.marketDirection {
            case .up: return GoldTheme.up
            case .down: return GoldTheme.down
            case .flat: return GoldTheme.textSecondary
            }
        }()
        return metricTile(
            title: priceTitle,
            value: displayPrice,
            subValue: subText,
            valueColor: GoldTheme.text,
            subColor: subColor
        )
    }

    private var thirdMetricTile: some View {
        let score = snapshot.temperatureScore ?? 0
        let level = snapshot.temperatureLevel ?? .neutral
        let tempColor = MacroPresentation.temperatureColor(for: level)
        return VStack(alignment: .leading, spacing: 4) {
            Text("当日黄金温度")
                .font(.system(size: 10))
                .foregroundStyle(GoldTheme.textSecondary)
                .lineLimit(1)
            Text("\(Int(score.rounded()))°")
                .font(.system(.subheadline, design: .rounded).bold())
                .monospacedDigit()
                .foregroundStyle(tempColor)
                .lineLimit(1)
            HStack(spacing: 4) {
                GoldTheme.circleShape
                    .fill(tempColor)
                    .frame(width: 5, height: 5)
                Text(level.defaultLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(GoldTheme.background.opacity(0.82), in: GoldTheme.subCardShape)
        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    private func metricTile(
        title: String,
        value: String,
        subValue: String,
        valueColor: Color,
        subColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(GoldTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(.subheadline, design: .rounded).bold())
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Text(subValue)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(subColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(GoldTheme.background.opacity(0.82), in: GoldTheme.subCardShape)
        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    @ViewBuilder
    private func eventRow(_ event: GoldCalendarDayEvent) -> some View {
        let content = HStack(spacing: 10) {
            GoldAssetGlyph(type: event.assetType, size: 28, emphasized: true)
                .frame(width: 36, height: 36)
                .background(GoldTheme.card, in: GoldTheme.badgeShape)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GoldTheme.text)
                        .lineLimit(1)
                    Text(eventKindLabel(event.kind))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(eventKindColor(event.kind))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(eventKindColor(event.kind).opacity(0.14), in: GoldTheme.capsuleShape)
                }
                Text(eventDetailText(event))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(GoldTheme.textFaint)
        }
        .padding(10)
        .background(GoldTheme.background.opacity(0.75), in: GoldTheme.subCardShape)
        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))

        if let record = recordLookup(event.recordID) {
            NavigationLink {
                HoldingDetailView(
                    record: record,
                    model: holdingsModel,
                    marketBasis: basis,
                    embeddedInNavigationStack: true
                )
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func eventKindLabel(_ kind: String) -> String {
        switch kind {
        case "buy": "购入"
        case "sold": "卖出"
        case "gift": "赠出"
        default: "记录"
        }
    }

    private func eventKindColor(_ kind: String) -> Color {
        switch kind {
        case "buy": GoldTheme.gold
        case "sold": GoldTheme.up
        default: GoldTheme.textSecondary
        }
    }

    private func eventDetailText(_ event: GoldCalendarDayEvent) -> String {
        if hideAmounts {
            return "•••• g · •••• 元"
        }
        let amountTitle = event.kind == "sold" ? "实收" : "成本"
        let amount = event.kind == "sold" ? event.proceeds : event.totalCost
        return "\(GoldVaultSummary.formatGrams(event.grams))g · \(amountTitle) ¥\(amount.moneyText)"
    }
}

// MARK: - 5. 「年览」Tab：年度总览 + 52 周 GitHub 热力图 + 12 个月宫格

struct GoldCalendarYearOverviewView: View {
    let yearSnapshot: GoldCalendarYearSnapshot
    let hasHoldings: Bool
    let basis: GoldMarketBasis
    let hideAmounts: Bool
    @Binding var heatmapMode: GoldCalendarYearHeatmapMode
    let onShiftYear: (Int) -> Void
    let onSelectMonth: (Int) -> Void
    let onSelectDay: (CalendarDayKey) -> Void

    private var isPnLHeadline: Bool {
        hasHoldings && yearSnapshot.totalPnL != nil
    }

    private var redDays: Int {
        isPnLHeadline ? yearSnapshot.pnlRedDays : yearSnapshot.marketRedDays
    }

    private var greenDays: Int {
        isPnLHeadline ? yearSnapshot.pnlGreenDays : yearSnapshot.marketGreenDays
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            yearHeaderAndSummary
            yearHeatmapCard
            twelveMonthGridCard
        }
    }

    private var yearHeaderAndSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { onShiftYear(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GoldTheme.text)
                        .frame(width: 34, height: 34)
                        .background(GoldTheme.background.opacity(0.6), in: GoldTheme.circleShape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("上一年")

                Spacer()

                Text("\(String(yearSnapshot.year))年 攒金年览")
                    .font(.system(.headline, design: .rounded).bold())
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.text)

                Spacer()

                Button { onShiftYear(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GoldTheme.text)
                        .frame(width: 34, height: 34)
                        .background(GoldTheme.background.opacity(0.6), in: GoldTheme.circleShape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("下一年")
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isPnLHeadline ? "年度预估盈亏" : "年度金价涨跌")
                        .font(.caption)
                        .foregroundStyle(GoldTheme.textSecondary)

                    let valueColor: Color = {
                        if isPnLHeadline {
                            if hideAmounts { return GoldTheme.textSecondary }
                            switch GoldCalendarDirection.from(yearSnapshot.totalPnL) {
                            case .up: return GoldTheme.up
                            case .down: return GoldTheme.down
                            case .flat: return GoldTheme.text
                            }
                        } else {
                            switch GoldCalendarDirection.from(yearSnapshot.marketYearChangePercent) {
                            case .up: return GoldTheme.up
                            case .down: return GoldTheme.down
                            case .flat: return GoldTheme.text
                            }
                        }
                    }()

                    Text(
                        isPnLHeadline
                            ? GoldCalendarFormat.signedCurrency(yearSnapshot.totalPnL, hideAmounts: hideAmounts)
                            : GoldCalendarFormat.signedPercent(yearSnapshot.marketYearChangePercent)
                    )
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                    Text(
                        hasHoldings
                            ? (hideAmounts
                                ? "年度新攒 •••• · \(yearSnapshot.totalBuyCount)笔"
                                : "年度新攒 +\(GoldVaultSummary.formatGrams(yearSnapshot.totalBuyGrams))g · \(yearSnapshot.totalBuyCount)笔")
                            : "\(basis.title)口径 · 全年行情复盘"
                    )
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("红 \(redDays)天").foregroundStyle(GoldTheme.up).fontWeight(.bold)
                        Text("·").foregroundStyle(GoldTheme.textFaint)
                        Text("绿 \(greenDays)天").foregroundStyle(GoldTheme.down).fontWeight(.bold)
                    }
                    .font(.system(size: 12, design: .rounded))
                    .monospacedDigit()

                    GoldCalendarRatioBar(redCount: redDays, greenCount: greenDays)
                        .frame(width: 112, height: 6)

                    Text("全年红绿交易日")
                        .font(.system(size: 10))
                        .foregroundStyle(GoldTheme.textFaint)
                }
            }
        }
        .padding(14)
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
                    colors: [GoldTheme.gold.opacity(0.3), GoldTheme.cardStroke],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        )
    }

    private var yearHeatmapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("52 周年度热力图")
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.text)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    ForEach(GoldCalendarYearHeatmapMode.allCases) { mode in
                        let selected = (heatmapMode == mode)
                        let label: String = {
                            if mode == .pnl && !hasHoldings { return "大盘热力" }
                            return mode.rawValue
                        }()
                        Button {
                            heatmapMode = mode
                        } label: {
                            Text(label)
                                .font(.system(size: 10.5, weight: selected ? .bold : .medium, design: .rounded))
                                .foregroundStyle(selected ? GoldTheme.onGold : GoldTheme.textSecondary)
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                                .background(selected ? GoldTheme.gold : Color.clear, in: GoldTheme.capsuleShape)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(GoldTheme.background, in: GoldTheme.capsuleShape)
                .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
            }

            HStack(alignment: .top, spacing: 6) {
                // 左侧星期微标
                VStack(spacing: 3) {
                    Color.clear.frame(width: 12, height: 13)
                    ForEach(0..<7, id: \.self) { row in
                        Text(row == 1 ? "一" : row == 3 ? "三" : row == 5 ? "五" : "")
                            .font(.system(size: 8.5))
                            .foregroundStyle(GoldTheme.textFaint)
                            .frame(width: 12, height: 10)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                ScrollView(.horizontal, showsIndicators: false) {
                    let colStep: CGFloat = 13
                    let totalGridWidth = max(0, CGFloat(yearSnapshot.weeks.count) * colStep - 3)
                    VStack(alignment: .leading, spacing: 3) {
                        // 月份标注行（绝对列偏移，彻底消除 10pt 窄列截断）
                        ZStack(alignment: .topLeading) {
                            Color.clear.frame(width: totalGridWidth, height: 13)
                            ForEach(Array(yearSnapshot.weeks.enumerated()), id: \.offset) { index, week in
                                let label = monthLabelForWeek(week, previousWeek: index > 0 ? yearSnapshot.weeks[index - 1] : nil)
                                if !label.isEmpty {
                                    Text(label)
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .foregroundStyle(GoldTheme.textFaint)
                                        .fixedSize()
                                        .offset(x: CGFloat(index) * colStep)
                                }
                            }
                        }

                        // 52~53 周 × 7 天色块矩阵
                        HStack(spacing: 3) {
                            ForEach(Array(yearSnapshot.weeks.enumerated()), id: \.offset) { _, week in
                                VStack(spacing: 3) {
                                    ForEach(week) { cell in
                                        let isFuture = cell.snapshot?.status == .future
                                        Button {
                                            if cell.inTargetYear && !isFuture {
                                                onSelectDay(cell.dayKey)
                                            }
                                        } label: {
                                            GoldTheme.rangeShape
                                                .fill(heatCellColor(cell))
                                                .frame(width: 10, height: 10)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(!cell.inTargetYear || isFuture)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.trailing, 8)
                }
                .defaultScrollAnchor(.trailing)
            }

            HStack {
                Text(heatmapMode == .footprint ? "按当日新攒克重深浅着色 · 轻点色块直达该日" : "按当日收益率幅度着色 · 轻点色块直达该日")
                    .font(.system(size: 10))
                    .foregroundStyle(GoldTheme.textFaint)
                Spacer()
            }
        }
        .padding(14)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    private var twelveMonthGridCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("12 个月战报宫格")
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.text)
                Spacer()
                Text("点击月份进入月历")
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textFaint)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(yearSnapshot.monthSummaries) { m in
                    Button {
                        onSelectMonth(m.month)
                    } label: {
                        monthCard(m)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    private func monthCard(_ summary: GoldCalendarMonthSummary) -> some View {
        let usePnL = hasHoldings && summary.totalPnL != nil
        let direction: GoldCalendarDirection = usePnL
            ? GoldCalendarDirection.from(summary.totalPnL)
            : GoldCalendarDirection.from(summary.marketMonthChangePercent)
        let accent: Color = {
            if usePnL && hideAmounts {
                return direction == .up ? GoldTheme.up.opacity(0.7) : direction == .down ? GoldTheme.down.opacity(0.7) : GoldTheme.textSecondary
            }
            switch direction {
            case .up: return GoldTheme.up
            case .down: return GoldTheme.down
            case .flat: return GoldTheme.textSecondary
            }
        }()
        let tintBackground: Color = {
            switch direction {
            case .up: return GoldTheme.up.opacity(0.08)
            case .down: return GoldTheme.down.opacity(0.08)
            case .flat: return Color.clear
            }
        }()
        let mainText: String = {
            if usePnL {
                if hideAmounts {
                    return direction == .up ? "盈利" : direction == .down ? "回调" : "持平"
                }
                return GoldCalendarFormat.compactCellPnL(summary.totalPnL, hideAmounts: false)
            }
            return summary.marketMonthChangePercent.map { GoldCalendarFormat.compactCellPercent($0) } ?? "—"
        }()

        let rDays = usePnL ? summary.pnlRedDays : summary.marketRedDays
        let gDays = usePnL ? summary.pnlGreenDays : summary.marketGreenDays

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("\(summary.month)月")
                    .font(.system(.caption, design: .rounded).bold())
                    .foregroundStyle(GoldTheme.text)
                Spacer(minLength: 2)
                if !summary.unlockedMilestones.isEmpty && !hideAmounts {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(GoldTheme.goldSoft)
                } else if summary.newBuyGrams > 1e-9 {
                    GoldTheme.circleShape
                        .fill(GoldTheme.gold)
                        .frame(width: 5, height: 5)
                }
            }

            Text(mainText)
                .font(.system(.subheadline, design: .rounded).bold())
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            HStack(spacing: 3) {
                if rDays + gDays > 0 {
                    Text("红\(rDays) 绿\(gDays)")
                        .foregroundStyle(GoldTheme.textFaint)
                } else {
                    Text("暂无交易")
                        .foregroundStyle(GoldTheme.textFaint)
                }
                Spacer(minLength: 2)
                if summary.newBuyGrams > 1e-9 && !hideAmounts {
                    Text("+\(GoldVaultSummary.formatGrams(summary.newBuyGrams))g")
                        .foregroundStyle(GoldTheme.goldSoft)
                }
            }
            .font(.system(size: 9.5, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                GoldTheme.subCardShape.fill(GoldTheme.background.opacity(0.85))
                GoldTheme.subCardShape.fill(tintBackground)
            }
        )
        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    private func monthLabelForWeek(_ week: [GoldCalendarYearHeatCell], previousWeek: [GoldCalendarYearHeatCell]?) -> String {
        guard let firstInYear = week.first(where: { $0.inTargetYear }) else { return "" }
        if let prev = previousWeek?.first(where: { $0.inTargetYear }), prev.dayKey.month == firstInYear.dayKey.month {
            return ""
        }
        return "\(firstInYear.dayKey.month)月"
    }

    private func heatCellColor(_ cell: GoldCalendarYearHeatCell) -> Color {
        guard cell.inTargetYear, let snap = cell.snapshot else {
            return Color.clear
        }
        if snap.status == .future {
            return GoldTheme.background.opacity(0.4)
        }
        switch heatmapMode {
        case .footprint:
            if snap.hasBuy {
                if hideAmounts { return GoldTheme.gold.opacity(0.45) }
                switch snap.footprintHeatLevel {
                case .none: return GoldTheme.calendarCell
                case .mild: return GoldTheme.gold.opacity(0.35)
                case .medium: return GoldTheme.gold.opacity(0.65)
                case .strong: return GoldTheme.gold
                }
            }
            return GoldTheme.calendarCell.opacity(0.7)
        case .pnl:
            guard snap.status == .trading else {
                return GoldTheme.calendarCell.opacity(0.55)
            }
            if hasHoldings {
                guard let pnl = snap.dailyPnL else { return GoldTheme.calendarCell.opacity(0.7) }
                let dir = GoldCalendarDirection.from(pnl)
                guard dir != .flat else { return GoldTheme.calendarCell.opacity(0.8) }
                let base = dir == .up ? GoldTheme.up : GoldTheme.down
                if hideAmounts { return base.opacity(0.38) }
                switch snap.pnlHeatLevel {
                case .none, .mild: return base.opacity(0.35)
                case .medium: return base.opacity(0.62)
                case .strong: return base.opacity(0.92)
                }
            } else {
                guard let pct = snap.marketChangePercent else { return GoldTheme.calendarCell.opacity(0.7) }
                let dir = GoldCalendarDirection.from(pct)
                guard dir != .flat else { return GoldTheme.calendarCell.opacity(0.8) }
                let base = dir == .up ? GoldTheme.up : GoldTheme.down
                switch snap.marketHeatLevel {
                case .none, .mild: return base.opacity(0.35)
                case .medium: return base.opacity(0.62)
                case .strong: return base.opacity(0.92)
                }
            }
        }
    }
}

// MARK: - 6. 快速年月选择器弹窗

struct GoldCalendarYearMonthPickerSheet: View {
    let currentYear: Int
    let currentMonth: Int
    let onSelect: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftYear: Int

    init(currentYear: Int, currentMonth: Int, onSelect: @escaping (Int, Int) -> Void) {
        self.currentYear = currentYear
        self.currentMonth = currentMonth
        self.onSelect = onSelect
        _draftYear = State(initialValue: currentYear)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack {
                    Button { draftYear = max(2000, draftYear - 1) } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 40, height: 40)
                            .background(GoldTheme.background, in: GoldTheme.circleShape)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("\(String(draftYear))年")
                        .font(.title3.bold())
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.text)

                    Spacer()

                    Button { draftYear = min(2100, draftYear + 1) } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 40, height: 40)
                            .background(GoldTheme.background, in: GoldTheme.circleShape)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(1...12, id: \.self) { m in
                        let selected = (draftYear == currentYear && m == currentMonth)
                        Button {
                            onSelect(draftYear, m)
                            dismiss()
                        } label: {
                            Text("\(m)月")
                                .font(.system(.subheadline, design: .rounded).weight(selected ? .bold : .medium))
                                .foregroundStyle(selected ? GoldTheme.onGold : GoldTheme.text)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(selected ? GoldTheme.gold : GoldTheme.background, in: GoldTheme.subCardShape)
                                .overlay(
                                    GoldTheme.subCardShape.strokeBorder(
                                        selected ? Color.clear : GoldTheme.cardStroke,
                                        lineWidth: 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(GoldTheme.card)
            .navigationTitle("选择年月")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(GoldTheme.textSecondary)
                }
            }
        }
        .tint(GoldTheme.gold)
        .presentationDetents([.height(340)])
        .presentationBackground(GoldTheme.card)
    }
}
