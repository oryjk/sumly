import Foundation
import Observation

/// 攒金陪伴日历视图模型（`@MainActor @Observable`）。
/// 编排 `MarketHistoryCache`（通过 `BackendGoldPriceService`）、`LiveGoldQuoteStore` 与 `MacroTemperatureHistoryCache`，
/// 使用组合缓存键隔离全年重算，并在 5 秒实时报价变化时仅做 O(1) 今日增量刷新。
@MainActor
@Observable
final class HoldingsCalendarViewModel {
    private struct ComputeCacheKey: Equatable {
        let recordsSignature: Int
        let filter: HoldingCalendarFilter
        let basis: GoldMarketBasis
        let dailyRevision: Int
        let tempRevision: Int
        let focusedYear: Int
        let todayKey: CalendarDayKey
        let fxRateBucket: Int
    }

    private struct CompanionCacheKey: Equatable {
        let recordsSignature: Int
        let todayKey: CalendarDayKey
    }

    // MARK: - 视图交互状态

    var activeTab: GoldCalendarViewTab = .month
    private(set) var selectedDate: Date
    private(set) var focusedYear: Int
    private(set) var focusedMonth: Int
    var yearHeatmapMode: GoldCalendarYearHeatmapMode = .pnl
    private(set) var userSelectedLayer: GoldCalendarLayer?

    // MARK: - 计算结果快照

    private(set) var yearSnapshot: GoldCalendarYearSnapshot?
    private(set) var companionStats = GoldCalendarCompanionStats(
        companionDays: 0,
        consecutiveActiveMonths: 0,
        currentHoldingGrams: 0,
        milestoneProgress: .evaluate(totalGrams: 0),
        milestoneFirstReached: [:],
        hasAnyRecords: false
    )
    private(set) var isLoadingMarket = false
    private(set) var hasTemperatureData = false

    // 诊断/测试计数器：核验 5 秒实时报价只走 O(1) 增量路径而不重算全年。
    private(set) var fullComputeCount = 0
    private(set) var incrementalPatchCount = 0

    // MARK: - 内部数据源与缓存隔离

    private let calendar: Calendar
    private let cachedDailyLoader: @Sendable (GoldMarketBasis) async -> [GoldDailyPrice]?
    private let dailyLoader: @Sendable (GoldMarketBasis) async -> [GoldDailyPrice]
    private let cachedTemperatureLoader: @Sendable (MacroHistoryRange) async -> [MacroTemperatureHistoryPoint]?
    private let temperatureLoader: @Sendable (MacroHistoryRange) async -> [MacroTemperatureHistoryPoint]

    private var rawDailyByBasis: [GoldMarketBasis: [GoldDailyPrice]] = [:]
    private var rawTemperaturePoints: [MacroTemperatureHistoryPoint] = []
    private var loadedTemperatureRange: MacroHistoryRange?

    private var dailyRevision = 0
    private var tempRevision = 0
    private var lastComputeKey: ComputeCacheKey?
    private var lastCompanionKey: CompanionCacheKey?
    private var lastLiveQuoteInput: CalendarLiveQuoteInput?

    private var cachedFilteredItems: [CalendarHoldingItem] = []
    private var cachedConvertedBars: [CalendarDayKey: CalendarDailyMarketBar] = [:]
    private var cachedTemperatureMap: [CalendarDayKey: CalendarTemperatureSample] = [:]
    private var lastSyncInputs: (items: [CalendarHoldingItem], filter: HoldingCalendarFilter, basis: GoldMarketBasis, liveQuote: GoldQuote?, now: Date)?

