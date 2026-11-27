import SwiftUI

/// 方案 A：当日完整分时图（红涨绿跌情绪色 + 昨收基准虚线 + 3 档极简双侧刻度 + 国内日/夜盘无断档连续轴 + 尾端呼吸脉冲点）。
/// 严格基于 `GoldTheme` 视觉令牌绘制，零硬编码颜色。
struct RealtimeIntradayChartView: View {
    let points: [ProjectedIntradayPoint]
    let axis: RealtimeIntradayAxis
    let referenceClose: Double?
    let priceScale: ChartPriceScale
    let isZoomed: Bool
    let isLive: Bool
    let selectedPoint: ProjectedIntradayPoint?
    let breakEvenPrice: Double?
    let onBeginGesture: () -> Void
    let onTransform: (Double, Double, Double) -> Void
    let onEndGesture: () -> Void
    let onSelectSlotFraction: (Double) -> Void
    let onReset: () -> Void
    let pointTimeLabel: (Date) -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseExpanded = false

    private var slotRange: ClosedRange<Double> {
        if isZoomed, let first = points.first?.slot, let last = points.last?.slot, last > first {
            return first...last
        }
        return 0...max(1, axis.totalSlots)
    }

    private var yDomain: ClosedRange<Double> {
        RealtimeIntradayAxis.intradayDomain(
            prices: points.map(\.price),
            referenceClose: referenceClose,
            scale: priceScale
        )
    }

    private var highPoint: ProjectedIntradayPoint? {
        points.max { a, b in a.price == b.price ? a.slot > b.slot : a.price < b.price }
    }

    private var lowPoint: ProjectedIntradayPoint? {
        points.min { a, b in a.price == b.price ? a.slot > b.slot : a.price < b.price }
    }

    private func inversePrice(_ scaled: Double) -> Double {
        priceScale == .linear ? scaled : pow(10, scaled)
    }

    private func signedPercent(_ price: Double, base: Double) -> String {
        let pct = (price - base) / base * 100
        let rounded = (pct * 100).rounded() / 100
        let display = rounded == 0 ? 0 : rounded
        return (rounded > 0 ? "+" : "") + String(format: "%.2f%%", display)
    }

    private func signedMoney(_ diff: Double) -> String {
        let rounded = (diff * 100).rounded() / 100
        let display = rounded == 0 ? 0 : rounded
        return (rounded > 0 ? "+" : "") + String(format: "%.2f", display)
    }

