import SwiftUI

/// 走势图买入红点交互文案、脱敏格式化与查价浮窗数据构建（纯 Sendable，便于单元测试）。
enum ChartPurchaseMarkerPresentation: Sendable {
    enum SpreadSentiment: Equatable, Sendable {
        /// 买入成本高于大盘参考价（买贵了 / 多花）→ 与全 App 亏损/不利语义一致（绿色）
        case unfavorable
        /// 买入成本低于大盘参考价（买便宜了 / 省了）→ 与全 App 盈利/划算语义一致（红色）
        case favorable
        /// 与大盘参考价持平 → 中性
        case neutral

        var color: Color {
            switch self {
            case .unfavorable: return GoldTheme.down
            case .favorable: return GoldTheme.up
            case .neutral: return GoldTheme.textSecondary
            }
        }

        var symbolName: String {
            switch self {
            case .unfavorable: return "arrow.down.right"
            case .favorable: return "arrow.up.right"
            case .neutral: return "equal"
            }
        }
    }

    struct SpreadMetric: Equatable, Sendable {
        let diff: Double
        let percent: Double?
        let capsuleText: String
        let compactText: String
        let isPremium: Bool
        let isDiscount: Bool
        let sentiment: SpreadSentiment
    }

    struct InspectionTooltipContent: Equatable, Sendable {
        let isMultiple: Bool
        let dateBadge: String?
        let headline: String
        let primaryMetric: String
        let secondaryMetric: String?
        let spread: SpreadMetric?
        let footerHint: String?
    }

    static func badgeText(for count: Int) -> String? {
        guard count >= 2 else { return nil }
        return count > 9 ? "9+" : "\(count)"
    }

    static func gramsText(_ grams: Double, hideAmounts: Bool, compact: Bool = false) -> String {
        if hideAmounts {
            return compact ? "••••g" : "•••• g"
        }
        let formatted = grams.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
        return compact ? "\(formatted)g" : "\(formatted) g"
    }

    static func totalCostText(_ totalCost: Double, hideAmounts: Bool) -> String {
        if hideAmounts { return "••••" }
        return "¥\(totalCost.moneyText)"
    }

    static func laborFeeTagText(_ laborFee: Double, hideAmounts: Bool) -> String? {
        guard laborFee.isFinite, laborFee > 0 else { return nil }
        return hideAmounts ? "含工费 ••••" : "含工费 ¥\(laborFee.moneyText)"
    }

    static func spreadMetric(
        unitCost: Double,
        marketAnchor: Double?,
        isInterpolatedMarketAnchor: Bool = false
    ) -> SpreadMetric? {
        guard let anchor = marketAnchor, anchor.isFinite, anchor > 0, unitCost.isFinite, unitCost > 0 else {
            return nil
        }
        let anchorLabel = isInterpolatedMarketAnchor ? "临近交易日" : "当日大盘"
        let diff = unitCost - anchor
        let pct = (diff / anchor) * 100
        if abs(diff) < 0.005 {
            return SpreadMetric(
                diff: 0,
                percent: 0,
                capsuleText: "与\(anchorLabel)持平 (¥0.00/g)",
                compactText: "与大盘持平",
                isPremium: false,
                isDiscount: false,
                sentiment: .neutral
            )
        }
        if diff > 0 {
            let absDiff = diff.moneyText
            let absPct = pct.moneyText
            return SpreadMetric(
                diff: diff,
                percent: pct,
                capsuleText: "较\(anchorLabel)多花 ¥\(absDiff)/g（贵 \(absPct)%）",
                compactText: "多花 ¥\(absDiff)",
                isPremium: true,
                isDiscount: false,
                sentiment: .unfavorable
            )
        } else {
            let absDiff = (-diff).moneyText
            let absPct = (-pct).moneyText
            return SpreadMetric(
                diff: diff,
                percent: pct,
                capsuleText: "较\(anchorLabel)省 ¥\(absDiff)/g（省 \(absPct)%）",
                compactText: "省 ¥\(absDiff)",
                isPremium: false,
                isDiscount: true,
                sentiment: .favorable
            )
        }
    }

