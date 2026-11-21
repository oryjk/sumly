import SwiftUI
import WidgetKit

// MARK: - 主题语义色映射（严格引用 GoldTheme，零硬编码）

extension GoldWidgetTrendDirection {
    var color: Color {
        switch self {
        case .up: GoldTheme.up
        case .down: GoldTheme.down
        case .flat: GoldTheme.textSecondary
        }
    }
}

extension GoldWidgetTemperatureLevel {
    var color: Color {
        switch self {
        case .freezing: GoldTheme.tempFreezing
        case .cool: GoldTheme.tempCool
        case .neutral: GoldTheme.tempNeutral
        case .warm: GoldTheme.tempWarm
        case .hot: GoldTheme.tempHot
        }
    }
}

extension GoldWidgetMacroRegime {
    var color: Color {
        switch self {
        case .tailwind: GoldTheme.goldSoft
        case .neutral: GoldTheme.textSecondary
        case .headwind: GoldTheme.tempFreezing
        }
    }
}

// MARK: - 桌面小组件暗黑金背景

struct GoldWidgetBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [GoldTheme.card, GoldTheme.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [GoldTheme.gold.opacity(0.13), Color.clear],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 150
            )
        }
    }
}

// MARK: - 轻量 SwiftUI Path 近一月金色折线图