    init(
        initialDate: Date = .now,
        calendar: Calendar = .current,
        cachedDailyLoader: (@Sendable (GoldMarketBasis) async -> [GoldDailyPrice]?)? = nil,
        dailyLoader: (@Sendable (GoldMarketBasis) async -> [GoldDailyPrice])? = nil,
        cachedTemperatureLoader: (@Sendable (MacroHistoryRange) async -> [MacroTemperatureHistoryPoint]?)? = nil,
        temperatureLoader: (@Sendable (MacroHistoryRange) async -> [MacroTemperatureHistoryPoint])? = nil
    ) {
        self.calendar = calendar
        let dayKey = CalendarDayKey(date: initialDate, calendar: calendar)
        self.selectedDate = dayKey.noonDate(calendar: calendar)
        self.focusedYear = dayKey.year
        self.focusedMonth = dayKey.month

        self.cachedDailyLoader = cachedDailyLoader ?? { basis in
            let service = BackendGoldPriceService(instrumentID: basis.instrumentID)
            return await service.cachedDailyPrices()
        }
        self.dailyLoader = dailyLoader ?? { basis in
            let service = BackendGoldPriceService(instrumentID: basis.instrumentID)
            return (try? await service.fetchDailyPrices()) ?? []
        }
        self.cachedTemperatureLoader = cachedTemperatureLoader ?? { range in
            let scope = SumlyProductionEndpoints.marketCacheScope(for: BackendGoldPriceService.defaultBaseURL)
            return await MacroTemperatureHistoryCache.shared.cached(scope: scope, range: range)
        }
        self.temperatureLoader = temperatureLoader ?? { range in
            let scope = SumlyProductionEndpoints.marketCacheScope(for: BackendGoldPriceService.defaultBaseURL)
            let service = BackendMacroService()
            return (try? await MacroTemperatureHistoryCache.shared.fetch(scope: scope, range: range, service: service)) ?? []
        }
    }

    // MARK: - 派生状态

    var hasAnyRecordsInScope: Bool {
        companionStats.hasAnyRecords
    }

    var availableLayers: [GoldCalendarLayer] {
        var result: [GoldCalendarLayer] = []
        if hasAnyRecordsInScope {
            result.append(.pnl)
        }
        result.append(.market)
        if hasTemperatureData {
            result.append(.temperature)
        }
        return result
    }

    var effectiveLayer: GoldCalendarLayer {
        if let userSelectedLayer, availableLayers.contains(userSelectedLayer) {
            return userSelectedLayer
        }
        return hasAnyRecordsInScope ? .pnl : .market
    }

    var focusedMonthDate: Date {
        CalendarDayKey(year: focusedYear, month: focusedMonth, day: 1).noonDate(calendar: calendar)
    }

    var focusedMonthSummary: GoldCalendarMonthSummary? {
        yearSnapshot?.monthSummary(focusedMonth)
    }

    var selectedDayKey: CalendarDayKey {
        CalendarDayKey(date: selectedDate, calendar: calendar)
    }

    var selectedDaySnapshot: GoldCalendarDaySnapshot? {
        let key = selectedDayKey
        if let snap = yearSnapshot?.daysByKey[key] {
            return snap
        }
        return nil
    }

    func isViewingToday(now: Date? = nil) -> Bool {
        let today = now.map { CalendarDayKey(date: $0, calendar: calendar) }
            ?? yearSnapshot?.todayKey
            ?? CalendarDayKey(date: .now, calendar: calendar)
        switch activeTab {
        case .month:
            return focusedYear == today.year && focusedMonth == today.month && selectedDayKey == today
        case .year:
            return focusedYear == today.year
        case .stats:
            return true
        }
    }

    func daySnapshot(for date: Date) -> GoldCalendarDaySnapshot? {
        let key = CalendarDayKey(date: date, calendar: calendar)
        return yearSnapshot?.daysByKey[key]
    }

    func selectLayer(_ layer: GoldCalendarLayer) {
        guard availableLayers.contains(layer) else { return }
        userSelectedLayer = layer
    }

    // MARK: - 导航操作（未来日期严格拦截）