    static func explanationText(isInterpolatedMarketAnchor: Bool) -> String {
        if isInterpolatedMarketAnchor {
            return "买入日为非交易日，大盘参考价按前后临近交易日收盘价插值估算；红点为计入工费与溢价后的实际买入综合单价，虚线长度即与参考价差额。"
        }
        return "红点位置为计入工费与溢价后的实际买入综合单价，图中垂直虚线长度即与当日大盘参考价的差额。"
    }

    static func shortDateText(_ date: Date, calendar: Calendar = .current) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return String(format: "%02d/%02d", month, day)
    }

    static func fullDateText(_ date: Date, calendar: Calendar = .current) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return String(format: "%04d年%02d月%02d日", year, month, day)
    }

    static func inspectionTooltip(
        match: ChartHoldingMarkerResolver.MatchedInspectionMarker,
        selectedPoint: MarketChartPoint,
        hideAmounts: Bool,
        calendar: Calendar = .current
    ) -> InspectionTooltipContent {
        let marker = match.resolved.marker
        let referencePrice = match.resolved.marketAnchorPrice ?? selectedPoint.price
        let isInterpolated = match.resolved.isInterpolatedMarketAnchor || !match.isSameDay
        let spread = spreadMetric(
            unitCost: marker.averageUnitPrice,
            marketAnchor: referencePrice,
            isInterpolatedMarketAnchor: isInterpolated
        )
        let dateBadge: String? = match.isSameDay
            ? nil
            : "\(shortDateText(marker.date, calendar: calendar)) 买入 · 休市参考"

        if marker.count >= 2 {
            let headline = "买入 \(marker.count) 笔 · 共 \(gramsText(marker.totalGrams, hideAmounts: hideAmounts, compact: true))"
            let primaryMetric = "均价 ¥\(marker.averageUnitPrice.moneyText)/g"
            let secondaryMetric: String? = abs(marker.maxUnitCost - marker.minUnitCost) >= 0.01
                ? "单笔 ¥\(marker.minUnitCost.moneyText)~¥\(marker.maxUnitCost.moneyText)"
                : nil
            return InspectionTooltipContent(
                isMultiple: true,
                dateBadge: dateBadge,
                headline: headline,
                primaryMetric: primaryMetric,
                secondaryMetric: secondaryMetric,
                spread: spread,
                footerHint: "轻点红点查看明细"
            )
        } else {
            let item = marker.items.first
            let typeText = item?.assetType.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let brandText = item?.brand.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let titlePart: String = {
                if !typeText.isEmpty && !brandText.isEmpty && brandText != typeText {
                    return "\(typeText) · \(brandText)"
                }
                if !brandText.isEmpty { return brandText }
                if !typeText.isEmpty { return typeText }
                return "买入记录"
            }()
            let grams = item?.grams ?? marker.totalGrams
            let headline = "\(titlePart) · \(gramsText(grams, hideAmounts: hideAmounts, compact: true))"
            let unitCost = item?.effectiveUnitCost ?? marker.averageUnitPrice
            let primaryMetric = "买入 ¥\(unitCost.moneyText)/g"
            return InspectionTooltipContent(
                isMultiple: false,
                dateBadge: dateBadge,
                headline: headline,
                primaryMetric: primaryMetric,
                secondaryMetric: nil,
                spread: spread,
                footerHint: nil
            )
        }
    }
}

/// 轻点走势图买入红点后弹出的暗黑金半屏明细抽屉：
/// 顶部展示「买入点位 vs 当日行情」对比卡，下方列出当日单笔或多笔购入明细并支持直达持仓详情。
struct ChartPurchaseMarkerSheet: View {
    let resolvedMarker: ChartHoldingMarkerResolver.ResolvedMarker
    let marketBasis: GoldMarketBasis
    let hideAmounts: Bool
    let currentQuote: GoldQuote?
    let recordLookup: (UUID) -> HoldingRecord?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDetent: PresentationDetent = .medium
    @State private var selectedRecord: HoldingRecord?
    @State private var detailHoldingsModel: HoldingsViewModel

