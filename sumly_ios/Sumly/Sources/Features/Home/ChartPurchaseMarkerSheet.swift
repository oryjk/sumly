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
        return hideAmounts ? L10n.tr("含工费 ••••") : L10n.fmt("含工费 ¥%@", laborFee.moneyText)
    }

    static func localizedAssetType(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let known = GoldAssetType(rawValue: trimmed) {
            switch known {
            case .bean: return L10n.tr("金豆")
            case .bar: return L10n.tr("金条")
            case .jewelry: return L10n.tr("金饰")
            case .accumulation: return L10n.tr("积存金")
            case .other: return L10n.tr("其他")
            }
        }
        return trimmed
    }

    static func spreadMetric(
        unitCost: Double,
        marketAnchor: Double?,
        isInterpolatedMarketAnchor: Bool = false,
        isPendingCloseAnchor: Bool = false
    ) -> SpreadMetric? {
        guard let anchor = marketAnchor, anchor.isFinite, anchor > 0, unitCost.isFinite, unitCost > 0 else {
            return nil
        }
        let anchorLabel: String = {
            if isPendingCloseAnchor { return L10n.tr("最近收盘") }
            return isInterpolatedMarketAnchor ? L10n.tr("临近交易日") : L10n.tr("当日大盘")
        }()
        let diff = unitCost - anchor
        let pct = (diff / anchor) * 100
        if abs(diff) < 0.005 {
            return SpreadMetric(
                diff: 0,
                percent: 0,
                capsuleText: L10n.fmt("与%@持平 (¥0.00/g)", anchorLabel),
                compactText: isPendingCloseAnchor ? L10n.tr("与最近收盘持平") : L10n.tr("与大盘持平"),
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
                capsuleText: L10n.fmt("较%@多花 ¥%@/g（贵 %@%%）", anchorLabel, absDiff, absPct),
                compactText: L10n.fmt("多花 ¥%@", absDiff),
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
                capsuleText: L10n.fmt("较%@省 ¥%@/g（省 %@%%）", anchorLabel, absDiff, absPct),
                compactText: L10n.fmt("省 ¥%@", absDiff),
                isPremium: false,
                isDiscount: true,
                sentiment: .favorable
            )
        }
    }

    static func statusBadgeText(
        isInterpolatedMarketAnchor: Bool,
        isPendingCloseAnchor: Bool = false
    ) -> String? {
        if isPendingCloseAnchor {
            return L10n.tr("休市/待收盘 · 参考最近收盘")
        }
        if isInterpolatedMarketAnchor {
            return L10n.tr("休市 · 参考临近交易日")
        }
        return nil
    }

    static func referencePriceTitle(
        isInterpolatedMarketAnchor: Bool,
        isPendingCloseAnchor: Bool = false
    ) -> String {
        if isPendingCloseAnchor {
            return L10n.tr("最近收盘参考价")
        }
        return isInterpolatedMarketAnchor ? L10n.tr("临近交易日参考") : L10n.tr("当日大盘参考价")
    }

    static func explanationText(
        isInterpolatedMarketAnchor: Bool,
        isPendingCloseAnchor: Bool = false
    ) -> String {
        if isPendingCloseAnchor {
            return L10n.tr("买入日尚未产生收盘日线（休市或盘中），红点暂挂靠于最近交易日末端并参考该日收盘价；次交易日收盘后自动归位。")
        }
        if isInterpolatedMarketAnchor {
            return L10n.tr("买入日为非交易日，大盘参考价按前后临近交易日收盘价插值估算；红点为计入工费与溢价后的实际买入综合单价，虚线长度即与参考价差额。")
        }
        return L10n.tr("红点位置为计入工费与溢价后的实际买入综合单价，图中垂直虚线长度即与当日大盘参考价的差额。")
    }

    static func shortDateText(_ date: Date, calendar: Calendar = .current) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return String(format: "%02d/%02d", month, day)
    }

    static func fullDateText(_ date: Date, calendar: Calendar = .current) -> String {
        if AppLanguage.resolvedLanguageCode == AppLanguage.zhHans.rawValue {
            let year = String(format: "%04d", calendar.component(.year, from: date))
            let month = String(format: "%02d", calendar.component(.month, from: date))
            let day = String(format: "%02d", calendar.component(.day, from: date))
            return L10n.fmt("%@年%@月%@日", year, month, day)
        }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: AppLanguage.currentLocale)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
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
            isInterpolatedMarketAnchor: isInterpolated,
            isPendingCloseAnchor: match.resolved.isPendingCloseAnchor
        )
        let dateBadge: String? = {
            if match.isSameDay { return nil }
            let shortDate = shortDateText(marker.date, calendar: calendar)
            if match.resolved.isPendingCloseAnchor {
                return L10n.fmt("%@ 买入 · 待收盘参考", shortDate)
            }
            return L10n.fmt("%@ 买入 · 休市参考", shortDate)
        }()

        if marker.count >= 2 {
            let headline = L10n.fmt("买入 %lld 笔 · 共 %@", Int64(marker.count), gramsText(marker.totalGrams, hideAmounts: hideAmounts, compact: true))
            let primaryMetric = L10n.fmt("均价 ¥%@/g", marker.averageUnitPrice.moneyText)
            let secondaryMetric: String? = abs(marker.maxUnitCost - marker.minUnitCost) >= 0.01
                ? L10n.fmt("单笔 ¥%@~¥%@", marker.minUnitCost.moneyText, marker.maxUnitCost.moneyText)
                : nil
            return InspectionTooltipContent(
                isMultiple: true,
                dateBadge: dateBadge,
                headline: headline,
                primaryMetric: primaryMetric,
                secondaryMetric: secondaryMetric,
                spread: spread,
                footerHint: L10n.tr("轻点红点查看明细")
            )
        } else {
            let item = marker.items.first
            let rawType = item?.assetType.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let typeText = localizedAssetType(rawType)
            let brandText = item?.brand.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let titlePart: String = {
                if !typeText.isEmpty && !brandText.isEmpty && brandText != rawType && brandText != typeText {
                    return "\(typeText) · \(brandText)"
                }
                if !brandText.isEmpty { return brandText }
                if !typeText.isEmpty { return typeText }
                return L10n.tr("买入记录")
            }()
            let grams = item?.grams ?? marker.totalGrams
            let headline = "\(titlePart) · \(gramsText(grams, hideAmounts: hideAmounts, compact: true))"
            let unitCost = item?.effectiveUnitCost ?? marker.averageUnitPrice
            let primaryMetric = L10n.fmt("买入 ¥%@/g", unitCost.moneyText)
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
            isInterpolatedMarketAnchor: resolvedMarker.isInterpolatedMarketAnchor,
            isPendingCloseAnchor: resolvedMarker.isPendingCloseAnchor
        )
    }

    private var displayItems: [MarketHoldingOverlay.PurchaseItem] {
        if !marker.items.isEmpty { return marker.items }
        return [
            MarketHoldingOverlay.PurchaseItem(
                id: UUID(),
                assetType: GoldAssetType.other.rawValue,
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
            .navigationTitle(L10n.tr("买入点位明细"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("完成")) { dismiss() }
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
        let statusBadge = ChartPurchaseMarkerPresentation.statusBadgeText(
            isInterpolatedMarketAnchor: resolvedMarker.isInterpolatedMarketAnchor,
            isPendingCloseAnchor: resolvedMarker.isPendingCloseAnchor
        )
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(GoldTheme.up)
                            .frame(width: 8, height: 8)
                        Text(ChartPurchaseMarkerPresentation.fullDateText(marker.date))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.text)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Text(L10n.fmt("%lld 笔 · %@", Int64(marker.count), ChartPurchaseMarkerPresentation.gramsText(marker.totalGrams, hideAmounts: hideAmounts)))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(GoldTheme.textSecondary)
                        .lineLimit(1)
                }

                if let statusBadge {
                    Text(statusBadge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GoldTheme.goldSoft)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(GoldTheme.gold.opacity(0.14), in: GoldTheme.capsuleShape)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(marker.count >= 2 ? L10n.tr("当日买入加权成本") : L10n.tr("你的买入综合成本"))
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
                        Text(L10n.fmt("单笔 ¥%@ ~ ¥%@", marker.minUnitCost.moneyText, marker.maxUnitCost.moneyText))
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
                    Text(ChartPurchaseMarkerPresentation.referencePriceTitle(
                        isInterpolatedMarketAnchor: resolvedMarker.isInterpolatedMarketAnchor,
                        isPendingCloseAnchor: resolvedMarker.isPendingCloseAnchor
                    ))
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
                    Text(marketBasis == .domestic ? L10n.tr("国内 Au99.99") : L10n.tr("国际伦敦金折算"))
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
                Text(ChartPurchaseMarkerPresentation.explanationText(
                    isInterpolatedMarketAnchor: resolvedMarker.isInterpolatedMarketAnchor,
                    isPendingCloseAnchor: resolvedMarker.isPendingCloseAnchor
                ))
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
                Text(L10n.tr("当日买入清单"))
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.text)
                Spacer()
                if hasNavigableRecord {
                    Text(L10n.tr("轻点单笔查看持仓详情"))
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
            isInterpolatedMarketAnchor: resolvedMarker.isInterpolatedMarketAnchor,
            isPendingCloseAnchor: resolvedMarker.isPendingCloseAnchor
        )
        let laborTag = ChartPurchaseMarkerPresentation.laborFeeTagText(item.laborFee, hideAmounts: hideAmounts)
        let trimmedNote = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let localizedType = ChartPurchaseMarkerPresentation.localizedAssetType(item.assetType)
        let trimmedBrand = item.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let localizedTitle: String = {
            if !trimmedBrand.isEmpty { return trimmedBrand }
            let trimmedType = item.assetType.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedType.isEmpty || GoldAssetType(rawValue: trimmedType) == .other {
                return L10n.tr("黄金记录")
            }
            return localizedType
        }()

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
                    Text(localizedTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GoldTheme.text)
                        .lineLimit(1)
                    if localizedType != localizedTitle, !localizedType.isEmpty {
                        Text(localizedType)
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
                    Text(L10n.fmt("总投入 %@", ChartPurchaseMarkerPresentation.totalCostText(item.totalCost, hideAmounts: hideAmounts)))
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