    func selectDate(_ date: Date, now: Date = .now) {
        let targetKey = CalendarDayKey(date: date, calendar: calendar)
        let todayKey = CalendarDayKey(date: now, calendar: calendar)
        guard targetKey <= todayKey else { return }

        selectedDate = targetKey.noonDate(calendar: calendar)
        let yearChanged = (focusedYear != targetKey.year)
        focusedYear = targetKey.year
        focusedMonth = targetKey.month

        if yearChanged {
            recomputeFromLastInputsIfAvailable()
        }
    }

    func shiftMonth(by delta: Int, now: Date = .now) {
        let base = CalendarDayKey(year: focusedYear, month: focusedMonth, day: 1).noonDate(calendar: calendar)
        guard let shifted = calendar.date(byAdding: .month, value: delta, to: base) else { return }
        let shiftedKey = CalendarDayKey(date: shifted, calendar: calendar)
        let todayKey = CalendarDayKey(date: now, calendar: calendar)

        let yearChanged = (focusedYear != shiftedKey.year)
        focusedYear = shiftedKey.year
        focusedMonth = shiftedKey.month

        // 切月后选中日策略：若切到本月则自动聚焦今天；若是历史月则聚焦该月 1 日（不选未来日）。
        if focusedYear == todayKey.year && focusedMonth == todayKey.month {
            selectedDate = todayKey.noonDate(calendar: calendar)
        } else if shiftedKey <= todayKey {
            selectedDate = shiftedKey.noonDate(calendar: calendar)
        }

        if yearChanged {
            recomputeFromLastInputsIfAvailable()
        }
    }

    func selectYearMonth(year: Int, month: Int, now: Date = .now) {
        guard (1...12).contains(month) else { return }
        let todayKey = CalendarDayKey(date: now, calendar: calendar)
        let targetFirst = CalendarDayKey(year: year, month: month, day: 1)
        let yearChanged = (focusedYear != year)
        focusedYear = year
        focusedMonth = month

        if year == todayKey.year && month == todayKey.month {
            selectedDate = todayKey.noonDate(calendar: calendar)
        } else if targetFirst <= todayKey {
            selectedDate = targetFirst.noonDate(calendar: calendar)
        }

        if yearChanged {
            recomputeFromLastInputsIfAvailable()
        }
    }

    func shiftYear(by delta: Int, now: Date = .now) {
        let targetYear = focusedYear + delta
        guard targetYear >= 1990 && targetYear <= 2100 else { return }
        focusedYear = targetYear
        let todayKey = CalendarDayKey(date: now, calendar: calendar)
        if targetYear == todayKey.year {
            focusedMonth = todayKey.month
            selectedDate = todayKey.noonDate(calendar: calendar)
        } else if targetYear < todayKey.year {
            focusedMonth = 12
            selectedDate = CalendarDayKey(year: targetYear, month: 12, day: 1).noonDate(calendar: calendar)
        }
        recomputeFromLastInputsIfAvailable()
    }

    func jumpToToday(now: Date = .now) {
        let todayKey = CalendarDayKey(date: now, calendar: calendar)
        let yearChanged = (focusedYear != todayKey.year)
        focusedYear = todayKey.year
        focusedMonth = todayKey.month
        selectedDate = todayKey.noonDate(calendar: calendar)
        if yearChanged {
            recomputeFromLastInputsIfAvailable()
        }
    }

    func jumpToMonth(year: Int, month: Int, now: Date = .now) {
        activeTab = .month
        selectYearMonth(year: year, month: month, now: now)
    }

    func jumpToDay(_ dayKey: CalendarDayKey, now: Date = .now) {
        let todayKey = CalendarDayKey(date: now, calendar: calendar)
        guard dayKey <= todayKey else { return }
        activeTab = .month
        selectDate(dayKey.noonDate(calendar: calendar), now: now)
    }

    // MARK: - 市场与温度数据加载