    var body: some View {
        let domain = yDomain
        let slots = slotRange
        let ref = referenceClose
        let segments: [IntradaySplitSegment] = {
            guard let ref else { return [] }
            return RealtimeIntradayAxis.splitSegments(points: points, referenceClose: ref)
        }()

        VStack(spacing: 4) {
            GeometryReader { geo in
                let plot = CGRect(x: 2, y: 12, width: max(1, geo.size.width - 4), height: max(1, geo.size.height - 16))
                let slotSpan = max(1e-6, slots.upperBound - slots.lowerBound)
                let ySpan = max(1e-9, domain.upperBound - domain.lowerBound)

                let xForSlot: (Double) -> CGFloat = { slot in
                    let frac = (slot - slots.lowerBound) / slotSpan
                    return plot.minX + CGFloat(frac) * plot.width
                }
                let yForPrice: (Double) -> CGFloat = { price in
                    let v = priceScale.value(price) ?? domain.lowerBound
                    let frac = (v - domain.lowerBound) / ySpan
                    return plot.maxY - CGFloat(frac) * plot.height
                }

                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in
                        // 1. 顶部与底部极细边界辅助线
                        var borderGrid = Path()
                        borderGrid.move(to: CGPoint(x: plot.minX, y: plot.minY))
                        borderGrid.addLine(to: CGPoint(x: plot.maxX, y: plot.minY))
                        borderGrid.move(to: CGPoint(x: plot.minX, y: plot.maxY))
                        borderGrid.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
                        ctx.stroke(borderGrid, with: .color(GoldTheme.gridline), lineWidth: 1)

                        // 2. 未到交易时段右侧轻留白提示（仅全天未缩放态）
                        if !isZoomed, let lastSlot = points.last?.slot {
                            let lastX = min(max(xForSlot(lastSlot), plot.minX), plot.maxX)
                            if lastX < plot.maxX - 2 {
                                let futureRect = CGRect(x: lastX, y: plot.minY, width: plot.maxX - lastX, height: plot.height)
                                ctx.fill(Path(futureRect), with: .color(GoldTheme.text.opacity(0.022)))
                            }
                        }

                        // 3. 国内午休 / 20:00 夜盘时段分界竖虚线
                        for divider in axis.dividers where slots.contains(divider.slot) {
                            let dx = xForSlot(divider.slot)
                            var vPath = Path()
                            vPath.move(to: CGPoint(x: dx, y: plot.minY))
                            vPath.addLine(to: CGPoint(x: dx, y: plot.maxY))
                            ctx.stroke(
                                vPath,
                                with: .color(GoldTheme.goldSoft.opacity(0.22)),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                            )
                        }

                        // 4. 昨收基准水平虚线（0.00% 平盘线）
                        let baseY: CGFloat? = ref.map { yForPrice($0) }
                        if let baseY, baseY >= plot.minY - 1, baseY <= plot.maxY + 1 {
                            var basePath = Path()
                            basePath.move(to: CGPoint(x: plot.minX, y: baseY))
                            basePath.addLine(to: CGPoint(x: plot.maxX, y: baseY))
                            ctx.stroke(
                                basePath,
                                with: .color(GoldTheme.goldSoft.opacity(0.55)),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                        }

                        // 5. 持仓保本虚线（若开启叠加且落在视口纵轴范围内）
                        if let breakEven = breakEvenPrice,
                           let scaledBE = priceScale.value(breakEven),
                           domain.contains(scaledBE) {
                            let by = yForPrice(breakEven)
                            var bePath = Path()
                            bePath.move(to: CGPoint(x: plot.minX, y: by))
                            bePath.addLine(to: CGPoint(x: plot.maxX, y: by))
                            ctx.stroke(
                                bePath,
                                with: .color(GoldTheme.goldSoft.opacity(0.75)),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                            )
                        }

                        // 6. 方案 A 红涨绿跌曲线与向昨收线渐隐填充
                        if let baseY, !segments.isEmpty {
                            let clampedBaseY = min(max(baseY, plot.minY), plot.maxY)
                            for segment in segments where !segment.vertices.isEmpty {
                                let cgPoints = segment.vertices.map { CGPoint(x: xForSlot($0.slot), y: yForPrice($0.price)) }
                                let strokeColor = segment.isAboveOrEqual ? GoldTheme.up : GoldTheme.down

                                if cgPoints.count >= 2 {
                                    var line = Path()
                                    line.move(to: cgPoints[0])
                                    for pt in cgPoints.dropFirst() { line.addLine(to: pt) }

                                    var fill = line
                                    fill.addLine(to: CGPoint(x: cgPoints.last!.x, y: clampedBaseY))
                                    fill.addLine(to: CGPoint(x: cgPoints.first!.x, y: clampedBaseY))
                                    fill.closeSubpath()

                                    let gradient: Gradient = segment.isAboveOrEqual
                                        ? Gradient(colors: [GoldTheme.up.opacity(0.32), GoldTheme.up.opacity(0.02)])
                                        : Gradient(colors: [GoldTheme.down.opacity(0.02), GoldTheme.down.opacity(0.32)])
                                    let startPoint = segment.isAboveOrEqual
                                        ? CGPoint(x: plot.midX, y: plot.minY)
                                        : CGPoint(x: plot.midX, y: clampedBaseY)
                                    let endPoint = segment.isAboveOrEqual
                                        ? CGPoint(x: plot.midX, y: clampedBaseY)
                                        : CGPoint(x: plot.midX, y: plot.maxY)

                                    ctx.fill(fill, with: .linearGradient(gradient, startPoint: startPoint, endPoint: endPoint))
                                    ctx.stroke(
                                        line,
                                        with: .color(strokeColor),
                                        style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                                    )
                                } else if let single = cgPoints.first {
                                    let dot = CGRect(x: single.x - 3, y: single.y - 3, width: 6, height: 6)
                                    ctx.fill(Path(ellipseIn: dot), with: .color(strokeColor))
                                }
                            }
                        } else if !points.isEmpty {
                            // 无昨收基准时的安全回退（金色曲线）
                            let cgPoints = points.map { CGPoint(x: xForSlot($0.slot), y: yForPrice($0.price)) }
                            if cgPoints.count >= 2 {
                                var line = Path()
                                line.move(to: cgPoints[0])
                                for pt in cgPoints.dropFirst() { line.addLine(to: pt) }
                                var fill = line
                                fill.addLine(to: CGPoint(x: cgPoints.last!.x, y: plot.maxY))
                                fill.addLine(to: CGPoint(x: cgPoints.first!.x, y: plot.maxY))
                                fill.closeSubpath()
                                ctx.fill(
                                    fill,
                                    with: .linearGradient(
                                        Gradient(colors: [GoldTheme.chartFill, GoldTheme.gold.opacity(0)]),
                                        startPoint: CGPoint(x: plot.midX, y: plot.minY),
                                        endPoint: CGPoint(x: plot.midX, y: plot.maxY)
                                    )
                                )
                                ctx.stroke(line, with: .color(GoldTheme.gold), style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
                            }
                        }

                        // 7. 查价十字竖线
                        if let sel = selectedPoint {
                            let sx = xForSlot(sel.slot)
                            let sy = yForPrice(sel.price)
                            var cross = Path()
                            cross.move(to: CGPoint(x: sx, y: plot.minY))
                            cross.addLine(to: CGPoint(x: sx, y: plot.maxY))
                            ctx.stroke(
                                cross,
                                with: .color(GoldTheme.goldSoft.opacity(0.55)),
                                style: StrokeStyle(lineWidth: 0.9, dash: [2.5, 2.5])
                            )
                            let dotColor: Color = ref.map { sel.price >= $0 ? GoldTheme.up : GoldTheme.down } ?? GoldTheme.gold
                            let outer = CGRect(x: sx - 5, y: sy - 5, width: 10, height: 10)
                            let inner = CGRect(x: sx - 3.5, y: sy - 3.5, width: 7, height: 7)
                            ctx.fill(Path(ellipseIn: outer), with: .color(GoldTheme.background))
                            ctx.fill(Path(ellipseIn: inner), with: .color(dotColor))
                        }
                    }

                    // 国内午休 / 20:00 夜盘微标（左对齐紧贴分界虚线右侧，不压线）
                    ForEach(axis.dividers) { divider in
                        if slots.contains(divider.slot) {
                            let dx = xForSlot(divider.slot)
                            Text(divider.label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(GoldTheme.goldSoft.opacity(0.72))
                                .lineLimit(1)
                                .fixedSize()
                                .offset(x: min(dx + 4, plot.maxX - 54), y: plot.minY + 14)
                                .allowsHitTesting(false)
                        }
                    }

                    // 持仓保本价标签
                    if let breakEven = breakEvenPrice,
                       let scaledBE = priceScale.value(breakEven),
                       domain.contains(scaledBE) {
                        let by = yForPrice(breakEven)
                        Text(L10n.fmt("保本 ¥%@", breakEven.moneyText))
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.onGold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(GoldTheme.goldSoft.opacity(0.92), in: GoldTheme.rangeShape)
                            .position(x: plot.minX + 46, y: max(plot.minY + 10, by - 10))
                            .allowsHitTesting(false)
                    }

                    // 3 档极简双侧纵轴刻度（左价格 / 右涨跌幅 %）
                    scaleLabelsOverlay(plot: plot, domain: domain, referenceClose: ref, yForPrice: yForPrice)

                    // 最高 / 最低微标（非查价态）
                    if selectedPoint == nil {
                        extremumOverlay(plot: plot, xForSlot: xForSlot, yForPrice: yForPrice)
                    }

                    // 尾端呼吸脉冲点
                    if let last = points.last {
                        let lx = xForSlot(last.slot)
                        let ly = yForPrice(last.price)
                        let liveColor: Color = ref.map { last.price >= $0 ? GoldTheme.up : GoldTheme.down } ?? GoldTheme.gold
                        ZStack {
                            if isLive && !reduceMotion {
                                Circle()
                                    .fill(liveColor.opacity(pulseExpanded ? 0 : 0.45))
                                    .frame(width: 9, height: 9)
                                    .scaleEffect(pulseExpanded ? 2.4 : 1.0)
                                    .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: pulseExpanded)
                            }
                            Circle()
                                .fill(GoldTheme.background)
                                .frame(width: 9, height: 9)
                            Circle()
                                .fill(liveColor)
                                .frame(width: 6.5, height: 6.5)
                        }
                        .position(x: lx, y: ly)
                        .allowsHitTesting(false)
                        .onAppear { pulseExpanded = true }
                    }

                    // 交互手势层（单指滑查、双指缩放、双击复位）
                    ChartGestureSurface(
                        begin: onBeginGesture,
                        transform: onTransform,
                        end: onEndGesture,
                        select: onSelectSlotFraction,
                        reset: onReset
                    )
                    .frame(width: plot.width, height: plot.height)
                    .position(x: plot.midX, y: plot.midY)

                    // 查价浮窗（显示价格、相对昨收涨跌额与涨跌幅%、时刻）
                    if let sel = selectedPoint {
                        inspectionPopover(for: sel, xInPlot: xForSlot(sel.slot), plot: plot, containerWidth: geo.size.width)
                    }
                }
            }

            // 底部交易日进度横轴标签
            xAxisRow(slots: slots)
        }
    }

