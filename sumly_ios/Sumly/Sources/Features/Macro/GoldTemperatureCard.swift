import SwiftUI

// MARK: - 黄金温度弧形仪表盘纯几何模型

struct GoldTemperatureGaugeGeometry: Sendable, Equatable {
    static let arcSpan: Double = 0.72 // 259.2°
    static let startAngleDegrees: Double = 140.4
    static let minimumTrim: Double = 0.001

    let score: Double
    let compact: Bool

    var size: CGFloat { compact ? 104 : 184 }
    var lineWidth: CGFloat { compact ? 9 : 14 }
    var strokeInset: CGFloat { lineWidth / 2 }
    var trackRadius: CGFloat { (size - lineWidth) / 2 }
    var outerStrokeRadius: CGFloat { trackRadius + lineWidth / 2 }
    var center: CGPoint { CGPoint(x: size / 2, y: size / 2) }
    var dotDiameter: CGFloat { compact ? 10 : 14 }
    var dotBorderWidth: CGFloat { compact ? 2.5 : 3 }

    var clampedScore: Double {
        MacroPresentation.clampedTemperatureScore(score)
    }

    var rawProgress: Double {
        clampedScore / 100.0
    }

    /// 共享的有效进度：弧线终点与指示圆点圆心使用完全一致的角度计算，避免 0° 附近错位。
    var effectiveProgress: Double {
        max(Self.minimumTrim / Self.arcSpan, rawProgress)
    }

    var trackTrimEnd: Double {
        Self.arcSpan
    }

    var activeTrimEnd: Double {
        Self.arcSpan * effectiveProgress
    }

    var startAngleDegrees: Double {
        Self.startAngleDegrees
    }

    var trackEndAngleDegrees: Double {
        Self.startAngleDegrees + Self.arcSpan * 360.0
    }

    var activeArcEndAngleDegrees: Double {
        Self.startAngleDegrees + activeTrimEnd * 360.0
    }

    var indicatorAngleDegrees: Double {
        Self.startAngleDegrees + Self.arcSpan * 360.0 * effectiveProgress
    }

    func pointOnTrack(atAngleDegrees degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180.0
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * trackRadius,
            y: center.y + CGFloat(sin(radians)) * trackRadius
        )
    }

    var activeArcEndPoint: CGPoint {
        pointOnTrack(atAngleDegrees: activeArcEndAngleDegrees)
    }

    var indicatorCenter: CGPoint {
        pointOnTrack(atAngleDegrees: indicatorAngleDegrees)
    }
}

// MARK: - 黄金温度弧形仪表盘

struct GoldTemperatureGauge: View {
    let score: Double
    let level: MacroTemperatureLevel
    let levelLabel: String
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var geometry: GoldTemperatureGaugeGeometry {
        GoldTemperatureGaugeGeometry(score: score, compact: compact)
    }

    private var accentColor: Color {
        MacroPresentation.temperatureColor(for: level)
    }