    init(
        resolvedMarker: ChartHoldingMarkerResolver.ResolvedMarker,
        marketBasis: GoldMarketBasis,
        hideAmounts: Bool,
        currentQuote: GoldQuote? = nil,
        recordLookup: @escaping (UUID) -> HoldingRecord? = { _ in nil }
    ) {
        self.resolvedMarker = resolvedMarker
        self.marketBasis = marketBasis
        self.hideAmounts = hideAmounts
        self.currentQuote = currentQuote
        self.recordLookup = recordLookup
        let vm = HoldingsViewModel(quoteService: nil)
        vm.applyExternalQuote(currentQuote, failed: false)
        _detailHoldingsModel = State(initialValue: vm)
    }

    private var marker: MarketHoldingOverlay.PurchaseMarker { resolvedMarker.marker }

    private var spread: ChartPurchaseMarkerPresentation.SpreadMetric? {
        ChartPurchaseMarkerPresentation.spreadMetric(
            unitCost: marker.averageUnitPrice,
            marketAnchor: resolvedMarker.marketAnchorPrice,
            isInterpolatedMarketAnchor: resolvedMarker.isInterpolatedMarketAnchor
        )
    }

    private var displayItems: [MarketHoldingOverlay.PurchaseItem] {
        if !marker.items.isEmpty { return marker.items }
        return [
            MarketHoldingOverlay.PurchaseItem(
                id: UUID(),
                assetType: "其他",
                brand: "",
                grams: marker.totalGrams,
                unitPrice: marker.averageUnitPrice,
                effectiveUnitCost: marker.averageUnitPrice,
                totalCost: marker.totalGrams * marker.averageUnitPrice,
                laborFee: 0,
                timestamp: marker.date,
                note: ""
            )
        ]
    }

