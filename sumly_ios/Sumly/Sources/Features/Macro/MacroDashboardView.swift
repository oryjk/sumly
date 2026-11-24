import SwiftUI
import Charts

struct MacroDashboardView: View {
    @Bindable var model: MacroDashboardViewModel
    let service: any MacroServicing

    @State private var selectedIndicator: MacroIndicatorSummary?
    @State private var selectedHistoryDate: Date?
    @State private var selectedDebtDate: Date?
    @State private var selectedYieldDate: Date?
    @State private var selectedCotDate: Date?
    @State private var showingGuideHelp = false
    @State private var showingTreasuryPressureGuide = false
    @State private var showingPanoramaGuide = false

    init(
        model: MacroDashboardViewModel,
        service: any MacroServicing = BackendMacroService()
    ) {
        self.model = model
        self.service = service
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                tabPicker

                switch model.selectedTab {
                case .temperature:
                    temperatureTabContent
                case .treasury:
                    treasuryTabContent
                case .panorama:
                    panoramaTabContent
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 112)
        }
        .scrollIndicators(.hidden)
        .background(GoldTheme.background)
        .foregroundStyle(GoldTheme.text)
        .navigationTitle(L10n.tr("黄金温度与宏观"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.refreshAll() }
                } label: {
                    if model.isRefreshingCurrentTab {
                        ProgressView()
                            .controlSize(.small)
                            .tint(GoldTheme.gold)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GoldTheme.gold)
                    }
                }
                .accessibilityLabel(L10n.tr("刷新宏观数据"))
            }
        }
        .navigationDestination(item: $selectedIndicator) { summary in
            MacroIndicatorDetailView(
                seriesID: summary.seriesID,
                initialSummary: summary,
                service: service
            )
        }
        .sheet(isPresented: $showingGuideHelp) {
            MacroTemperatureGuideSheet(
                help: model.temperature?.resolvedGuideHelp ?? .defaultGuide,
                disclaimer: model.temperature.map { MacroPresentation.objectiveDisclaimer(for: $0.actionGuide) } ?? MacroPresentation.defaultDisclaimer,
                currentLevel: model.temperature?.hasAvailableData == true ? model.temperature?.level : nil
            )
        }
        .sheet(isPresented: $showingTreasuryPressureGuide) {
            MacroTreasuryPressureGuideSheet(
                currentLevel: model.treasuryPressureModel?.level,
                disclaimer: model.temperature.map { MacroPresentation.objectiveDisclaimer(for: $0.actionGuide) } ?? MacroPresentation.defaultDisclaimer
            )
        }
        .sheet(isPresented: $showingPanoramaGuide) {
            MacroPanoramaThermometerGuideSheet(
                currentLevel: model.panoramaThermometerModel.level,
                disclaimer: model.temperature.map { MacroPresentation.objectiveDisclaimer(for: $0.actionGuide) } ?? MacroPresentation.defaultDisclaimer
            )
        }
        .refreshable {
            await model.refreshAll()
        }
        .task {
            await model.loadDashboard()
        }
        .task(id: model.selectedTab) {
            if model.selectedTab == .panorama {
                await model.ensurePanoramaDependenciesLoaded()
            }
        }
        .sensoryFeedback(.selection, trigger: model.selectedTab)
        .sensoryFeedback(.selection, trigger: model.selectedSectionID)
        .sensoryFeedback(.selection, trigger: model.temperatureGoldPriceScale)
        .sensoryFeedback(.selection, trigger: model.treasuryDebtScale)
        .sensoryFeedback(.selection, trigger: model.treasuryYieldScale)
        .sensoryFeedback(.selection, trigger: model.cotScale)
    }

    // MARK: - 顶部分段切换

    private var tabPicker: some View {
        HStack(spacing: 6) {
            ForEach(MacroDashboardTab.allCases) { tab in
                let isSelected = model.selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.selectedTab = tab
                    }
                } label: {
                    Text(tab.localizedTitle)
                        .font(.system(size: 13.5, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? GoldTheme.onGold : GoldTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(isSelected ? GoldTheme.gold : GoldTheme.card, in: GoldTheme.capsuleShape)
                        .overlay(GoldTheme.capsuleShape.strokeBorder(isSelected ? Color.clear : GoldTheme.cardStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("macro.tab.\(tab.rawValue)")
            }
        }
    }

    // MARK: - Tab 1: 黄金温度

    @ViewBuilder
    private var temperatureTabContent: some View {
        if model.isLoadingTemperature && model.temperature == nil {
            loadingCard(L10n.tr("正在计算黄金温度与市场状态…"))
        } else if let error = model.temperatureError, model.temperature == nil {
            errorCard(title: L10n.tr("黄金温度加载失败"), message: error) {
                Task { await model.loadTemperature() }
            }
        } else if let report = model.temperature {
            if report.hasAvailableData {
                let dual = MacroPresentation.dualHorizonSummary(for: report)
                temperatureHeroCard(report, dual: dual)
                if report.volatilityAlert {
                    volatilityAlertCard(MacroPresentation.objectiveVolatilityNote(for: report))
                }
                macroRegimeCard(dual)
                dualHorizonComparisonCard(report, dual: dual)
                temperatureHistoryCard
                dimensionsCard(report.dimensions)
                Text(MacroPresentation.objectiveDisclaimer(for: report.actionGuide))
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textFaint)
                    .padding(.horizontal, 4)
            } else {
                emptyCard(
                    icon: "arrow.triangle.2.circlepath.circle",
                    title: L10n.tr("黄金温度正在初始化同步"),
                    detail: L10n.tr("后端首次同步宏观与黄金历史数据完成后会自动生成 0~100° 温度读数，当前不展示估算假数据。")
                ) {
                    Task { await model.loadTemperature() }
                }
                temperatureHistoryCard
            }
        } else {
            loadingCard(L10n.tr("正在准备黄金温度数据…"))
        }
    }

    private func temperatureHeroCard(_ report: MacroTemperatureReport, dual: MacroDualHorizonSummary) -> some View {
        let shortTint = MacroPresentation.temperatureColor(for: dual.shortTermLevel)
        return VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(L10n.tr("黄金温度计"))
                            .font(.headline)
                            .foregroundStyle(GoldTheme.text)

                        Text(L10n.tr("短期 · 交易热度"))
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(shortTint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(shortTint.opacity(0.14), in: GoldTheme.capsuleShape)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        Button {
                            showingGuideHelp = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(GoldTheme.textSecondary)
                                .frame(width: 26, height: 26)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.tr("查看黄金温度计说明"))
                        .accessibilityIdentifier("macro.dashboard.guideButton")
                    }

                    Text(L10n.fmt("截至 %@ · 模型 %@", MacroDateParser.displayDay(report.asOf), report.modelVersion))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                Spacer(minLength: 4)
                if report.degraded {
                    Label(L10n.tr("降级模式"), systemImage: "exclamationmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(GoldTheme.tempWarm)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(GoldTheme.tempWarm.opacity(0.14), in: GoldTheme.capsuleShape)
                }
            }

            GoldTemperatureGauge(
                score: report.score,
                level: report.level,
                levelLabel: dual.shortTermLevelLabel,
                compact: false
            )
            .padding(.top, 2)

            Text(dual.shortTermDetailNote)
                .font(.footnote)
                .foregroundStyle(GoldTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            HStack(spacing: 10) {
                deltaChip(title: L10n.tr("较前1日"), value: report.change1d)
                deltaChip(title: L10n.tr("较前5日"), value: report.change5d)
            }

            if report.degraded && !report.missingFactors.isEmpty {
                let names = report.missingFactors.map(MacroPresentation.factorDisplayName).joined(separator: L10n.tr("、"))
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(GoldTheme.goldSoft)
                    Text(L10n.fmt("当前缺失因子：%@，已按其余可用维度权重等比归一化计算。", names))
                        .font(.caption2)
                        .foregroundStyle(GoldTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(GoldTheme.background, in: GoldTheme.subCardShape)
            }
        }
        .goldCard(padding: 16)
    }

    private func deltaChip(title: String, value: Double?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(GoldTheme.textSecondary)
            Text(MacroPresentation.formatSignedPoints(value))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(MacroPresentation.changeColor(for: value))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(GoldTheme.background, in: GoldTheme.subCardShape)
        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    private func volatilityAlertCard(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.title3.weight(.semibold))
                .foregroundStyle(GoldTheme.up)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("高波动状态提示"))
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.up)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(GoldTheme.text)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(GoldTheme.up.opacity(0.11), in: GoldTheme.cardShape)
        .overlay(GoldTheme.cardShape.strokeBorder(GoldTheme.up.opacity(0.32), lineWidth: 1))
    }

    private func macroRegimeCard(_ dual: MacroDualHorizonSummary) -> some View {
        let tint = MacroPresentation.regimeColor(for: dual.longTermRegime)
        let clamped = dual.longTermScore
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.tr("长期 · 宏观背景"), systemImage: "globe.americas.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.gold)
                Spacer()
                Text(dual.longTermState)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.14), in: GoldTheme.capsuleShape)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", clamped))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.text)
                Text(L10n.tr("/ 100分"))
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
                Spacer()
                Text(L10n.tr("美债/财政压力/央行购金/实际利率"))
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    GoldTheme.capsuleShape.fill(GoldTheme.calendarCell)
                    GoldTheme.capsuleShape
                        .fill(tint)
                        .frame(width: max(8, proxy.size.width * (clamped / 100.0)))
                }
            }
            .frame(height: 7)

            Text(dual.longTermDetailNote)
                .font(.footnote)
                .foregroundStyle(GoldTheme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .goldCard(padding: 16)
    }

    private func dualHorizonComparisonCard(_ report: MacroTemperatureReport, dual: MacroDualHorizonSummary) -> some View {
        let guide = report.actionGuide
        let shortTint = MacroPresentation.temperatureColor(for: dual.shortTermLevel)
        let longTint = MacroPresentation.regimeColor(for: dual.longTermRegime)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 6) {
                Label(L10n.tr("短长周期状态对照"), systemImage: "safari.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.gold)

                Spacer(minLength: 4)

                Text(dual.combinedPatternLabel)
                    .font(.caption.bold())
                    .foregroundStyle(GoldTheme.onGold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(GoldTheme.gold, in: GoldTheme.capsuleShape)
            }

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(shortTint)
                        .frame(width: 7, height: 7)
                    Text(L10n.fmt("短期 %@ · %@", String(format: "%.1f°", dual.shortTermScore), dual.shortTermState))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("×")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(GoldTheme.textFaint)

                HStack(spacing: 5) {
                    Circle()
                        .fill(longTint)
                        .frame(width: 7, height: 7)
                    Text(L10n.fmt("长期 %@ · %@", dual.longTermScoreText, dual.longTermState))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(GoldTheme.background, in: GoldTheme.subCardShape)
            .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))

            Text(dual.combinedSummary)
                .font(.footnote)
                .foregroundStyle(GoldTheme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                cushionTile(
                    title: L10n.tr("200日均线偏离"),
                    value: MacroPresentation.formatPercent(guide.ma200DeviationPct, signed: true),
                    note: MacroPresentation.objectiveMa200Note(for: guide),
                    tint: MacroPresentation.changeColor(for: guide.ma200DeviationPct)
                )
                cushionTile(
                    title: L10n.tr("上海金溢价"),
                    value: MacroPresentation.formatPercent(guide.domesticPremiumPct, signed: true),
                    note: MacroPresentation.objectiveDomesticPremiumNote(for: guide),
                    tint: MacroPresentation.changeColor(for: guide.domesticPremiumPct)
                )
            }
        }
        .goldCard(padding: 16)
    }

    private func cushionTile(title: String, value: String, note: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(GoldTheme.textSecondary)
            Text(value)
                .font(.system(.headline, design: .rounded).bold())
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(note.isEmpty ? L10n.tr("暂无补充说明") : note)
                .font(.caption2)
                .foregroundStyle(GoldTheme.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(GoldTheme.background, in: GoldTheme.subCardShape)
        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    // MARK: - 金价 vs 黄金温度 历史联动曲线

    private var temperatureHistoryCard: some View {
        let points = model.temperatureHistory?.points ?? []
        let inspected: MacroTemperatureHistoryPoint? = selectedHistoryDate.flatMap { target in
            points.min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.tr("金价 vs 黄金温度"))
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.text)
                Spacer()
                if let inspected {
                    HStack(spacing: 6) {
                        Text(inspected.dateString)
                            .foregroundStyle(GoldTheme.textSecondary)
                        if let price = inspected.goldPriceUSD {
                            Text("$" + price.formatted(.number.precision(.fractionLength(0))))
                                .foregroundStyle(GoldTheme.gold)
                        }
                        Text(MacroPresentation.formatScore(inspected.score))
                            .foregroundStyle(MacroPresentation.temperatureColor(for: inspected.level))
                    }
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                } else {
                    HStack(spacing: 10) {
                        legendDot(color: GoldTheme.gold, label: L10n.tr("国际金价"))
                        legendDot(color: GoldTheme.chartSecondary, label: L10n.tr("温度"))
                    }
                }
            }

            historyRangeBar(selected: model.temperatureRange) { chosen in
                selectedHistoryDate = nil
                Task { await model.selectTemperatureRange(chosen) }
            }

            if model.isLoadingHistory && points.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().tint(GoldTheme.gold)
                    Text(L10n.tr("正在加载历史温度曲线…"))
                        .font(.footnote)
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 190)
            } else if let error = model.historyError, points.isEmpty {
                inlineErrorView(message: error) {
                    Task { await model.loadTemperatureHistory() }
                }
            } else if points.isEmpty {
                Text(L10n.tr("暂无历史温度曲线数据，待首次历史回算完成后展示。"))
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                let goldPoints = points.compactMap { p -> (Date, Double)? in
                    guard let price = p.goldPriceUSD else { return nil }
                    return (p.date, price)
                }
                if !goldPoints.isEmpty {
                    let goldContext = model.temperatureGoldPriceScaleContext
                    VStack(alignment: .leading, spacing: 6) {
                        MacroChartScaleBar(
                            context: goldContext,
                            leadingLabel: L10n.tr("国际金价（USD/oz）"),
                            accessibilityPrefix: "macro.temperature.gold"
                        ) { chosen in
                            withAnimation(.easeInOut(duration: 0.18)) {
                                model.setTemperatureGoldPriceScale(chosen)
                            }
                        }
                        Chart {
                            ForEach(points) { point in
                                if let price = point.goldPriceUSD {
                                    let plotY = goldContext.clampedPlotValue(price)
                                    LineMark(
                                        x: .value(L10n.tr("日期"), point.date),
                                        y: .value(L10n.tr("金价"), plotY)
                                    )
                                    .foregroundStyle(GoldTheme.gold)
                                    .lineStyle(StrokeStyle(lineWidth: 1.8))
                                    .interpolationMethod(.monotone)

                                    if goldPoints.count == 1 {
                                        PointMark(
                                            x: .value(L10n.tr("日期"), point.date),
                                            y: .value(L10n.tr("金价"), plotY)
                                        )
                                        .foregroundStyle(GoldTheme.gold)
                                        .symbolSize(36)
                                    }
                                }
                            }
                            if let inspected, let price = inspected.goldPriceUSD {
                                RuleMark(x: .value(L10n.tr("选中"), inspected.date))
                                    .foregroundStyle(GoldTheme.goldSoft.opacity(0.6))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                PointMark(
                                    x: .value(L10n.tr("选中"), inspected.date),
                                    y: .value(L10n.tr("金价"), goldContext.clampedPlotValue(price))
                                )
                                .foregroundStyle(GoldTheme.gold)
                                .symbolSize(36)
                            }
                        }
                        .chartYScale(domain: goldContext.domain)
                        .chartPlotStyle { $0.clipped() }
                        .chartXSelection(value: $selectedHistoryDate)
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(position: .trailing, values: goldContext.yAxisTicks) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(GoldTheme.gridline)
                                AxisValueLabel {
                                    if let plotY = value.as(Double.self) {
                                        Text(goldContext.axisLabel(forPlotValue: plotY))
                                            .font(.caption2)
                                            .monospacedDigit()
                                            .foregroundStyle(GoldTheme.textSecondary)
                                    }
                                }
                            }
                        }
                        .frame(height: 112)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("短期交易温度（0~100° · 虚线 20° 极冷 / 80° 极热）"))
                        .font(.caption2)
                        .foregroundStyle(GoldTheme.textSecondary)
                    Chart {
                        RuleMark(y: .value(L10n.tr("过热"), 80))
                            .foregroundStyle(GoldTheme.tempHot.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        RuleMark(y: .value(L10n.tr("冰点"), 20))
                            .foregroundStyle(GoldTheme.tempFreezing.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        ForEach(points) { point in
                            AreaMark(
                                x: .value(L10n.tr("日期"), point.date),
                                yStart: .value(L10n.tr("底"), 0),
                                yEnd: .value(L10n.tr("温度"), point.score)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [GoldTheme.chartSecondary.opacity(0.18), GoldTheme.chartSecondary.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.monotone)

                            LineMark(
                                x: .value(L10n.tr("日期"), point.date),
                                y: .value(L10n.tr("温度"), point.score)
                            )
                            .foregroundStyle(GoldTheme.chartSecondary)
                            .lineStyle(StrokeStyle(lineWidth: 1.8))
                            .interpolationMethod(.monotone)

                            if points.count == 1 {
                                PointMark(x: .value(L10n.tr("日期"), point.date), y: .value(L10n.tr("温度"), point.score))
                                    .foregroundStyle(GoldTheme.chartSecondary)
                                    .symbolSize(40)
                            }
                        }

                        if let inspected {
                            RuleMark(x: .value(L10n.tr("选中"), inspected.date))
                                .foregroundStyle(GoldTheme.goldSoft.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            PointMark(x: .value(L10n.tr("选中"), inspected.date), y: .value(L10n.tr("温度"), inspected.score))
                                .foregroundStyle(MacroPresentation.temperatureColor(for: inspected.level))
                                .symbolSize(40)
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartPlotStyle { $0.clipped() }
                    .chartXSelection(value: $selectedHistoryDate)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(GoldTheme.gridline)
                            AxisValueLabel().foregroundStyle(GoldTheme.textSecondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: [20, 50, 80]) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(GoldTheme.gridline)
                            AxisValueLabel().foregroundStyle(GoldTheme.textSecondary)
                        }
                    }
                    .frame(height: 126)
                }
            }
        }
        .goldCard(padding: 16)
    }

    // MARK: - 五维因子拆解

    private func dimensionsCard(_ dimensions: [MacroTemperatureDimension]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.tr("短期温度 · 五维拆解"))
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.text)
                Spacer()
                Text(L10n.tr("基于 3 年滚动历史分位"))
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textFaint)
            }

            if dimensions.isEmpty {
                Text(L10n.tr("暂无维度拆分数据"))
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.textSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(dimensions) { dim in
                        dimensionRow(dim)
                    }
                }
            }
        }
        .goldCard(padding: 16)
    }

    private func dimensionRow(_ dim: MacroTemperatureDimension) -> some View {
        let clamped = MacroPresentation.clampedTemperatureScore(dim.score)
        let tint = dim.available ? MacroPresentation.temperatureColor(forScore: clamped) : GoldTheme.textFaint
        let summaryText = dim.localizedSummary
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(dim.localizedName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(GoldTheme.text)
                Text(L10n.fmt("权重 %@", "\(Int((dim.weight * 100).rounded()))%"))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.textFaint)
                Spacer()
                if dim.available {
                    Text(String(format: "%.1f°", clamped))
                        .font(.footnote.bold())
                        .monospacedDigit()
                        .foregroundStyle(tint)
                } else {
                    Text(L10n.tr("暂缺"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(GoldTheme.textFaint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(GoldTheme.calendarCell, in: GoldTheme.badgeShape)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    GoldTheme.capsuleShape.fill(GoldTheme.calendarCell)
                    if dim.available {
                        GoldTheme.capsuleShape
                            .fill(tint)
                            .frame(width: max(6, proxy.size.width * (clamped / 100.0)))
                    }
                }
            }
            .frame(height: 6)

            if !summaryText.isEmpty {
                Text(summaryText)
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(GoldTheme.background, in: GoldTheme.subCardShape)
        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    // MARK: - Tab 2: 美国国债专题

    @ViewBuilder
    private var treasuryTabContent: some View {
        if model.isLoadingTreasury && model.treasury == nil {
            loadingCard(L10n.tr("正在加载美国国债与利率专题…"))
        } else if let error = model.treasuryError, model.treasury == nil {
            errorCard(title: L10n.tr("美国国债数据加载失败"), message: error) {
                Task { await model.loadTreasury() }
            }
        } else if let report = model.treasury {
            if report.hasAnyData {
                MacroTreasuryPressureCard(
                    model: MacroTreasuryPressureModel.make(from: report),
                    asOf: report.asOf
                ) {
                    showingTreasuryPressureGuide = true
                }
                treasurySummaryCard(report)
                extendedRangeBar(selected: model.treasuryRange) { chosen in
                    selectedDebtDate = nil
                    selectedYieldDate = nil
                    Task { await model.selectTreasuryRange(chosen) }
                }
                treasuryDebtChartCard(report.debtSeries)
                treasuryYieldChartCard(real: report.realYieldSeries, nominal: report.nominalYieldSeries)
                if !report.cards.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.tr("美债与长债 ETF 核心指标"))
                            .font(.subheadline.bold())
                            .foregroundStyle(GoldTheme.text)
                            .padding(.horizontal, 2)
                        ForEach(report.cards) { item in
                            MacroIndicatorRowCard(summary: item) {
                                selectedIndicator = item
                            }
                        }
                    }
                }
            } else {
                emptyCard(
                    icon: "building.columns",
                    title: L10n.tr("美国国债数据正在同步中"),
                    detail: L10n.tr("待 Treasury Fiscal Data 与 FRED 首次同步完成后，将自动展示美债总规模、实际利率与财政压力。")
                ) {
                    Task { await model.loadTreasury() }
                }
            }
        } else {
            loadingCard(L10n.tr("正在准备美国国债专题…"))
        }
    }

    private func treasurySummaryCard(_ report: MacroTreasuryReport) -> some View {
        let s = report.summary
        let impactNote = s.localizedGoldImpactNote
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("美国联邦国债总规模"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(GoldTheme.textSecondary)
                    Text(MacroPresentation.formatTrillionUSD(s.totalDebtTrillionUSD))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.gold)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(L10n.tr("近1年净增"))
                        .font(.caption2)
                        .foregroundStyle(GoldTheme.textSecondary)
                    Text(MacroPresentation.formatTrillionUSD(s.debtChangeYoYTrillion, signed: true))
                        .font(.subheadline.bold())
                        .monospacedDigit()
                        .foregroundStyle(MacroPresentation.changeColor(for: s.debtChangeYoYTrillion))
                    Text(L10n.fmt("截至 %@", MacroDateParser.displayDay(report.asOf)))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.textFaint)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                treasuryMetricCell(L10n.tr("10Y 实际利率"), MacroPresentation.formatPercent(s.yield10yRealPct), tint: GoldTheme.goldSoft)
                treasuryMetricCell(L10n.tr("10Y 名义利率"), MacroPresentation.formatPercent(s.yield10yNominalPct))
                treasuryMetricCell(L10n.tr("2Y 名义利率"), MacroPresentation.formatPercent(s.yield2yNominalPct))
                treasuryMetricCell(L10n.tr("10Y-2Y 利差"), MacroPresentation.formatPercent(s.spread10y2yPct, signed: true), tint: MacroPresentation.changeColor(for: s.spread10y2yPct))
                treasuryMetricCell(L10n.tr("10Y 通胀预期"), MacroPresentation.formatPercent(s.breakeven10yPct))
                treasuryMetricCell(L10n.tr("TLT 长债 ETF"), s.tltPrice.map { "$" + $0.formatted(.number.precision(.fractionLength(2))) } ?? "—")
                treasuryMetricCell(L10n.tr("美债 / GDP"), MacroPresentation.formatPercent(s.debtToGDPPct))
                treasuryMetricCell(L10n.tr("付息 / 财政收入"), MacroPresentation.formatPercent(s.interestToRevenuePct))
                treasuryMetricCell(L10n.tr("财政压力指数"), s.fiscalStressScore.map { String(format: "%.1f", $0) } ?? "—", tint: s.fiscalStressScore.map { MacroPresentation.temperatureColor(forScore: $0) } ?? GoldTheme.text)
            }

            if !impactNote.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(GoldTheme.gold)
                    Text(impactNote)
                        .font(.footnote)
                        .foregroundStyle(GoldTheme.text)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GoldTheme.background, in: GoldTheme.subCardShape)
                .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.gold.opacity(0.25), lineWidth: 1))
            }
        }
        .goldCard(padding: 16)
    }

    private func treasuryMetricCell(_ title: String, _ value: String, tint: Color = GoldTheme.text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(GoldTheme.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(GoldTheme.background, in: GoldTheme.subCardShape)
        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    private func treasuryDebtChartCard(_ series: [MacroTimePoint]) -> some View {
        let inspected = selectedDebtDate.flatMap { target in
            series.min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.tr("美债总规模走势（万亿美元）"))
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.text)
                Spacer()
                if let inspected {
                    Text("\(inspected.dateString) · \(MacroPresentation.formatTrillionUSD(inspected.value))")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.goldSoft)
                }
            }

            if series.isEmpty {
                Text(L10n.tr("暂无美债总规模历史序列"))
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                let debtContext = model.treasuryDebtScaleContext
                let domain = debtContext.domain

                MacroChartScaleBar(
                    context: debtContext,
                    accessibilityPrefix: "macro.treasury.debt"
                ) { chosen in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.setTreasuryDebtScale(chosen)
                    }
                }

                Chart {
                    ForEach(series) { point in
                        let plotY = debtContext.clampedPlotValue(point.value)
                        AreaMark(
                            x: .value(L10n.tr("日期"), point.date),
                            yStart: .value(L10n.tr("基线"), domain.lowerBound),
                            yEnd: .value(L10n.tr("规模"), plotY)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [GoldTheme.chartFill, GoldTheme.gold.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value(L10n.tr("日期"), point.date),
                            y: .value(L10n.tr("规模"), plotY)
                        )
                        .foregroundStyle(GoldTheme.gold)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)

                        if series.count == 1 {
                            PointMark(x: .value(L10n.tr("日期"), point.date), y: .value(L10n.tr("规模"), plotY))
                                .foregroundStyle(GoldTheme.gold)
                                .symbolSize(44)
                        }
                    }
                    if let inspected {
                        RuleMark(x: .value(L10n.tr("选中"), inspected.date))
                            .foregroundStyle(GoldTheme.goldSoft.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        PointMark(
                            x: .value(L10n.tr("选中"), inspected.date),
                            y: .value(L10n.tr("规模"), debtContext.clampedPlotValue(inspected.value))
                        )
                        .foregroundStyle(GoldTheme.gold)
                        .symbolSize(44)
                    }
                }
                .chartYScale(domain: domain)
                .chartPlotStyle { $0.clipped() }
                .chartXSelection(value: $selectedDebtDate)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(GoldTheme.gridline)
                        AxisValueLabel().foregroundStyle(GoldTheme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: debtContext.yAxisTicks) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(GoldTheme.gridline)
                        AxisValueLabel {
                            if let plotY = value.as(Double.self) {
                                Text(debtContext.axisLabel(forPlotValue: plotY))
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(GoldTheme.textSecondary)
                            }
                        }
                    }
                }
                .frame(height: 185)
            }
        }
        .goldCard(padding: 16)
    }

    private func treasuryYieldChartCard(real: [MacroTimePoint], nominal: [MacroTimePoint]) -> some View {
        let inspectedReal = selectedYieldDate.flatMap { target in
            real.min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }
        }
        let inspectedNominal = selectedYieldDate.flatMap { target in
            nominal.min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.tr("10Y 实际利率 vs 名义利率（%）"))
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.text)
                Spacer()
                if inspectedReal != nil || inspectedNominal != nil {
                    HStack(spacing: 6) {
                        if let r = inspectedReal {
                            Text(L10n.fmt("实 %@", MacroPresentation.formatPercent(r.value)))
                                .foregroundStyle(GoldTheme.gold)
                        }
                        if let n = inspectedNominal {
                            Text(L10n.fmt("名 %@", MacroPresentation.formatPercent(n.value)))
                                .foregroundStyle(GoldTheme.chartSecondary)
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                } else {
                    HStack(spacing: 10) {
                        legendDot(color: GoldTheme.gold, label: L10n.tr("实际"))
                        legendDot(color: GoldTheme.chartSecondary, label: L10n.tr("名义"))
                    }
                }
            }

            if real.isEmpty && nominal.isEmpty {
                Text(L10n.tr("暂无 10Y 美债收益率历史数据（需配置 FRED 数据源）"))
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                let yieldContext = model.treasuryYieldScaleContext

                MacroChartScaleBar(
                    context: yieldContext,
                    accessibilityPrefix: "macro.treasury.yield"
                ) { chosen in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.setTreasuryYieldScale(chosen)
                    }
                }

                Chart {
                    if yieldContext.effectiveScale == .linear {
                        RuleMark(y: .value(L10n.tr("零轴"), 0))
                            .foregroundStyle(GoldTheme.textFaint.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }

                    ForEach(nominal) { point in
                        let plotY = yieldContext.clampedPlotValue(point.value)
                        LineMark(
                            x: .value(L10n.tr("日期"), point.date),
                            y: .value(L10n.tr("收益率"), plotY),
                            series: .value(L10n.tr("类型"), L10n.tr("名义"))
                        )
                        .foregroundStyle(GoldTheme.chartSecondary)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                        .interpolationMethod(.monotone)

                        if nominal.count == 1 {
                            PointMark(x: .value(L10n.tr("日期"), point.date), y: .value(L10n.tr("收益率"), plotY))
                                .foregroundStyle(GoldTheme.chartSecondary)
                                .symbolSize(36)
                        }
                    }

                    ForEach(real) { point in
                        let plotY = yieldContext.clampedPlotValue(point.value)
                        LineMark(
                            x: .value(L10n.tr("日期"), point.date),
                            y: .value(L10n.tr("收益率"), plotY),
                            series: .value(L10n.tr("类型"), L10n.tr("实际"))
                        )
                        .foregroundStyle(GoldTheme.gold)
                        .lineStyle(StrokeStyle(lineWidth: 2.0))
                        .interpolationMethod(.monotone)

                        if real.count == 1 {
                            PointMark(x: .value(L10n.tr("日期"), point.date), y: .value(L10n.tr("收益率"), plotY))
                                .foregroundStyle(GoldTheme.gold)
                                .symbolSize(36)
                        }
                    }

                    if let target = inspectedReal?.date ?? inspectedNominal?.date {
                        RuleMark(x: .value(L10n.tr("选中"), target))
                            .foregroundStyle(GoldTheme.goldSoft.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    if let r = inspectedReal {
                        PointMark(
                            x: .value(L10n.tr("选中"), r.date),
                            y: .value(L10n.tr("收益率"), yieldContext.clampedPlotValue(r.value))
                        )
                        .foregroundStyle(GoldTheme.gold)
                        .symbolSize(36)
                    }
                    if let n = inspectedNominal {
                        PointMark(
                            x: .value(L10n.tr("选中"), n.date),
                            y: .value(L10n.tr("收益率"), yieldContext.clampedPlotValue(n.value))
                        )
                        .foregroundStyle(GoldTheme.chartSecondary)
                        .symbolSize(36)
                    }
                }
                .chartYScale(domain: yieldContext.domain)
                .chartPlotStyle { $0.clipped() }
                .chartXSelection(value: $selectedYieldDate)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(GoldTheme.gridline)
                        AxisValueLabel().foregroundStyle(GoldTheme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: yieldContext.yAxisTicks) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(GoldTheme.gridline)
                        AxisValueLabel {
                            if let plotY = value.as(Double.self) {
                                Text(yieldContext.axisLabel(forPlotValue: plotY))
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(GoldTheme.textSecondary)
                            }
                        }
                    }
                }
                .frame(height: 185)
            }
        }
        .goldCard(padding: 16)
    }

    // MARK: - Tab 3: 宏观全景（全景温度计 + 6 大板块 + COT）

    @ViewBuilder
    private var panoramaTabContent: some View {
        let panoramaModel = model.panoramaThermometerModel
        if panoramaModel.hasAnyData {
            MacroPanoramaThermometerCard(
                model: panoramaModel,
                selectedSectionID: model.selectedSectionID,
                onToggleSection: { sectionID in
                    withAnimation(.easeInOut(duration: 0.16)) {
                        model.toggleSectionSelection(sectionID)
                    }
                },
                onClearSelection: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        model.selectedSectionID = nil
                    }
                },
                onShowGuide: {
                    showingPanoramaGuide = true
                }
            )
        }

        if model.isLoadingCatalog && model.catalog == nil {
            cotSectionCard
            loadingCard(L10n.tr("正在加载 6 大板块宏观指标…"))
        } else if let error = model.catalogError, model.catalog == nil {
            cotSectionCard
            errorCard(title: L10n.tr("宏观指标目录加载失败"), message: error) {
                Task { await model.loadCatalog() }
            }
        } else if let catalog = model.catalog, !catalog.sections.isEmpty {
            sectionFilterBar(sections: catalog.sections)

            if model.selectedSectionID == nil {
                cotSectionCard
            }

            ForEach(model.filteredSections) { section in
                let sectionDescription = section.localizedDescription
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(section.localizedName)
                                .font(.headline)
                                .foregroundStyle(GoldTheme.gold)
                            Spacer()
                            Text(L10n.fmt("%lld 项", Int64(section.indicators.count)))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(GoldTheme.textFaint)
                        }
                        if !sectionDescription.isEmpty {
                            Text(sectionDescription)
                                .font(.caption)
                                .foregroundStyle(GoldTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.top, 4)

                    ForEach(section.indicators) { summary in
                        MacroIndicatorRowCard(summary: summary) {
                            selectedIndicator = summary
                        }
                    }
                }
            }

            if model.selectedSectionID != nil {
                cotSectionCard
            }
        } else {
            cotSectionCard
            emptyCard(
                icon: "square.grid.2x2",
                title: L10n.tr("宏观指标目录暂为空"),
                detail: L10n.tr("待后端完成元数据初始化后即可查看全部 6 大宏观板块与历史走势。")
            ) {
                Task { await model.loadCatalog() }
            }
        }
    }

    private func sectionFilterBar(sections: [MacroIndicatorSection]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                sectionFilterChip(id: nil, title: L10n.tr("全部板块"))
                ForEach(sections) { section in
                    sectionFilterChip(id: section.id, title: section.localizedName)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func sectionFilterChip(id: String?, title: String) -> some View {
        let isSelected = model.selectedSectionID == id
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                model.selectedSectionID = id
            }
        } label: {
            Text(title)
                .font(.caption.weight(isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? GoldTheme.onGold : GoldTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? GoldTheme.gold : GoldTheme.card, in: GoldTheme.capsuleShape)
                .overlay(GoldTheme.capsuleShape.strokeBorder(isSelected ? Color.clear : GoldTheme.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - CFTC 黄金持仓（COT）

    private var cotSectionCard: some View {
        let points = model.cot?.points ?? []
        let latest = model.cot?.latest ?? points.last
        let inspected = selectedCotDate.flatMap { target in
            points.min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }
        }
        let activePoint = inspected ?? latest

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.tr("CFTC 黄金持仓（COT）"), systemImage: "chart.bar.doc.horizontal")
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.gold)
                Spacer()
                if let activePoint {
                    Text(activePoint.dateString)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.textSecondary)
                }
            }

            historyRangeBar(selected: model.cotRange) { chosen in
                selectedCotDate = nil
                Task { await model.selectCotRange(chosen) }
            }

            if model.isLoadingCot && points.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().tint(GoldTheme.gold)
                    Text(L10n.tr("正在加载 CFTC 持仓周报…"))
                        .font(.footnote)
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else if let error = model.cotError, points.isEmpty {
                inlineErrorView(message: error) {
                    Task { await model.loadCot() }
                }
            } else if points.isEmpty {
                Text(L10n.tr("暂无 CFTC 黄金期货持仓数据。"))
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                if let activePoint {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        treasuryMetricCell(
                            L10n.tr("管理基金净多"),
                            MacroPresentation.formatContracts(activePoint.mmNet, signed: true),
                            tint: MacroPresentation.changeColor(for: activePoint.mmNet)
                        )
                        treasuryMetricCell(
                            L10n.tr("Swap 净头寸"),
                            MacroPresentation.formatContracts(activePoint.swapNet, signed: true),
                            tint: GoldTheme.chartSecondary
                        )
                        treasuryMetricCell(
                            L10n.tr("总持仓量"),
                            MacroPresentation.formatContracts(activePoint.openInterest),
                            tint: GoldTheme.goldSoft
                        )
                    }

                    HStack(spacing: 12) {
                        Text(L10n.fmt("管理基金净多占比：%@", MacroPresentation.formatPercent(activePoint.mmNetRatioPct)))
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.textSecondary)
                        Spacer()
                        HStack(spacing: 10) {
                            legendDot(color: GoldTheme.up, label: L10n.tr("基金净多"))
                            legendDot(color: GoldTheme.chartSecondary, label: L10n.tr("Swap 净头寸"))
                        }
                    }
                }

                let cotContext = model.cotScaleContext

                MacroChartScaleBar(
                    context: cotContext,
                    accessibilityPrefix: "macro.panorama.cot"
                ) { chosen in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.setCotScale(chosen)
                    }
                }

                Chart {
                    if cotContext.effectiveScale == .linear {
                        RuleMark(y: .value(L10n.tr("零轴"), 0))
                            .foregroundStyle(GoldTheme.textFaint.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }

                    ForEach(points) { point in
                        let mmPlotY = cotContext.clampedPlotValue(point.mmNet)
                        let swapPlotY = cotContext.clampedPlotValue(point.swapNet)
                        LineMark(
                            x: .value(L10n.tr("日期"), point.date),
                            y: .value(L10n.tr("头寸"), mmPlotY),
                            series: .value(L10n.tr("阵营"), L10n.tr("管理基金净多"))
                        )
                        .foregroundStyle(GoldTheme.up)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value(L10n.tr("日期"), point.date),
                            y: .value(L10n.tr("头寸"), swapPlotY),
                            series: .value(L10n.tr("阵营"), L10n.tr("Swap 净头寸"))
                        )
                        .foregroundStyle(GoldTheme.chartSecondary)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                        .interpolationMethod(.monotone)

                        if points.count == 1 {
                            PointMark(x: .value(L10n.tr("日期"), point.date), y: .value(L10n.tr("头寸"), mmPlotY))
                                .foregroundStyle(GoldTheme.up)
                                .symbolSize(36)
                            PointMark(x: .value(L10n.tr("日期"), point.date), y: .value(L10n.tr("头寸"), swapPlotY))
                                .foregroundStyle(GoldTheme.chartSecondary)
                                .symbolSize(36)
                        }
                    }

                    if let inspected {
                        RuleMark(x: .value(L10n.tr("选中"), inspected.date))
                            .foregroundStyle(GoldTheme.goldSoft.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        PointMark(
                            x: .value(L10n.tr("选中"), inspected.date),
                            y: .value(L10n.tr("头寸"), cotContext.clampedPlotValue(inspected.mmNet))
                        )
                        .foregroundStyle(GoldTheme.up)
                        .symbolSize(36)
                        PointMark(
                            x: .value(L10n.tr("选中"), inspected.date),
                            y: .value(L10n.tr("头寸"), cotContext.clampedPlotValue(inspected.swapNet))
                        )
                        .foregroundStyle(GoldTheme.chartSecondary)
                        .symbolSize(36)
                    }
                }
                .chartYScale(domain: cotContext.domain)
                .chartPlotStyle { $0.clipped() }
                .chartXSelection(value: $selectedCotDate)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(GoldTheme.gridline)
                        AxisValueLabel().foregroundStyle(GoldTheme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: cotContext.yAxisTicks) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(GoldTheme.gridline)
                        AxisValueLabel {
                            if let plotY = value.as(Double.self) {
                                Text(cotContext.axisLabel(forPlotValue: plotY))
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(GoldTheme.textSecondary)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
        .goldCard(padding: 16)
    }

    // MARK: - 通用辅助组件

    private func historyRangeBar(selected: MacroHistoryRange, onSelect: @escaping (MacroHistoryRange) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(MacroHistoryRange.allCases) { item in
                let isSelected = selected == item
                Button {
                    onSelect(item)
                } label: {
                    Text(item.title)
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? GoldTheme.onGold : GoldTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(isSelected ? GoldTheme.gold : GoldTheme.background, in: GoldTheme.capsuleShape)
                        .overlay(GoldTheme.capsuleShape.strokeBorder(isSelected ? Color.clear : GoldTheme.cardStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func extendedRangeBar(selected: MacroExtendedRange, onSelect: @escaping (MacroExtendedRange) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(MacroExtendedRange.allCases) { item in
                let isSelected = selected == item
                Button {
                    onSelect(item)
                } label: {
                    Text(item.title)
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? GoldTheme.onGold : GoldTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(isSelected ? GoldTheme.gold : GoldTheme.card, in: GoldTheme.capsuleShape)
                        .overlay(GoldTheme.capsuleShape.strokeBorder(isSelected ? Color.clear : GoldTheme.cardStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(GoldTheme.textSecondary)
        }
    }

    private func loadingCard(_ text: String) -> some View {
        VStack(spacing: 12) {
            ProgressView().tint(GoldTheme.gold)
            Text(text)
                .font(.footnote)
                .foregroundStyle(GoldTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .goldCard(padding: 16)
    }

    private func errorCard(title: String, message: String, onRetry: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title2)
                .foregroundStyle(GoldTheme.tempWarm)
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(GoldTheme.text)
            Text(message)
                .font(.footnote)
                .foregroundStyle(GoldTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button(L10n.tr("重新加载"), action: onRetry)
                .buttonStyle(GoldCapsuleStyle(isSelected: true))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .goldCard(padding: 20)
    }

    private func emptyCard(icon: String, title: String, detail: String, onRefresh: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(GoldTheme.goldSoft)
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(GoldTheme.text)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(GoldTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Button(L10n.tr("刷新看看"), action: onRefresh)
                .buttonStyle(GoldCapsuleStyle(isSelected: false))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .goldCard(padding: 20)
    }

    private func inlineErrorView(message: String, onRetry: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(GoldTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button(L10n.tr("重试"), action: onRetry)
                .buttonStyle(GoldCapsuleStyle(isSelected: false))
        }
        .frame(maxWidth: .infinity, minHeight: 110)
    }
}

// MARK: - 宏观单指标卡片（供美债专题与 6 大板块复用）

struct MacroIndicatorRowCard: View {
    let summary: MacroIndicatorSummary
    let onTap: () -> Void

    private var primaryChange: (label: String, value: Double?) {
        if let d5 = summary.change5d { return (L10n.tr("5日"), d5) }
        if let d20 = summary.change20d { return (L10n.tr("20日"), d20) }
        if let d3m = summary.change3m { return (L10n.tr("3月"), d3m) }
        return (L10n.tr("同比"), summary.changeYoY)
    }

    var body: some View {
        let noteText = summary.localizedPlainNote
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(summary.localizedName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(GoldTheme.text)
                                .lineLimit(1)
                            Text(MacroPresentation.goldRelationLabel(summary.goldRelation))
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(GoldTheme.goldSoft)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(GoldTheme.gold.opacity(0.12), in: GoldTheme.badgeShape)
                        }
                        Text("\(summary.seriesID) · \(MacroPresentation.frequencyLabel(summary.frequency))")
                            .font(.caption2)
                            .foregroundStyle(GoldTheme.textFaint)
                    }

                    Spacer(minLength: 6)

                    MacroSparklineView(
                        values: summary.sparkline,
                        tint: MacroPresentation.changeColor(for: primaryChange.value) == GoldTheme.textSecondary
                            ? GoldTheme.gold
                            : MacroPresentation.changeColor(for: primaryChange.value)
                    )
                    .frame(width: 62, height: 26)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(MacroPresentation.formatValue(summary.latestValue, unit: summary.unit))
                        .font(.system(.title3, design: .rounded).bold())
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.text)

                    let change = primaryChange
                    if change.value != nil {
                        Text("\(change.label) \(MacroPresentation.formatDelta(change.value, unit: summary.unit))")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(MacroPresentation.changeColor(for: change.value))
                    }

                    Spacer(minLength: 4)

                    if let pct = summary.percentile3y {
                        let tint = MacroPresentation.temperatureColor(forScore: pct)
                        Text(L10n.fmt("3年分位 %@", MacroPresentation.formatPercentile(pct)))
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(tint.opacity(0.13), in: GoldTheme.capsuleShape)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(GoldTheme.textFaint)
                }

                if !noteText.isEmpty {
                    Text(noteText)
                        .font(.caption)
                        .foregroundStyle(GoldTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .goldCard(padding: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("macro.indicator.\(summary.seriesID)")
    }
}
