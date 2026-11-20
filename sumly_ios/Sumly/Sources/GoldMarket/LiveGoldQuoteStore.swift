import Foundation
import Observation

/// 单口径盘口展示模型（全部折算为人民币/克，供行情页盘口卡片与涨跌胶囊使用）。
struct MarketQuoteSnapshot: Equatable, Sendable {
    let basis: GoldMarketBasis
    let cnyPerGram: Double
    let changeCNY: Double?
    let changePercent: Double?
    let openCNY: Double?
    let highCNY: Double?
    let lowCNY: Double?
    let prevCloseCNY: Double?
    let usdPerOz: Double?
    let usdCNY: Double?
    let asOf: Date

    static func make(from quote: GoldQuote, basis: GoldMarketBasis) -> MarketQuoteSnapshot? {
        guard quote.cnyPerGram.isFinite, quote.cnyPerGram > 0 else { return nil }
        let ratio: Double? = {
            switch basis {
            case .domestic:
                return 1
            case .international:
                if quote.price.isFinite, quote.price > 0 {
                    return quote.cnyPerGram / quote.price
                }
                if quote.usdCNY.isFinite, quote.usdCNY > 0 {
                    return quote.usdCNY / 31.1034768
                }
                return nil
            }
        }()

        func convert(_ raw: Double) -> Double? {
            guard raw.isFinite, raw > 0, let ratio else { return nil }
            let value = raw * ratio
            return value.isFinite && value > 0 ? value : nil
        }

        let prevCloseCNY = convert(quote.prevClose)
        let changeCNY = prevCloseCNY.map { quote.cnyPerGram - $0 }
        let changePercent: Double? = {
            guard let prevCloseCNY, prevCloseCNY > 0, let changeCNY else { return nil }
            return changeCNY / prevCloseCNY * 100
        }()

        return MarketQuoteSnapshot(
            basis: basis,
            cnyPerGram: quote.cnyPerGram,
            changeCNY: changeCNY,
            changePercent: changePercent,
            openCNY: convert(quote.open),
            highCNY: convert(quote.high),
            lowCNY: convert(quote.low),
            prevCloseCNY: prevCloseCNY,
            usdPerOz: basis == .international && quote.price.isFinite && quote.price > 0 ? quote.price : nil,
            usdCNY: quote.usdCNY.isFinite && quote.usdCNY > 0 ? quote.usdCNY : nil,
            asOf: quote.asOf
        )
    }
}

/// 国内 Au99.99 相对国际伦敦金折算价的实时价差（溢价）。
struct GoldMarketSpread: Equatable, Sendable {
    let domesticCNY: Double
    let internationalCNY: Double
    /// 国内 - 国际（正值代表国内溢价，负值代表国内折价）。
    let spreadCNY: Double
    let spreadPercent: Double

    static func calculate(domestic: GoldQuote?, international: GoldQuote?) -> GoldMarketSpread? {
        guard let d = domestic?.cnyPerGram, d.isFinite, d > 0,
              let i = international?.cnyPerGram, i.isFinite, i > 0 else { return nil }
        let diff = d - i
        return GoldMarketSpread(
            domesticCNY: d,
            internationalCNY: i,
            spreadCNY: diff,
            spreadPercent: diff / i * 100
        )
    }
}

/// 全局共享实时行情报价中心：统一维护国内/国际双口径最新报价，
/// 避免各 Tab 与弹窗各自轮询、切页丢失参考价，并为记一笔秒填金价与溢价计算提供单一数据源。
@MainActor
@Observable
final class LiveGoldQuoteStore {
    private(set) var quotes: [GoldMarketBasis: GoldQuote] = [:]
    private(set) var failedBases: Set<GoldMarketBasis> = []

    private let serviceFactory: (GoldMarketBasis) -> any GoldQuoteServicing
    private var pollingTask: Task<Void, Never>?

    init(serviceFactory: @escaping (GoldMarketBasis) -> any GoldQuoteServicing = {
        BackendGoldPriceService(instrumentID: $0.instrumentID)
    }) {
        self.serviceFactory = serviceFactory
    }

    func quote(for basis: GoldMarketBasis) -> GoldQuote? {
        quotes[basis]
    }

    func isFailed(for basis: GoldMarketBasis) -> Bool {
        failedBases.contains(basis)
    }

    func snapshot(for basis: GoldMarketBasis) -> MarketQuoteSnapshot? {
        quotes[basis].flatMap { MarketQuoteSnapshot.make(from: $0, basis: basis) }
    }

    var spread: GoldMarketSpread? {
        GoldMarketSpread.calculate(domestic: quotes[.domestic], international: quotes[.international])
    }

    /// 由其他页面（如行情主视图）拉到最新报价时回写，保持全局一致。
    func ingest(_ quote: GoldQuote, for basis: GoldMarketBasis) {
        guard quote.cnyPerGram.isFinite, quote.cnyPerGram > 0 else { return }
        if let existing = quotes[basis], existing.asOf > quote.asOf { return }
        quotes[basis] = quote
        failedBases.remove(basis)
    }

    func clearCache() {
        quotes = [:]
        failedBases = []
    }

    func start(primaryBasis: @escaping @MainActor () -> GoldMarketBasis) async {
        await loadCachedQuotes()
        var tick = 0
        while !Task.isCancelled {
            let primary = primaryBasis()
            await refresh(basis: primary)
            if tick % 3 == 0 {
                let secondary: GoldMarketBasis = primary == .domestic ? .international : .domestic
                await refresh(basis: secondary)
            }
            tick &+= 1
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
        }
    }

    func refreshAll() async {
        async let d: Void = refresh(basis: .domestic)
        async let i: Void = refresh(basis: .international)
        _ = await (d, i)
    }

    func refresh(basis: GoldMarketBasis) async {
        let service = serviceFactory(basis)
        if quotes[basis] == nil, let cached = await service.cachedQuote() {
            if !Task.isCancelled, cached.cnyPerGram.isFinite, cached.cnyPerGram > 0 {
                quotes[basis] = cached
            }
        }
        do {
            let fetched = try await service.fetchQuote()
            guard !Task.isCancelled else { return }
            guard fetched.cnyPerGram.isFinite, fetched.cnyPerGram > 0 else {
                failedBases.insert(basis)
                return
            }
            quotes[basis] = fetched
            failedBases.remove(basis)
        } catch {
            if !Task.isCancelled {
                failedBases.insert(basis)
            }
        }
    }

    private func loadCachedQuotes() async {
        for basis in GoldMarketBasis.allCases {
            if quotes[basis] == nil, let cached = await serviceFactory(basis).cachedQuote(),
               cached.cnyPerGram.isFinite, cached.cnyPerGram > 0 {
                quotes[basis] = cached
            }
        }
    }
}