struct GoldWidgetSparklineView: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let points = GoldWidgetSparkline.sampleAndNormalize(values, maxPoints: 30)
            let size = proxy.size
            let insetX: CGFloat = 3
            let insetY: CGFloat = 5
            let usableW = max(size.width - insetX * 2, 1)
            let usableH = max(size.height - insetY * 2, 1)

            if points.count >= 2 {
                let coords: [CGPoint] = points.map { point in
                    CGPoint(
                        x: insetX + CGFloat(point.x) * usableW,
                        y: insetY + CGFloat(1 - point.y) * usableH
                    )
                }

                ZStack {
                    // 极淡中位参考线
                    Path { path in
                        let midY = size.height * 0.5
                        path.move(to: CGPoint(x: insetX, y: midY))
                        path.addLine(to: CGPoint(x: size.width - insetX, y: midY))
                    }
                    .stroke(GoldTheme.gridline, style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))

                    // 金色渐变面积填充
                    Path { path in
                        guard let first = coords.first, let last = coords.last else { return }
                        path.move(to: CGPoint(x: first.x, y: size.height))
                        path.addLine(to: first)
                        for pt in coords.dropFirst() {
                            path.addLine(to: pt)
                        }
                        path.addLine(to: CGPoint(x: last.x, y: size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [GoldTheme.gold.opacity(0.28), GoldTheme.gold.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // 主折线
                    Path { path in
                        guard let first = coords.first else { return }
                        path.move(to: first)
                        for pt in coords.dropFirst() {
                            path.addLine(to: pt)
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [GoldTheme.goldSoft, GoldTheme.gold],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )

                    // 末端实时亮点
                    if let last = coords.last {
                        Circle()
                            .fill(GoldTheme.gold.opacity(0.28))
                            .frame(width: 9, height: 9)
                            .position(last)
                        Circle()
                            .fill(GoldTheme.gold)
                            .frame(width: 4.5, height: 4.5)
                            .position(last)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(GoldTheme.card.opacity(0.45))
                    .overlay(
                        Text("走势待同步")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(GoldTheme.textFaint)
                    )
            }
        }
    }
}

// MARK: - 1. 桌面小号小组件（systemSmall）

struct GoldSmallWidgetView: View {
    let basis: GoldWidgetBasis
    let snapshot: GoldWidgetSnapshot?
    let now: Date

    init(basis: GoldWidgetBasis, snapshot: GoldWidgetSnapshot?, now: Date = Date()) {
        self.basis = basis
        self.snapshot = snapshot
        self.now = now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部口径 + 单位
            HStack(alignment: .center, spacing: 5) {
                Circle()
                    .fill(GoldTheme.gold)
                    .frame(width: 6, height: 6)
                Text(basis.displayName)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(GoldTheme.goldSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 2)
                Text("¥/克")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(GoldTheme.textSecondary)
            }

            if let snapshot, snapshot.hasValidPrice {
                Spacer(minLength: 6)

                // 核心大号实时克价
                Text(GoldWidgetFormatting.formatPriceCNY(snapshot.cnyPerGram))
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                // 今日涨跌额与涨跌幅（国内红涨绿跌）
                HStack(spacing: 4) {
                    Text(snapshot.trendDirection.arrowSymbol)
                        .font(.system(size: 8.5, weight: .bold))
                    Text(GoldWidgetFormatting.formatSignedChangeCNY(snapshot.changeCNY))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(GoldWidgetFormatting.formatSignedPercent(snapshot.changePercent))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(snapshot.trendDirection.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 3)

                Spacer(minLength: 8)

                // 底部黄金温度徽章 + 更新时间
                HStack(alignment: .center, spacing: 4) {
                    if let temp = snapshot.temperature {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(temp.level.color)
                                .frame(width: 5.5, height: 5.5)
                            Text(temp.shortBadgeText)
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(temp.level.color)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(temp.level.color.opacity(0.15), in: GoldTheme.capsuleShape)
                        .overlay(
                            GoldTheme.capsuleShape
                                .strokeBorder(temp.level.color.opacity(0.28), lineWidth: 0.75)
                        )
                        .layoutPriority(1)
                    } else {
                        Text(basis.symbolBadge)
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(GoldTheme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(GoldTheme.calendarCell, in: GoldTheme.capsuleShape)
                    }

                    Spacer(minLength: 2)

                    Text(updatedLabel(for: snapshot))
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.textFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            } else {
                Spacer(minLength: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text("暂无实时金价")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(GoldTheme.text)
                    Text("轻点打开记金同步最新行情")
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundStyle(GoldTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func updatedLabel(for snapshot: GoldWidgetSnapshot) -> String {
        let time = GoldWidgetFormatting.formatUpdatedTime(snapshot.asOf, now: now, compact: true)
        return snapshot.isCachedFallback ? "缓存 \(time)" : time
    }
}

// MARK: - 2. 桌面中号小组件（systemMedium）

struct GoldMediumWidgetView: View {
    let basis: GoldWidgetBasis
    let snapshot: GoldWidgetSnapshot?
    let now: Date

    init(basis: GoldWidgetBasis, snapshot: GoldWidgetSnapshot?, now: Date = Date()) {
        self.basis = basis
        self.snapshot = snapshot
        self.now = now
    }

    var body: some View {
        if let snapshot, snapshot.hasValidPrice {
            HStack(spacing: 12) {
                // 左侧：口径 + 大号克价 + 涨跌 + 双周期温度/宏观标签
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(GoldTheme.gold)
                            .frame(width: 6, height: 6)
                        Text(basis.displayName)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(GoldTheme.goldSoft)
                            .lineLimit(1)
                        Text("¥/克")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(GoldTheme.textSecondary)
                    }

                    Spacer(minLength: 4)

                    Text(GoldWidgetFormatting.formatPriceCNY(snapshot.cnyPerGram))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    HStack(spacing: 4) {
                        Text(snapshot.trendDirection.arrowSymbol)
                            .font(.system(size: 8.5, weight: .bold))
                        Text(GoldWidgetFormatting.formatSignedChangeCNY(snapshot.changeCNY))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("(\(GoldWidgetFormatting.formatSignedPercent(snapshot.changePercent)))")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(snapshot.trendDirection.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 2)

                    if let usdText = GoldWidgetFormatting.formatUSDPerOz(snapshot.usdPerOz) {
                        Text("国际现货 \(usdText)")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.textFaint)
                            .padding(.top, 2)
                    }

                    Spacer(minLength: 6)

                    if let temp = snapshot.temperature {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(temp.level.color)
                                .frame(width: 6, height: 6)
                            Text(temp.dualHorizonText)
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(GoldTheme.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.76)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(GoldTheme.calendarCell.opacity(0.9), in: GoldTheme.capsuleShape)
                        .overlay(
                            GoldTheme.capsuleShape
                                .strokeBorder(temp.level.color.opacity(0.32), lineWidth: 0.75)
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                // 中间极细分割线
                Rectangle()
                    .fill(GoldTheme.cardStroke)
                    .frame(width: 1)
                    .padding(.vertical, 4)

                // 右侧：近一月折线图 + 最高/最低价 + 更新时间
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 4) {
                        Text("近一月走势")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(GoldTheme.textSecondary)
                        Spacer(minLength: 2)
                        Text(updatedLabel(for: snapshot))
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.textFaint)
                            .lineLimit(1)
                    }

                    GoldWidgetSparklineView(values: snapshot.sparklineValues)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    HStack(spacing: 6) {
                        if let high = snapshot.rangeHighCNY {
                            HStack(spacing: 2) {
                                Text("高")
                                    .foregroundStyle(GoldTheme.textFaint)
                                Text(GoldWidgetFormatting.formatCompactPriceCNY(high))
                                    .foregroundStyle(GoldTheme.goldSoft)
                            }
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        }
                        Spacer(minLength: 4)
                        if let low = snapshot.rangeLowCNY {
                            HStack(spacing: 2) {
                                Text("低")
                                    .foregroundStyle(GoldTheme.textFaint)
                                Text(GoldWidgetFormatting.formatCompactPriceCNY(low))
                                    .foregroundStyle(GoldTheme.textSecondary)
                            }
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        }
                    }
                }
                .frame(width: 138)
                .frame(maxHeight: .infinity)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(GoldTheme.gold)
                            .frame(width: 6, height: 6)
                        Text(basis.displayName)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(GoldTheme.goldSoft)
                    }
                    Text("暂未获取到实时金价")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(GoldTheme.text)
                    Text("网络恢复后自动同步，轻点可进入记金查看行情")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func updatedLabel(for snapshot: GoldWidgetSnapshot) -> String {
        let time = GoldWidgetFormatting.formatUpdatedTime(snapshot.asOf, now: now, compact: true)
        return snapshot.isCachedFallback ? "缓存 \(time)" : time
    }
}

// MARK: - 3. 锁屏圆形小组件（accessoryCircular）

struct GoldAccessoryCircularView: View {
    let basis: GoldWidgetBasis
    let snapshot: GoldWidgetSnapshot?

    var body: some View {
        let progress = (snapshot?.temperature?.clampedScore ?? 0) / 100.0
        ZStack {
            AccessoryWidgetBackground()

            // 外圈黄金温度进度环（0~100°）
            Circle()
                .stroke(.primary.opacity(0.22), lineWidth: 4.5)
                .padding(3.5)

            if snapshot?.temperature != nil {
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(progress, 0.04), 1.0)))
                    .stroke(
                        .primary,
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(3.5)
                    .widgetAccentable()
            }

            VStack(spacing: 0.5) {
                if let snapshot, snapshot.hasValidPrice {
                    Text(GoldWidgetFormatting.formatIntegerPriceCNY(snapshot.cnyPerGram))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let temp = snapshot.temperature {
                        Text(temp.degreeText)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        Text("¥/克")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("记金")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text("--")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
        }
    }
}

// MARK: - 4. 锁屏矩形小组件（accessoryRectangular）

struct GoldAccessoryRectangularView: View {
    let basis: GoldWidgetBasis
    let snapshot: GoldWidgetSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(basis.compactTitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let temp = snapshot?.temperature {
                    Text(temp.shortBadgeText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .widgetAccentable()
                }
            }

            if let snapshot, snapshot.hasValidPrice {
                Text("¥\(GoldWidgetFormatting.formatPriceCNY(snapshot.cnyPerGram))/克")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                HStack(spacing: 4) {
                    Text(snapshot.trendDirection.arrowSymbol)
                        .font(.system(size: 8.5, weight: .bold))
                    Text(GoldWidgetFormatting.formatSignedChangeCNY(snapshot.changeCNY))
                        .monospacedDigit()
                    Text(GoldWidgetFormatting.formatSignedPercent(snapshot.changePercent))
                        .monospacedDigit()
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else {
                Text("暂无金价")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("轻点打开记金刷新")
                    .font(.system(size: 10.5, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
