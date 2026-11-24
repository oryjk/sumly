import SwiftUI

/// 高质感暗黑金 3 页新手引导弹窗：100% 使用 GoldTheme 令牌，不打断已有持仓老用户。
struct OnboardingSheetView: View {
    let onCompleteAndRecord: () -> Void
    let onDismiss: () -> Void

    @State private var currentIndex = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var steps: [OnboardingStep] { OnboardingStep.allSteps }

    private var currentStep: OnboardingStep {
        steps[min(max(0, currentIndex), steps.count - 1)]
    }

    var body: some View {
        ZStack {
            backgroundGlow

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 6)

                TabView(selection: $currentIndex) {
                    ForEach(steps) { step in
                        stepPage(step)
                            .tag(step.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                bottomControls
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 22)
            }
        }
        .background(GoldTheme.background)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: currentIndex)
    }

    // MARK: - 背景光晕

    private var backgroundGlow: some View {
        ZStack {
            GoldTheme.background.ignoresSafeArea()

            RadialGradient(
                gradient: Gradient(colors: [
                    GoldTheme.gold.opacity(0.15),
                    GoldTheme.goldSoft.opacity(0.05),
                    Color.clear
                ]),
                center: UnitPoint(x: 0.5, y: 0.14),
                startRadius: 12,
                endRadius: 340
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    // MARK: - 顶部栏

    private var topBar: some View {
        HStack {
            Text(currentStep.badge)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(GoldTheme.goldSoft)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(GoldTheme.card, in: GoldTheme.capsuleShape)
                .overlay(
                    GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.28), lineWidth: 1)
                )
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: currentIndex)

            Spacer(minLength: 8)

            Button {
                onDismiss()
            } label: {
                Text(L10n.tr("跳过"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(GoldTheme.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("跳过新手引导"))
            .accessibilityIdentifier("onboarding.skip")
        }
    }

    // MARK: - 单页内容

    private func stepPage(_ step: OnboardingStep) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 22) {
                artworkContainer(for: step.kind)
                    .padding(.top, 8)

                VStack(spacing: 12) {
                    Text(step.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(GoldTheme.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(step.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(GoldTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(step.highlights, id: \.self) { point in
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(GoldTheme.gold)
                            Text(point)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(GoldTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(GoldTheme.card.opacity(0.78), in: GoldTheme.subCardShape)
                        .overlay(
                            GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    // MARK: - 迷你功能预览插画容器

    private func artworkContainer(for kind: OnboardingStep.Kind) -> some View {
        ZStack {
            GoldTheme.cardShape
                .fill(
                    LinearGradient(
                        colors: [
                            GoldTheme.card,
                            GoldTheme.calendarCell.opacity(0.82),
                            GoldTheme.card
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            GoldTheme.cardShape
                .fill(
                    RadialGradient(
                        colors: [GoldTheme.gold.opacity(0.11), Color.clear],
                        center: .topTrailing,
                        startRadius: 8,
                        endRadius: 210
                    )
                )

            Group {
                switch kind {
                case .holdings:
                    HoldingsPreviewArtwork()
                case .marketChart:
                    MarketChartPreviewArtwork()
                case .calendarVault:
                    CalendarVaultPreviewArtwork()
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 238)
        .overlay(
            GoldTheme.cardShape.strokeBorder(
                LinearGradient(
                    colors: [GoldTheme.goldSoft.opacity(0.32), GoldTheme.cardStroke, GoldTheme.gold.opacity(0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        )
        .accessibilityHidden(true)
    }

    // MARK: - 底部页码指示器与操作按钮

    private var bottomControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(steps) { step in
                    let isActive = step.id == currentIndex
                    Button {
                        if reduceMotion {
                            currentIndex = step.id
                        } else {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                currentIndex = step.id
                            }
                        }
                    } label: {
                        GoldTheme.capsuleShape
                            .fill(isActive ? GoldTheme.gold : GoldTheme.textFaint.opacity(0.55))
                            .frame(width: isActive ? 24 : 7, height: 7)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.fmt("第 %d 页，共 %d 页", step.id + 1, steps.count))
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }

            if currentStep.isFinalStep {
                Button {
                    onCompleteAndRecord()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.subheadline.weight(.bold))
                        Text(currentStep.primaryButtonTitle)
                    }
                }
                .buttonStyle(GoldPrimaryButtonStyle())
                .shadow(color: GoldTheme.addButtonShadow, radius: 12, x: 0, y: 5)
                .accessibilityIdentifier("onboarding.recordFirst")
            } else {
                Button {
                    let next = min(steps.count - 1, currentIndex + 1)
                    if reduceMotion {
                        currentIndex = next
                    } else {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentIndex = next
                        }
                    }
                } label: {
                    Text(currentStep.primaryButtonTitle)
                }
                .buttonStyle(GoldPrimaryButtonStyle())
                .accessibilityIdentifier("onboarding.next")
            }

            ZStack {
                if let secondaryTitle = currentStep.secondaryButtonTitle {
                    Button {
                        onDismiss()
                    } label: {
                        Text(secondaryTitle)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(GoldTheme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.browseFirst")
                } else {
                    Color.clear
                        .frame(height: 44)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

// MARK: - 第 1 页插画：4 种黄金形态微卡 + 3 秒极简入库胶囊

private struct HoldingsPreviewArtwork: View {
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(GoldAssetType.primaryQuickTypes) { type in
                    HStack(spacing: 10) {
                        GoldAssetGlyph(type: type, size: 32, emphasized: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.rawValue)
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundStyle(GoldTheme.text)
                            Text(type.quickTagline)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(GoldTheme.goldSoft)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(GoldTheme.background.opacity(0.68), in: GoldTheme.subCardShape)
                    .overlay(
                        GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1)
                    )
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.gold)
                Text(L10n.tr("3 秒极简入库 · 自动算清保本价"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(GoldTheme.goldSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(GoldTheme.gold.opacity(0.13), in: GoldTheme.capsuleShape)
            .overlay(
                GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.32), lineWidth: 1)
            )
        }
    }
}

// MARK: - 第 2 页插画：暗金走势微曲线 + 黄色保本虚线 + 红色买入点连线 + 温度胶囊

private struct MarketChartPreviewArtwork: View {
    /// 归一化曲线点（x: 0...1, y: 0...1，y 越大代表价格越高）。
    private static let normalizedPoints: [CGPoint] = [
        CGPoint(x: 0.02, y: 0.30),
        CGPoint(x: 0.14, y: 0.42),
        CGPoint(x: 0.25, y: 0.35),
        CGPoint(x: 0.38, y: 0.54),
        CGPoint(x: 0.50, y: 0.48),
        CGPoint(x: 0.62, y: 0.66),
        CGPoint(x: 0.74, y: 0.58),
        CGPoint(x: 0.86, y: 0.78),
        CGPoint(x: 0.98, y: 0.86)
    ]

    /// 买入点定义：(曲线索引, 实际成交归一化高度 y)。
    private static let buyMarkers: [(curveIndex: Int, buyY: CGFloat)] = [
        (2, 0.22),
        (5, 0.44)
    ]

    private static let breakEvenY: CGFloat = 0.50

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(GoldTheme.gold)
                        .frame(width: 6, height: 6)
                    Text(L10n.tr("Au99.99 走势"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GoldTheme.text)
                }

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    Image(systemName: "thermometer.medium")
                        .font(.caption2.weight(.semibold))
                    Text(L10n.tr("52° 温和"))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(GoldTheme.tempNeutral)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(GoldTheme.background.opacity(0.75), in: GoldTheme.capsuleShape)
                .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.tempNeutral.opacity(0.32), lineWidth: 1))

                Text(L10n.tr("美债压力"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(GoldTheme.chartSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(GoldTheme.background.opacity(0.75), in: GoldTheme.capsuleShape)
                    .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.chartSecondary.opacity(0.30), lineWidth: 1))
            }

            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let chartPoints = Self.normalizedPoints.map { pt in
                    CGPoint(x: pt.x * width, y: (1 - pt.y) * height)
                }
                let breakEvenScreenY = (1 - Self.breakEvenY) * height

                ZStack(alignment: .topLeading) {
                    // 极细网格线
                    Path { p in
                        for row in [0.22, 0.52, 0.82] as [CGFloat] {
                            let y = row * height
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: width, y: y))
                        }
                    }
                    .stroke(GoldTheme.gridline, lineWidth: 1)

                    // 面积填充
                    Path { p in
                        guard let first = chartPoints.first, let last = chartPoints.last else { return }
                        p.move(to: CGPoint(x: first.x, y: height))
                        p.addLine(to: first)
                        for pt in chartPoints.dropFirst() {
                            p.addLine(to: pt)
                        }
                        p.addLine(to: CGPoint(x: last.x, y: height))
                        p.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [GoldTheme.chartFill, Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // 暗金走势曲线
                    Path { p in
                        guard let first = chartPoints.first else { return }
                        p.move(to: first)
                        for pt in chartPoints.dropFirst() {
                            p.addLine(to: pt)
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [GoldTheme.goldSoft, GoldTheme.gold],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                    )

                    // 黄色保本虚线
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: breakEvenScreenY))
                        p.addLine(to: CGPoint(x: width, y: breakEvenScreenY))
                    }
                    .stroke(
                        GoldTheme.goldSoft.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.25, dash: [5, 3])
                    )

                    // 红色买入点与垂直连接虚线
                    ForEach(Array(Self.buyMarkers.enumerated()), id: \.offset) { idx, marker in
                        let curvePt = chartPoints[marker.curveIndex]
                        let buyPt = CGPoint(x: curvePt.x, y: (1 - marker.buyY) * height)

                        Path { p in
                            p.move(to: buyPt)
                            p.addLine(to: curvePt)
                        }
                        .stroke(
                            GoldTheme.up.opacity(0.72),
                            style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2.5])
                        )

                        Circle()
                            .fill(GoldTheme.gold)
                            .frame(width: 5, height: 5)
                            .position(curvePt)

                        ZStack {
                            Circle()
                                .fill(GoldTheme.up.opacity(0.24))
                                .frame(width: 16, height: 16)
                            Circle()
                                .fill(GoldTheme.up)
                                .frame(width: 8, height: 8)
                            Circle()
                                .strokeBorder(GoldTheme.text.opacity(0.9), lineWidth: 1.2)
                                .frame(width: 8, height: 8)
                        }
                        .position(buyPt)

                        if idx == 0 {
                            Text(L10n.tr("买入点"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(GoldTheme.up)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(GoldTheme.background.opacity(0.9), in: GoldTheme.capsuleShape)
                                .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.up.opacity(0.42), lineWidth: 0.8))
                                .position(x: buyPt.x + 34, y: min(height - 10, buyPt.y + 4))
                        }
                    }

                    // 保本线右侧微标签
                    Text(L10n.tr("保本虚线"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GoldTheme.goldSoft)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(GoldTheme.background.opacity(0.9), in: GoldTheme.capsuleShape)
                        .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.goldSoft.opacity(0.35), lineWidth: 0.8))
                        .position(x: width - 32, y: max(12, breakEvenScreenY - 12))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(GoldTheme.background.opacity(0.62), in: GoldTheme.subCardShape)
            .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
    }
}

// MARK: - 第 3 页插画：7×4 暗金日历热力矩阵 + 攒金盒里程碑微卡

private struct CalendarVaultPreviewArtwork: View {
    private static var weekdays: [String] {
        [L10n.tr("一"), L10n.tr("二"), L10n.tr("三"), L10n.tr("四"), L10n.tr("五"), L10n.tr("六"), L10n.tr("日")]
    }
    /// 28 格热力强度：0=无记录，1=轻度，2=中度，3=高光。
    private static let intensities: [Int] = [
        0, 1, 0, 0, 2, 0, 0,
        0, 0, 1, 0, 0, 3, 0,
        1, 0, 0, 2, 0, 0, 1,
        0, 2, 0, 0, 3, 0, 1
    ]

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    ForEach(Self.weekdays, id: \.self) { label in
                        Text(label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(GoldTheme.textFaint)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: gridColumns, spacing: 5) {
                    ForEach(Array(Self.intensities.enumerated()), id: \.offset) { _, level in
                        GoldTheme.rangeShape
                            .fill(cellFill(for: level))
                            .frame(height: 19)
                            .overlay(
                                GoldTheme.rangeShape.strokeBorder(
                                    level > 0 ? GoldTheme.goldSoft.opacity(0.35) : GoldTheme.cardStroke,
                                    lineWidth: 0.8
                                )
                            )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(GoldTheme.background.opacity(0.64), in: GoldTheme.subCardShape)
            .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))

            HStack(spacing: 10) {
                GoldAssetGlyph(type: .bar, size: 28, emphasized: true)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(L10n.tr("攒金盒里程碑"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(GoldTheme.text)
                        Text(L10n.tr("10g 初成"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(GoldTheme.goldSoft)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            GoldTheme.capsuleShape.fill(GoldTheme.calendarCell)
                            GoldTheme.capsuleShape
                                .fill(
                                    LinearGradient(
                                        colors: [GoldTheme.gold, GoldTheme.goldSoft],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * 0.72)
                        }
                    }
                    .frame(height: 5)
                }

                Text(L10n.tr("云同步可选"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(GoldTheme.goldSoft)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(GoldTheme.gold.opacity(0.14), in: GoldTheme.capsuleShape)
                    .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.30), lineWidth: 0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(GoldTheme.background.opacity(0.72), in: GoldTheme.subCardShape)
            .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.gold.opacity(0.22), lineWidth: 1))
        }
    }

    private func cellFill(for level: Int) -> Color {
        switch level {
        case 1: GoldTheme.gold.opacity(0.28)
        case 2: GoldTheme.gold.opacity(0.56)
        case 3: GoldTheme.gold.opacity(0.90)
        default: GoldTheme.calendarCell
        }
    }
}
