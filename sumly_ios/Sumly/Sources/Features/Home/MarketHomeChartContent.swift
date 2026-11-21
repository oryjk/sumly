import SwiftUI
import Charts

/// One complete pricing basis, used by both the live and frozen outgoing layer.
struct MarketHomeChartContent: View {
    @Bindable var model: MarketHomeViewModel
    let availableHeight: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var showingHistorySources: Bool
    @Binding var showingDates: Bool
    var holdingOverlay: MarketHoldingOverlay? = nil
    var showHoldingOverlay: Bool = false
    var onToggleHoldingOverlay: (() -> Void)? = nil

    private static let quickRanges: [MarketRange] = [.realtime, .month, .quarter, .year, .fiveYears]

    private var quoteSnapshot: MarketQuoteSnapshot? {
        model.quote.flatMap { MarketQuoteSnapshot.make(from: $0, basis: model.basis) }
    }

    var body: some View {
        MarketDashboardLayout(availableHeight: availableHeight) {
            quoteHeader
            chartControls
            VStack(alignment: .leading, spacing: 6) {
                chartCaption
                HStack(spacing: 8) {
                    ChartWindowSummary(statistics: model.windowStatistics)
                    if showHoldingOverlay, let breakEven = holdingOverlay?.breakEvenPrice {
                        Text("· 保本 ¥\(breakEven.moneyText)")
                            .font(.system(size: 12, weight: .medium)).monospacedDigit()
                            .foregroundStyle(GoldTheme.goldSoft)
                            .lineLimit(1)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)

            if model.range == .realtime || model.range.dateBounds() != nil {
                trendChart
                    .accessibilityLabel("\(rangeTitle(model.range))黄金价格走势图，当前区间\(model.windowPoints.count)个行情点")
            } else {
                Text("今年暂无已收盘数据，首个交易日收盘后更新")
                    .font(.subheadline).foregroundStyle(GoldTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            navigator
        }
        .sensoryFeedback(.selection, trigger: model.selectedPoint?.date)
        .sensoryFeedback(.selection, trigger: model.range)
        .sensoryFeedback(.selection, trigger: model.priceScale)
    }

    private var quoteHeader: some View {
        VStack(spacing: 4) {
            Text("黄金价格")
                .font(.caption.weight(.medium)).foregroundStyle(GoldTheme.goldSoft)
                .frame(maxWidth: .infinity)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(model.price.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never)) } ?? "—")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: model.price)
                Text("元/克").font(.caption)
            }.foregroundStyle(GoldTheme.gold)
                .lineLimit(1).minimumScaleFactor(0.75)
                .padding(.horizontal, 44)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("黄金价格，\(model.price.map { String(format: "%.2f", $0) } ?? "暂无报价") 元每克")
            if let snapshot = quoteSnapshot, let change = snapshot.changeCNY, let percent = snapshot.changePercent {
                let isUp = change >= 0
                let tintColor = change == 0 ? GoldTheme.textSecondary : (isUp ? GoldTheme.up : GoldTheme.down)
                HStack(spacing: 6) {
                    Text("今日 \(change.signedMoneyText)")
                    Text("(\(percent.signedMoneyText)%)")
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tintColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(tintColor.opacity(0.12), in: GoldTheme.capsuleShape)
            }
            ZStack {
                if let message = model.message {
                    Button(message) { Task { await model.refresh() } }
                        .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, minHeight: 18, maxHeight: dynamicTypeSize.isAccessibilitySize ? nil : 18)
        }
    }

    @ViewBuilder private var chartControls: some View {
        VStack(spacing: 8) {
            quickRangeBar
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    rangeMenu
                        .padding(3)
                        .background(GoldTheme.card, in: GoldTheme.capsuleShape)
                        .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
                    HStack(spacing: 6) {
                        scalePicker
                        Spacer(minLength: 0)
                        holdingOverlayToggle
                        resetButton
                    }
                    .padding(3)
                    .background(GoldTheme.card, in: GoldTheme.capsuleShape)
                    .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
                }
            } else {
                HStack(spacing: 4) {
                    rangeMenu
                    Rectangle().fill(GoldTheme.cardStroke).frame(width: 1, height: 16)
                        .accessibilityHidden(true)
                    scalePicker
                    holdingOverlayToggle
                    resetButton
                }
                .padding(3)
                .background(GoldTheme.card, in: GoldTheme.capsuleShape)
                .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
            }
        }
    }

    private var quickRangeBar: some View {
        HStack(spacing: 6) {
            ForEach(Self.quickRanges, id: \.self) { range in
                let isSelected = model.range == range
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.range = range
                    }
                } label: {
                    Text(rangeTitle(range))
                        .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isSelected ? GoldTheme.onGold : GoldTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 34, maxHeight: dynamicTypeSize.isAccessibilitySize ? nil : 34)
                        .background(isSelected ? GoldTheme.gold : GoldTheme.card, in: GoldTheme.capsuleShape)
                        .overlay(GoldTheme.capsuleShape.strokeBorder(isSelected ? Color.clear : GoldTheme.cardStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var holdingOverlayToggle: some View {
        if holdingOverlay != nil, let onToggleHoldingOverlay {
            Button(action: onToggleHoldingOverlay) {
                HStack(spacing: 3) {
                    Image(systemName: showHoldingOverlay ? "checkmark.circle.fill" : "circle")
                        .font(.caption2)
                    Text("保本线")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                }
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(minHeight: 30)
                .foregroundStyle(showHoldingOverlay ? GoldTheme.onGold : GoldTheme.goldSoft)
                .background(showHoldingOverlay ? GoldTheme.gold : GoldTheme.background, in: GoldTheme.capsuleShape)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("在走势图叠加持仓保本线")
            .accessibilityValue(showHoldingOverlay ? "已开启" : "已关闭")
        }
    }

    private var rangeMenu: some View {
        Menu {
            Picker("时间区间", selection: $model.range) {
                ForEach(MarketRange.allCases, id: \.self) { range in
                    Text(rangeTitle(range)).tag(range)
                }
            }
        } label: {
            let isQuick = Self.quickRanges.contains(model.range)
            HStack(spacing: 4) {
                Text(isQuick ? "更多区间" : rangeTitle(model.range))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .foregroundStyle(isQuick ? GoldTheme.textSecondary : GoldTheme.goldSoft)
            .lineLimit(1).minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 30)
            .contentShape(GoldTheme.capsuleShape)
        }
        .accessibilityLabel("时间区间")
        .accessibilityValue(rangeTitle(model.range))
        .accessibilityIdentifier("chart.range")
    }

    private var scalePicker: some View {
        HStack(spacing: 2) {
            ForEach(ChartPriceScale.allCases, id: \.self) { scale in
                let isSelected = model.priceScale == scale
                Button { model.priceScale = scale } label: {
                    Text(scale.rawValue)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .frame(minWidth: 38, minHeight: 30)
                        .foregroundStyle(isSelected ? GoldTheme.onGold : GoldTheme.textSecondary)
                        .background(isSelected ? GoldTheme.gold : Color.clear, in: GoldTheme.capsuleShape)
                        .contentShape(GoldTheme.capsuleShape)
                }.buttonStyle(.plain)
                    .accessibilityLabel(scale.rawValue + "价格刻度")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier(scale == .linear ? "chart.scale.linear" : "chart.scale.log")
            }
        }
        .background(GoldTheme.background, in: GoldTheme.capsuleShape)
        .fixedSize()
    }

    private var resetButton: some View {
        Button { model.resetViewport() } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption2.weight(.semibold))
                Text("复位")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
            }
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(minHeight: 30)
            .foregroundStyle(model.canReset ? GoldTheme.goldSoft : GoldTheme.textFaint)
            .contentShape(GoldTheme.capsuleShape)
        }.buttonStyle(.plain).disabled(!model.canReset)
            .fixedSize().accessibilityIdentifier("chart.reset")
    }

    private var navigator: some View {
        VStack(spacing: 6) {
            if model.range == .realtime {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        realtimeWindowText.fixedSize()
                        Spacer(minLength: 0)
                        pointCount.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        realtimeWindowText.fixedSize(horizontal: false, vertical: true)
                        pointCount
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 4) {
                    Button { showingDates = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                            Text(windowLabel).monospacedDigit()
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                        }.font(.system(size: 12, weight: .medium)).foregroundStyle(GoldTheme.goldSoft)
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("chart.dates")
                    Spacer(minLength: 0)
                    pointCount
                }.lineLimit(1).minimumScaleFactor(0.8)
            }
            ChartRangeNavigator(points: model.points, bounds: model.fullDomain, window: model.xDomain,
                                scale: model.priceScale, daily: model.range != .realtime,
                                begin: model.beginNavigatorGesture, move: model.moveNavigator, end: model.endChartGesture)
                .disabled(model.points.isEmpty)
            HStack {
                Text(overviewLabel(model.fullDomain.lowerBound))
                Spacer()
                Text(overviewLabel(model.fullDomain.upperBound))
            }.font(.system(size: 10)).foregroundStyle(GoldTheme.textFaint)
            Text("区间内拖动浏览 · 两端缩放 · 主图单指查价")
                .font(.system(size: 11)).foregroundStyle(GoldTheme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private var realtimeWindowText: some View {
        Text(windowLabel).font(.caption.monospacedDigit()).foregroundStyle(GoldTheme.text)
    }

    private var pointCount: some View {
        Text("\(model.windowPoints.count) 个点").font(.caption).foregroundStyle(GoldTheme.textSecondary)
    }

    private func rangeTitle(_ range: MarketRange) -> String {
        if model.basis == .domestic, range == .history { return "全部历史" }
        return range.rawValue
    }

    private var windowLabel: String {
        let window = model.xDomain
        if model.range == .realtime {
            return model.realtimeTiming.windowLabel(window)
        }
        return window.lowerBound.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)) + " — " + window.upperBound.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }

    private var chartCaption: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                if model.range == .realtime {
                    Text(model.basis == .domestic ? "国内 Au99.99 · 元/克" : "国际伦敦金 · 人民币折算 / 克")
                    Text(model.realtimeTiming.caption)
                        .foregroundStyle(model.realtimeTiming.state == .paused ? GoldTheme.goldSoft : GoldTheme.textSecondary)
                } else {
                    Text(model.basis == .domestic ? "截至昨天 · 元/克 · Au99.99" : "截至昨天 · 元/克 · 按最新汇率折算")
                }
            }
            Button { showingHistorySources = true } label: {
                Image(systemName: "info.circle").foregroundStyle(GoldTheme.goldSoft)
            }.accessibilityLabel("行情数据说明")
        }.font(.system(size: 11)).foregroundStyle(GoldTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var trendChart: some View {
        let data = model.visiblePoints
        let domain = model.priceScale.domain(data.map(\.price))
        let baseline = domain.lowerBound
        let statistics = model.windowStatistics
        let resolvedMarkers: [ChartHoldingMarkerResolver.ResolvedMarker] = {
            guard showHoldingOverlay, let overlay = holdingOverlay, model.range != .realtime else { return [] }
            return ChartHoldingMarkerResolver.resolve(
                markers: overlay.markers,
                curvePoints: data,
                scale: model.priceScale,
                domain: domain
            )
        }()
        return ZStack {
            Chart {
                ForEach(data, id: \.date) { point in
                    AreaMark(x: .value("时间", point.date),
                             yStart: .value("基线", baseline),
                             yEnd: .value("价格刻度", model.priceScale.value(point.price) ?? domain.lowerBound))
                        .foregroundStyle(LinearGradient(
                            colors: [GoldTheme.chartFill, GoldTheme.gold.opacity(0)],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("时间", point.date), y: .value("价格刻度", model.priceScale.value(point.price) ?? domain.lowerBound))
                        .foregroundStyle(GoldTheme.gold)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                    if data.count == 1 {
                        PointMark(x: .value("时间", point.date), y: .value("价格刻度", model.priceScale.value(point.price) ?? domain.lowerBound))
                            .foregroundStyle(GoldTheme.gold)
                    }
                }
                if let high = statistics.high {
                    PointMark(x: .value("时间", high.date), y: .value("价格刻度", model.priceScale.value(high.price) ?? baseline))
                        .foregroundStyle(GoldTheme.goldSoft).symbolSize(24)
                }
                if let low = statistics.low, low.price != statistics.high?.price {
                    PointMark(x: .value("时间", low.date), y: .value("价格刻度", model.priceScale.value(low.price) ?? baseline))
                        .foregroundStyle(GoldTheme.goldSoft).symbolSize(24)
                }
                if showHoldingOverlay, let overlay = holdingOverlay {
                    if let breakEven = overlay.breakEvenPrice,
                       let scaled = model.priceScale.value(breakEven),
                       domain.contains(scaled) {
                        RuleMark(y: .value("保本价", scaled))
                            .foregroundStyle(GoldTheme.goldSoft.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("保本 ¥\(breakEven.moneyText)")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(GoldTheme.onGold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(GoldTheme.goldSoft.opacity(0.92), in: GoldTheme.rangeShape)
                            }
                    }
                    ForEach(resolvedMarkers) { item in
                        if let range = item.connectorRange, let anchor = item.scaledMarketAnchor {
                            RuleMark(
                                x: .value("时间", item.marker.date),
                                yStart: .value("价格刻度", range.lowerBound),
                                yEnd: .value("价格刻度", range.upperBound)
                            )
                            .foregroundStyle(GoldTheme.up.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))

                            PointMark(
                                x: .value("时间", item.marker.date),
                                y: .value("价格刻度", anchor)
                            )
                            .foregroundStyle(GoldTheme.up.opacity(0.55))
                            .symbolSize(16)
                        }
                        PointMark(
                            x: .value("时间", item.marker.date),
                            y: .value("价格刻度", item.scaledCost)
                        )
                        .foregroundStyle(GoldTheme.up)
                        .symbolSize(46)
                    }
                }
                if let point = model.selectedPoint {
                    RuleMark(x: .value("时间", point.date))
                        .foregroundStyle(GoldTheme.gold.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 0.6))
                    PointMark(x: .value("时间", point.date), y: .value("价格刻度", model.priceScale.value(point.price) ?? domain.lowerBound))
                        .foregroundStyle(GoldTheme.gold)
                        .symbolSize(32)
                }
            }
            .chartYScale(domain: domain)
            .chartXScale(domain: model.xDomain)
            .chartXScale(range: .plotDimension(startPadding: 0, endPadding: 0))
            .chartXAxis {
                AxisMarks(values: model.axisDates) { value in
                    AxisValueLabel(anchor: value.index == 0 ? .topLeading : (value.index == model.axisDates.count - 1 ? .topTrailing : .top)) {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(date)).font(.system(size: 10)).foregroundStyle(GoldTheme.textSecondary)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartPlotStyle { plot in plot.clipped() }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        let frame = geometry[plotFrame]
                        if model.selectedPoint == nil {
                            if let high = statistics.high {
                                extremumLabel(high, title: high.price == statistics.low?.price ? "最高 / 最低" : "最高", above: true, other: high.price == statistics.low?.price ? nil : statistics.low, proxy: proxy, frame: frame)
                            }
                            if let low = statistics.low, low.price != statistics.high?.price {
                                extremumLabel(low, title: "最低", above: false, other: statistics.high, proxy: proxy, frame: frame)
                            }
                        }
                        ChartGestureSurface(begin: model.beginChartGesture,
                                            transform: model.transformChart,
                                            end: model.endChartGesture,
                                            select: model.selectChart,
                                            reset: model.resetViewport)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .accessibilityLabel("走势图时间轴")
                            .accessibilityValue("\(axisLabel(model.xDomain.lowerBound))至\(axisLabel(model.xDomain.upperBound))")
                            .accessibilityAction(named: "放大") { model.accessibleZoom(2) }
                            .accessibilityAction(named: "缩小") { model.accessibleZoom(0.5) }
                            .accessibilityAction(named: "复位") { model.resetViewport() }
                    }
                    if let point = model.selectedPoint, let x = proxy.position(forX: point.date) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("¥ " + point.price.formatted(.number.precision(.fractionLength(2))))
                                .font(.system(size: 14, weight: .semibold))
                            Text(pointLabel(point))
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(GoldTheme.gold)
                        .padding(10)
                        .frame(width: 162, alignment: .leading)
                        .background(GoldTheme.card, in: GoldTheme.rangeShape)
                        .position(x: min(max(x + (proxy.plotFrame.map { geometry[$0].minX } ?? 0) + 82, 81), max(81, geometry.size.width - 81)), y: 32)
                        .allowsHitTesting(false)
                    }
                }
            }
            if data.isEmpty {
                Text(model.chartLoading ? "正在加载走势…" : (model.range == .realtime ? "暂无最新走势" : "暂无走势数据"))
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
            }
        }
    }
    @ViewBuilder
    private func extremumLabel(_ point: MarketChartPoint, title: String, above: Bool, other: MarketChartPoint?, proxy: ChartProxy, frame: CGRect) -> some View {
        if let value = model.priceScale.value(point.price),
           let x = proxy.position(forX: point.date), let y = proxy.position(forY: value) {
            let width = min(126.0, frame.width)
            let centerX = min(max(frame.minX + x, frame.minX + width / 2), frame.maxX - width / 2)
            let otherY = other.flatMap { model.priceScale.value($0.price) }.flatMap { proxy.position(forY: $0) }
            let centerY = frame.minY + ChartExtremaLabelLayout.y(point: y, other: otherY.map { Double($0) }, height: frame.height, above: above)
            VStack(spacing: 3) {
                Text(title + " ¥" + point.price.formatted(.number.precision(.fractionLength(2))))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(GoldTheme.goldSoft)
                Text(pointLabel(point))
                    .font(.system(size: 9)).foregroundStyle(GoldTheme.textSecondary)
            }
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                .frame(width: width, height: 40)
                .background(GoldTheme.card.opacity(0.95), in: GoldTheme.rangeShape)
                .position(x: centerX, y: centerY)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title + " " + point.price.formatted(.number.precision(.fractionLength(2))) + " 元每克，" + pointLabel(point))
                .allowsHitTesting(false)
        }
    }

    private func overviewLabel(_ date: Date) -> String {
        if model.range != .realtime { return date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)) }
        return axisLabel(date)
    }
    private func axisLabel(_ date: Date) -> String {
        let span = model.xDomain.upperBound.timeIntervalSince(model.xDomain.lowerBound)
        if span > 730 * 86400 { return date.formatted(.dateTime.year()) }
        if model.range != .realtime { return date.formatted(.dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits)) }
        return model.realtimeTiming.axisLabel(date, window: model.xDomain)
    }
    private func pointLabel(_ point: MarketChartPoint) -> String {
        switch point.granularity {
        case .annual: return point.date.formatted(.dateTime.year()) + " · 年均价参考"
        case .daily: return point.date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)) + " · 收盘"
        case .realtime: return point.date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
        }
    }

}

