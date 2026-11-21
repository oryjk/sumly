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
    var hideAmounts: Bool = false
    var highlightedMarkerID: Date? = nil
    var onToggleHoldingOverlay: (() -> Void)? = nil
    var onSelectPurchaseMarker: ((ChartHoldingMarkerResolver.ResolvedMarker) -> Void)? = nil
    @State private var markerTapFeedbackTrigger = 0

    private static let quickRanges: [MarketRange] = [.realtime, .month, .quarter, .year, .fiveYears]

    private var quoteSnapshot: MarketQuoteSnapshot? {
        model.quote.flatMap { MarketQuoteSnapshot.make(from: $0, basis: model.basis) }
    }

    var body: some View {
        let visibleData = model.visiblePoints
        let priceDomain = model.priceScale.domain(visibleData.map(\.price))
        let resolvedMarkers: [ChartHoldingMarkerResolver.ResolvedMarker] = {
            guard showHoldingOverlay, let overlay = holdingOverlay, model.range != .realtime else { return [] }
            return ChartHoldingMarkerResolver.resolve(
                markers: overlay.markers,
                curvePoints: visibleData,
                scale: model.priceScale,
                domain: priceDomain
            )
        }()
        MarketDashboardLayout(availableHeight: availableHeight) {
            quoteHeader
            chartControls
            VStack(alignment: .leading, spacing: 6) {
                chartCaption
                HStack(spacing: 6) {
                    ChartWindowSummary(statistics: model.windowStatistics)
                    if showHoldingOverlay, let breakEven = holdingOverlay?.breakEvenPrice {
                        Text("· 保本 ¥\(breakEven.moneyText)")
                            .font(.system(size: 12, weight: .medium)).monospacedDigit()
                            .foregroundStyle(GoldTheme.goldSoft)
                            .lineLimit(1)
                    }
                    if showHoldingOverlay, !resolvedMarkers.isEmpty {
                        HStack(spacing: 4) {
                            Text("·")
                                .foregroundStyle(GoldTheme.textSecondary)
                            Circle()
                                .fill(GoldTheme.up)
                                .frame(width: 6, height: 6)
                            Text("买入点")
                                .foregroundStyle(GoldTheme.textSecondary)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("红点代表历史买入成本")
                    }
                }
                .minimumScaleFactor(0.82)
            }.frame(maxWidth: .infinity, alignment: .leading)

            if model.range == .realtime || model.range.dateBounds() != nil {
                trendChart(data: visibleData, domain: priceDomain, resolvedMarkers: resolvedMarkers)
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
        .sensoryFeedback(.impact(weight: .light), trigger: markerTapFeedbackTrigger)
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
                    Text("持仓")
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
            .accessibilityLabel("在走势图叠加持仓保本线与买入点")
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

    private func trendChart(
        data: [MarketChartPoint],
        domain: ClosedRange<Double>,
        resolvedMarkers: [ChartHoldingMarkerResolver.ResolvedMarker]
    ) -> some View {
        let baseline = domain.lowerBound
        let statistics = model.windowStatistics
        let inspectedMarkerMatch: ChartHoldingMarkerResolver.MatchedInspectionMarker? = {
            guard showHoldingOverlay, let point = model.selectedPoint, !resolvedMarkers.isEmpty else { return nil }
            return ChartHoldingMarkerResolver.matchForInspection(
                selectedDate: point.date,
                curvePoints: data,
                resolvedMarkers: resolvedMarkers
            )
        }()
        let activeMarkerID = highlightedMarkerID ?? inspectedMarkerMatch?.resolved.id

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
                        let isActive = item.id == activeMarkerID
                        if let range = item.connectorRange, let anchor = item.scaledMarketAnchor {
                            RuleMark(
                                x: .value("时间", item.marker.date),
                                yStart: .value("价格刻度", range.lowerBound),
                                yEnd: .value("价格刻度", range.upperBound)
                            )
                            .foregroundStyle(GoldTheme.up.opacity(isActive ? 0.9 : 0.45))
                            .lineStyle(StrokeStyle(
                                lineWidth: isActive ? 1.8 : 1,
                                dash: isActive ? [3, 2.5] : [2.5, 2.5]
                            ))

                            PointMark(
                                x: .value("时间", item.marker.date),
                                y: .value("价格刻度", anchor)
                            )
                            .foregroundStyle(GoldTheme.up.opacity(isActive ? 0.92 : 0.55))
                            .symbolSize(isActive ? 28 : 16)
                        }
                        PointMark(
                            x: .value("时间", item.marker.date),
                            y: .value("价格刻度", item.scaledCost)
                        )
                        .symbol {
                            purchaseMarkerSymbol(count: item.marker.count, isActive: isActive)
                        }
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
                        let markerScreenPoints: [ChartHoldingMarkerResolver.MarkerScreenPoint] = resolvedMarkers.compactMap { item in
                            guard let x = proxy.position(forX: item.marker.date),
                                  let y = proxy.position(forY: item.scaledCost),
                                  x >= 0, x <= frame.width,
                                  y >= 0, y <= frame.height else {
                                return nil
                            }
                            return ChartHoldingMarkerResolver.MarkerScreenPoint(
                                resolved: item,
                                point: CGPoint(x: x, y: y)
                            )
                        }

                        if model.selectedPoint == nil {
                            if let high = statistics.high {
                                extremumLabel(high, title: high.price == statistics.low?.price ? "最高 / 最低" : "最高", above: true, other: high.price == statistics.low?.price ? nil : statistics.low, proxy: proxy, frame: frame)
                            }
                            if let low = statistics.low, low.price != statistics.high?.price {
                                extremumLabel(low, title: "最低", above: false, other: statistics.high, proxy: proxy, frame: frame)
                            }
                        }

                        ForEach(markerScreenPoints, id: \.resolved.id) { screenPoint in
                            if let badge = ChartPurchaseMarkerPresentation.badgeText(for: screenPoint.resolved.marker.count) {
                                let isActive = screenPoint.resolved.id == activeMarkerID
                                let badgeCenterX = min(max(frame.minX + screenPoint.point.x + 10, frame.minX + 10), frame.maxX - 10)
                                let badgeCenterY = min(max(frame.minY + screenPoint.point.y - 10, frame.minY + 9), frame.maxY - 9)
                                Text(badge)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(isActive ? GoldTheme.onGold : GoldTheme.text)
                                    .padding(.horizontal, badge.count > 1 ? 4 : 0)
                                    .frame(minWidth: 15, minHeight: 15)
                                    .background(isActive ? GoldTheme.goldSoft : GoldTheme.card, in: GoldTheme.capsuleShape)
                                    .overlay(GoldTheme.capsuleShape.strokeBorder(isActive ? GoldTheme.gold : GoldTheme.up, lineWidth: 1))
                                    .position(x: badgeCenterX, y: badgeCenterY)
                                    .allowsHitTesting(false)
                            }
                        }

                        ChartGestureSurface(
                            begin: model.beginChartGesture,
                            transform: model.transformChart,
                            end: model.endChartGesture,
                            select: model.selectChart,
                            reset: model.resetViewport,
                            tapPoint: { location in
                                guard onSelectPurchaseMarker != nil,
                                      let hit = ChartHoldingMarkerResolver.hitTest(
                                          tapPoint: location,
                                          markerPoints: markerScreenPoints
                                      ) else {
                                    return false
                                }
                                markerTapFeedbackTrigger &+= 1
                                onSelectPurchaseMarker?(hit)
                                return true
                            }
                        )
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .accessibilityLabel("走势图时间轴")
                            .accessibilityValue("\(axisLabel(model.xDomain.lowerBound))至\(axisLabel(model.xDomain.upperBound))")
                            .accessibilityAction(named: "放大") { model.accessibleZoom(2) }
                            .accessibilityAction(named: "缩小") { model.accessibleZoom(0.5) }
                            .accessibilityAction(named: "复位") { model.resetViewport() }
                    }
                    if let point = model.selectedPoint, let x = proxy.position(forX: point.date) {
                        inspectionTooltip(
                            for: point,
                            markerMatch: inspectedMarkerMatch,
                            pointXInPlot: x,
                            plotMinX: proxy.plotFrame.map { geometry[$0].minX } ?? 0,
                            containerSize: geometry.size
                        )
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
    private func purchaseMarkerSymbol(count: Int, isActive: Bool) -> some View {
        let isMultiple = count >= 2
        let coreSize: CGFloat = isMultiple ? (isActive ? 11 : 9) : (isActive ? 10 : 7.5)
        ZStack {
            if isActive {
                Circle()
                    .fill(GoldTheme.up.opacity(0.28))
                    .frame(width: coreSize + 10, height: coreSize + 10)
            }
            if isMultiple {
                Circle()
                    .fill(GoldTheme.background)
                    .frame(width: coreSize + 4.5, height: coreSize + 4.5)
                Circle()
                    .strokeBorder(isActive ? GoldTheme.gold : GoldTheme.goldSoft, lineWidth: isActive ? 1.5 : 1.2)
                    .frame(width: coreSize + 4.5, height: coreSize + 4.5)
            } else if isActive {
                Circle()
                    .strokeBorder(GoldTheme.text.opacity(0.9), lineWidth: 1.3)
                    .frame(width: coreSize + 2.5, height: coreSize + 2.5)
            }
            Circle()
                .fill(GoldTheme.up)
                .frame(width: coreSize, height: coreSize)
        }
    }

    @ViewBuilder
    private func inspectionTooltip(
        for point: MarketChartPoint,
        markerMatch: ChartHoldingMarkerResolver.MatchedInspectionMarker?,
        pointXInPlot: CGFloat,
        plotMinX: CGFloat,
        containerSize: CGSize
    ) -> some View {
        let tooltipContent = markerMatch.map {
            ChartPurchaseMarkerPresentation.inspectionTooltip(
                match: $0,
                selectedPoint: point,
                hideAmounts: hideAmounts
            )
        }
        let targetWidth: CGFloat = tooltipContent == nil ? 162 : min(204, max(172, containerSize.width - 12))
        let anchorX = plotMinX + pointXInPlot
        let preferredLeft: CGFloat = {
            let rightCandidate = anchorX + 10
            if rightCandidate + targetWidth <= containerSize.width - 4 {
                return rightCandidate
            }
            return anchorX - 10 - targetWidth
        }()
        let clampedLeft = min(max(preferredLeft, 4), max(4, containerSize.width - targetWidth - 4))

        VStack(alignment: .leading, spacing: 4) {
            Text("¥ " + point.price.formatted(.number.precision(.fractionLength(2))))
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(GoldTheme.gold)
            Text(pointLabel(point))
                .font(.system(size: 11))
                .foregroundStyle(GoldTheme.goldSoft)
                .lineLimit(1)

            if let tooltipContent {
                GoldTheme.cardStroke.frame(height: 1)
                    .padding(.vertical, 2)

                if let dateBadge = tooltipContent.dateBadge {
                    Text(dateBadge)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(GoldTheme.goldSoft)
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Circle()
                        .fill(GoldTheme.up)
                        .frame(width: 6, height: 6)
                    Text(tooltipContent.headline)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                HStack(spacing: 6) {
                    Text(tooltipContent.primaryMetric)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if let spread = tooltipContent.spread {
                        Text(spread.compactText)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(spread.sentiment.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                if let secondary = tooltipContent.secondaryMetric {
                    Text(secondary)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                if let footerHint = tooltipContent.footerHint {
                    HStack(spacing: 3) {
                        Text(footerHint)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(GoldTheme.goldSoft)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: targetWidth, alignment: .leading)
        .background(GoldTheme.card.opacity(0.96), in: GoldTheme.rangeShape)
        .overlay(GoldTheme.rangeShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .offset(x: clampedLeft, y: 4)
        .allowsHitTesting(false)
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
        /// 当日是否为非交易日（周末/休市），大盘参考价由临近交易日插值或回退得出。
        let isInterpolatedMarketAnchor: Bool

        init(
            marker: MarketHoldingOverlay.PurchaseMarker,
            scaledCost: Double,
            marketAnchorPrice: Double?,
            scaledMarketAnchor: Double?,
            isInterpolatedMarketAnchor: Bool = false
        ) {
            self.marker = marker
            self.scaledCost = scaledCost
            self.marketAnchorPrice = marketAnchorPrice
            self.scaledMarketAnchor = scaledMarketAnchor
            self.isInterpolatedMarketAnchor = isInterpolatedMarketAnchor
        }

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

    struct MatchedInspectionMarker: Equatable, Sendable {
        let resolved: ResolvedMarker
        /// 是否精确匹配同一自然日；false 表示买入日为休市/周末并吸附到了临近交易日。
        let isSameDay: Bool
        /// 与当前滑动查价日期相差的自然日数（同日为 0，临近吸附为 1 或 2）。
        let dayDistance: Int
    }

    struct MarkerScreenPoint: Equatable, Sendable {
        let resolved: ResolvedMarker
        /// 相对于图表 plotFrame 左上角的坐标点。
        let point: CGPoint
    }

    /// 44pt 隐形命中热区半径（直径 44pt）。
    static let defaultHitRadius: CGFloat = 22

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
            let hasExactTradingDay = validPoints.contains { calendar.isDate($0.date, inSameDayAs: marker.date) }
            let anchorPrice = marketAnchorPriceSorted(for: marker.date, in: validPoints, calendar: calendar)
            let scaledAnchor: Double? = anchorPrice.flatMap { price in
                guard let scaled = scale.value(price), domain.contains(scaled) else { return nil }
                return scaled
            }
            return ResolvedMarker(
                marker: marker,
                scaledCost: scaledCost,
                marketAnchorPrice: anchorPrice,
                scaledMarketAnchor: scaledAnchor,
                isInterpolatedMarketAnchor: anchorPrice != nil && !hasExactTradingDay
            )
        }
    }

    /// 单指滑动查价自动匹配买入红点：
    /// 1. 优先精确命中与 `selectedDate` 同一自然日的买入红点；
    /// 2. 若无同日红点，仅对本身在 `curvePoints` 中无同日交易数据的休市/周末红点，在临近 2 个自然日内匹配最靠近且无冲突的红点
    ///    （每个休市红点仅唯一吸附到距离其最近的交易日，若等距则优先吸附至更早的节前收盘日）。
    static func matchForInspection(
        selectedDate: Date,
        curvePoints: [MarketChartPoint],
        resolvedMarkers: [ResolvedMarker],
        maxCalendarDayDistance: Int = 2,
        calendar: Calendar = .current
    ) -> MatchedInspectionMarker? {
        guard !resolvedMarkers.isEmpty else { return nil }

        if let exact = resolvedMarkers.first(where: { calendar.isDate($0.marker.date, inSameDayAs: selectedDate) }) {
            return MatchedInspectionMarker(resolved: exact, isSameDay: true, dayDistance: 0)
        }

        guard maxCalendarDayDistance > 0 else { return nil }
        let selectedDayStart = calendar.startOfDay(for: selectedDate)
        let tradingDayStarts = Array(Set(
            curvePoints
                .filter { $0.price.isFinite && $0.price > 0 }
                .map { calendar.startOfDay(for: $0.date) }
        )).sorted()

        var bestCandidate: (resolved: ResolvedMarker, dayDistance: Int)?
        for item in resolvedMarkers {
            let markerDayStart = calendar.startOfDay(for: item.marker.date)
            // 本身就在交易日上的红点只应由对应交易日触发，不跨日抢占相邻交易日。
            if tradingDayStarts.contains(markerDayStart) { continue }

            let dayDistance = abs(calendar.dateComponents([.day], from: selectedDayStart, to: markerDayStart).day ?? Int.max)
            guard dayDistance > 0, dayDistance <= maxCalendarDayDistance else { continue }

            // 若曲线上存在交易日，仅当 selectedDayStart 是距离该休市红点最近的交易日（等距取更早交易日）时才允许吸附，确保唯一无冲突。
            if !tradingDayStarts.isEmpty {
                let nearestTradingDay = tradingDayStarts.min { lhs, rhs in
                    let dl = abs(calendar.dateComponents([.day], from: lhs, to: markerDayStart).day ?? Int.max)
                    let dr = abs(calendar.dateComponents([.day], from: rhs, to: markerDayStart).day ?? Int.max)
                    if dl != dr { return dl < dr }
                    return lhs < rhs
                }
                guard nearestTradingDay == selectedDayStart else { continue }
            }

            if let current = bestCandidate {
                if dayDistance < current.dayDistance || (dayDistance == current.dayDistance && item.marker.date > current.resolved.marker.date) {
                    bestCandidate = (item, dayDistance)
                }
            } else {
                bestCandidate = (item, dayDistance)
            }
        }

        guard let bestCandidate else { return nil }
        return MatchedInspectionMarker(
            resolved: bestCandidate.resolved,
            isSameDay: false,
            dayDistance: bestCandidate.dayDistance
        )
    }

    /// 44pt 隐形命中热区判定：返回欧氏距离 ≤ `hitRadius`（默认 22pt）内的最近红点；未命中返回 nil。
    static func hitTest(
        tapPoint: CGPoint,
        markerPoints: [MarkerScreenPoint],
        hitRadius: CGFloat = defaultHitRadius
    ) -> ResolvedMarker? {
        guard hitRadius >= 0, tapPoint.x.isFinite, tapPoint.y.isFinite else { return nil }
        let maxDistanceSquared = hitRadius * hitRadius
        var best: (resolved: ResolvedMarker, distanceSquared: CGFloat)?
        for candidate in markerPoints {
            guard candidate.point.x.isFinite, candidate.point.y.isFinite else { continue }
            let dx = candidate.point.x - tapPoint.x
            let dy = candidate.point.y - tapPoint.y
            let distSq = dx * dx + dy * dy
            guard distSq <= maxDistanceSquared else { continue }
            if let current = best {
                if distSq < current.distanceSquared || (distSq == current.distanceSquared && candidate.resolved.marker.date > current.resolved.marker.date) {
                    best = (candidate.resolved, distSq)
                }
            } else {
                best = (candidate.resolved, distSq)
            }
        }
        return best?.resolved
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
