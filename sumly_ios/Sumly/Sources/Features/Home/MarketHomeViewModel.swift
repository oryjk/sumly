import Foundation
import Observation

struct MarketChartPoint: Sendable, Equatable {
    let date: Date
    let price: Double
    var granularity: GoldPointGranularity = .realtime
    var intervalSeconds: Int = 5
}

protocol GoldIntradayServicing: Sendable {
    func fetchIntraday() async throws -> [MarketChartPoint]
}

protocol GoldRealtimeServicing: Sendable {
    func fetchRealtime() async throws -> [MarketChartPoint]
}

struct MarketHomeDataServices {
    let daily: any GoldPriceServicing
    let quote: any GoldQuoteServicing
    let realtime: any GoldRealtimeServicing
    let history: any GoldHistoryServicing

    static func backend(for basis: GoldMarketBasis) -> MarketHomeDataServices {
        let backend = BackendGoldPriceService(instrumentID: basis.instrumentID)
        return MarketHomeDataServices(daily: backend, quote: backend, realtime: backend, history: backend)
    }
}

enum MarketRange: String, CaseIterable {
    case realtime = "实时"
    case month = "近一月"
    case quarter = "近三月"
    case yearToDate = "今年以来"
    case year = "近一年"
    case twoYears = "近两年"
    case threeYears = "近三年"
    case fiveYears = "近五年"
    case tenYears = "近十年"
    case history = "1900年至今"

    var localizedTitle: String {
        switch self {
        case .realtime: L10n.tr("实时")
        case .month: L10n.tr("近一月")
        case .quarter: L10n.tr("近三月")
        case .yearToDate: L10n.tr("今年以来")
        case .year: L10n.tr("近一年")
        case .twoYears: L10n.tr("近两年")
        case .threeYears: L10n.tr("近三年")
        case .fiveYears: L10n.tr("近五年")
        case .tenYears: L10n.tr("近十年")
        case .history: L10n.tr("1900年至今")
        }
    }

    func dateBounds(now: Date = .now, calendar: Calendar = Calendar(identifier: .gregorian)) -> ClosedRange<Date>? {
        let end = ChartViewport.noon(calendar.date(byAdding: .day, value: -1, to: now)!, calendar: calendar)
        let start: Date
        switch self {
        case .realtime: return nil
        case .month, .quarter:
            start = calendar.date(byAdding: .month, value: self == .month ? -1 : -3, to: end)!
        case .yearToDate:
            start = calendar.date(from: DateComponents(year: calendar.component(.year, from: now), month: 1, day: 1, hour: 12))!
        case .year, .twoYears, .threeYears, .fiveYears, .tenYears:
            let years = self == .year ? 1 : self == .twoYears ? 2 : self == .threeYears ? 3 : self == .fiveYears ? 5 : 10
            start = calendar.date(byAdding: .year, value: -years, to: end)!
        case .history:
            start = calendar.date(from: DateComponents(year: 1900, month: 1, day: 1, hour: 12))!
        }
        return start <= end ? start...end : nil
    }
}

@MainActor @Observable
final class MarketHomeViewModel {
    var range: MarketRange = .quarter {
        didSet {
            resetViewport()
            syncShowsInitialLoading()
        }
    }
    var selectedDate: Date? {
        didSet {
            selectionExpiryTask?.cancel()
            selectionExpiryTask = nil
        }
    }
    @ObservationIgnored private var selectionExpiryTask: Task<Void, Never>?
    var priceScale: ChartPriceScale = .linear
    private var cacheGeneration: UInt = 0
    private(set) var viewport: ClosedRange<Date>?
    private var gestureViewport: ClosedRange<Date>?
    private(set) var history: [GoldHistoryPoint] = [] {
        didSet { if history != oldValue { historyRevision &+= 1 } }
    }
    private var historyFailed = false
    private(set) var historyLoading = false
    private(set) var basis: GoldMarketBasis
    private var historyService: any GoldHistoryServicing
    private(set) var quote: GoldQuote?
    private(set) var daily: [GoldDailyPrice] = [] {
        didSet { if daily != oldValue { historyRevision &+= 1 } }
    }
    private(set) var realtime: [MarketChartPoint] = [] {
        didSet {
            if realtime != oldValue {
                realtimeRevision &+= 1
                syncDomesticDayPlusNightAnchor()
            }
        }
    }
    /// 当国内分时曲线同时包含今日连续日盘（09:00–15:30）与当晚夜盘（20:00 起）时，缓存该自然日 00:00 锚点。
    /// 仅在跨入日+夜联合态时变更一次，避免非实时视图为统一昨收基准而订阅每 5 秒 `realtime` 变化。
    private(set) var domesticDayPlusNightAnchor: Date?
    private var quoteLoading = true
    private var dailyLoading = true
    private var realtimeLoading = true
    private var quoteRequest: UUID?
    private var dailyRequest: UUID?
    private var realtimeRequest: UUID?
    private var historyRequest: UUID?
    /// Stored initial-loading flag so `HomeView.body` does not subscribe to high-frequency `quote` or `loading` churn after initial load.
    private(set) var showsInitialLoading = true
    var chartLoading: Bool { range == .realtime ? realtimeLoading : (dailyLoading || historyLoading) }
    var loading: Bool { (quote == nil && quoteLoading) || (points.isEmpty && chartLoading) }
    private var quoteFailed = false
    private var dailyFailed = false
    private var realtimeFailed = false
    private var dailyService: any GoldPriceServicing
    private var quoteService: any GoldQuoteServicing
    private var realtimeService: any GoldRealtimeServicing
    private let serviceFactory: (GoldMarketBasis) -> MarketHomeDataServices
    private let nowProvider: @Sendable () -> Date
    private let calendar: Calendar
    private var basisSwitchRequest: UUID?
    private(set) var isSwitchingBasis = false
    @ObservationIgnored var onNetworkQuote: (@MainActor (GoldQuote, GoldMarketBasis) -> Void)?

