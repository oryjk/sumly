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
        .navigationTitle("黄金温度与宏观")
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
                .accessibilityLabel("刷新宏观数据")
            }
        }
        .navigationDestination(item: $selectedIndicator) { summary in
            MacroIndicatorDetailView(
                seriesID: summary.seriesID,
                initialSummary: summary,
                service: service
            )
        }
        .refreshable {
            await model.refreshAll()
        }
        .task {
            await model.loadDashboard()
        }
        .sensoryFeedback(.selection, trigger: model.selectedTab)
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
                    Text(tab.rawValue)
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
            loadingCard("正在计算黄金温度与操作指南针…")
        } else if let error = model.temperatureError, model.temperature == nil {
            errorCard(title: "黄金温度加载失败", message: error) {
                Task { await model.loadTemperature() }
            }
        } else if let report = model.temperature {
            if report.hasAvailableData {
                temperatureHeroCard(report)
                if report.volatilityAlert && !report.volatilityNote.isEmpty {
                    volatilityAlertCard(report.volatilityNote)
                }
                macroRegimeCard(report.macroRegime)
                actionGuideCard(report.actionGuide)
                temperatureHistoryCard
                dimensionsCard(report.dimensions)
                if !report.actionGuide.disclaimer.isEmpty {
                    Text(report.actionGuide.disclaimer)
                        .font(.caption2)
                        .foregroundStyle(GoldTheme.textFaint)
                        .padding(.horizontal, 4)
                }
            } else {
                emptyCard(
                    icon: "arrow.triangle.2.circlepath.circle",
                    title: "黄金温度正在初始化同步",
                    detail: "后端首次同步宏观与黄金历史数据完成后会自动生成 0~100° 温度读数，当前不展示估算假数据。"
                ) {
                    Task { await model.loadTemperature() }
                }
                temperatureHistoryCard
            }
        } else {
            loadingCard("正在准备黄金温度数据…")
        }
    }

    private func temperatureHeroCard(_ report: MacroTemperatureReport) -> some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("黄金市场温度")
                        .font(.headline)
                        .foregroundStyle(GoldTheme.text)
                    Text("截至 \(MacroDateParser.displayDay(report.asOf)) · 模型 \(report.modelVersion)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                Spacer()
                if report.degraded {
                    Label("降级模式", systemImage: "exclamationmark.circle.fill")
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
                levelLabel: report.levelLabel,
                compact: false
            )
            .padding(.top, 2)

            HStack(spacing: 10) {
                deltaChip(title: "较前1日", value: report.change1d)
                deltaChip(title: "较前5日", value: report.change5d)
            }

            if report.degraded && !report.missingFactors.isEmpty {
                let names = report.missingFactors.map(MacroPresentation.factorDisplayName).joined(separator: "、")
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(GoldTheme.goldSoft)
                    Text("当前缺失因子：\(names)，已按其余可用维度权重等比归一化计算。")
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
                Text("高波动安全阀提醒")
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

    private func macroRegimeCard(_ regime: MacroRegime) -> some View {
        let tint = MacroPresentation.regimeColor(for: regime.regime)
        let clamped = MacroPresentation.clampedTemperatureScore(regime.score)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("长期宏观底座", systemImage: "globe.americas.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.gold)
                Spacer()
                Text(regime.label.isEmpty ? regime.regime.defaultLabel : regime.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.14), in: GoldTheme.capsuleShape)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.1f", clamped))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.text)
                Text("/ 100")
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
                Spacer()
                Text("美债/财政压力/央行购金/实际利率")
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textFaint)
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

            if !regime.summary.isEmpty {
                Text(regime.summary)
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .goldCard(padding: 16)
    }

    private func actionGuideCard(_ guide: MacroActionGuide) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Label("操作指南针", systemImage: "safari.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.gold)
                Spacer()
                HStack(spacing: 4) {
                    Text("定投系数")
                        .font(.caption2)
                        .foregroundStyle(GoldTheme.onGold.opacity(0.8))
                    Text(MacroPresentation.formatDCAMultiplier(guide.dcaMultiplier))
                        .font(.caption.bold())
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.onGold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(GoldTheme.gold, in: GoldTheme.capsuleShape)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(guide.title.isEmpty ? "当前观察" : guide.title)
                        .font(.headline)
                        .foregroundStyle(GoldTheme.text)
                    if !guide.dcaLabel.isEmpty {
                        Text(guide.dcaLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(GoldTheme.goldSoft)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(GoldTheme.gold.opacity(0.14), in: GoldTheme.badgeShape)
                    }
                }
                if !guide.summary.isEmpty {
                    Text(guide.summary)
                        .font(.footnote)
                        .foregroundStyle(GoldTheme.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                cushionTile(
                    title: "年线偏离安全垫",
                    value: MacroPresentation.formatPercent(guide.ma200DeviationPct, signed: true),
                    note: guide.ma200Note,
                    tint: MacroPresentation.changeColor(for: guide.ma200DeviationPct)
                )
                cushionTile(
                    title: "国内溢价划算度",
                    value: MacroPresentation.formatPercent(guide.domesticPremiumPct, signed: true),
                    note: guide.domesticPremiumNote,
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
            Text(note.isEmpty ? "暂无补充说明" : note)
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
                Text("金价 vs 黄金温度")
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
                        legendDot(color: GoldTheme.gold, label: "国际金价")
                        legendDot(color: GoldTheme.chartSecondary, label: "温度")
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
                    Text("正在加载历史温度曲线…")
                        .font(.footnote)
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 190)
            } else if let error = model.historyError, points.isEmpty {
                inlineErrorView(message: error) {
                    Task { await model.loadTemperatureHistory() }
                }
            } else if points.isEmpty {
                Text("暂无历史温度曲线数据，待首次历史回算完成后展示。")
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
                            leadingLabel: "国际金价（USD/oz）",
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
                                        x: .value("日期", point.date),
                                        y: .value("金价", plotY)
                                    )
                                    .foregroundStyle(GoldTheme.gold)
                                    .lineStyle(StrokeStyle(lineWidth: 1.8))
                                    .interpolationMethod(.monotone)

                                    if goldPoints.count == 1 {
                                        PointMark(
                                            x: .value("日期", point.date),
                                            y: .value("金价", plotY)
                                        )
                                        .foregroundStyle(GoldTheme.gold)
                                        .symbolSize(36)
                                    }
                                }
                            }
                            if let inspected, let price = inspected.goldPriceUSD {
                                RuleMark(x: .value("选中", inspected.date))
                                    .foregroundStyle(GoldTheme.goldSoft.opacity(0.6))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                PointMark(
                                    x: .value("选中", inspected.date),
                                    y: .value("金价", goldContext.clampedPlotValue(price))
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
                    Text("黄金温度（0~100° · 虚线 20° 冰点 / 80° 过热）")
                        .font(.caption2)
                        .foregroundStyle(GoldTheme.textSecondary)
                    Chart {
                        RuleMark(y: .value("过热", 80))
                            .foregroundStyle(GoldTheme.tempHot.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        RuleMark(y: .value("冰点", 20))
                            .foregroundStyle(GoldTheme.tempFreezing.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        ForEach(points) { point in
                            AreaMark(
                                x: .value("日期", point.date),
                                yStart: .value("底", 0),
                                yEnd: .value("温度", point.score)
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
                                x: .value("日期", point.date),
                                y: .value("温度", point.score)
                            )
                            .foregroundStyle(GoldTheme.chartSecondary)
                            .lineStyle(StrokeStyle(lineWidth: 1.8))
                            .interpolationMethod(.monotone)

                            if points.count == 1 {
                                PointMark(x: .value("日期", point.date), y: .value("温度", point.score))
                                    .foregroundStyle(GoldTheme.chartSecondary)
                                    .symbolSize(40)
                            }
                        }

                        if let inspected {
                            RuleMark(x: .value("选中", inspected.date))
                                .foregroundStyle(GoldTheme.goldSoft.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            PointMark(x: .value("选中", inspected.date), y: .value("温度", inspected.score))
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
                Text("五维温度拆解")
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.text)
                Spacer()
                Text("基于 3 年滚动历史分位")
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textFaint)
            }

            if dimensions.isEmpty {
                Text("暂无维度拆分数据")
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
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(dim.name.isEmpty ? MacroPresentation.factorDisplayName(dim.key) : dim.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(GoldTheme.text)
                Text("权重 \(Int((dim.weight * 100).rounded()))%")
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
                    Text("暂缺")
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

            if !dim.summary.isEmpty {
                Text(dim.summary)
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
            loadingCard("正在加载美国国债与利率专题…")
        } else if let error = model.treasuryError, model.treasury == nil {
            errorCard(title: "美国国债数据加载失败", message: error) {
                Task { await model.loadTreasury() }
            }
        } else if let report = model.treasury {
            if report.hasAnyData {
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
                        Text("美债与长债 ETF 核心指标")
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
                    title: "美国国债数据正在同步中",
                    detail: "待 Treasury Fiscal Data 与 FRED 首次同步完成后，将自动展示美债总规模、实际利率与财政压力。"
                ) {
                    Task { await model.loadTreasury() }
                }
            }
        } else {
            loadingCard("正在准备美国国债专题…")
        }
    }

    private func treasurySummaryCard(_ report: MacroTreasuryReport) -> some View {
        let s = report.summary
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("美国联邦国债总规模")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(GoldTheme.textSecondary)
                    Text(MacroPresentation.formatTrillionUSD(s.totalDebtTrillionUSD))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.gold)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("近1年净增")
                        .font(.caption2)
                        .foregroundStyle(GoldTheme.textSecondary)
                    Text(MacroPresentation.formatTrillionUSD(s.debtChangeYoYTrillion, signed: true))
                        .font(.subheadline.bold())
                        .monospacedDigit()
                        .foregroundStyle(MacroPresentation.changeColor(for: s.debtChangeYoYTrillion))
                    Text("截至 \(MacroDateParser.displayDay(report.asOf))")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.textFaint)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                treasuryMetricCell("10Y 实际利率", MacroPresentation.formatPercent(s.yield10yRealPct), tint: GoldTheme.goldSoft)
                treasuryMetricCell("10Y 名义利率", MacroPresentation.formatPercent(s.yield10yNominalPct))
                treasuryMetricCell("2Y 名义利率", MacroPresentation.formatPercent(s.yield2yNominalPct))
                treasuryMetricCell("10Y-2Y 利差", MacroPresentation.formatPercent(s.spread10y2yPct, signed: true), tint: MacroPresentation.changeColor(for: s.spread10y2yPct))
                treasuryMetricCell("10Y 通胀预期", MacroPresentation.formatPercent(s.breakeven10yPct))
                treasuryMetricCell("TLT 长债 ETF", s.tltPrice.map { "$" + $0.formatted(.number.precision(.fractionLength(2))) } ?? "—")
                treasuryMetricCell("美债 / GDP", MacroPresentation.formatPercent(s.debtToGDPPct))
                treasuryMetricCell("付息 / 财政收入", MacroPresentation.formatPercent(s.interestToRevenuePct))
                treasuryMetricCell("财政压力指数", s.fiscalStressScore.map { String(format: "%.1f", $0) } ?? "—", tint: s.fiscalStressScore.map { MacroPresentation.temperatureColor(forScore: $0) } ?? GoldTheme.text)
            }

            if !s.goldImpactNote.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(GoldTheme.gold)
                    Text(s.goldImpactNote)
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
                Text("美债总规模走势（万亿美元）")
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
                Text("暂无美债总规模历史序列")
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
                            x: .value("日期", point.date),
                            yStart: .value("基线", domain.lowerBound),
                            yEnd: .value("规模", plotY)
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
                            x: .value("日期", point.date),
                            y: .value("规模", plotY)
                        )
                        .foregroundStyle(GoldTheme.gold)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)

                        if series.count == 1 {
                            PointMark(x: .value("日期", point.date), y: .value("规模", plotY))
                                .foregroundStyle(GoldTheme.gold)
                                .symbolSize(44)
                        }
                    }
                    if let inspected {
                        RuleMark(x: .value("选中", inspected.date))
                            .foregroundStyle(GoldTheme.goldSoft.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        PointMark(
                            x: .value("选中", inspected.date),
                            y: .value("规模", debtContext.clampedPlotValue(inspected.value))
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
                Text("10Y 实际利率 vs 名义利率（%）")
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.text)
                Spacer()
                if inspectedReal != nil || inspectedNominal != nil {
                    HStack(spacing: 6) {
                        if let r = inspectedReal {
                            Text("实 \(MacroPresentation.formatPercent(r.value))")
                                .foregroundStyle(GoldTheme.gold)
                        }
                        if let n = inspectedNominal {
                            Text("名 \(MacroPresentation.formatPercent(n.value))")
                                .foregroundStyle(GoldTheme.chartSecondary)
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                } else {
                    HStack(spacing: 10) {
                        legendDot(color: GoldTheme.gold, label: "实际")
                        legendDot(color: GoldTheme.chartSecondary, label: "名义")
                    }
                }
            }

            if real.isEmpty && nominal.isEmpty {
                Text("暂无 10Y 美债收益率历史数据（需配置 FRED 数据源）")
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
                        RuleMark(y: .value("零轴", 0))
                            .foregroundStyle(GoldTheme.textFaint.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }

                    ForEach(nominal) { point in
                        let plotY = yieldContext.clampedPlotValue(point.value)
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("收益率", plotY),
                            series: .value("类型", "名义")
                        )
                        .foregroundStyle(GoldTheme.chartSecondary)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                        .interpolationMethod(.monotone)

                        if nominal.count == 1 {
                            PointMark(x: .value("日期", point.date), y: .value("收益率", plotY))
                                .foregroundStyle(GoldTheme.chartSecondary)
                                .symbolSize(36)
                        }
                    }

                    ForEach(real) { point in
                        let plotY = yieldContext.clampedPlotValue(point.value)
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("收益率", plotY),
                            series: .value("类型", "实际")
                        )
                        .foregroundStyle(GoldTheme.gold)
                        .lineStyle(StrokeStyle(lineWidth: 2.0))
                        .interpolationMethod(.monotone)

                        if real.count == 1 {
                            PointMark(x: .value("日期", point.date), y: .value("收益率", plotY))
                                .foregroundStyle(GoldTheme.gold)
                                .symbolSize(36)
                        }
                    }

                    if let target = inspectedReal?.date ?? inspectedNominal?.date {
                        RuleMark(x: .value("选中", target))
                            .foregroundStyle(GoldTheme.goldSoft.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    if let r = inspectedReal {
                        PointMark(
                            x: .value("选中", r.date),
                            y: .value("收益率", yieldContext.clampedPlotValue(r.value))
                        )
                        .foregroundStyle(GoldTheme.gold)
                        .symbolSize(36)
                    }
                    if let n = inspectedNominal {
                        PointMark(
                            x: .value("选中", n.date),
                            y: .value("收益率", yieldContext.clampedPlotValue(n.value))
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

    // MARK: - Tab 3: 宏观全景（COT + 6 大板块）

    @ViewBuilder
    private var panoramaTabContent: some View {
        cotSectionCard

        if model.isLoadingCatalog && model.catalog == nil {
            loadingCard("正在加载 6 大板块宏观指标…")
        } else if let error = model.catalogError, model.catalog == nil {
            errorCard(title: "宏观指标目录加载失败", message: error) {
                Task { await model.loadCatalog() }
            }
        } else if let catalog = model.catalog, !catalog.sections.isEmpty {
            sectionFilterBar(sections: catalog.sections)

            ForEach(model.filteredSections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(section.nameZh)
                                .font(.headline)
                                .foregroundStyle(GoldTheme.gold)
                            Spacer()
                            Text("\(section.indicators.count) 项")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(GoldTheme.textFaint)
                        }
                        if !section.description.isEmpty {
                            Text(section.description)
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
        } else {
            emptyCard(
                icon: "square.grid.2x2",
                title: "宏观指标目录暂为空",
                detail: "待后端完成元数据初始化后即可查看全部 6 大宏观板块与历史走势。"
            ) {
                Task { await model.loadCatalog() }
            }
        }
    }

    private func sectionFilterBar(sections: [MacroIndicatorSection]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                sectionFilterChip(id: nil, title: "全部板块")
                ForEach(sections) { section in
                    sectionFilterChip(id: section.id, title: section.nameZh)
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
                Label("CFTC 黄金持仓（COT）", systemImage: "chart.bar.doc.horizontal")
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
                    Text("正在加载 CFTC 持仓周报…")
                        .font(.footnote)
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else if let error = model.cotError, points.isEmpty {
                inlineErrorView(message: error) {
                    Task { await model.loadCot() }
                }
            } else if points.isEmpty {
                Text("暂无 CFTC 黄金期货持仓数据。")
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                if let activePoint {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        treasuryMetricCell(
                            "管理基金净多",
                            MacroPresentation.formatContracts(activePoint.mmNet, signed: true),
                            tint: MacroPresentation.changeColor(for: activePoint.mmNet)
                        )
                        treasuryMetricCell(
                            "Swap 净头寸",
                            MacroPresentation.formatContracts(activePoint.swapNet, signed: true),
                            tint: GoldTheme.chartSecondary
                        )
                        treasuryMetricCell(
                            "总持仓量",
                            MacroPresentation.formatContracts(activePoint.openInterest),
                            tint: GoldTheme.goldSoft
                        )
                    }

                    HStack(spacing: 12) {
                        Text("管理基金净多占比：\(MacroPresentation.formatPercent(activePoint.mmNetRatioPct))")
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.textSecondary)
                        Spacer()
                        HStack(spacing: 10) {
                            legendDot(color: GoldTheme.up, label: "基金净多")
                            legendDot(color: GoldTheme.chartSecondary, label: "Swap 净头寸")
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
                        RuleMark(y: .value("零轴", 0))
                            .foregroundStyle(GoldTheme.textFaint.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }

                    ForEach(points) { point in
                        let mmPlotY = cotContext.clampedPlotValue(point.mmNet)
                        let swapPlotY = cotContext.clampedPlotValue(point.swapNet)
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("头寸", mmPlotY),
                            series: .value("阵营", "管理基金净多")
                        )
                        .foregroundStyle(GoldTheme.up)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("头寸", swapPlotY),
                            series: .value("阵营", "Swap 净头寸")
                        )
                        .foregroundStyle(GoldTheme.chartSecondary)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                        .interpolationMethod(.monotone)

                        if points.count == 1 {
                            PointMark(x: .value("日期", point.date), y: .value("头寸", mmPlotY))
                                .foregroundStyle(GoldTheme.up)
                                .symbolSize(36)
                            PointMark(x: .value("日期", point.date), y: .value("头寸", swapPlotY))
                                .foregroundStyle(GoldTheme.chartSecondary)
                                .symbolSize(36)
                        }
                    }

                    if let inspected {
                        RuleMark(x: .value("选中", inspected.date))
                            .foregroundStyle(GoldTheme.goldSoft.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        PointMark(
                            x: .value("选中", inspected.date),
                            y: .value("头寸", cotContext.clampedPlotValue(inspected.mmNet))
                        )
                        .foregroundStyle(GoldTheme.up)
                        .symbolSize(36)
                        PointMark(
                            x: .value("选中", inspected.date),
                            y: .value("头寸", cotContext.clampedPlotValue(inspected.swapNet))
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
            Button("重新加载", action: onRetry)
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
            Button("刷新看看", action: onRefresh)
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
            Button("重试", action: onRetry)
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
        if let d5 = summary.change5d { return ("5日", d5) }
        if let d20 = summary.change20d { return ("20日", d20) }
        if let d3m = summary.change3m { return ("3月", d3m) }
        return ("同比", summary.changeYoY)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(summary.nameZh)
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
                        Text("3年分位 \(MacroPresentation.formatPercentile(pct))")
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

                if !summary.plainNote.isEmpty {
                    Text(summary.plainNote)
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