/// Measure fixed controls first, then give the chart the actual remaining height.
/// Large accessibility text can exceed the screen and use the parent scroll view.
private struct MarketDashboardLayout: Layout {
    let availableHeight: CGFloat
    private let spacing: CGFloat = 10
    private let minimumChartHeight: CGFloat = 140

    private func measurements(width: CGFloat, subviews: Subviews) -> (heights: [CGFloat], total: CGFloat) {
        let proposal = ProposedViewSize(width: width, height: nil)
        var heights = subviews.enumerated().map { index, view in
            index == 3 ? 0 : view.sizeThatFits(proposal).height
        }
        let fixedHeight = heights.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1))
        if heights.indices.contains(3) {
            heights[3] = max(minimumChartHeight, availableHeight - fixedHeight)
        }
        return (heights, heights.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1)))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: measurements(width: width, subviews: subviews).total)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let heights = measurements(width: bounds.width, subviews: subviews).heights
        var y = bounds.minY
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                       proposal: ProposedViewSize(width: bounds.width, height: heights[index]))
            y += heights[index] + spacing
        }
    }
}

/// 走势图买入红点与当日大盘曲线落点的纯计算逻辑（Sendable，独立可测）。
enum ChartHoldingMarkerResolver: Sendable {
    struct ResolvedMarker: Identifiable, Equatable, Sendable {
        let marker: MarketHoldingOverlay.PurchaseMarker
        /// 真实买入综合均价在当前价格刻度下的纵坐标。
        let scaledCost: Double
        /// 匹配到的当日/区间大盘参考金价（人民币/克，未做刻度映射）。
        let marketAnchorPrice: Double?
        /// 大盘参考金价在当前价格刻度下的纵坐标（仅当落在 domain 内时有效）。
        let scaledMarketAnchor: Double?