    // Derived data is not observable state: filling this cache during a view read
    // must not schedule another SwiftUI render. Source properties remain observed.
    private var historyRevision: UInt = 0
    private var realtimeRevision: UInt = 0
    @ObservationIgnored private var preparedKey: HistoricalPointsKey?
    @ObservationIgnored private var preparedPoints: [MarketChartPoint] = []
    @ObservationIgnored private var scopedKey: HistoricalPointsKey?
    @ObservationIgnored private var scopedRange: MarketRange?
    @ObservationIgnored private var scopedPoints: [MarketChartPoint] = []
    @ObservationIgnored private var cachedWindowKey: WindowCacheKey?
    @ObservationIgnored private var cachedWindowPoints: [MarketChartPoint] = []
    @ObservationIgnored private var cachedWindowStats: ChartWindowStatistics = ChartWindowStatistics(points: [])
    private struct HistoricalPointsKey: Equatable {
        let revision: UInt
        let factor: Double
        let lastDay: Date
        let timeZone: TimeZone
    }
    private struct WindowCacheKey: Equatable {
        let basis: GoldMarketBasis
        let range: MarketRange
        let historyRevision: UInt
        let usdCNY: Double
        let lower: Date
        let upper: Date
    }

    init(basis: GoldMarketBasis = .international,
         dailyService: (any GoldPriceServicing)? = nil,
         quoteService: (any GoldQuoteServicing)? = nil,
         realtimeService: (any GoldRealtimeServicing)? = nil,
         historyService: (any GoldHistoryServicing)? = nil,
         serviceFactory: ((GoldMarketBasis) -> MarketHomeDataServices)? = nil,
         nowProvider: @escaping @Sendable () -> Date = { .now },
         calendar: Calendar = .current) {
        let backend = MarketHomeDataServices.backend(for: basis)
        self.basis = basis
        self.historyService = historyService ?? backend.history
        self.dailyService = dailyService ?? backend.daily
        self.quoteService = quoteService ?? backend.quote
        self.realtimeService = realtimeService ?? backend.realtime
        self.serviceFactory = serviceFactory ?? { MarketHomeDataServices.backend(for: $0) }
        self.nowProvider = nowProvider
        self.calendar = calendar
    }

    var price: Double? {
        guard let quote, quote.cnyPerGram.isFinite, quote.cnyPerGram > 0 else { return nil }
        return quote.cnyPerGram
    }