    @ViewBuilder
    private func scaleLabelsOverlay(
        plot: CGRect,
        domain: ClosedRange<Double>,
        referenceClose: Double?,
        yForPrice: (Double) -> CGFloat
    ) -> some View {
        let topPrice = inversePrice(domain.upperBound)
        let botPrice = inversePrice(domain.lowerBound)
        let baseY = referenceClose.map { yForPrice($0) }
        let hideTopEdge = baseY.map { abs($0 - plot.minY) < 18 } ?? false
        let hideBotEdge = baseY.map { abs(plot.maxY - $0) < 18 } ?? false

        ZStack(alignment: .topLeading) {
            if !hideTopEdge {
                HStack {
                    Text(topPrice.moneyText)
                        .foregroundStyle(GoldTheme.up.opacity(0.88))
                    Spacer()
                    if let ref = referenceClose {
                        Text(signedPercent(topPrice, base: ref))
                            .foregroundStyle(GoldTheme.up)
                            .fontWeight(.semibold)
                    }
                }
                .font(.system(size: 9.5, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 4)
                .frame(width: plot.width)
                .position(x: plot.midX, y: plot.minY + 7)
            }

            if let ref = referenceClose, let baseY, baseY >= plot.minY - 2, baseY <= plot.maxY + 2 {
                let labelY = baseY - plot.minY < 16 ? baseY + 8 : baseY - 7
                HStack {
                    Text(L10n.fmt("昨收 %@", ref.moneyText))
                        .foregroundStyle(GoldTheme.goldSoft)
                    Spacer()
                    Text("0.00%")
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                .font(.system(size: 9.5, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 4)
                .frame(width: plot.width)
                .position(x: plot.midX, y: labelY)
            }

            if !hideBotEdge {
                HStack {
                    Text(botPrice.moneyText)
                        .foregroundStyle(GoldTheme.down.opacity(0.88))
                    Spacer()
                    if let ref = referenceClose {
                        Text(signedPercent(botPrice, base: ref))
                            .foregroundStyle(GoldTheme.down)
                            .fontWeight(.semibold)
                    }
                }
                .font(.system(size: 9.5, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 4)
                .frame(width: plot.width)
                .position(x: plot.midX, y: plot.maxY - 7)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func extremumOverlay(
        plot: CGRect,
        xForSlot: (Double) -> CGFloat,
        yForPrice: (Double) -> CGFloat
    ) -> some View {
        if let hi = highPoint {
            let hx = min(max(xForSlot(hi.slot), plot.minX + 46), plot.maxX - 46)
            let hy = max(plot.minY + 18, yForPrice(hi.price) - 11)
            HStack(spacing: 3) {
                Circle().fill(GoldTheme.goldSoft).frame(width: 4.5, height: 4.5)
                Text(L10n.fmt("高 %@", hi.price.moneyText))
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.goldSoft)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(GoldTheme.card.opacity(0.86), in: GoldTheme.rangeShape)
            .position(x: hx, y: hy)
            .allowsHitTesting(false)
        }
        if let lo = lowPoint, lo.price != highPoint?.price {
            let lx = min(max(xForSlot(lo.slot), plot.minX + 76), plot.maxX - 66)
            let ly = min(plot.maxY - 22, yForPrice(lo.price) + 11)
            HStack(spacing: 3) {
                Circle().fill(GoldTheme.textSecondary).frame(width: 4.5, height: 4.5)
                Text(L10n.fmt("低 %@", lo.price.moneyText))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.textSecondary)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(GoldTheme.card.opacity(0.86), in: GoldTheme.rangeShape)
            .position(x: lx, y: ly)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func inspectionPopover(
        for point: ProjectedIntradayPoint,
        xInPlot: CGFloat,
        plot: CGRect,
        containerWidth: CGFloat
    ) -> some View {
        let cardW: CGFloat = 158
        let rightCandidate = xInPlot + 10
        let left = (rightCandidate + cardW <= containerWidth - 4) ? rightCandidate : (xInPlot - 10 - cardW)
        let clampedLeft = min(max(left, 4), max(4, containerWidth - cardW - 4))

        VStack(alignment: .leading, spacing: 3) {
            Text("¥ " + point.price.moneyText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(GoldTheme.gold)
            if let ref = referenceClose {
                let diff = point.price - ref
                let tint = diff > 0 ? GoldTheme.up : (diff < 0 ? GoldTheme.down : GoldTheme.textSecondary)
                Text("\(signedMoney(diff)) (\(signedPercent(point.price, base: ref)))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            Text(pointTimeLabel(point.date))
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(GoldTheme.goldSoft)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: cardW, alignment: .leading)
        .background(GoldTheme.card.opacity(0.96), in: GoldTheme.rangeShape)
        .overlay(GoldTheme.rangeShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        .offset(x: clampedLeft, y: plot.minY + 4)
        .allowsHitTesting(false)
    }

    private func xAxisRow(slots: ClosedRange<Double>) -> some View {
        Group {
            if !isZoomed {
                let ticks = axis.ticks
                GeometryReader { geo in
                    let total = max(1, axis.totalSlots)
                    ZStack(alignment: .leading) {
                        ForEach(Array(ticks.enumerated()), id: \.element.id) { idx, tick in
                            let frac = tick.slot / total
                            let rawX = CGFloat(frac) * geo.size.width
                            let clampedX: CGFloat = {
                                if idx == 0 { return 18 }
                                if idx == ticks.count - 1 { return max(18, geo.size.width - 18) }
                                return min(max(rawX, 34), max(34, geo.size.width - 34))
                            }()
                            Text(tick.label)
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(GoldTheme.textSecondary)
                                .position(x: clampedX, y: 7)
                        }
                    }
                }
                .frame(height: 15)
            } else {
                HStack {
                    if let first = points.first {
                        Text(pointTimeLabel(first.date))
                    }
                    Spacer()
                    if points.count >= 3 {
                        Text(pointTimeLabel(points[points.count / 2].date))
                        Spacer()
                    }
                    if let last = points.last {
                        Text(pointTimeLabel(last.date))
                    }
                }
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(GoldTheme.textSecondary)
                .frame(height: 15)
            }
        }
    }
}
