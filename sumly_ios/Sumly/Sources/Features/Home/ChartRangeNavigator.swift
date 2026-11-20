import SwiftUI

/// Pure geometry and hit-testing model for `ChartRangeNavigator`.
/// Decouples the compact visual handles from full 48pt touch targets so narrow
/// or edge-aligned selections never overlap, mis-grab, or lock out window panning.
struct ChartRangeNavigatorLayout: Sendable, Equatable {
    static let handleHitWidth: CGFloat = 48
    static let trackHeight: CGFloat = 48
    static let handleVisualWidth: CGFloat = 18
    static let minimumBoxWidth: CGFloat = 104
    static let minimumWindowHitWidth: CGFloat = 24
    static let dragMinimumDistance: CGFloat = 0
    static let coordinateSpaceName = "chartNavigator"

    let trackWidth: CGFloat
    let boxRange: ClosedRange<CGFloat>
    let startHandleHitRange: ClosedRange<CGFloat>
    let windowHitRange: ClosedRange<CGFloat>?
    let endHandleHitRange: ClosedRange<CGFloat>
    let interactiveRange: ClosedRange<CGFloat>

    var boxWidth: CGFloat { boxRange.upperBound - boxRange.lowerBound }
    var startHandleVisualRange: ClosedRange<CGFloat> {
        let visualWidth = min(Self.handleVisualWidth, boxWidth / 2)
        return boxRange.lowerBound...(boxRange.lowerBound + visualWidth)
    }
    var endHandleVisualRange: ClosedRange<CGFloat> {
        let visualWidth = min(Self.handleVisualWidth, boxWidth / 2)
        return (boxRange.upperBound - visualWidth)...boxRange.upperBound
    }

    init(trackWidth: CGFloat, bounds: ClosedRange<Date>, window: ClosedRange<Date>) {
        let width = max(1, trackWidth.isFinite ? trackWidth : 1)
        let span = max(1, bounds.upperBound.timeIntervalSince(bounds.lowerBound))
        let rawLeft = CGFloat(window.lowerBound.timeIntervalSince(bounds.lowerBound) / span) * width
        let rawRight = CGFloat(window.upperBound.timeIntervalSince(bounds.lowerBound) / span) * width
        let actualLeft = min(max(0, rawLeft), width)
        let actualRight = min(max(actualLeft, rawRight), width)

        let boxWidth = min(width, max(Self.minimumBoxWidth, actualRight - actualLeft))
        let boxLeft = min(max(0, (actualLeft + actualRight - boxWidth) / 2), width - boxWidth)
        let boxRight = boxLeft + boxWidth

        let targetHitWidth = min(Self.handleHitWidth, width)
        let halfHit = targetHitWidth / 2

        // Center each 48pt handle target on its selection edge and clamp inside the track
        // so both handles always cover their visual grips without bleeding outside bounds.
        var startLower = max(0, boxLeft - halfHit)
        var startUpper = min(width, startLower + targetHitWidth)
        startLower = max(0, startUpper - targetHitWidth)

        var endUpper = min(width, boxRight + halfHit)
        var endLower = max(0, endUpper - targetHitWidth)
        endUpper = min(width, endLower + targetHitWidth)

        // Preserve a dedicated pan region between handles even in unusually narrow containers.
        let reservedWindow = min(Self.minimumWindowHitWidth, width / 3)
        if endLower - startUpper < reservedWindow {
            let deficit = reservedWindow - (endLower - startUpper)
            let shiftLeft = min(startLower, deficit / 2)
            startLower -= shiftLeft
            startUpper -= shiftLeft

            let remaining = deficit - shiftLeft
            let shiftRight = min(width - endUpper, remaining)
            endLower += shiftRight
            endUpper += shiftRight

            if endLower - startUpper < reservedWindow {
                let mid = (boxLeft + boxRight) / 2
                let halfWindow = reservedWindow / 2
                startUpper = max(startLower, min(startUpper, mid - halfWindow))
                endLower = min(endUpper, max(endLower, mid + halfWindow))
            }
        }

        self.trackWidth = width
        self.boxRange = boxLeft...boxRight
        self.startHandleHitRange = startLower...startUpper
        self.endHandleHitRange = endLower...endUpper
        self.windowHitRange = endLower > startUpper ? startUpper...endLower : nil
        self.interactiveRange = startLower...endUpper
    }