    func loadMarketData(for basis: GoldMarketBasis, now: Date = .now) async {
        let preferredTempRange = MacroTemperatureHistoryCache.preferredRange(for: focusedYear, now: now, calendar: calendar)

        // 先尝试立即命中磁盘/内存缓存，消除冷启动闪烁。
        if rawDailyByBasis[basis] == nil, let cachedDaily = await cachedDailyLoader(basis), !cachedDaily.isEmpty {
            rawDailyByBasis[basis] = cachedDaily
            dailyRevision &+= 1
            recomputeFromLastInputsIfAvailable()
        }
        if rawTemperaturePoints.isEmpty, let cachedTemp = await cachedTemperatureLoader(preferredTempRange), !cachedTemp.isEmpty {
            rawTemperaturePoints = cachedTemp
            hasTemperatureData = true
            tempRevision &+= 1
            recomputeFromLastInputsIfAvailable()
        }

        isLoadingMarket = true
        defer { isLoadingMarket = false }

        async let fetchedDaily = dailyLoader(basis)
        async let fetchedTemp = temperatureLoader(preferredTempRange)

        let (daily, temp) = await (fetchedDaily, fetchedTemp)
        guard !Task.isCancelled else { return }

        var changed = false
        if !daily.isEmpty && daily != rawDailyByBasis[basis] {
            rawDailyByBasis[basis] = daily
            dailyRevision &+= 1
            changed = true
        }
        if !temp.isEmpty && (temp != rawTemperaturePoints || loadedTemperatureRange != preferredTempRange) {
            rawTemperaturePoints = temp
            loadedTemperatureRange = preferredTempRange
            hasTemperatureData = true
            tempRevision &+= 1
            changed = true
        }

        if changed {
            recomputeFromLastInputsIfAvailable()
        }
    }

    func ensureTemperatureCoverageIfNeeded(for year: Int, now: Date = .now) async {
        let needed = MacroTemperatureHistoryCache.preferredRange(for: year, now: now, calendar: calendar)
        guard needed == .all, loadedTemperatureRange != .all else { return }
        let fetched = await temperatureLoader(.all)
        guard !Task.isCancelled, !fetched.isEmpty else { return }
        if fetched != rawTemperaturePoints {
            rawTemperaturePoints = fetched
            loadedTemperatureRange = .all
            hasTemperatureData = true
            tempRevision &+= 1
            recomputeFromLastInputsIfAvailable()
        } else {
            loadedTemperatureRange = .all
        }
    }

    func clearCachedData() async {
        rawDailyByBasis.removeAll()
        rawTemperaturePoints.removeAll()
        loadedTemperatureRange = nil
        hasTemperatureData = false
        dailyRevision &+= 1
        tempRevision &+= 1
        lastComputeKey = nil
        await MacroTemperatureHistoryCache.shared.clear()
        recomputeFromLastInputsIfAvailable()
    }

    // MARK: - 核心同步入口（组合缓存键防重算 + 今日实时 O(1) 增量更新）