    var body: some View {
        let g = geometry

        ZStack {
            // 背景轨道（内缩 lineWidth / 2，使中线半径严格等于 trackRadius 且描边外缘不溢出边界框）
            Circle()
                .inset(by: g.strokeInset)
                .trim(from: 0, to: g.trackTrimEnd)
                .stroke(
                    GoldTheme.calendarCell,
                    style: StrokeStyle(lineWidth: g.lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(g.startAngleDegrees))

            // 五段冷热渐变弧（与背景轨道同圆心同中线半径，终点角度与指示圆点严格共享 effectiveProgress）
            Circle()
                .inset(by: g.strokeInset)
                .trim(from: 0, to: g.activeTrimEnd)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: GoldTheme.tempFreezing, location: 0.00),
                            .init(color: GoldTheme.tempFreezing, location: 0.06),
                            .init(color: GoldTheme.tempCool, location: 0.24),
                            .init(color: GoldTheme.tempNeutral, location: 0.42),
                            .init(color: GoldTheme.tempWarm, location: 0.60),
                            .init(color: GoldTheme.tempHot, location: 0.78),
                            .init(color: GoldTheme.tempHot, location: 0.86),
                            .init(color: GoldTheme.tempFreezing, location: 0.96)
                        ]),
                        center: .center,
                        startAngle: .degrees(-20),
                        endAngle: .degrees(340)
                    ),
                    style: StrokeStyle(lineWidth: g.lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(g.startAngleDegrees))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: g.effectiveProgress)

            // 指示圆点（圆心严格落在 trackRadius 圆环中线与彩色弧线终点上）
            Circle()
                .fill(GoldTheme.text)
                .frame(width: g.dotDiameter, height: g.dotDiameter)
                .overlay(Circle().stroke(accentColor, lineWidth: g.dotBorderWidth))
                .position(g.indicatorCenter)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: g.effectiveProgress)
                .allowsHitTesting(false)

            // 中心温度读数
            let resolvedLabel = MacroLocalization.temperatureLevelLabel(level: level, fallback: levelLabel)
            VStack(spacing: compact ? 2 : 4) {
                Text(String(format: "%.1f°", g.clampedScore))
                    .font(.system(size: compact ? 23 : 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.text)
                    .contentTransition(.numericText())
                Text(resolvedLabel)
                    .font(.system(size: compact ? 10.5 : 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, compact ? 6 : 10)
                    .padding(.vertical, compact ? 2 : 4)
                    .background(accentColor.opacity(0.14), in: GoldTheme.capsuleShape)
                if !compact {
                    Text(L10n.tr("0° 极冷  ·  100° 极热"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(GoldTheme.textFaint)
                        .padding(.top, 2)
                }
            }
            .offset(y: compact ? 4 : 6)
        }
        .frame(width: g.size, height: g.size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.fmt("黄金温度 %@ 度，%@", String(format: "%.1f", g.clampedScore), MacroLocalization.temperatureLevelLabel(level: level, fallback: levelLabel))
        )
    }
}

// MARK: - 首页黄金温度计摘要卡

struct GoldTemperatureCard: View {
    let temperature: MacroTemperatureReport?
    let treasury: MacroTreasurySummary?
    let isLoading: Bool
    let errorMessage: String?
    let onRetry: () -> Void
    let onOpenDashboard: () -> Void

    @State private var showingGuideHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            Group {
                if isLoading && temperature == nil {
                    loadingContent
                } else if let report = temperature {
                    if report.hasAvailableData {
                        loadedContent(report)
                    } else {
                        coldStartContent(report)
                    }
                } else if let errorMessage {
                    errorContent(errorMessage)
                } else {
                    loadingContent
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onOpenDashboard()
            }
        }
        .goldCard(padding: 16)
        .sheet(isPresented: $showingGuideHelp) {
            MacroTemperatureGuideSheet(
                help: temperature?.resolvedGuideHelp ?? .defaultGuide,
                disclaimer: temperature.map { MacroPresentation.objectiveDisclaimer(for: $0.actionGuide) } ?? MacroPresentation.defaultDisclaimer,
                currentLevel: temperature?.hasAvailableData == true ? temperature?.level : nil
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.macroTemperatureCard")
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Button(action: onOpenDashboard) {
                Label(L10n.tr("黄金温度计"), systemImage: "thermometer.medium")
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.gold)
            }
            .buttonStyle(.plain)

            Button {
                showingGuideHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(GoldTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("查看黄金温度计说明"))
            .accessibilityIdentifier("home.macroTemperatureGuideButton")

            Spacer(minLength: 4)

            Button(action: onOpenDashboard) {
                HStack(spacing: 3) {
                    Text(L10n.tr("宏观与美债"))
                        .font(.caption.weight(.medium))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(GoldTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("进入黄金温度与美国国债专题页"))
        }
    }

    private var loadingContent: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(GoldTheme.gold)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr("正在同步黄金温度与美债数据…"))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(GoldTheme.text)
                Text(L10n.tr("点击可进入宏观国债全景看板"))
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    private func errorContent(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(GoldTheme.tempWarm)
            VStack(alignment: .leading, spacing: 3) {
                Text(message)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(GoldTheme.text)
                Text(L10n.tr("不影响行情查看，可点击重试或进入专题页"))
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
            }
            Spacer(minLength: 8)
            Button(L10n.tr("重试"), action: onRetry)
                .buttonStyle(GoldCapsuleStyle(isSelected: false))
        }
        .padding(.vertical, 6)
    }

    private func coldStartContent(_ report: MacroTemperatureReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.title2)
                    .foregroundStyle(GoldTheme.goldSoft)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("宏观指标正在初始化同步中"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GoldTheme.text)
                    Text(L10n.tr("待后端完成首次数据同步后将自动呈现 0~100° 市场温度，绝不展示估算假数据。"))
                        .font(.caption)
                        .foregroundStyle(GoldTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(MacroPresentation.objectiveDisclaimer(for: report.actionGuide))
                .font(.caption2)
                .foregroundStyle(GoldTheme.textFaint)
        }
        .padding(.vertical, 4)
    }

    private func loadedContent(_ report: MacroTemperatureReport) -> some View {
        let dual = MacroPresentation.dualHorizonSummary(for: report)
        let shortTint = MacroPresentation.temperatureColor(for: dual.shortTermLevel)
        let longTint = MacroPresentation.regimeColor(for: dual.longTermRegime)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                GoldTemperatureGauge(
                    score: report.score,
                    level: report.level,
                    levelLabel: dual.shortTermLevelLabel,
                    compact: true
                )

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            horizonMicroTag(L10n.tr("短期热度"))
                            Text(dual.shortTermCompactTitle)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(shortTint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }

                        Text(dual.shortTermPlainNote)
                            .font(.caption2)
                            .foregroundStyle(GoldTheme.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Rectangle()
                        .fill(GoldTheme.cardStroke)
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            horizonMicroTag(L10n.tr("长期宏观"))
                            Text(dual.longTermState)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(longTint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)

                            Spacer(minLength: 4)

                            Text(dual.longTermScoreText)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(GoldTheme.textFaint)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }

                        Text(dual.longTermPlainNote)
                            .font(.caption2)
                            .foregroundStyle(GoldTheme.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if report.volatilityAlert || report.degraded {
                HStack(spacing: 6) {
                    if report.volatilityAlert {
                        Label(L10n.tr("短期高波动"), systemImage: "waveform.path.ecg")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(GoldTheme.up)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(GoldTheme.up.opacity(0.14), in: GoldTheme.capsuleShape)
                    }

                    if report.degraded {
                        Text(L10n.tr("部分因子降级"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(GoldTheme.goldSoft)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(GoldTheme.goldSoft.opacity(0.12), in: GoldTheme.capsuleShape)
                    }

                    Spacer(minLength: 0)
                }
            }

            quickMacroStrip(report)
        }
    }

    private func horizonMicroTag(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(GoldTheme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(GoldTheme.calendarCell, in: GoldTheme.badgeShape)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func quickMacroStrip(_ report: MacroTemperatureReport) -> some View {
        HStack(spacing: 8) {
            quickStatCell(
                title: L10n.tr("美债总规模"),
                value: MacroPresentation.formatTrillionUSD(treasury?.totalDebtTrillionUSD),
                tint: GoldTheme.goldSoft
            )
            quickStatCell(
                title: L10n.tr("10Y 实际利率"),
                value: MacroPresentation.formatPercent(treasury?.yield10yRealPct),
                tint: GoldTheme.text
            )
            quickStatCell(
                title: L10n.tr("200日均线偏离"),
                value: MacroPresentation.formatPercent(report.actionGuide.ma200DeviationPct, signed: true),
                tint: MacroPresentation.changeColor(for: report.actionGuide.ma200DeviationPct)
            )
        }
    }

    private func quickStatCell(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(GoldTheme.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(GoldTheme.background, in: GoldTheme.subCardShape)
        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }
}

// MARK: - 迷你趋势 Sparkline

struct MacroSparklineView: View {
    let values: [Double]
    var tint: Color = GoldTheme.gold

    var body: some View {
        let normalized = MacroPresentation.normalizedSparkline(values)
        GeometryReader { proxy in
            if normalized.count >= 2 {
                let width = proxy.size.width
                let height = proxy.size.height
                let step = width / CGFloat(normalized.count - 1)
                Path { path in
                    for (index, yNorm) in normalized.enumerated() {
                        let x = CGFloat(index) * step
                        let y = height - CGFloat(yNorm) * (height - 4) - 2
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            } else {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2))
                }
                .stroke(GoldTheme.cardStroke, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .accessibilityHidden(true)
    }
}