        var id: Date { marker.id }

        /// 垂直细虚线连接范围（保证 lowerBound < upperBound 且两端均在 domain 内）。
        var connectorRange: ClosedRange<Double>? {
            guard let anchor = scaledMarketAnchor else { return nil }
            let low = min(scaledCost, anchor)
            let high = max(scaledCost, anchor)
            guard high - low > 1e-9 else { return nil }
            return low...high
        }
    }

    /// 为指定买入日期匹配大盘金价：
    /// 1. 优先精确命中同一自然日的交易日收盘价；
    /// 2. 若落在休市/周末（介于前后两交易日之间），按时间比例在前后两点间线性插值；
    /// 3. 若早于曲线首点或晚于末点，回退至同一区间内最近的交易日价格；
    /// 4. 空曲线或无有效正价格时返回 nil。
    static func marketAnchorPrice(
        for date: Date,
        in points: [MarketChartPoint],
        calendar: Calendar = .current
    ) -> Double? {
        let valid = points
            .filter { $0.price.isFinite && $0.price > 0 }
            .sorted { $0.date < $1.date }
        return marketAnchorPriceSorted(for: date, in: valid, calendar: calendar)
    }

    /// 将持仓买入标记安全映射至当前刻度与纵轴 domain：
    /// - 真实买入均价若超出 domain 则跳过不绘制；
    /// - 仅当大盘锚点坐标也位于 domain 内时，才提供垂直连接线与曲线锚点。
    static func resolve(
        markers: [MarketHoldingOverlay.PurchaseMarker],
        curvePoints: [MarketChartPoint],
        scale: ChartPriceScale,
        domain: ClosedRange<Double>,
        calendar: Calendar = .current
    ) -> [ResolvedMarker] {
        let validPoints = curvePoints
            .filter { $0.price.isFinite && $0.price > 0 }
            .sorted { $0.date < $1.date }

        return markers.compactMap { marker in
            guard let scaledCost = scale.value(marker.averageUnitPrice),
                  domain.contains(scaledCost) else {
                return nil
            }
            let anchorPrice = marketAnchorPriceSorted(for: marker.date, in: validPoints, calendar: calendar)
            let scaledAnchor: Double? = anchorPrice.flatMap { price in
                guard let scaled = scale.value(price), domain.contains(scaled) else { return nil }
                return scaled
            }
            return ResolvedMarker(
                marker: marker,
                scaledCost: scaledCost,
                marketAnchorPrice: anchorPrice,
                scaledMarketAnchor: scaledAnchor
            )
        }
    }

    private static func marketAnchorPriceSorted(
        for date: Date,
        in sortedPoints: [MarketChartPoint],
        calendar: Calendar
    ) -> Double? {
        guard !sortedPoints.isEmpty else { return nil }

        if let exact = sortedPoints.last(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            return exact.price
        }
        if date <= sortedPoints[0].date {
            return sortedPoints[0].price
        }
        if date >= sortedPoints[sortedPoints.count - 1].date {
            return sortedPoints[sortedPoints.count - 1].price
        }

        var low = 0
        var high = sortedPoints.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if sortedPoints[mid].date < date {
                low = mid
            } else {
                high = mid
            }
        }
        let previous = sortedPoints[low]
        let next = sortedPoints[high]
        let span = next.date.timeIntervalSince(previous.date)
        guard span > 0 else { return previous.price }
        let ratio = date.timeIntervalSince(previous.date) / span
        return previous.price + (next.price - previous.price) * ratio
    }
}
