import Foundation
import Observation

/// 持仓页状态：实时「元/克」价轮询与汇总统计。
/// 记录的增删走 SwiftData（视图持有 modelContext），这里只负责行情与计算。
@MainActor
@Observable
final class HoldingsViewModel {
    /// 实时报价轮询间隔，与行情页一致。
    static let quotePollInterval: Duration = .seconds(3)

    private(set) var quote: GoldQuote?
    private(set) var quoteFailed = false

    private let quoteService: (any GoldQuoteServicing)?

    init(quoteService: (any GoldQuoteServicing)? = BackendGoldPriceService(instrumentID: "au9999")) {
        self.quoteService = quoteService
    }

    convenience init(basis: GoldMarketBasis) {
        self.init(quoteService: BackendGoldPriceService(instrumentID: basis.instrumentID))
    }

    /// 页面入口：立即取一次报价，随后每 3 秒轮询；视图销毁自动取消。
    func start() async {
        await pollQuote()
        guard quoteService != nil else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.quotePollInterval)
            guard !Task.isCancelled else { return }
            await pollQuote()
        }
    }

    /// 同步外部共享报价源，避免多个 Tab 重复轮询同一接口。
    func applyExternalQuote(_ externalQuote: GoldQuote?, failed: Bool) {
        if let externalQuote, GoldReturnCalculator.validPrice(externalQuote.cnyPerGram) != nil {
            if quote != externalQuote {
                quote = externalQuote
            }
            if quoteFailed {
                quoteFailed = false
            }
        } else if failed {
            if !quoteFailed {
                quoteFailed = true
            }
        }
    }

    /// 拉一次实时报价；失败静默保留旧值。
    func pollQuote() async {
        guard let quoteService else { return }
        do {
            let fetched = try await quoteService.fetchQuote()
            guard GoldReturnCalculator.validPrice(fetched.cnyPerGram) != nil else {
                if !quoteFailed { quoteFailed = true }
                return
            }
            guard !Task.isCancelled else { return }
            if quote != fetched { quote = fetched }
            if quoteFailed { quoteFailed = false }
        } catch {
            if !quoteFailed { quoteFailed = true }
        }
    }

    func returns(for records: [HoldingRecord]) -> GoldPortfolioReturn? {
        let previous = quote.flatMap { q in
            q.price > 0 && q.prevClose > 0 ? q.cnyPerGram * q.prevClose / q.price : nil
        }
        return GoldReturnCalculator.aggregate(records.filter { $0.disposition == "holding" }.map(\.returnInput),
                                              referencePrice: quote?.cnyPerGram, previousPrice: previous)
    }

    func stats(for records: [HoldingRecord]) -> HoldingsStats {
        guard let result = returns(for: records) else { return .empty }
        return .init(totalGrams: result.grams, totalCost: result.totalCost, totalValue: result.bookValue ?? 0,
                     profit: result.profit ?? 0, profitPercent: result.profitPercent ?? 0, hasValuation: result.proceeds != nil)
    }
    func recordProfit(_ record: HoldingRecord) -> Double? {
        GoldReturnCalculator.calculate(record.returnInput, referencePrice: quote?.cnyPerGram)?.profit
    }
}