    func hitPart(at x: CGFloat) -> ChartViewport.Part? {
        guard x.isFinite, interactiveRange.contains(x) else { return nil }

        let inStart = startHandleHitRange.contains(x)
        let inEnd = endHandleHitRange.contains(x)
        if inStart && inEnd {
            let distanceToStart = abs(x - boxRange.lowerBound)
            let distanceToEnd = abs(x - boxRange.upperBound)
            return distanceToStart <= distanceToEnd ? .start : .end
        }
        if inStart { return .start }
        if inEnd { return .end }
        if let windowHitRange, windowHitRange.contains(x) { return .window }
        return nil
    }

    func translationFraction(for translationX: CGFloat) -> Double {
        guard translationX.isFinite, trackWidth > 0 else { return 0 }
        return Double(translationX / trackWidth)
    }
}

private struct ChartNavigatorHitArea: Shape {
    var minX: CGFloat
    var maxX: CGFloat

    func path(in rect: CGRect) -> Path {
        let clampedMin = min(max(0, minX), rect.width)
        let clampedMax = min(max(clampedMin, maxX), rect.width)
        return Path(CGRect(x: clampedMin, y: rect.minY, width: clampedMax - clampedMin, height: rect.height))
    }
}

/// Overview remains at the full available range while the main chart zooms.
/// Very narrow windows get a wider manipulation frame without changing their dates.
struct ChartRangeNavigator: View {
    let points: [MarketChartPoint]
    let bounds: ClosedRange<Date>
    let window: ClosedRange<Date>
    let scale: ChartPriceScale
    let daily: Bool
    let begin: () -> Void
    let move: (ChartViewport.Part, Double) -> Void
    let end: () -> Void

    @State private var dragging = false
    @State private var activePart: ChartViewport.Part?
    @GestureState private var gestureActive = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { geo in
            let layout = ChartRangeNavigatorLayout(trackWidth: geo.size.width, bounds: bounds, window: window)
            let span = max(1, bounds.upperBound.timeIntervalSince(bounds.lowerBound))
            let boxLeft = layout.boxRange.lowerBound
            let boxWidth = layout.boxWidth
            let startVisual = layout.startHandleVisualRange
            let endVisual = layout.endHandleVisualRange

            ZStack(alignment: .topLeading) {
                // Visual track and selection chrome: decoupled from gesture hit-testing.
                ZStack(alignment: .topLeading) {
                    GoldTheme.rangeShape.fill(GoldTheme.card)
                    overview(width: layout.trackWidth, height: geo.size.height)
                        .stroke(GoldTheme.goldSoft.opacity(0.55), lineWidth: 1)
                        .padding(.vertical, 8)
                    Rectangle().fill(GoldTheme.background.opacity(0.6))
                        .frame(width: max(0, boxLeft))
                    Rectangle().fill(GoldTheme.background.opacity(0.6))
                        .frame(width: max(0, layout.trackWidth - layout.boxRange.upperBound))
                        .offset(x: layout.boxRange.upperBound)
                    GoldTheme.rangeShape.fill(GoldTheme.chartFill)
                        .overlay(
                            GoldTheme.rangeShape.strokeBorder(
                                activePart == nil ? GoldTheme.gold : GoldTheme.goldSoft,
                                lineWidth: 1.5
                            )
                        )
                        .frame(width: boxWidth)
                        .offset(x: boxLeft)
                    handleVisual(isActive: activePart == .start)
                        .frame(width: startVisual.upperBound - startVisual.lowerBound, height: geo.size.height)
                        .offset(x: startVisual.lowerBound)
                    handleVisual(isActive: activePart == .end)
                        .frame(width: endVisual.upperBound - endVisual.lowerBound, height: geo.size.height)
                        .offset(x: endVisual.lowerBound)
                }
                .clipShape(GoldTheme.rangeShape)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                // Accessibility elements match the expanded 48pt handle and window targets.
                accessibleHandle("开始", part: .start, range: layout.startHandleHitRange, height: geo.size.height, span: span)
                accessibleHandle("结束", part: .end, range: layout.endHandleHitRange, height: geo.size.height, span: span)
                if let windowRange = layout.windowHitRange {
                    Color.clear
                        .frame(width: windowRange.upperBound - windowRange.lowerBound, height: geo.size.height)
                        .offset(x: windowRange.lowerBound)
                        .allowsHitTesting(false)
                        .accessibilityElement()
                        .accessibilityLabel("移动时间区间")
                        .accessibilityValue(
                            window.lowerBound.formatted(date: .abbreviated, time: daily ? .omitted : .shortened)
                                + "至"
                                + window.upperBound.formatted(date: .abbreviated, time: daily ? .omitted : .shortened)
                        )
                        .accessibilityAdjustableAction { direction in
                            begin()
                            let fraction = window.upperBound.timeIntervalSince(window.lowerBound) / span
                            move(.window, direction == .increment ? fraction : -fraction)
                            end()
                        }
                        .accessibilityIdentifier("chart.navigator.window")
                }

                // Single stationary high-priority gesture surface prevents moving-view cancellation,
                // scroll-view hijacking inside the interactive track, and handle overlap conflicts.
                Color.clear
                    .frame(width: layout.trackWidth, height: geo.size.height)
                    .contentShape(
                        ChartNavigatorHitArea(
                            minX: layout.interactiveRange.lowerBound,
                            maxX: layout.interactiveRange.upperBound
                        )
                    )
                    .highPriorityGesture(navigatorDrag(layout: layout))
                    .accessibilityHidden(true)
            }
        }
        .frame(height: ChartRangeNavigatorLayout.trackHeight)
        .coordinateSpace(name: ChartRangeNavigatorLayout.coordinateSpaceName)
        .defersSystemGestures(on: .horizontal)
        .sensoryFeedback(.selection, trigger: activePart) { _, next in next != nil }
        .onChange(of: gestureActive) { _, active in
            if !active { finishDrag() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { finishDrag() }
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { finishDrag() }
        }
        .onDisappear { finishDrag() }
    }

