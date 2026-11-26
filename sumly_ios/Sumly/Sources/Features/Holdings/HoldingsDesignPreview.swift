import Foundation
import SwiftData

/// 仅 Debug 的截图验证入口：始终使用独立内存容器，不向真实账本写入示例。
@MainActor enum HoldingsDesignPreview {
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--holdings-design-preview")
        #else
        false
        #endif
    }
    static func makeModel(basis: GoldMarketBasis = .domestic) -> HoldingsViewModel {
        #if DEBUG
        if isEnabled { return HoldingsViewModel(quoteService: QuoteFixture()) }
        #endif
        return HoldingsViewModel(basis: basis)
    }
    static func container() throws -> ModelContainer {
        let result = try ModelContainer(for: HoldingRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        #if DEBUG
        let first = HoldingRecord(grams: 2, unitPriceCNY: 6, timestamp: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 12))!)
        let second = HoldingRecord(grams: 6, unitPriceCNY: 800.0 / 6, timestamp: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 12))!)
        second.brand = "周生生"
        if ProcessInfo.processInfo.arguments.contains("--profit-breakdown-preview") {
            first.grams = 10; first.unitPriceCNY = 800; first.purity = 0.99
            first.laborFee = 100; first.extraFee = 20; first.brand = "测试金条"
            first.recoveryDeduction = 10; first.recoveryDiscount = 0.02; first.recoveryFixedFee = 20
            second.grams = 10; second.purchaseTotalOverride = 9500
        }
        if ProcessInfo.processInfo.arguments.contains("--holder-preview") {
            let samples: [(String, GoldAssetType, Double, Double, HoldingHolder?)] = [
                ("周大福手镯", .jewelry, 25, 792, .mother),
                ("招行积存金", .accumulation, 50, 760, .father),
                ("投资金条", .bar, 30, 775, .husband),
                ("六福吊坠", .jewelry, 12.5, 815, .wife),
                ("小金豆", .bean, 3, 780, .child),
                ("贺岁金条", .bar, 20, 745, .grandfather),
                ("古法金镯", .jewelry, 32, 768, .grandmother),
                ("海外购买", .bar, 10, 770, nil)
            ]
            for (idx, item) in samples.enumerated() {
                let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: max(1, 28 - idx), hour: 12))!
                let rec = HoldingRecord(grams: item.2, unitPriceCNY: item.3, timestamp: day)
                rec.brand = item.0
                rec.assetType = item.1.rawValue
                rec.holder = item.4?.rawValue ?? ""
                result.mainContext.insert(rec)
            }
            try result.mainContext.save()
            return result
        }
        result.mainContext.insert(first); result.mainContext.insert(second)
        try result.mainContext.save()
        #endif
        return result
    }
    #if DEBUG
    private struct QuoteFixture: GoldQuoteServicing {
        func fetchQuote() async throws -> GoldQuote {
            GoldQuote(symbol: "AU9999", price: 942.27, open: 940, high: 943, low: 939, prevClose: 940, usdCNY: 0, cnyPerGram: 942.27, asOf: .now)
        }
    }
    #endif
}
