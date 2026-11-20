import SwiftUI

// MARK: - 黄金温度弧形仪表盘

struct GoldTemperatureGauge: View {
    let score: Double
    let level: MacroTemperatureLevel
    let levelLabel: String
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double {
        MacroPresentation.clampedTemperatureScore(score)
    }

    private var progress: Double {
        clamped / 100.0
    }

    private var accentColor: Color {
        MacroPresentation.temperatureColor(for: level)
    }

    private let arcSpan: Double = 0.72 // 259.2°
    private let startDegrees: Double = 140.4

    var body: some View {
        let size: CGFloat = compact ? 104 : 184
        let lineWidth: CGFloat = compact ? 9 : 14

        ZStack {
            // 背景轨道
            Circle()
                .trim(from: 0, to: arcSpan)
                .stroke(
                    GoldTheme.calendarCell,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(startDegrees))

            // 五段冷热渐变弧
            Circle()
                .trim(from: 0, to: max(0.01, arcSpan * progress))
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
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(startDegrees))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: progress)

            // 指示圆点
            GeometryReader { proxy in
                let radius = (min(proxy.size.width, proxy.size.height) - lineWidth) / 2
                let angleDeg = startDegrees + (arcSpan * 360.0 * progress)
                let rad = angleDeg * .pi / 180.0
                let cx = proxy.size.width / 2 + CGFloat(cos(rad)) * radius
                let cy = proxy.size.height / 2 + CGFloat(sin(rad)) * radius
                Circle()
                    .fill(GoldTheme.text)
                    .frame(width: compact ? 10 : 14, height: compact ? 10 : 14)
                    .overlay(Circle().stroke(accentColor, lineWidth: compact ? 2.5 : 3))
                    .position(x: cx, y: cy)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: progress)
            }
            .allowsHitTesting(false)

            // 中心温度读数
            VStack(spacing: compact ? 2 : 4) {
                Text(String(format: "%.1f°", clamped))
                    .font(.system(size: compact ? 23 : 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.text)
                    .contentTransition(.numericText())
                Text(levelLabel.isEmpty ? level.defaultLabel : levelLabel)
                    .font(.system(size: compact ? 10.5 : 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, compact ? 6 : 10)
                    .padding(.vertical, compact ? 2 : 4)
                    .background(accentColor.opacity(0.14), in: GoldTheme.capsuleShape)
                if !compact {
                    Text("0° 极冷  ·  100° 极热")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(GoldTheme.textFaint)
                        .padding(.top, 2)
                }
            }
            .offset(y: compact ? 4 : 6)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("黄金温度 \(String(format: "%.1f", clamped)) 度，\(levelLabel.isEmpty ? level.defaultLabel : levelLabel)")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

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
        .goldCard(padding: 16)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenDashboard()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.macroTemperatureCard")
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Label("黄金温度计", systemImage: "thermometer.medium")
                .font(.subheadline.bold())
                .foregroundStyle(GoldTheme.gold)

            if let report = temperature, report.hasAvailableData {
                let regimeTint = MacroPresentation.regimeColor(for: report.macroRegime.regime)
                Text(report.macroRegime.label.isEmpty ? report.macroRegime.regime.defaultLabel : report.macroRegime.label)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(regimeTint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(regimeTint.opacity(0.14), in: GoldTheme.capsuleShape)
            }

            Spacer(minLength: 4)

            Button(action: onOpenDashboard) {
                HStack(spacing: 3) {
                    Text("宏观与美债")
                        .font(.caption.weight(.medium))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(GoldTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("进入黄金温度与美国国债专题页")
        }
    }

    private var loadingContent: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(GoldTheme.gold)
            VStack(alignment: .leading, spacing: 3) {
                Text("正在同步黄金温度与美债数据…")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(GoldTheme.text)
                Text("点击可进入宏观国债全景看板")
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
                Text("不影响行情查看，可点击重试或进入专题页")
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
            }
            Spacer(minLength: 8)
            Button("重试", action: onRetry)
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
                    Text("宏观指标正在初始化同步中")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GoldTheme.text)
                    Text("待后端完成首次数据同步后将自动呈现 0~100° 市场温度，绝不展示估算假数据。")
                        .font(.caption)
                        .foregroundStyle(GoldTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !report.actionGuide.disclaimer.isEmpty {
                Text(report.actionGuide.disclaimer)
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textFaint)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadedContent(_ report: MacroTemperatureReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                GoldTemperatureGauge(
                    score: report.score,
                    level: report.level,
                    levelLabel: report.levelLabel,
                    compact: true
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(report.actionGuide.title.isEmpty ? report.levelLabel : report.actionGuide.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(GoldTheme.text)
                        .lineLimit(2)

                    Text(report.actionGuide.summary)
                        .font(.caption)
                        .foregroundStyle(GoldTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Text("定投 \(MacroPresentation.formatDCAMultiplier(report.actionGuide.dcaMultiplier))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.onGold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(GoldTheme.gold, in: GoldTheme.capsuleShape)

                        if report.volatilityAlert {
                            Label("高波动", systemImage: "waveform.path.ecg")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(GoldTheme.up)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(GoldTheme.up.opacity(0.14), in: GoldTheme.capsuleShape)
                        }

                        if report.degraded {
                            Text("部分降级")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(GoldTheme.goldSoft)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(GoldTheme.goldSoft.opacity(0.12), in: GoldTheme.capsuleShape)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            quickMacroStrip(report)
        }
    }

    private func quickMacroStrip(_ report: MacroTemperatureReport) -> some View {
        HStack(spacing: 8) {
            quickStatCell(
                title: "美债总规模",
                value: MacroPresentation.formatTrillionUSD(treasury?.totalDebtTrillionUSD),
                tint: GoldTheme.goldSoft
            )
            quickStatCell(
                title: "10Y 实际利率",
                value: MacroPresentation.formatPercent(treasury?.yield10yRealPct),
                tint: GoldTheme.text
            )
            quickStatCell(
                title: "年线偏离",
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