    private var hasNavigableRecord: Bool {
        displayItems.contains { recordLookup($0.id) != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    comparisonCard
                    itemsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .background(GoldTheme.background)
            .navigationTitle("买入点位明细")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(GoldTheme.gold)
                }
            }
            .navigationDestination(item: $selectedRecord) { record in
                HoldingDetailView(
                    record: record,
                    model: detailHoldingsModel,
                    marketBasis: marketBasis,
                    embeddedInNavigationStack: true
                )
            }
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .presentationBackground(GoldTheme.background)
        .preferredColorScheme(.dark)
        .tint(GoldTheme.gold)
        .onChange(of: currentQuote) { _, latest in
            detailHoldingsModel.applyExternalQuote(latest, failed: false)
        }
        .onChange(of: selectedRecord) { _, record in
            if record != nil {
                selectedDetent = .large
            }
        }
    }

    // MARK: - 顶部「买入点位 vs 当日行情」对比卡

    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(GoldTheme.up)
                        .frame(width: 8, height: 8)
                    Text(ChartPurchaseMarkerPresentation.fullDateText(marker.date))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.text)
                }

                if resolvedMarker.isInterpolatedMarketAnchor {
                    Text("休市 · 参考临近交易日")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GoldTheme.goldSoft)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(GoldTheme.gold.opacity(0.14), in: GoldTheme.capsuleShape)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text("\(marker.count) 笔 · \(ChartPurchaseMarkerPresentation.gramsText(marker.totalGrams, hideAmounts: hideAmounts))")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineLimit(1)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(marker.count >= 2 ? "当日买入加权成本" : "你的买入综合成本")
                        .font(.caption)
                        .foregroundStyle(GoldTheme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("¥\(marker.averageUnitPrice.moneyText)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text("/g")
                            .font(.caption)
                            .foregroundStyle(GoldTheme.textSecondary)
                    }
                    if marker.count >= 2 && abs(marker.maxUnitCost - marker.minUnitCost) >= 0.01 {
                        Text("单笔 ¥\(marker.minUnitCost.moneyText) ~ ¥\(marker.maxUnitCost.moneyText)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(GoldTheme.cardStroke)
                    .frame(width: 1, height: 48)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(resolvedMarker.isInterpolatedMarketAnchor ? "临近交易日参考" : "当日大盘参考价")
                        .font(.caption)
                        .foregroundStyle(GoldTheme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(resolvedMarker.marketAnchorPrice.map { "¥\($0.moneyText)" } ?? "—")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.gold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        if resolvedMarker.marketAnchorPrice != nil {
                            Text("/g")
                                .font(.caption)
                                .foregroundStyle(GoldTheme.textSecondary)
                        }
                    }
                    Text(marketBasis == .domestic ? "国内 Au99.99" : "国际伦敦金折算")
                        .font(.caption2)
                        .foregroundStyle(GoldTheme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let spread {
                let tint = spreadColor(spread)
                HStack(spacing: 6) {
                    Image(systemName: spread.sentiment.symbolName)
                        .font(.system(size: 10, weight: .bold))
                    Text(spread.capsuleText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tint.opacity(0.14), in: GoldTheme.capsuleShape)
            }

            GoldTheme.cardStroke.frame(height: 1)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.goldSoft)
                    .padding(.top, 2)
                Text(ChartPurchaseMarkerPresentation.explanationText(isInterpolatedMarketAnchor: resolvedMarker.isInterpolatedMarketAnchor))
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .goldCard(padding: 14)
    }

    // MARK: - 逐笔买入清单

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("当日买入清单")
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.text)
                Spacer()
                if hasNavigableRecord {
                    Text("轻点单笔查看持仓详情")
                        .font(.caption2)
                        .foregroundStyle(GoldTheme.goldSoft)
                }
            }
            .padding(.horizontal, 2)

            VStack(spacing: 8) {
                ForEach(displayItems) { item in
                    let matchedRecord = recordLookup(item.id)
                    if let matchedRecord {
                        Button {
                            selectedRecord = matchedRecord
                        } label: {
                            purchaseItemRow(item, navigable: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        purchaseItemRow(item, navigable: false)
                    }
                }
            }
        }
    }

    private func purchaseItemRow(_ item: MarketHoldingOverlay.PurchaseItem, navigable: Bool) -> some View {
        let itemSpread = ChartPurchaseMarkerPresentation.spreadMetric(
            unitCost: item.effectiveUnitCost,
            marketAnchor: resolvedMarker.marketAnchorPrice,
            isInterpolatedMarketAnchor: resolvedMarker.isInterpolatedMarketAnchor
        )
        let laborTag = ChartPurchaseMarkerPresentation.laborFeeTagText(item.laborFee, hideAmounts: hideAmounts)
        let trimmedNote = item.note.trimmingCharacters(in: .whitespacesAndNewlines)

        return HStack(spacing: 10) {
            ZStack {
                GoldTheme.subCardShape
                    .fill(GoldTheme.background)
                    .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
                GoldAssetGlyph(type: item.resolvedAssetType, size: 30, emphasized: true)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GoldTheme.text)
                        .lineLimit(1)
                    if item.assetType != item.displayName, !item.assetType.isEmpty {
                        Text(item.assetType)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(GoldTheme.goldSoft)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(GoldTheme.gold.opacity(0.12), in: GoldTheme.capsuleShape)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 6) {
                    Text(ChartPurchaseMarkerPresentation.gramsText(item.grams, hideAmounts: hideAmounts))
                    Text("·")
                    Text("总投入 \(ChartPurchaseMarkerPresentation.totalCostText(item.totalCost, hideAmounts: hideAmounts))")
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(GoldTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

                if laborTag != nil || !trimmedNote.isEmpty {
                    HStack(spacing: 6) {
                        if let laborTag {
                            Text(laborTag)
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(GoldTheme.goldSoft)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(GoldTheme.calendarCell, in: GoldTheme.rangeShape)
                                .lineLimit(1)
                        }
                        if !trimmedNote.isEmpty {
                            Text(trimmedNote)
                                .font(.caption2)
                                .foregroundStyle(GoldTheme.textFaint)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("¥\(item.effectiveUnitCost.moneyText)")
                            .font(.system(.subheadline, design: .rounded).bold())
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.text)
                        Text("/g")
                            .font(.caption2)
                            .foregroundStyle(GoldTheme.textSecondary)
                    }
                    .lineLimit(1)

                    if let itemSpread {
                        Text(itemSpread.compactText)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(spreadColor(itemSpread))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                if navigable {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(GoldTheme.textFaint)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        .contentShape(GoldTheme.holdingsCardShape)
    }

    private func spreadColor(_ metric: ChartPurchaseMarkerPresentation.SpreadMetric) -> Color {
        metric.sentiment.color
    }
}