    func syncInputs(
        items: [CalendarHoldingItem],
        filter: HoldingCalendarFilter,
        basis: GoldMarketBasis,
        liveQuote: GoldQuote?,
        now: Date = .now
    ) {
        lastSyncInputs = (items, filter, basis, liveQuote, now)

        let filtered = GoldCalendarEngine.filterItems(items, filter: filter)
        let signature = Self.signature(for: filtered)
        let todayKey = CalendarDayKey(date: now, calendar: calendar)
        let liveInput = liveQuote.flatMap { CalendarLiveQuoteInput(quote: $0, basis: basis) }

        let fxBucket: Int = {
            guard basis == .international, let fx = liveInput?.usdCNY, fx.isFinite, fx > 0 else { return 0 }
            return Int((fx * 1000).rounded())
        }()

        let cacheKey = ComputeCacheKey(
            recordsSignature: signature,
            filter: filter,
            basis: basis,
            dailyRevision: dailyRevision,
            tempRevision: tempRevision,
            focusedYear: focusedYear,
            todayKey: todayKey,
            fxRateBucket: fxBucket
        )

        let companionKey = CompanionCacheKey(recordsSignature: signature, todayKey: todayKey)
        if lastCompanionKey != companionKey {
            companionStats = GoldCalendarEngine.computeCompanionStats(items: filtered, now: now, calendar: calendar)
            lastCompanionKey = companionKey
        }

        // 情况 A：缓存键一致，且仅有今日实时报价变化 -> 走 O(1) 增量补丁！
        if cacheKey == lastComputeKey, let existingSnapshot = yearSnapshot {
            guard liveInput != lastLiveQuoteInput else { return }
            lastLiveQuoteInput = liveInput
            yearSnapshot = GoldCalendarEngine.patchToday(
                in: existingSnapshot,
                items: cachedFilteredItems,
                dailyBars: cachedConvertedBars,
                liveQuote: liveInput,
                temperature: cachedTemperatureMap[todayKey],
                unlockedMilestones: companionStats.milestoneFirstReached[todayKey] ?? [],
                now: now,
                calendar: calendar
            )
            incrementalPatchCount &+= 1
            return
        }

        // 情况 B：持仓 / 筛选 / 口径 / 日线 / 温度 / 年份变化 -> 执行一次 Sweep-Line O(D + N log N)
        let rawDaily = rawDailyByBasis[basis] ?? []
        let convertedBars = GoldCalendarEngine.convertDailyBars(
            rawDaily,
            basis: basis,
            usdCNY: liveInput?.usdCNY,
            calendar: calendar
        )
        let tempMap = GoldCalendarEngine.temperatureMap(from: rawTemperaturePoints, calendar: calendar)

        cachedFilteredItems = filtered
        cachedConvertedBars = convertedBars
        cachedTemperatureMap = tempMap
        lastComputeKey = cacheKey
        lastLiveQuoteInput = liveInput

        yearSnapshot = GoldCalendarEngine.buildYearSnapshot(
            year: focusedYear,
            items: filtered,
            dailyBars: convertedBars,
            liveQuote: liveInput,
            temperatures: tempMap,
            milestoneFirstReached: companionStats.milestoneFirstReached,
            now: now,
            calendar: calendar
        )
        fullComputeCount &+= 1
    }

    /// 便于单测与模拟器可视化渲染直接注入确定性行情与温度数据。
    func applyDirectFixtures(
        dailyPrices: [GoldDailyPrice],
        temperaturePoints: [MacroTemperatureHistoryPoint],
        basis: GoldMarketBasis,
        items: [CalendarHoldingItem],
        filter: HoldingCalendarFilter = HoldingCalendarFilter(),
        liveQuote: GoldQuote? = nil,
        now: Date = .now
    ) {
        rawDailyByBasis[basis] = dailyPrices
        rawTemperaturePoints = temperaturePoints
        hasTemperatureData = !temperaturePoints.isEmpty
        dailyRevision &+= 1
        tempRevision &+= 1
        syncInputs(items: items, filter: filter, basis: basis, liveQuote: liveQuote, now: now)
    }

    // MARK: - 私有辅助

    private func recomputeFromLastInputsIfAvailable() {
        guard let last = lastSyncInputs else { return }
        syncInputs(items: last.items, filter: last.filter, basis: last.basis, liveQuote: last.liveQuote, now: last.now)
    }

    private static func signature(for items: [CalendarHoldingItem]) -> Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        for item in items {
            hasher.combine(item.id)
            hasher.combine(item.purchaseID)
            hasher.combine(item.grams.bitPattern)
            hasher.combine(item.purity.bitPattern)
            hasher.combine(item.unitPriceCNY.bitPattern)
            hasher.combine(item.totalPurchaseCost.bitPattern)
            hasher.combine(item.timestamp.timeIntervalSinceReferenceDate.bitPattern)
            hasher.combine(item.disposition)
            hasher.combine(item.disposedAt?.timeIntervalSinceReferenceDate.bitPattern ?? 0)
            hasher.combine(item.disposalAmount.bitPattern)
            hasher.combine(item.bookName)
            hasher.combine(item.brand)
            hasher.combine(item.assetType)
        }
        return hasher.finalize()
    }
}
