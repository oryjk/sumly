import SwiftUI
import Charts

struct MacroIndicatorDetailView: View {
    @State private var model: MacroIndicatorDetailViewModel
    @State private var selectedChartDate: Date?

    init(
        seriesID: String,
        initialSummary: MacroIndicatorSummary? = nil,
        service: any MacroServicing = BackendMacroService()
    ) {
        _model = State(initialValue: MacroIndicatorDetailViewModel(
            seriesID: seriesID,
            initialSummary: initialSummary,
            service: service
        ))
    }

    private var inspectedPoint: MacroTimePoint? {
        guard let selectedChartDate else { return nil }
        return model.observations.min {
            abs($0.date.timeIntervalSince(selectedChartDate)) < abs($1.date.timeIntervalSince(selectedChartDate))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerSummaryCard
                chartCard
                changeStatsCard
                percentilesCard
                interpretationCard
                syncMetaCard
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 112)
        }
        .scrollIndicators(.hidden)
        .background(GoldTheme.background)
        .foregroundStyle(GoldTheme.text)
        .navigationTitle(model.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable {
            await model.load()
        }
        .task {
            await model.load()
        }
        .sensoryFeedback(.selection, trigger: model.range)
    }

    // MARK: - 头部摘要

    private var headerSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayTitle)
                        .font(.title3.bold())
                        .foregroundStyle(GoldTheme.text)
                    Text(model.seriesID)
                        .font(.caption.monospaced())
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                Spacer(minLength: 8)
                Text(MacroPresentation.goldRelationLabel(model.displayGoldRelation))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(GoldTheme.goldSoft)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(GoldTheme.gold.opacity(0.14), in: GoldTheme.capsuleShape)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(MacroPresentation.formatValue(model.latestValue, unit: model.displayUnit))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("近3年分位 \(MacroPresentation.formatPercentile(model.percentile3y))")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.text)
                    Text("最新日期 \(MacroDateParser.displayDay(model.latestDate))")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.textSecondary)
                }
            }

            if !model.displayPlainNote.isEmpty {
                Text(model.displayPlainNote)
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .goldCard(padding: 16)
    }

    // MARK: - 历史走势图

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("历史走势")
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.text)
                Spacer()
                if let point = inspectedPoint {
                    Text("\(point.dateString) · \(MacroPresentation.formatValue(point.value, unit: model.displayUnit))")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.goldSoft)
                } else if !model.observations.isEmpty {
                    Text("\(model.observations.count) 个观测点")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.textSecondary)
                }
            }

            rangeSelector

            if model.isLoading && model.observations.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().tint(GoldTheme.gold)
                    Text("正在加载历史曲线…")
                        .font(.footnote)
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if let error = model.errorMessage, model.observations.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(GoldTheme.tempWarm)
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(GoldTheme.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("重新加载") {
                        Task { await model.load() }
                    }
                    .buttonStyle(GoldCapsuleStyle(isSelected: false))
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if model.observations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.flattrend.xyaxis")
                        .font(.title2)
                        .foregroundStyle(GoldTheme.textFaint)
                    Text("当前区间暂无历史观测数据")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(GoldTheme.textSecondary)
                    if let status = model.detail?.syncStatus {
                        Text("同步状态：\(MacroPresentation.syncStatusLabel(status))")
                            .font(.caption2)
                            .foregroundStyle(GoldTheme.textFaint)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                indicatorChart(points: model.observations)

                if let low = model.periodMin, let high = model.periodMax {
                    HStack(spacing: 12) {
                        Label("区间最高 \(MacroPresentation.formatValue(high.value, unit: model.displayUnit))", systemImage: "arrow.up.right")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.up)
                        Spacer()
                        Label("区间最低 \(MacroPresentation.formatValue(low.value, unit: model.displayUnit))", systemImage: "arrow.down.right")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.down)
                    }
                }
            }

            if let error = model.errorMessage, !model.observations.isEmpty {
                HStack {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(GoldTheme.tempWarm)
                    Spacer()
                    Button("重试") { Task { await model.load() } }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GoldTheme.gold)
                }
            }
        }
        .goldCard(padding: 16)
    }

    private var rangeSelector: some View {
        HStack(spacing: 6) {
            ForEach(MacroExtendedRange.allCases) { item in
                let isSelected = model.range == item
                Button {
                    selectedChartDate = nil
                    Task { await model.selectRange(item) }
                } label: {
                    Text(item.title)
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? GoldTheme.onGold : GoldTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(isSelected ? GoldTheme.gold : GoldTheme.background, in: GoldTheme.capsuleShape)
                        .overlay(GoldTheme.capsuleShape.strokeBorder(isSelected ? Color.clear : GoldTheme.cardStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func indicatorChart(points: [MacroTimePoint]) -> some View {
        let values = points.map(\.value)
        let minVal = values.min() ?? 0
        let maxVal = values.max() ?? 1
        let pad = max((maxVal - minVal) * 0.08, abs(maxVal) * 0.01, 0.01)
        let domain = (minVal - pad)...(maxVal + pad)

        return Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("日期", point.date),
                    yStart: .value("基线", domain.lowerBound),
                    yEnd: .value("数值", point.value)
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
                    y: .value("数值", point.value)
                )
                .foregroundStyle(GoldTheme.gold)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)

                if points.count == 1 {
                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("数值", point.value)
                    )
                    .foregroundStyle(GoldTheme.gold)
                    .symbolSize(48)
                }
            }

            if let selected = inspectedPoint {
                RuleMark(x: .value("选中日期", selected.date))
                    .foregroundStyle(GoldTheme.goldSoft.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                PointMark(
                    x: .value("选中日期", selected.date),
                    y: .value("选中数值", selected.value)
                )
                .foregroundStyle(GoldTheme.gold)
                .symbolSize(48)
            }
        }
        .chartYScale(domain: domain)
        .chartXSelection(value: $selectedChartDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(GoldTheme.gridline)
                AxisValueLabel()
                    .foregroundStyle(GoldTheme.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(GoldTheme.gridline)
                AxisValueLabel()
                    .foregroundStyle(GoldTheme.textSecondary)
            }
        }
        .frame(height: 220)
    }

    // MARK: - 区间变化统计

    private var changeStatsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("近期变化")
                .font(.subheadline.bold())
                .foregroundStyle(GoldTheme.text)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                deltaTile("近5日", model.change5d)
                deltaTile("近20日", model.change20d)
                deltaTile("近3月", model.change3m)
                deltaTile("同比", model.changeYoY)
            }
        }
        .goldCard(padding: 16)
    }

    private func deltaTile(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(GoldTheme.textSecondary)
            Text(MacroPresentation.formatDelta(value, unit: model.displayUnit))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(MacroPresentation.changeColor(for: value))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(GoldTheme.background, in: GoldTheme.subCardShape)
        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    // MARK: - 多窗口历史分位数

    @ViewBuilder
    private var percentilesCard: some View {
        let windows = model.detail?.percentiles ?? []
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("多窗口历史分位")
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.text)
                Spacer()
                Text("0% 历史最低 · 100% 历史最高")
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textFaint)
            }

            if windows.isEmpty {
                Text("暂无足够历史样本计算分位数")
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.textSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(windows) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(item.windowTitle)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(GoldTheme.text)
                                Text("(\(item.observationCount) 点)")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(GoldTheme.textFaint)
                                Spacer()
                                Text(MacroPresentation.percentileBadgeText(item.percentile))
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(percentileTint(item.percentile))
                            }

                            GeometryReader { proxy in
                                let pct = min(max((item.percentile ?? 0) / 100.0, 0), 1)
                                ZStack(alignment: .leading) {
                                    GoldTheme.capsuleShape
                                        .fill(GoldTheme.calendarCell)
                                    if item.percentile != nil {
                                        GoldTheme.capsuleShape
                                            .fill(percentileTint(item.percentile))
                                            .frame(width: max(6, proxy.size.width * pct))
                                    }
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
        }
        .goldCard(padding: 16)
    }

    private func percentileTint(_ percentile: Double?) -> Color {
        guard let percentile, percentile.isFinite else { return GoldTheme.textSecondary }
        return MacroPresentation.temperatureColor(forScore: percentile)
    }

    // MARK: - 指标说明与元数据

    private var interpretationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("指标档案")
                .font(.subheadline.bold())
                .foregroundStyle(GoldTheme.text)

            metaRow("数据来源", model.displaySource.isEmpty ? "—" : model.displaySource)
            metaRow("更新频率", MacroPresentation.frequencyLabel(model.displayFrequency))
            metaRow("计量单位", model.displayUnit.isEmpty ? "—" : model.displayUnit)
            metaRow("黄金逻辑", MacroPresentation.goldRelationLabel(model.displayGoldRelation))
        }
        .goldCard(padding: 16)
    }

    private var syncMetaCard: some View {
        let status = model.detail?.syncStatus ?? "pending"
        return HStack(spacing: 10) {
            Circle()
                .fill(MacroPresentation.syncStatusColor(for: status))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("同步状态：\(MacroPresentation.syncStatusLabel(status))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.text)
                Text("最近同步：\(MacroDateParser.displaySyncedAt(model.detail?.lastSyncedAt))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.textSecondary)
            }
            Spacer()
        }
        .goldCard(padding: 14)
    }

    private func metaRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(GoldTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(GoldTheme.text)
        }
    }
}