    private func finishDrag() {
        if dragging {
            dragging = false
            activePart = nil
            end()
        } else if activePart != nil {
            activePart = nil
        }
    }

    private func handleVisual(isActive: Bool) -> some View {
        ZStack {
            GoldTheme.gold.opacity(isActive ? 0.32 : 0.2)
            GoldTheme.capsuleShape
                .fill(isActive ? GoldTheme.goldSoft : GoldTheme.gold)
                .frame(width: isActive ? 4 : 3, height: isActive ? 26 : 22)
        }
    }

    private func accessibleHandle(
        _ label: String,
        part: ChartViewport.Part,
        range: ClosedRange<CGFloat>,
        height: CGFloat,
        span: TimeInterval
    ) -> some View {
        Color.clear
            .frame(width: max(1, range.upperBound - range.lowerBound), height: height)
            .offset(x: range.lowerBound)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(label + "时间")
            .accessibilityAdjustableAction { direction in
                begin()
                move(part, (direction == .increment ? 1 : -1) * (daily ? 86400 : 30) / span)
                end()
            }
            .accessibilityIdentifier(part == .start ? "chart.navigator.start" : "chart.navigator.end")
    }

    private func navigatorDrag(layout: ChartRangeNavigatorLayout) -> some Gesture {
        DragGesture(
            minimumDistance: ChartRangeNavigatorLayout.dragMinimumDistance,
            coordinateSpace: .named(ChartRangeNavigatorLayout.coordinateSpaceName)
        )
        .updating($gestureActive) { _, active, _ in active = true }
        .onChanged { value in
            if !dragging {
                guard let part = layout.hitPart(at: value.startLocation.x) else { return }
                dragging = true
                activePart = part
                begin()
            }
            guard let part = activePart else { return }
            if value.translation.width != 0 {
                move(part, layout.translationFraction(for: value.translation.width))
            }
        }
        .onEnded { value in
            if dragging, let part = activePart, value.translation.width != 0 {
                move(part, layout.translationFraction(for: value.translation.width))
            }
            finishDrag()
        }
    }

    private func overview(width: CGFloat, height: CGFloat) -> Path {
        let domain = scale.domain(points.map(\.price))
        let span = max(1, bounds.upperBound.timeIntervalSince(bounds.lowerBound))
        let vertical = domain.upperBound - domain.lowerBound
        // Display sampling only: cache and selectable main-chart records remain intact.
        let renderPoints = ChartOverviewSampling.points(points, daily: daily)
        return Path { path in
            for (i, p) in renderPoints.enumerated() {
                guard let value = scale.value(p.price) else { continue }
                let x = p.date.timeIntervalSince(bounds.lowerBound) / span * width
                let y = (1 - (value - domain.lowerBound) / vertical) * max(1, height - 16)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }
}
