import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// 主 App 与 `SumlyWidget` 的轻量桥接层：
/// - 将主 App 已有行情报价、历史日线、黄金温度计快照及脱敏持仓摘要转换为小组件快照；
/// - 写入共享缓存（启用 App Group 时跨进程共享，未启用时自动降级 `.standard` 不报错）；
/// - 触发 WidgetKit 刷新时间线。
enum WidgetSnapshotBridge {
    /// 将主 App 报价口径映射为小组件口径。
    static func widgetBasis(from basis: GoldMarketBasis) -> GoldWidgetBasis {
        switch basis {
        case .domestic: .domestic
        case .international: .international
        }
    }

    /// 将主 App 黄金温度计模型转换为小组件精简温度快照（100% 客户端客观文案）。
    static func widgetTemperature(from report: MacroTemperatureReport) -> GoldWidgetTemperatureSnapshot? {
        guard report.hasAvailableData else { return nil }
        let level: GoldWidgetTemperatureLevel = {
            switch report.level {
            case .freezing: .freezing
            case .cool: .cool
            case .neutral: .neutral
            case .warm: .warm
            case .hot: .hot
            }
        }()
        let regime: GoldWidgetMacroRegime = {
            switch report.macroRegime.regime {
            case .tailwind: .tailwind
            case .neutral: .neutral
            case .headwind: .headwind
            }
        }()
        return GoldWidgetTemperatureSnapshot(
            score: report.clampedScore,
            level: level,
            regime: regime,
            asOf: report.asOf
        )
    }

    /// 将主 App 实时报价与可选日线/温度组合成 `GoldWidgetSnapshot`。
    static func makeSnapshot(
        quote: GoldQuote,
        basis: GoldMarketBasis,
        dailyPrices: [GoldDailyPrice] = [],
        temperature: MacroTemperatureReport? = nil,
        fetchedAt: Date = Date()
    ) -> GoldWidgetSnapshot? {
        guard let marketSnapshot = MarketQuoteSnapshot.make(from: quote, basis: basis) else {
            return nil
        }
        let targetBasis = widgetBasis(from: basis)
        let conversionRatio: Double = {
            switch basis {
            case .domestic:
                return 1
            case .international:
                if quote.price.isFinite, quote.price > 0 {
                    return quote.cnyPerGram / quote.price
                }
                if quote.usdCNY.isFinite, quote.usdCNY > 0 {
                    return quote.usdCNY / GoldWidgetAPIClient.gramsPerTroyOunce
                }
                return 0
            }
        }()

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let recentSeries: [GoldWidgetPricePoint] = {
            guard conversionRatio > 0 else { return [] }
            return dailyPrices
                .filter { $0.close.isFinite && $0.close > 0 }
                .sorted { $0.date < $1.date }
                .suffix(30)
                .map { bar in
                    GoldWidgetPricePoint(
                        date: formatter.string(from: bar.date),
                        priceCNY: bar.close * conversionRatio
                    )
                }
        }()

        return GoldWidgetSnapshot(
            basis: targetBasis,
            cnyPerGram: marketSnapshot.cnyPerGram,
            changeCNY: marketSnapshot.changeCNY,
            changePercent: marketSnapshot.changePercent,
            usdPerOz: marketSnapshot.usdPerOz,
            asOf: marketSnapshot.asOf,
            fetchedAt: fetchedAt,
            recentSeries: recentSeries,
            temperature: temperature.flatMap { widgetTemperature(from: $0) },
            isCachedFallback: false
        )
    }

    /// 写入最新行情快照并通知 WidgetKit 刷新。
    @discardableResult
    static func publishQuote(
        _ quote: GoldQuote,
        basis: GoldMarketBasis,
        dailyPrices: [GoldDailyPrice] = [],
        temperature: MacroTemperatureReport? = nil,
        store: GoldWidgetCacheStore = .shared,
        reloadTimeline: Bool = true,
        now: Date = Date()
    ) -> GoldWidgetSnapshot? {
        let existing = store.loadSnapshot(for: widgetBasis(from: basis))
        guard let fresh = makeSnapshot(
            quote: quote,
            basis: basis,
            dailyPrices: dailyPrices,
            temperature: temperature,
            fetchedAt: now
        ) else {
            return nil
        }

        // 若本次仅更新实时报价而未传日线或温度，则保留已有缓存中的日线与温度信息。
        let merged = GoldWidgetSnapshot(
            basis: fresh.basis,
            cnyPerGram: fresh.cnyPerGram,
            changeCNY: fresh.changeCNY,
            changePercent: fresh.changePercent,
            usdPerOz: fresh.usdPerOz,
            asOf: fresh.asOf,
            fetchedAt: fresh.fetchedAt,
            recentSeries: fresh.recentSeries.isEmpty ? (existing?.recentSeries ?? []) : fresh.recentSeries,
            temperature: fresh.temperature ?? existing?.temperature,
            isCachedFallback: false
        )
        store.saveSnapshot(merged)
        if reloadTimeline {
            reloadWidgets()
        }
        return merged
    }

    /// 写入脱敏持有总克重摘要（不包含金额、成本或账户信息）。
    static func publishHoldingsSummary(
        totalGrams: Double,
        store: GoldWidgetCacheStore = .shared,
        now: Date = Date()
    ) {
        guard totalGrams.isFinite, totalGrams >= 0 else { return }
        store.saveHoldingsSummary(GoldWidgetHoldingsSummary(totalGrams: totalGrams, updatedAt: now))
    }

    /// 通知系统刷新全部记金小组件时间线。
    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "SumlyGoldWidget")
        #endif
    }
}