    var points: [MarketChartPoint] {
        if range == .realtime { return Self.realtimeWindow(realtime, now: nowProvider()) }
        let factor: Double
        switch basis {
        case .domestic:
            factor = 1
        case .international:
            guard let quote, quote.usdCNY.isFinite, quote.usdCNY > 0 else { return [] }
            factor = quote.usdCNY / 31.1034768
        }
        let lastDay = ChartViewport.noon(Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        if history.isEmpty && range == .history { return [] }
        let key = HistoricalPointsKey(revision: historyRevision, factor: factor, lastDay: lastDay, timeZone: .current)
        if preparedKey == key { return pointsInSelectedRange(key: key) }
        let source = history.isEmpty
            ? daily.map { MarketChartPoint(date: $0.date, price: $0.close, granularity: .daily) }
            : history.map { MarketChartPoint(date: $0.date, price: $0.price, granularity: $0.granularity) }
        preparedPoints = source.compactMap { point in
            let date = ChartViewport.noon(point.date)
            let price = point.price * factor
            guard date <= lastDay, price.isFinite, price > 0 else { return nil }
            return MarketChartPoint(date: date, price: price, granularity: point.granularity)
        }.sorted { $0.date < $1.date }
        preparedKey = key
        return pointsInSelectedRange(key: key)
    }

    private func pointsInSelectedRange(key: HistoricalPointsKey) -> [MarketChartPoint] {
        if scopedKey == key && scopedRange == range { return scopedPoints }
        if let bounds = range.dateBounds() {
            scopedPoints = preparedPoints.filter { bounds.contains($0.date) }
        } else { scopedPoints = [] }
        scopedKey = key
        scopedRange = range
        return scopedPoints
    }

    private func syncShowsInitialLoading() {
        let next = price == nil && points.isEmpty && loading
        if showsInitialLoading != next {
            showsInitialLoading = next
        }
    }

    var realtimeTiming: RealtimeChartTiming {
        let now = nowProvider()
        let window = Self.realtimeWindow(realtime, now: now)
        let latest = window.last
        let span: TimeInterval = {
            guard let first = window.first?.date, let last = latest?.date else { return 0 }
            return max(0, last.timeIntervalSince(first))
        }()
        return RealtimeChartTiming(
            latestSample: latest?.date,
            latestQuote: quote?.asOf,
            basis: basis,
            intervalSeconds: latest?.intervalSeconds ?? 5,
            windowSpan: span,
            now: now,
            calendar: calendar
        )
    }

    var liveStreamPollInterval: Duration {
        realtimeTiming.state == .paused ? Self.pausedPollInterval : Self.livePollInterval
    }

    var message: String? {
        if loading { return L10n.tr("正在获取行情…") }
        if quoteFailed { return quote == nil ? L10n.tr("行情加载失败，点击重试") : L10n.tr("刷新失败，显示上次行情 · 点击重试") }
        if price == nil { return L10n.tr("人民币报价暂不可用 · 点击重试") }
        if range == .history && historyLoading { return L10n.tr("正在加载百年走势…") }
        if range == .history && historyFailed { return L10n.tr("历史走势加载失败 · 点击重试") }
        if range == .realtime ? realtimeFailed : (range == .history ? historyFailed : dailyFailed) { return L10n.tr("走势刷新失败 · 点击重试") }
        if range == .realtime {
            let timing = realtimeTiming
            if timing.state == .paused, let date = quote?.asOf ?? timing.latestSample {
                return timing.pausedMessage(for: date)
            }
            if let quote, timing.now.timeIntervalSince(quote.asOf) > 180 {
                return timing.pausedMessage(for: quote.asOf)
            }
            if realtime.isEmpty { return L10n.tr("暂无最新走势，请稍后再试") }
        } else if let quote {
            let now = nowProvider()
            if now.timeIntervalSince(quote.asOf) > 180 {
                let timing = RealtimeChartTiming(
                    latestSample: nil,
                    latestQuote: quote.asOf,
                    basis: basis,
                    now: now,
                    calendar: calendar
                )
                return timing.pausedMessage(for: quote.asOf)
            }
        }
        return nil
    }

    nonisolated static let realtimeMinimumSpan: TimeInterval = 1200
    nonisolated static let realtimeMaximumSpan: TimeInterval = 24 * 3600
    nonisolated static let realtimeSessionGap: TimeInterval = 6 * 3600
    static let livePollInterval: Duration = .seconds(5)
    static let pausedPollInterval: Duration = .seconds(30)

    /// 保留完整当日交易分时（限制最大 24 小时：容纳国际 23h 全天与国内日盘+夜盘 4.5h 闭市连贯，
    /// 超过 6h 视为隔夜 02:30–09:00 或周末长停盘自动截断）。
    nonisolated static func realtimeWindow(_ points: [MarketChartPoint], now: Date) -> [MarketChartPoint] {
        let valid = points.filter { $0.date <= now && $0.price.isFinite && $0.price > 0 }
            .sorted { $0.date < $1.date }
        guard !valid.isEmpty else { return [] }

        var deduped: [MarketChartPoint] = []
        deduped.reserveCapacity(valid.count)
        for point in valid {
            if let last = deduped.last, last.date == point.date {
                deduped[deduped.count - 1] = point
            } else {
                deduped.append(point)
            }
        }
        guard let latest = deduped.last else { return [] }

        let maxCutoff = latest.date.addingTimeInterval(-realtimeMaximumSpan)
        let bounded = deduped.filter { $0.date >= maxCutoff }
        guard !bounded.isEmpty else { return [] }

        // 保留最近一个连续交易时段：相邻点间隔 > 3h 视为跨日/夜盘或周末停盘，
        // 既完整保留上金所日盘 11:30–13:30 两小时午休，又避免拼接前一时段旧曲线。
        var sessionStartIndex = 0
        if bounded.count > 1 {
            for index in stride(from: bounded.count - 1, through: 1, by: -1) {
                let gap = bounded[index].date.timeIntervalSince(bounded[index - 1].date)
                if gap > realtimeSessionGap {
                    sessionStartIndex = index
                    break
                }
            }
        }
        return Array(bounded[sessionStartIndex...])
    }

    /// 盘中追加实时新点时保留同一交易时段早期的分时点，并由 `realtimeWindow` 保证最大 12h 与不跨休市跳空。
    nonisolated static func mergeRealtimeSession(
        existing: [MarketChartPoint],
        incoming: [MarketChartPoint],
        now: Date
    ) -> [MarketChartPoint] {
        let cleanedIncoming = realtimeWindow(incoming, now: now)
        guard let firstIncoming = cleanedIncoming.first, let lastIncoming = cleanedIncoming.last else {
            return []
        }
        let cleanedExisting = realtimeWindow(existing, now: now)
        guard let lastExisting = cleanedExisting.last else { return cleanedIncoming }
        guard lastIncoming.date >= lastExisting.date else { return cleanedIncoming }
        let earlierSameSession = cleanedExisting.filter { $0.date < firstIncoming.date }
        guard !earlierSameSession.isEmpty else { return cleanedIncoming }
        return realtimeWindow(earlierSameSession + cleanedIncoming, now: now)
    }

    /// 纵轴保留呼吸空间，以半元为刻度边界，避免每次尾点变化都拉伸整条曲线。
    nonisolated static func chartDomain(_ points: [MarketChartPoint]) -> ClosedRange<Double> {
        let low = points.map(\.price).min() ?? 0
        let high = points.map(\.price).max() ?? 1
        let center = (low + high) / 2
        let span = max((high - low) * 1.5, 1)
        return (floor((center - span / 2) * 2) / 2)...(ceil((center + span / 2) * 2) / 2)
    }

    var quoteSnapshot: MarketQuoteSnapshot? {
        guard let quote else { return nil }
        let overrideClose: Double? = {
            guard basis == .domestic, let dayAnchor = domesticDayPlusNightAnchor else { return nil }
            return RealtimeIntradayAxis.priorTradingDayClose(before: dayAnchor, in: daily)
        }()
        return MarketQuoteSnapshot.make(from: quote, basis: basis, referenceCloseOverride: overrideClose)
    }

    var realtimeReferenceClose: Double? {
        let intradayPoints = Self.realtimeWindow(realtime, now: nowProvider())
        return RealtimeIntradayAxis.resolveReferenceClose(
            basis: basis,
            quote: quote,
            points: intradayPoints,
            daily: daily
        )
    }

    var realtimeIntradayAxis: RealtimeIntradayAxis {
        let intradayPoints = range == .realtime ? points : Self.realtimeWindow(realtime, now: nowProvider())
        let anchor = intradayPoints.last?.date ?? quote?.asOf ?? nowProvider()
        return RealtimeIntradayAxis.make(basis: basis, anchorDate: anchor, points: intradayPoints)
    }

    private func syncDomesticDayPlusNightAnchor() {
        let next: Date? = {
            guard basis == .domestic else { return nil }
            let intradayPoints = Self.realtimeWindow(realtime, now: nowProvider())
            return RealtimeIntradayAxis.domesticDayPlusNightAnchor(for: intradayPoints)
        }()
        if domesticDayPlusNightAnchor != next {
            domesticDayPlusNightAnchor = next
        }
    }

    var realtimeProjectedPoints: [ProjectedIntradayPoint] {
        realtimeIntradayAxis.project(visiblePoints)
    }

    var selectedPoint: MarketChartPoint? {
        let window = xDomain
        guard let selectedDate, window.contains(selectedDate) else { return nil }
        return Self.nearestPoint(in: windowPoints, to: selectedDate)
    }

    /// 二分查找有序点列中距离目标时刻最近的点，O(log n)，保障长历史数据拖动查价丝滑。
    nonisolated static func nearestPoint(in sortedPoints: [MarketChartPoint], to target: Date) -> MarketChartPoint? {
        guard !sortedPoints.isEmpty else { return nil }
        var low = 0
        var high = sortedPoints.count
        while low < high {
            let mid = (low + high) / 2
            if sortedPoints[mid].date < target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        if low == 0 { return sortedPoints[0] }
        if low >= sortedPoints.count { return sortedPoints[sortedPoints.count - 1] }
        let previous = sortedPoints[low - 1]
        let next = sortedPoints[low]
        let dPrev = abs(previous.date.timeIntervalSince(target))
        let dNext = abs(next.date.timeIntervalSince(target))
        return dPrev <= dNext ? previous : next
    }

    func start(includeQuotePolling: Bool = true) async {
        // Each stream owns its retry schedule: slow historical sync must not
        // prevent live prices recovering after a foreground/network transition.
        if includeQuotePolling {
            async let quotes: Void = poll(interval: { self.liveStreamPollInterval }) { await self.loadQuote() }
            async let realtime: Void = poll(interval: { self.realtimePollInterval }) { await self.loadRealtime() }
            async let history: Void = poll(interval: { .seconds(60) }) {
                await self.loadDaily()
                if self.range != .realtime { await self.loadHistory() }
            }
            _ = await (quotes, realtime, history)
        } else {
            async let realtime: Void = poll(interval: { self.realtimePollInterval }) { await self.loadRealtime() }
            async let history: Void = poll(interval: { .seconds(60) }) {
                await self.loadDaily()
                if self.range != .realtime { await self.loadHistory() }
            }
            _ = await (realtime, history)
        }
    }

    private var realtimePollInterval: Duration {
        range == .realtime ? liveStreamPollInterval : Self.pausedPollInterval
    }

    /// 同步外部共享报价源，消除与 LiveGoldQuoteStore 的双重 5 秒轮询冗余。
    func applyExternalQuote(_ externalQuote: GoldQuote?, failed: Bool) {
        if let externalQuote, externalQuote.cnyPerGram.isFinite, externalQuote.cnyPerGram > 0 {
            if let current = quote, current.asOf > externalQuote.asOf {
                if quoteFailed { quoteFailed = false }
                if quoteLoading { quoteLoading = false }
                syncShowsInitialLoading()
                return
            }
            if quote != externalQuote { quote = externalQuote }
            if quoteFailed { quoteFailed = false }
            if quoteLoading { quoteLoading = false }
        } else if failed {
            if !quoteFailed { quoteFailed = true }
            if quoteLoading { quoteLoading = false }
        }
        syncShowsInitialLoading()
    }

    func refreshRealtimeIfNeeded() async {
        await loadRealtime()
    }

    private func poll(interval: @MainActor () -> Duration, operation: @MainActor () async -> Void) async {
        while !Task.isCancelled {
            await operation()
            do { try await Task.sleep(for: interval()) } catch { return }
        }
    }

    func refresh() async {
        async let q: Void = loadQuote()
        async let d: Void = loadDaily()
        async let i: Void = loadRealtime()
        _ = await (q, d, i)
        if range != .realtime { await loadHistory() }
    }

    /// 在不重建页面的情况下切换行情口径。新口径的数据准备完成前保留当前快照，
    /// 成功后在同一个 MainActor 周期内替换报价、实时走势和历史数据，避免新旧口径混用。
    @discardableResult
    func switchBasis(to newBasis: GoldMarketBasis, beforeCommit: @MainActor () -> Void = {}) async -> Bool {
        guard newBasis != basis else { return true }
        guard !isSwitchingBasis else { return false }

        let request = UUID()
        basisSwitchRequest = request
        isSwitchingBasis = true
        defer {
            if basisSwitchRequest == request {
                isSwitchingBasis = false
            }
        }

        let next = serviceFactory(newBasis)
        async let quoteFetch: GoldQuote = next.quote.fetchQuote()
        async let realtimeFetch: [MarketChartPoint] = next.realtime.fetchRealtime()
        async let dailyFetch: [GoldDailyPrice] = next.daily.fetchDailyPrices()
        async let historyFetch: [GoldHistoryPoint] = next.history.fetchHistory()

        do {
            let fetchedQuote = try await quoteFetch
            let fetchedRealtime = (try? await realtimeFetch) ?? []
            let fetchedDaily = (try? await dailyFetch) ?? []
            let fetchedHistory = (try? await historyFetch) ?? []
            guard basisSwitchRequest == request, !Task.isCancelled else { return false }

            guard fetchedQuote.cnyPerGram.isFinite, fetchedQuote.cnyPerGram > 0 else { return false }
            if range == .realtime {
                guard !Self.realtimeWindow(fetchedRealtime, now: nowProvider()).isEmpty else { return false }
            } else {
                if newBasis == .international {
                    guard fetchedQuote.usdCNY.isFinite, fetchedQuote.usdCNY > 0 else { return false }
                }
                let usableHistory = fetchedHistory.contains { $0.price.isFinite && $0.price > 0 }
                let usableDaily = fetchedDaily.contains { $0.close.isFinite && $0.close > 0 }
                guard range == .history ? usableHistory : (usableHistory || usableDaily) else { return false }
            }
            beforeCommit()
            cacheGeneration &+= 1
            preparedKey = nil; preparedPoints = []
            scopedKey = nil; scopedRange = nil; scopedPoints = []
            cachedWindowKey = nil; cachedWindowPoints = []

            basis = newBasis
            dailyService = next.daily
            quoteService = next.quote
            realtimeService = next.realtime
            historyService = next.history
            quote = fetchedQuote
            realtime = fetchedRealtime
            daily = fetchedDaily
            history = fetchedHistory
            syncDomesticDayPlusNightAnchor()
            quoteFailed = false
            realtimeFailed = fetchedRealtime.isEmpty
            dailyFailed = fetchedDaily.isEmpty && fetchedHistory.isEmpty
            historyFailed = fetchedHistory.isEmpty && fetchedDaily.isEmpty
            quoteLoading = false
            realtimeLoading = false
            dailyLoading = false
            historyLoading = false
            selectedDate = nil
            gestureViewport = nil
            syncShowsInitialLoading()
            onNetworkQuote?(fetchedQuote, newBasis)
            return true
        } catch {
            return false
        }
    }

    /// Unlock immediately even when a cancelled transport is still unwinding.
    /// The token prevents that transport from committing into a later switch.
    func cancelBasisSwitch() {
        basisSwitchRequest = nil
        isSwitchingBasis = false
    }

    /// A frozen display layer for the outgoing crossfade. It never starts tasks;
    /// arrays share storage until the live model changes them.
    func makeDisplaySnapshot() -> MarketHomeViewModel {
        let snapshot = MarketHomeViewModel(basis: basis, dailyService: dailyService,
            quoteService: quoteService, realtimeService: realtimeService,
            historyService: historyService, serviceFactory: serviceFactory,
            nowProvider: nowProvider, calendar: calendar)
        snapshot.range = range
        snapshot.priceScale = priceScale
        snapshot.quote = quote
        snapshot.daily = daily
        snapshot.history = history
        snapshot.realtime = realtime
        snapshot.viewport = xDomain
        snapshot.selectedDate = selectedDate
        snapshot.quoteLoading = quoteLoading
        snapshot.dailyLoading = dailyLoading
        snapshot.realtimeLoading = realtimeLoading
        snapshot.historyLoading = historyLoading
        snapshot.quoteFailed = quoteFailed
        snapshot.dailyFailed = dailyFailed
        snapshot.realtimeFailed = realtimeFailed
        snapshot.historyFailed = historyFailed
        snapshot.historyRevision = historyRevision
        snapshot.showsInitialLoading = showsInitialLoading
        snapshot.domesticDayPlusNightAnchor = domesticDayPlusNightAnchor
        snapshot.preparedKey = preparedKey; snapshot.preparedPoints = preparedPoints
        snapshot.scopedKey = scopedKey; snapshot.scopedRange = scopedRange; snapshot.scopedPoints = scopedPoints
        return snapshot
    }

    var fullDomain: ClosedRange<Date> {
        let values = points
        if range == .realtime {
            let end = values.last?.date ?? nowProvider()
            let earliest = values.first?.date ?? end
            let start = min(earliest, end.addingTimeInterval(-Self.realtimeMinimumSpan))
            return start...end
        }
        if range == .history, basis == .domestic, let first = values.first?.date, let last = values.last?.date {
            return first...last
        }
        // The selected range is the hard boundary, including navigator and date picker.
        // No completed YTD day exists on January 1. The UI shows an empty state;
        // its inert geometry stays inside this year, never in the previous year.
        let today = ChartViewport.noon(.now)
        return range.dateBounds() ?? today...today
    }
    var presetDomain: ClosedRange<Date> { fullDomain }
    var xDomain: ClosedRange<Date> {
        guard let viewport else { return presetDomain }
        let bounds = fullDomain
        if range == .realtime { return ChartViewport.pan(viewport, fraction: 0, bounds: bounds) }
        return ChartViewport.dayAligned(viewport, bounds: bounds)
    }
    var windowPoints: [MarketChartPoint] {
        let window = xDomain
        if range == .realtime {
            return points.filter { window.contains($0.date) }
        }
        let fx = basis == .international ? (quote?.usdCNY ?? 0) : 1
        let key = WindowCacheKey(basis: basis, range: range, historyRevision: historyRevision,
                                 usdCNY: fx, lower: window.lowerBound, upper: window.upperBound)
        if cachedWindowKey == key { return cachedWindowPoints }
        let filtered = points.filter { window.contains($0.date) }
        cachedWindowKey = key
        cachedWindowPoints = filtered
        cachedWindowStats = ChartWindowStatistics(points: filtered)
        return filtered
    }
    var windowStatistics: ChartWindowStatistics {
        if range == .realtime { return ChartWindowStatistics(points: windowPoints) }
        _ = windowPoints
        return cachedWindowStats
    }
    var canReset: Bool { xDomain != presetDomain }
    var axisDates: [Date] {
        let window = xDomain
        if range == .realtime {
            let span = window.upperBound.timeIntervalSince(window.lowerBound)
            return (0...3).map { window.lowerBound.addingTimeInterval(span * Double($0) / 3) }
        }
        let days = Calendar.current.dateComponents([.day], from: window.lowerBound, to: window.upperBound).day ?? 1
        let offsets = Set((0...3).map { Int((Double(days) * Double($0) / 3).rounded()) })
        return offsets.sorted().map { Calendar.current.date(byAdding: .day, value: $0, to: window.lowerBound)! }
    }
    var visiblePoints: [MarketChartPoint] {
        let values = points
        let window = xDomain
        // Adjacent actual points keep a clipped line continuous without making new observations.
        let first = values.firstIndex { $0.date >= window.lowerBound } ?? values.count
        let last = values.lastIndex { $0.date <= window.upperBound } ?? -1
        let lower = max(0, first - 1)
        let upper = min(values.count, last + 2)
        guard lower < upper else { return [] }
        let visible = Array(values[lower..<upper])
        return range == .realtime ? RealtimeChartCompaction.points(visible) : visible
    }
    func resetViewport() { viewport = nil; gestureViewport = nil; selectedDate = nil }
    func beginChartGesture() { gestureViewport = xDomain; selectedDate = nil }
    func transformChart(scale: Double, anchor: Double, translation: Double) {
        guard let initial = gestureViewport else { return }
        let focal = initial.lowerBound.addingTimeInterval(initial.upperBound.timeIntervalSince(initial.lowerBound) * anchor)
        let minimum: TimeInterval = range == .realtime ? 30 : (focal < GoldDailyPrice.parseDay("2016-01-01")! ? 366 * 86400 : 86400)
        let zoomed = ChartViewport.zoom(initial, scale: scale, anchor: anchor, bounds: fullDomain, minimumSpan: minimum)
        let moved = ChartViewport.pan(zoomed, fraction: translation, bounds: fullDomain)
        viewport = range == .realtime ? moved : ChartViewport.dayAligned(moved, bounds: fullDomain)
        selectedDate = nil
    }
    func beginNavigatorGesture() { gestureViewport = xDomain; selectedDate = nil }
    func moveNavigator(part: ChartViewport.Part, fraction: Double) {
        guard let initial = gestureViewport else { return }
        viewport = ChartViewport.navigate(initial, part: part, fraction: fraction, bounds: fullDomain, daily: range != .realtime)
    }
    func setDateWindow(_ window: ClosedRange<Date>) {
        viewport = ChartViewport.dayAligned(window, bounds: fullDomain)
        selectedDate = nil
    }
    func endChartGesture() { gestureViewport = nil }
    func accessibleZoom(_ scale: Double) { beginChartGesture(); transformChart(scale: scale, anchor: 0.5, translation: 0); endChartGesture() }
    func selectChart(at fraction: Double) {
        guard gestureViewport == nil else { return }
        let clamped = min(1, max(0, fraction))
        if range == .realtime {
            let axis = realtimeIntradayAxis
            let projected = axis.project(windowPoints)
            let slotRange: ClosedRange<Double> = {
                if canReset, let first = projected.first?.slot, let last = projected.last?.slot, last > first {
                    return first...last
                }
                return 0...max(1, axis.totalSlots)
            }()
            let targetSlot = slotRange.lowerBound + (slotRange.upperBound - slotRange.lowerBound) * clamped
            if let hit = RealtimeIntradayAxis.nearestPoint(in: projected, toSlot: targetSlot) {
                selectedDate = hit.date
            } else {
                let domain = xDomain
                selectedDate = domain.lowerBound.addingTimeInterval(domain.upperBound.timeIntervalSince(domain.lowerBound) * clamped)
            }
        } else {
            let domain = xDomain
            selectedDate = domain.lowerBound.addingTimeInterval(domain.upperBound.timeIntervalSince(domain.lowerBound) * clamped)
        }
        selectionExpiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.selectedDate = nil
        }
    }
    func loadHistory() async {
        guard !historyLoading else { return }
        guard !Task.isCancelled else { return }
        let request = UUID()
        historyRequest = request
        historyLoading = true
        defer {
            if historyRequest == request {
                historyLoading = false
                syncShowsInitialLoading()
            }
        }
        let generation = cacheGeneration
        if let cached = await historyService.cachedHistory(), generation == cacheGeneration, historyRequest == request {
            if history != cached { history = cached }
            syncShowsInitialLoading()
        }
        guard generation == cacheGeneration, historyRequest == request, !Task.isCancelled else { return }
        do {
            let fetched = try await historyService.fetchHistory()
            guard generation == cacheGeneration, historyRequest == request, !Task.isCancelled else { return }
            if history != fetched { history = fetched }
            if historyFailed { historyFailed = false }
            syncShowsInitialLoading()
        }
        catch { if generation == cacheGeneration, historyRequest == request, !Task.isCancelled, !historyFailed { historyFailed = true } }
    }

    func clearMarketCache() {
        cancelBasisSwitch()
        historyRequest = nil; historyLoading = false
        cacheGeneration &+= 1
        preparedKey = nil; preparedPoints = []
        scopedKey = nil; scopedRange = nil; scopedPoints = []
        cachedWindowKey = nil; cachedWindowPoints = []
        daily = []; history = []; realtime = []; quote = nil; selectedDate = nil
        resetViewport()
        syncShowsInitialLoading()
    }

    private func loadQuote() async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        quoteRequest = request
        quoteLoading = true
        defer {
            if quoteRequest == request {
                quoteLoading = false
                syncShowsInitialLoading()
            }
        }
        let generation = cacheGeneration
        if quote == nil, let cached = await quoteService.cachedQuote(), generation == cacheGeneration, quoteRequest == request {
            quote = cached
            syncShowsInitialLoading()
        }
        guard generation == cacheGeneration, quoteRequest == request, !Task.isCancelled else { return }
        do {
            let fetched = try await quoteService.fetchQuote()
            guard generation == cacheGeneration, quoteRequest == request, !Task.isCancelled else { return }
            if quote != fetched { quote = fetched }
            if quoteFailed { quoteFailed = false }
            syncShowsInitialLoading()
            onNetworkQuote?(fetched, basis)
        }
        catch { if generation == cacheGeneration, quoteRequest == request, !Task.isCancelled, !quoteFailed { quoteFailed = true } }
    }
    private func loadDaily() async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        dailyRequest = request
        dailyLoading = true
        defer {
            if dailyRequest == request {
                dailyLoading = false
                syncShowsInitialLoading()
            }
        }
        let generation = cacheGeneration
        if let cached = await dailyService.cachedDailyPrices(), generation == cacheGeneration, dailyRequest == request {
            if daily != cached { daily = cached }
            syncShowsInitialLoading()
        }
        guard generation == cacheGeneration, dailyRequest == request, !Task.isCancelled else { return }
        do {
            let fetched = try await dailyService.fetchDailyPrices()
            guard generation == cacheGeneration, dailyRequest == request, !Task.isCancelled else { return }
            if daily != fetched { daily = fetched }
            if dailyFailed { dailyFailed = false }
            syncShowsInitialLoading()
        }
        catch { if generation == cacheGeneration, dailyRequest == request, !Task.isCancelled, !dailyFailed { dailyFailed = true } }
    }
    private func loadRealtime() async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        realtimeRequest = request
        realtimeLoading = true
        defer {
            if realtimeRequest == request {
                realtimeLoading = false
                syncShowsInitialLoading()
            }
        }
        let generation = cacheGeneration
        guard generation == cacheGeneration, realtimeRequest == request, !Task.isCancelled else { return }
        do {
            let fetched = try await realtimeService.fetchRealtime()
            guard generation == cacheGeneration, realtimeRequest == request, !Task.isCancelled else { return }
            // An empty/invalid refresh is not a replacement for a usable curve.
            let now = nowProvider()
            let merged = Self.mergeRealtimeSession(existing: realtime, incoming: fetched, now: now)
            guard !merged.isEmpty else {
                if !realtimeFailed { realtimeFailed = true }
                return
            }
            if realtime != merged { realtime = merged }
            if realtimeFailed { realtimeFailed = false }
            syncShowsInitialLoading()
        }
        catch { if generation == cacheGeneration, realtimeRequest == request, !Task.isCancelled, !realtimeFailed { realtimeFailed = true } }
    }
}
