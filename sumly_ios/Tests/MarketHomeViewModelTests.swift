import Foundation
import Testing
@testable import Sumly

@MainActor @Test func marketHomeOpensWithThreeMonthRange() {
    #expect(MarketHomeViewModel().range == .quarter)
}

@MainActor private func waitForMarketCondition(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(25))
    }
}

private struct HomeMarketFixture: GoldPriceServicing, GoldQuoteServicing, GoldRealtimeServicing {
    var failing = false
    var usdCNY = 7.0
    func fetchQuote() async throws -> GoldQuote {
        if failing { throw URLError(.notConnectedToInternet) }
        return GoldQuote(symbol: "XAUUSD", price: 3100, open: 3000, high: 3150, low: 2900,
                         prevClose: 3000, usdCNY: usdCNY, cnyPerGram: usdCNY > 0 ? 697.67 : 0, asOf: .now)
    }
    func fetchDailyPrices() async throws -> [GoldDailyPrice] {
        if failing { throw URLError(.notConnectedToInternet) }
        return [5, 45, 120].map { days in
            GoldDailyPrice(date: Calendar.current.date(byAdding: .day, value: -days, to: .now)!,
                           open: 3000, high: 3100, low: 2900, close: 3000)
        }
    }
    func fetchRealtime() async throws -> [MarketChartPoint] {
        if failing { throw URLError(.notConnectedToInternet) }
        return [MarketChartPoint(date: .now.addingTimeInterval(-60), price: 675.25)]
    }
}

@MainActor @Test func homeKeepsRealtimeSamplePriceWithoutReconversionOrExtraQuote() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service)
    model.range = .realtime
    await model.refresh()
    #expect(model.price == 697.67)
    #expect(model.points.count == 1)
    #expect(model.points[0].price == 675.25)
}

private struct DomesticHistoryFixture: GoldHistoryServicing {
    let date = ChartViewport.noon(Calendar.current.date(byAdding: .day, value: -5, to: .now)!)
    func fetchHistory() async throws -> [GoldHistoryPoint] {
        [GoldHistoryPoint(date: date, price: 942.35, granularity: .daily, source: "sge-au9999")]
    }
}

private struct DomesticQuoteFixture: GoldQuoteServicing {
    func fetchQuote() async throws -> GoldQuote {
        GoldQuote(symbol: "AU9999", price: 945.20, open: 940, high: 946, low: 938,
                  prevClose: 941, usdCNY: 0, cnyPerGram: 945.20, asOf: .now)
    }
}

@MainActor @Test func domesticHistoryStaysInNativeCNYPerGramWithoutFXConversion() async {
    let service = HomeMarketFixture()
    let history = DomesticHistoryFixture()
    let model = MarketHomeViewModel(basis: .domestic, dailyService: service, quoteService: DomesticQuoteFixture(), realtimeService: service, historyService: history)
    model.range = .month
    await model.refresh()
    #expect(model.price == 945.20)
    #expect(model.points.count == 1)
    #expect(model.points.first?.price == 942.35)
    model.range = .history
    #expect(model.fullDomain.lowerBound == history.date)
}

private actor BasisSwitchGate {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private struct BasisSwitchFixture: GoldPriceServicing, GoldQuoteServicing, GoldRealtimeServicing, GoldHistoryServicing {
    let symbol: String
    let quotePrice: Double
    let historyPrice: Double
    let gate: BasisSwitchGate?

    func fetchQuote() async throws -> GoldQuote {
        if let gate { await gate.wait() }
        return GoldQuote(symbol: symbol, price: quotePrice, open: quotePrice, high: quotePrice, low: quotePrice,
                         prevClose: quotePrice, usdCNY: symbol == "AU9999" ? 0 : 7,
                         cnyPerGram: symbol == "AU9999" ? quotePrice : quotePrice * 7 / 31.1034768, asOf: .now)
    }

    func fetchDailyPrices() async throws -> [GoldDailyPrice] {
        if let gate { await gate.wait() }
        let date = ChartViewport.noon(Calendar.current.date(byAdding: .day, value: -5, to: .now)!)
        return [GoldDailyPrice(date: date, open: historyPrice, high: historyPrice, low: historyPrice, close: historyPrice)]
    }

    func fetchRealtime() async throws -> [MarketChartPoint] {
        if let gate { await gate.wait() }
        return [MarketChartPoint(date: .now.addingTimeInterval(-1), price: symbol == "AU9999" ? quotePrice : quotePrice * 7 / 31.1034768)]
    }

    func fetchHistory() async throws -> [GoldHistoryPoint] {
        if let gate { await gate.wait() }
        let date = ChartViewport.noon(Calendar.current.date(byAdding: .day, value: -5, to: .now)!)
        return [GoldHistoryPoint(date: date, price: historyPrice, granularity: .daily, source: "fixture")]
    }
}

@MainActor @Test func basisSwitchKeepsExistingPageStateUntilNewSnapshotIsReady() async {
    let international = BasisSwitchFixture(symbol: "XAUUSD", quotePrice: 3100, historyPrice: 3000, gate: nil)
    let gate = BasisSwitchGate()
    let domestic = BasisSwitchFixture(symbol: "AU9999", quotePrice: 945.2, historyPrice: 942.35, gate: gate)
    let model = MarketHomeViewModel(
        basis: .international,
        dailyService: international,
        quoteService: international,
        realtimeService: international,
        historyService: international,
        serviceFactory: { basis in
            let service = basis == .domestic ? domestic : international
            return MarketHomeDataServices(daily: service, quote: service, realtime: service, history: service)
        }
    )
    await model.refresh()
    model.range = .month
    model.priceScale = .logarithmic
    let oldPrice = model.price
    let oldPoints = model.points

    let switching = Task { await model.switchBasis(to: .domestic) }
    await Task.yield()

    #expect(model.basis == .international)
    #expect(model.price == oldPrice)
    #expect(model.points == oldPoints)
    #expect(model.range == .month)
    #expect(model.priceScale == .logarithmic)

    await gate.release()
    #expect(await switching.value)
    #expect(model.basis == .domestic)
    #expect(model.price == 945.2)
    #expect(model.points.map(\.price) == [942.35])
    #expect(model.range == .month)
    #expect(model.priceScale == .logarithmic)
}

@MainActor @Test func homeRangesUseRealDailyDates() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service)
    model.range = .realtime
    await model.refresh()
    model.range = .month
    #expect(model.windowPoints.count == 1)
    model.range = .quarter
    #expect(model.windowPoints.count == 2)
}

@MainActor @Test func homeNetworkFailureDoesNotDisplayReferencePrice() async {
    let service = HomeMarketFixture(failing: true)
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service)
    model.range = .realtime
    await model.refresh()
    #expect(model.price == nil)
    #expect(model.points.isEmpty)
    #expect(model.message != nil)
}

@MainActor @Test func homeMissingFXDoesNotShowZeroAsGoldPrice() async {
    let service = HomeMarketFixture(usdCNY: 0)
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service)
    model.range = .realtime
    await model.refresh()
    #expect(model.price == nil)
    #expect(model.points.count == 1) // 已采集的人民币报价不依赖当前汇率。
    #expect(model.message != nil)
}

@Test func realtimeWindowKeepsFullContinuousSessionAndExcludesPriorSessionOrOver12hHistory() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    // Overnight break (>6h, e.g. 02:30 -> 09:00 = 6.5h) must be excluded.
    let priorSession = [
        MarketChartPoint(date: now.addingTimeInterval(-10 * 3600), price: 880, intervalSeconds: 60),
        MarketChartPoint(date: now.addingTimeInterval(-7.5 * 3600), price: 885, intervalSeconds: 60)
    ]
    let currentSamples = (0..<300).map {
        MarketChartPoint(date: now.addingTimeInterval(Double(-$0 * 5)), price: Double(900 + $0))
    }
    let window = MarketHomeViewModel.realtimeWindow(priorSession + currentSamples, now: now)
    #expect(window.count == 300)
    #expect(window.first?.date == now.addingTimeInterval(-1495))
    #expect(window.last?.price == 900)
    #expect(window.last?.date == now)

    // Continuous 28-hour stream without gaps is capped at 24 hours.
    let longStream = (0...336).map {
        MarketChartPoint(date: now.addingTimeInterval(Double($0 - 336) * 300), price: 910, intervalSeconds: 60)
    }
    let capped = MarketHomeViewModel.realtimeWindow(longStream, now: now)
    #expect(capped.first?.date == now.addingTimeInterval(-24 * 3600))
    #expect(capped.last?.date == now)

    // SGE day + night session (2h lunch + 4.5h afternoon-to-night break <= 6h) stays intact as one continuous trading day.
    let dayStart = now.addingTimeInterval(-13.5 * 3600)
    let dayMorning = [
        MarketChartPoint(date: dayStart, price: 920, intervalSeconds: 60),
        MarketChartPoint(date: dayStart.addingTimeInterval(2.5 * 3600), price: 922, intervalSeconds: 60)
    ]
    let dayAfternoon = [
        MarketChartPoint(date: dayStart.addingTimeInterval(4.5 * 3600), price: 923, intervalSeconds: 60),
        MarketChartPoint(date: dayStart.addingTimeInterval(6.5 * 3600), price: 925, intervalSeconds: 60)
    ]
    let nightSession = [
        MarketChartPoint(date: dayStart.addingTimeInterval(11.0 * 3600), price: 926, intervalSeconds: 60),
        MarketChartPoint(date: now, price: 928, intervalSeconds: 60)
    ]
    let fullDay = MarketHomeViewModel.realtimeWindow(dayMorning + dayAfternoon + nightSession, now: now)
    #expect(fullDay.count == 6)
    #expect(fullDay.first?.date == dayStart)
}

@Test func realtimeWindowDoesNotSynthesizeMissingSamples() {
    let now = Date.now
    let points = [MarketChartPoint(date: now.addingTimeInterval(-120), price: 938),
                  MarketChartPoint(date: now, price: 939)]
    #expect(MarketHomeViewModel.realtimeWindow(points, now: now) == points)
}

@Test func realtimeYAxisDoesNotAmplifyTinyMovements() {
    let points = [MarketChartPoint(date: .now, price: 938.2), MarketChartPoint(date: .now, price: 938.21)]
    let domain = MarketHomeViewModel.chartDomain(points)
    #expect(domain.upperBound - domain.lowerBound >= 1)
    #expect(domain == MarketHomeViewModel.chartDomain([MarketChartPoint(date: .now, price: 938.22)]))
}

@MainActor @Test func chartSelectionUsesSamplePriceAndClearsOnRangeChange() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service)
    model.range = .realtime
    await model.refresh()
    model.selectedDate = model.points.first?.date
    #expect(model.selectedPoint?.price == 675.25)
    model.range = .month
    #expect(model.selectedPoint == nil)
}

@MainActor @Test func chartSelectionExpiresAfterFiveSecondsAndRestoresExtrema() async throws {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service)
    model.range = .realtime
    await model.refresh()
    model.selectChart(at: 0.5)
    #expect(model.selectedPoint?.price == 675.25)
    let snapshot = model.makeDisplaySnapshot()
    try await waitForMarketCondition { model.selectedDate == nil }
    #expect(model.selectedDate == nil)
    #expect(model.selectedPoint == nil)
    #expect(model.windowStatistics.high?.price == 675.25)
    #expect(model.windowStatistics.low?.price == 675.25)
    // The outgoing animation layer must remain frozen rather than start timers.
    #expect(snapshot.selectedPoint?.price == 675.25)
}

@MainActor @Test func selectingAgainRestartsFiveSecondExpiryEvenAtTheSamePosition() async throws {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service)
    model.range = .realtime
    await model.refresh()
    model.selectChart(at: 0.5)
    try await Task.sleep(for: .seconds(3))
    model.selectChart(at: 0.5)
    let latestSelection = model.selectedDate
    try await Task.sleep(for: .seconds(2.4))
    #expect(model.selectedDate == latestSelection)
    #expect(model.selectedPoint?.price == 675.25)
    try await waitForMarketCondition { model.selectedDate == nil }
    #expect(model.selectedDate == nil)
}

@Test func flatPriceDomainAlwaysHasOneYuanOfRoom() {
    for value in [938.0, 938.1, 938.25, 938.5, 938.75] {
        let domain = MarketHomeViewModel.chartDomain([MarketChartPoint(date: .now, price: value)])
        #expect(domain.upperBound - domain.lowerBound >= 1)
    }
}

@MainActor @Test func initialLoadingEndsOnSuccessAndFailure() async {
    for failing in [false, true] {
        let service = HomeMarketFixture(failing: failing)
        let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service)
        model.range = .realtime
        #expect(model.showsInitialLoading)
        await model.refresh()
        #expect(!model.showsInitialLoading)
        if failing { #expect(model.message != nil) }
    }
}

@Test func realtimeWindowRemainsAtLastAvailableSessionDuringClosure() {
    let last = Date(timeIntervalSince1970: 1_789_764_840)
    let start = last.addingTimeInterval(-23400) // 6.5h trading session
    let points = (0..<256).map { index in
        let date = start.addingTimeInterval(Double(index) * (23400.0 / 255.0))
        return MarketChartPoint(date: date, price: 773.48 - Double(index) * 0.05, intervalSeconds: 60)
    }
    let result = MarketHomeViewModel.realtimeWindow(points, now: last.addingTimeInterval(48 * 3600))
    #expect(result.count == 256)
    #expect(result.first?.date == start)
    #expect(result.last?.date == last)
}

private struct HomeHistoryFixture: GoldHistoryServicing {
    var failing = false
    func fetchHistory() async throws -> [GoldHistoryPoint] {
        if failing { throw URLError(.notConnectedToInternet) }
        return [GoldHistoryPoint(date: GoldDailyPrice.parseDay("1900-07-01")!, price: 19, granularity: .annual, source: "usgs-ds140"),
                GoldHistoryPoint(date: GoldDailyPrice.parseDay("2015-07-01")!, price: 1163, granularity: .annual, source: "usgs-ds140"),
                GoldHistoryPoint(date: GoldDailyPrice.parseDay("2016-01-04")!, price: 1074, granularity: .daily, source: "sina-xauusd")]
    }
}
@MainActor @Test func historyKeepsGranularityAndPinchStateAcrossQuoteRefresh() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service, historyService: HomeHistoryFixture())
    model.range = .history
    await model.refresh()
    #expect(model.points.count == 3)
    #expect(model.points.first?.granularity == .annual)
    #expect(abs(model.points[0].price - 19 * 7 / 31.1034768) < 0.000001)
    #expect(model.fullDomain.lowerBound == GoldDailyPrice.parseDay("1900-01-01"))
    model.beginChartGesture()
    model.transformChart(scale: 10, anchor: 1, translation: 0)
    model.endChartGesture()
    let window = model.xDomain
    #expect(window.lowerBound > model.fullDomain.lowerBound)
    await model.refresh()
    #expect(model.xDomain == window)
    model.range = .month
    #expect(model.viewport == nil)
    #expect(model.selectedDate == nil)
}
@MainActor @Test func unavailableHistoryDoesNotPretendOneLiveQuoteIsCenturyOfHistory() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service, historyService: HomeHistoryFixture(failing: true))
    model.range = .history
    await model.refresh()
    #expect(model.points.isEmpty)
    #expect(model.message?.contains("历史走势加载失败") == true)
}

@MainActor @Test func zoomedAnnualPointCanBeInspectedAcrossItsYear() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service, historyService: HomeHistoryFixture())
    model.range = .history
    await model.refresh()
    model.beginChartGesture()
    model.transformChart(scale: 10000, anchor: 0, translation: 0)
    model.endChartGesture()
    model.selectChart(at: 0.1)
    #expect(model.selectedPoint?.date == GoldDailyPrice.parseDay("1900-07-01"))
}
private actor AdvancingRealtimeFixture: GoldRealtimeServicing {
    var end = Date.now.addingTimeInterval(-900)
    func advance() { end = end.addingTimeInterval(900) }
    func fetchRealtime() async throws -> [MarketChartPoint] {
        (0...240).map { MarketChartPoint(date: end.addingTimeInterval(Double($0 - 240) * 5), price: 900) }
    }
}
@MainActor @Test func rollingRealtimeWindowClampsOldZoomWithoutGoingBlank() async {
    let service = HomeMarketFixture()
    let realtime = AdvancingRealtimeFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: realtime)
    model.range = .realtime
    await model.refresh()
    model.beginChartGesture()
    model.transformChart(scale: 100, anchor: 0, translation: 0)
    model.endChartGesture()
    await realtime.advance()
    await model.refresh()
    #expect(model.xDomain.lowerBound >= model.fullDomain.lowerBound)
    #expect(model.xDomain.upperBound.timeIntervalSince(model.xDomain.lowerBound) == 30)
    #expect(model.visiblePoints.contains { model.xDomain.contains($0.date) })
}

@MainActor @Test func nonRealtimeChartUsesDayAlignedDatesAndCannotLeavePreset() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service, historyService: HomeHistoryFixture())
    model.range = .month
    await model.refresh()
    #expect(model.points.allSatisfy { Calendar.current.component(.hour, from: $0.date) == 12 && Calendar.current.component(.second, from: $0.date) == 0 })
    let preset = model.xDomain
    model.beginNavigatorGesture()
    model.moveNavigator(part: .window, fraction: -0.5)
    model.endChartGesture()
    #expect(model.xDomain == preset)
    #expect(Calendar.current.dateComponents([.day], from: model.xDomain.lowerBound, to: model.xDomain.upperBound).day == Calendar.current.dateComponents([.day], from: preset.lowerBound, to: preset.upperBound).day)
    model.resetViewport()
    #expect(model.xDomain == preset)
}
@MainActor @Test func dailyZoomAndDateSelectionNeverCreateSecondScaleWindows() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service, historyService: HomeHistoryFixture())
    model.range = .quarter
    await model.refresh()
    model.accessibleZoom(100000)
    #expect(Calendar.current.dateComponents([.day], from: model.xDomain.lowerBound, to: model.xDomain.upperBound).day! >= 1)
    #expect(Calendar.current.component(.hour, from: model.xDomain.lowerBound) == 12)
    #expect(Calendar.current.component(.second, from: model.xDomain.upperBound) == 0)
    #expect(model.axisDates.allSatisfy { Calendar.current.component(.hour, from: $0) == 12 })
}

private struct ClosedDayHistoryFixture: GoldHistoryServicing {
    func fetchHistory() async throws -> [GoldHistoryPoint] {
        [-2, -1, 0].map { offset in
            GoldHistoryPoint(date: Calendar.current.date(byAdding: .day, value: offset, to: ChartViewport.noon(.now))!, price: Double(3000 + offset), granularity: .daily, source: "test")
        }
    }
}
@MainActor @Test func nonRealtimeChartStopsYesterdayAndNeverAppendsLiveQuote() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service, historyService: ClosedDayHistoryFixture())
    for range in [MarketRange.month, .quarter, .history] {
        model.range = range
        await model.refresh()
        let yesterday = ChartViewport.noon(Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        #expect(model.points.count == 2)
        #expect(model.points.last?.date == yesterday)
        #expect(model.fullDomain.upperBound == yesterday)
        #expect(model.points.allSatisfy { $0.granularity == .daily })
    }
}

private struct YesterdayOnlyFixture: GoldPriceServicing {
    func fetchDailyPrices() async throws -> [GoldDailyPrice] {
        let yesterday = ChartViewport.noon(Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        return [GoldDailyPrice(date: yesterday, open: 3000, high: 3000, low: 3000, close: 3000)]
    }
}
@MainActor @Test func singleYesterdayObservationNeverExtendsDomainIntoToday() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: YesterdayOnlyFixture(), quoteService: service, realtimeService: service, historyService: HomeHistoryFixture(failing: true))
    model.range = .month
    await model.refresh()
    let yesterday = ChartViewport.noon(Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
    #expect(model.fullDomain.upperBound == yesterday)
    #expect(model.fullDomain.lowerBound < yesterday)
    #expect(model.xDomain.upperBound == yesterday)
}

private struct LargeHomeHistoryFixture: GoldHistoryServicing {
    func fetchHistory() async throws -> [GoldHistoryPoint] {
        let end = ChartViewport.noon(.now)
        return (1...5308).map { day in
            GoldHistoryPoint(date: end.addingTimeInterval(Double(-day) * 86400), price: Double(2000 + day % 100), granularity: .daily, source: "fixture")
        }
    }
}

@MainActor @Test func historicalViewportReadsStayWithinInteractionBudget() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service, historyService: LargeHomeHistoryFixture())
    model.range = .month
    await model.refresh()
    let start = ContinuousClock.now
    var count = 0
    // Repeated SwiftUI body, axis and navigator reads while switching/panning.
    for _ in 0..<20 {
        count += model.visiblePoints.count + model.windowPoints.count + model.axisDates.count
        _ = model.fullDomain
        _ = model.canReset
    }
    let elapsed = start.duration(to: .now)
    print("HOME_PERF repeated viewport reads: \(elapsed)")
    #expect(count > 0)
    #expect(elapsed < .milliseconds(500))
}

private actor MutableHomeHistoryFixture: GoldHistoryServicing, GoldQuoteServicing {
    let date = ChartViewport.noon(Date.now.addingTimeInterval(-86400))
    var value = 2000.0
    var fx = 7.0
    func change(value: Double, fx: Double) { self.value = value; self.fx = fx }
    func fetchHistory() async throws -> [GoldHistoryPoint] {
        [GoldHistoryPoint(date: date, price: value, granularity: .daily, source: "fixture")]
    }
    func fetchQuote() async throws -> GoldQuote {
        GoldQuote(symbol: "XAUUSD", price: value, open: value, high: value, low: value,
                  prevClose: value, usdCNY: fx, cnyPerGram: value * fx / 31.1034768, asOf: .now)
    }
}

@MainActor @Test func preparedHistoryReflectsCorrectionsFXAndCacheClear() async {
    let daily = HomeMarketFixture()
    let history = MutableHomeHistoryFixture()
    let model = MarketHomeViewModel(dailyService: daily, quoteService: history, realtimeService: daily, historyService: history)
    model.range = .month
    await model.refresh()
    #expect(abs(model.points[0].price - 2000 * 7 / 31.1034768) < 0.000001)
    await history.change(value: 2200, fx: 7)
    await model.refresh()
    #expect(abs(model.points[0].price - 2200 * 7 / 31.1034768) < 0.000001)
    await history.change(value: 2200, fx: 8)
    await model.refresh()
    #expect(abs(model.points[0].price - 2200 * 8 / 31.1034768) < 0.000001)
    model.clearMarketCache()
    #expect(model.points.isEmpty)
    await model.refresh()
    #expect(abs(model.points[0].price - 2200 * 8 / 31.1034768) < 0.000001)
}

@Test func calendarRangesRespectYesterdayLeapYearsAndYearStart() {
    let now = GoldDailyPrice.parseDay("2024-03-01")!
    #expect(MarketRange.year.dateBounds(now: now)?.lowerBound == GoldDailyPrice.parseDay("2023-02-28"))
    #expect(MarketRange.yearToDate.dateBounds(now: now)?.lowerBound == GoldDailyPrice.parseDay("2024-01-01"))
    #expect(MarketRange.tenYears.dateBounds(now: now)?.lowerBound == GoldDailyPrice.parseDay("2014-02-28"))
    #expect(MarketRange.yearToDate.dateBounds(now: GoldDailyPrice.parseDay("2024-01-01")!) == nil)
}

@MainActor @Test func everyHistoricalRangeClampsAllNavigationAndFiltersData() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service, historyService: LargeHomeHistoryFixture())
    model.range = .month
    await model.refresh()
    for range in MarketRange.allCases where range != .realtime {
        model.range = range
        let bounds = model.fullDomain
        #expect(model.points.allSatisfy { bounds.contains($0.date) })
        model.accessibleZoom(0.00001)
        #expect(model.xDomain == bounds)
        model.accessibleZoom(10)
        for part in [ChartViewport.Part.window, .start, .end] {
            for fraction in [-100.0, 100.0] {
                model.beginNavigatorGesture()
                model.moveNavigator(part: part, fraction: fraction)
                model.endChartGesture()
                #expect(model.xDomain.lowerBound >= bounds.lowerBound)
                #expect(model.xDomain.upperBound <= bounds.upperBound)
            }
        }
        model.setDateWindow(Date.distantPast...Date.distantFuture)
        #expect(model.xDomain == bounds)
        model.priceScale = .logarithmic
        model.resetViewport()
        #expect(model.xDomain == bounds)
        #expect(model.priceScale == .logarithmic)
    }
}

@Test func singleDayBoundsCannotExpandOutsideSelectedRange() {
    let date = GoldDailyPrice.parseDay("2026-01-01")!
    let bounds = date...date
    #expect(ChartViewport.dayAligned(bounds, bounds: bounds) == bounds)
    #expect(ChartViewport.navigate(bounds, part: .end, fraction: 1, bounds: bounds) == bounds)
}

@MainActor @Test func viewportStatisticsFollowNavigatorAndIgnorePriceScale() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service, historyService: LargeHomeHistoryFixture())
    model.range = .quarter
    await model.refresh()
    let original = model.windowStatistics
    model.beginNavigatorGesture()
    model.moveNavigator(part: .start, fraction: 0.8)
    model.endChartGesture()
    let resized = model.windowStatistics
    #expect(resized.first?.date != original.first?.date)
    #expect(resized.high == model.windowPoints.max(by: { $0.price < $1.price }))
    model.beginNavigatorGesture()
    model.moveNavigator(part: .window, fraction: -0.5)
    model.endChartGesture()
    #expect(model.windowStatistics.first?.date != resized.first?.date)
    let moved = model.windowStatistics
    model.priceScale = .logarithmic
    #expect(model.windowStatistics == moved)
    model.resetViewport()
    #expect(model.windowStatistics == original)
}


private actor RecoveringHomeService: GoldPriceServicing, GoldQuoteServicing, GoldRealtimeServicing {
    var realtimeCalls = 0
    private let retryGate = BasisSwitchGate()
    let slowDaily: Bool
    let emptyAfterFirst: Bool
    init(slowDaily: Bool = false, emptyAfterFirst: Bool = false) {
        self.slowDaily = slowDaily; self.emptyAfterFirst = emptyAfterFirst
    }
    func fetchQuote() async throws -> GoldQuote { try await HomeMarketFixture().fetchQuote() }
    func fetchDailyPrices() async throws -> [GoldDailyPrice] {
        if slowDaily { try await Task.sleep(for: .seconds(60)) }
        return try await HomeMarketFixture().fetchDailyPrices()
    }
    func fetchRealtime() async throws -> [MarketChartPoint] {
        realtimeCalls += 1
        if slowDaily && realtimeCalls == 1 { throw URLError(.networkConnectionLost) }
        if slowDaily { await retryGate.wait() }
        if emptyAfterFirst && realtimeCalls > 1 { return [] }
        return try await HomeMarketFixture().fetchRealtime()
    }
    func releaseRetry() async { await retryGate.release() }
}

@MainActor @Test func slowDailySyncDoesNotHideRealtimeFailureOrBlockItsRetry() async throws {
    let service = RecoveringHomeService(slowDaily: true)
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service)
    model.range = .realtime
    let task = Task { await model.start() }
    // Daily sync is still pending. A failed realtime request must leave loading,
    // then recover through its own five-second polling schedule.
    try await waitForMarketCondition { !model.loading }
    #expect(!model.loading)
    #expect(model.message?.contains("失败") == true)
    await service.releaseRetry()
    try await waitForMarketCondition { !model.points.isEmpty }
    #expect(await service.realtimeCalls >= 2)
    #expect(!model.points.isEmpty)
    task.cancel()
    await task.value
}

@MainActor @Test func emptyRealtimeRefreshRetainsVisibleCurveAndOffersRetry() async {
    let service = RecoveringHomeService(emptyAfterFirst: true)
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service)
    model.range = .realtime
    await model.refresh()
    let previous = model.points
    await model.refresh()
    #expect(!previous.isEmpty)
    #expect(model.points == previous)
    #expect(model.message?.contains("失败") == true)
}


private actor SuspendedRealtimeService: GoldRealtimeServicing {
    private var calls = 0
    private var pending: [Int: CheckedContinuation<[MarketChartPoint], Never>] = [:]
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    func fetchRealtime() async throws -> [MarketChartPoint] {
        calls += 1
        let id = calls
        return await withCheckedContinuation { continuation in
            pending[id] = continuation
            waiters.removeValue(forKey: id)?.resume()
        }
    }
    func waitForCall(_ id: Int) async {
        if calls >= id { return }
        await withCheckedContinuation { waiters[id] = $0 }
    }
    func resolve(_ id: Int, price: Double) {
        pending.removeValue(forKey: id)?.resume(returning: [MarketChartPoint(date: .now.addingTimeInterval(-1), price: price)])
    }
}

@MainActor @Test func olderRefreshCannotReplaceNewerRealtimeResponse() async {
    let service = SuspendedRealtimeService()
    let fixture = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: fixture, quoteService: fixture, realtimeService: service)
    model.range = .realtime
    let first = Task { await model.refresh() }
    await service.waitForCall(1)
    let second = Task { await model.refresh() }
    await service.waitForCall(2)
    await service.resolve(2, price: 800)
    await second.value
    await service.resolve(1, price: 700)
    await first.value
    #expect(model.points.first?.price == 800)
    #expect(!model.chartLoading)
}

@MainActor @Test func foregroundRestartSurvivesLateCancelledRequest() async {
    let service = SuspendedRealtimeService()
    let fixture = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: fixture, quoteService: fixture, realtimeService: service)
    model.range = .realtime
    let backgrounded = Task { await model.start() }
    await service.waitForCall(1)
    backgrounded.cancel()
    let foreground = Task { await model.start() }
    await service.waitForCall(2)
    await service.resolve(1, price: 700)
    await backgrounded.value
    #expect(model.chartLoading) // Old cancellation must not finish the new load.
    #expect(model.points.isEmpty)
    await service.resolve(2, price: 800)
    // Await the actor-isolated response application without a wall-clock delay.
    for _ in 0..<1000 {
        if !model.chartLoading { break }
        await Task.yield()
    }
    #expect(model.points.first?.price == 800)
    #expect(!model.chartLoading)
    foreground.cancel()
    await foreground.value
    #expect(model.points.first?.price == 800)
}


@MainActor @Test func basisTransitionCapturesOldPricesBeforeAtomicCommit() async {
    let international = BasisSwitchFixture(symbol: "XAUUSD", quotePrice: 3100, historyPrice: 3000, gate: nil)
    let domestic = BasisSwitchFixture(symbol: "AU9999", quotePrice: 945.2, historyPrice: 942.35, gate: nil)
    let model = MarketHomeViewModel(basis: .international, dailyService: international,
        quoteService: international, realtimeService: international, historyService: international,
        serviceFactory: { _ in MarketHomeDataServices(daily: domestic, quote: domestic, realtime: domestic, history: domestic) })
    model.range = .month
    model.priceScale = .logarithmic
    await model.refresh()
    model.setDateWindow(model.fullDomain)
    let originalPoints = model.points
    let originalPrice = model.price
    let originalWindow = model.xDomain
    var outgoing: MarketHomeViewModel?
    var commits = 0
    let switched = await model.switchBasis(to: .domestic, beforeCommit: {
        commits += 1
        outgoing = model.makeDisplaySnapshot()
        #expect(model.basis == .international)
    })
    #expect(switched)
    #expect(commits == 1)
    #expect(outgoing?.basis == .international)
    #expect(outgoing?.price == originalPrice)
    #expect(outgoing?.points == originalPoints)
    #expect(outgoing?.xDomain == originalWindow)
    #expect(outgoing?.priceScale == .logarithmic)
    #expect(model.price == 945.2)
    #expect(model.range == .month)
    #expect(model.priceScale == .logarithmic)
    model.clearMarketCache()
    #expect(outgoing?.points == originalPoints)
    #expect(outgoing?.price == originalPrice)
}

@MainActor @Test func failedBasisSwitchDoesNotBeginDisplayTransition() async {
    let service = HomeMarketFixture()
    let failure = HomeMarketFixture(failing: true)
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service,
        serviceFactory: { _ in MarketHomeDataServices(daily: failure, quote: failure, realtime: failure, history: DomesticHistoryFixture()) })
    model.range = .realtime
    await model.refresh()
    let old = model.points
    var commits = 0
    #expect(await model.switchBasis(to: .domestic, beforeCommit: { commits += 1 }) == false)
    #expect(commits == 0)
    #expect(model.basis == .international)
    #expect(model.points == old)
    #expect(!model.isSwitchingBasis)
}


private struct FailingRealtimeOnly: GoldRealtimeServicing {
    func fetchRealtime() async throws -> [MarketChartPoint] { throw URLError(.networkConnectionLost) }
}

@MainActor @Test func successfulQuoteWithFailedSelectedChartKeepsOldBasis() async {
    let service = HomeMarketFixture()
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service,
        serviceFactory: { _ in MarketHomeDataServices(daily: service, quote: DomesticQuoteFixture(), realtime: FailingRealtimeOnly(), history: DomesticHistoryFixture()) })
    model.range = .realtime
    await model.refresh()
    let old = model.points
    var commits = 0
    #expect(await model.switchBasis(to: .domestic, beforeCommit: { commits += 1 }) == false)
    #expect(model.basis == .international)
    #expect(model.points == old)
    #expect(commits == 0)
}

private actor DelayedFailingHistory: GoldHistoryServicing {
    private var pending: CheckedContinuation<[GoldHistoryPoint], Error>?
    private var started: CheckedContinuation<Void, Never>?
    func fetchHistory() async throws -> [GoldHistoryPoint] {
        try await withCheckedThrowingContinuation {
            pending = $0
            started?.resume(); started = nil
        }
    }
    func waitForStart() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func fail() { pending?.resume(throwing: URLError(.networkConnectionLost)); pending = nil }
}

@MainActor @Test func oldHistoryFailureCannotMarkNewBasisAsFailed() async {
    let service = HomeMarketFixture()
    let history = DelayedFailingHistory()
    let domestic = BasisSwitchFixture(symbol: "AU9999", quotePrice: 945.2, historyPrice: 942.35, gate: nil)
    let model = MarketHomeViewModel(dailyService: service, quoteService: service, realtimeService: service, historyService: history,
        serviceFactory: { _ in MarketHomeDataServices(daily: domestic, quote: domestic, realtime: domestic, history: domestic) })
    model.range = .realtime
    await model.refresh()
    model.range = .history
    let loading = Task { await model.loadHistory() }
    await history.waitForStart()
    #expect(await model.switchBasis(to: .domestic))
    await history.fail()
    await loading.value
    #expect(model.basis == .domestic)
    #expect(model.message?.contains("失败") != true)
    #expect(!model.points.isEmpty)
}


@MainActor @Test func cancelledBasisSwitchAllowsImmediateRetryBeforeTransportFinishes() async {
    let original = HomeMarketFixture()
    let gate = BasisSwitchGate()
    let domestic = BasisSwitchFixture(symbol: "AU9999", quotePrice: 945.2, historyPrice: 942.35, gate: gate)
    let model = MarketHomeViewModel(dailyService: original, quoteService: original, realtimeService: original,
        serviceFactory: { _ in MarketHomeDataServices(daily: domestic, quote: domestic, realtime: domestic, history: domestic) })
    model.range = .realtime
    await model.refresh()
    let first = Task { await model.switchBasis(to: .domestic) }
    for _ in 0..<1000 {
        if model.isSwitchingBasis { break }
        await Task.yield()
    }
    #expect(model.isSwitchingBasis)
    first.cancel()
    model.cancelBasisSwitch()
    #expect(!model.isSwitchingBasis)
    var commits = 0
    let retry = Task { await model.switchBasis(to: .domestic, beforeCommit: { commits += 1 }) }
    await gate.release()
    #expect(await first.value == false)
    #expect(await retry.value)
    #expect(commits == 1)
    #expect(model.basis == .domestic)
    #expect(model.price == 945.2)
    #expect(!model.isSwitchingBasis)
}

private actor SessionAppendRealtimeFixture: GoldPriceServicing, GoldQuoteServicing, GoldRealtimeServicing {
    private var samples: [MarketChartPoint]
    private var quoteTime: Date

    init(initialSamples: [MarketChartPoint], quoteTime: Date) {
        self.samples = initialSamples
        self.quoteTime = quoteTime
    }

    func setSamples(_ next: [MarketChartPoint], quoteTime: Date) {
        self.samples = next
        self.quoteTime = quoteTime
    }

    func fetchDailyPrices() async throws -> [GoldDailyPrice] { [] }
    func fetchQuote() async throws -> GoldQuote {
        let lastPrice = samples.last?.price ?? 755.01
        return GoldQuote(symbol: "AU9999", price: lastPrice, open: 773.48, high: 775, low: 754,
                         prevClose: 770, usdCNY: 0, cnyPerGram: lastPrice, asOf: quoteTime)
    }
    func fetchRealtime() async throws -> [MarketChartPoint] { samples }
}

@MainActor @Test func nightSessionLoadsFullCrossMidnightPointsAndPreservesEarlyPointsOnLiveAppend() async {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    // Build a 6.5h cross-midnight night session (20:00 -> 02:30, 256 points) anchored safely in the past.
    let anchorDay = calendar.date(byAdding: .day, value: -2, to: .now)!
    let sessionStart = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: anchorDay)!
    let sessionSpan: TimeInterval = 6.5 * 3600 // 23400s -> next day 02:30
    let sessionEnd = sessionStart.addingTimeInterval(sessionSpan)
    let nightSession: [MarketChartPoint] = (0..<256).map { index in
        let offset = sessionSpan * Double(index) / 255.0
        return MarketChartPoint(
            date: sessionStart.addingTimeInterval(offset),
            price: 773.48 - Double(index) * 0.072,
            intervalSeconds: 60
        )
    }
    let fixture = SessionAppendRealtimeFixture(initialSamples: nightSession, quoteTime: sessionEnd)
    let model = MarketHomeViewModel(basis: .domestic, dailyService: fixture, quoteService: fixture, realtimeService: fixture)
    model.range = .realtime

    await model.refresh()
    #expect(model.points.count == 256)
    #expect(model.points.first?.date == sessionStart)
    #expect(model.points.last?.date == sessionEnd)
    #expect(model.fullDomain.lowerBound == sessionStart)
    #expect(model.fullDomain.upperBound == sessionEnd)
    #expect(model.realtimeTiming.isSessionWindow)

    // Subsequent live poll appends a trailing 5s tick (even if server returned only the incremental tail);
    // early session points from 20:00 must stay intact.
    let tailTick1 = MarketChartPoint(date: sessionEnd.addingTimeInterval(5), price: 755.30, intervalSeconds: 5)
    await fixture.setSamples([tailTick1], quoteTime: tailTick1.date)
    await model.refresh()
    #expect(model.points.count == 257)
    #expect(model.points.first?.date == sessionStart)
    #expect(model.points.last == tailTick1)
    #expect(model.fullDomain == sessionStart...tailTick1.date)

    // Full-session refresh with another trailing tick keeps all 258 points cleanly.
    let tailTick2 = MarketChartPoint(date: sessionEnd.addingTimeInterval(10), price: 755.45, intervalSeconds: 5)
    await fixture.setSamples(nightSession + [tailTick1, tailTick2], quoteTime: tailTick2.date)
    await model.refresh()
    #expect(model.points.count == 258)
    #expect(model.points.first?.date == sessionStart)
    #expect(model.points.last == tailTick2)
}

@MainActor @Test func newlyOpenedSessionKeepsMinimumTwentyMinuteDomainFloor() async {
    let end = Date.now.addingTimeInterval(-2)
    let openingTicks = [
        MarketChartPoint(date: end.addingTimeInterval(-5), price: 760.0, intervalSeconds: 5),
        MarketChartPoint(date: end, price: 760.2, intervalSeconds: 5)
    ]
    let fixture = SessionAppendRealtimeFixture(initialSamples: openingTicks, quoteTime: end)
    let model = MarketHomeViewModel(basis: .domestic, dailyService: fixture, quoteService: fixture, realtimeService: fixture)
    model.range = .realtime

    await model.refresh()
    #expect(model.points.count == 2)
    #expect(model.fullDomain.upperBound == end)
    #expect(abs(model.fullDomain.upperBound.timeIntervalSince(model.fullDomain.lowerBound) - 1200) < 0.001)
}

@MainActor @Test func pausedRealtimeThrottlesPollIntervalAndRestoresLiveCadence() async {
    let staleEnd = Date.now.addingTimeInterval(-3600)
    let staleSample = MarketChartPoint(date: staleEnd, price: 755.01, intervalSeconds: 60)
    let fixture = SessionAppendRealtimeFixture(initialSamples: [staleSample], quoteTime: staleEnd)
    let model = MarketHomeViewModel(basis: .domestic, dailyService: fixture, quoteService: fixture, realtimeService: fixture)
    model.range = .realtime

    // Before first load (.empty): keep responsive 5s schedule.
    #expect(model.realtimeTiming.state == .empty)
    #expect(model.liveStreamPollInterval == MarketHomeViewModel.livePollInterval)

    // After loading closed market data (.paused): throttle to 30s.
    await model.refresh()
    #expect(model.realtimeTiming.state == .paused)
    #expect(model.liveStreamPollInterval == MarketHomeViewModel.pausedPollInterval)

    // Once fresh live ticks arrive (.live): immediately restore 5s cadence.
    let liveNow = Date.now.addingTimeInterval(-2)
    await fixture.setSamples([MarketChartPoint(date: liveNow, price: 758.50, intervalSeconds: 5)], quoteTime: liveNow)
    await model.refresh()
    #expect(model.realtimeTiming.state == .live)
    #expect(model.liveStreamPollInterval == MarketHomeViewModel.livePollInterval)
}

private struct StatusCopyFixture: GoldPriceServicing, GoldQuoteServicing, GoldRealtimeServicing, GoldHistoryServicing {
    let basis: GoldMarketBasis
    let quoteDate: Date
    let sessionSpan: TimeInterval

    func fetchDailyPrices() async throws -> [GoldDailyPrice] {
        let yesterday = ChartViewport.noon(quoteDate.addingTimeInterval(-86400))
        return [GoldDailyPrice(date: yesterday, open: 900, high: 910, low: 895, close: 905)]
    }

    func fetchHistory() async throws -> [GoldHistoryPoint] {
        let yesterday = ChartViewport.noon(quoteDate.addingTimeInterval(-86400))
        return [GoldHistoryPoint(date: yesterday, price: basis == .domestic ? 905 : 3000, granularity: .daily, source: "fixture")]
    }

    func fetchQuote() async throws -> GoldQuote {
        GoldQuote(
            symbol: basis == .domestic ? "AU9999" : "XAUUSD",
            price: basis == .domestic ? 907.61 : 3100,
            open: 900,
            high: 910,
            low: 898,
            prevClose: 902,
            usdCNY: basis == .domestic ? 0 : 7.0,
            cnyPerGram: 907.61,
            asOf: quoteDate
        )
    }

    func fetchRealtime() async throws -> [MarketChartPoint] {
        [
            MarketChartPoint(date: quoteDate.addingTimeInterval(-sessionSpan), price: 905.0, intervalSeconds: 60),
            MarketChartPoint(date: quoteDate, price: 907.61, intervalSeconds: 60)
        ]
    }
}

@MainActor @Test func domesticViewModelMessagesReflectSessionStatusAcrossRealtimeAndHistoricalRanges() async {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let parse = { (iso: String) in BackendGoldPriceService.parseRFC3339(iso)! }

    let cases: [(now: String, quote: String, expectedMessage: String, expectedCaption: String)] = [
        ("2026-11-21T02:35:00+08:00", "2026-11-21T02:30:00+08:00", "周末休市 · 收盘价 11/21 02:30", "周末休市 · 展示最近交易时段分时"),
        ("2026-11-22T10:38:00+08:00", "2026-11-21T02:30:00+08:00", "周末休市 · 收盘价 11/21 02:30", "周末休市 · 展示最近交易时段分时"),
        ("2026-11-23T08:50:00+08:00", "2026-11-21T02:30:00+08:00", "周末休市 · 收盘价 11/21 02:30", "周末休市 · 展示最近交易时段分时"),
        ("2026-11-24T12:00:00+08:00", "2026-11-24T11:30:00+08:00", "午间休盘 · 最近报价 11/24 11:30", "午间休盘 · 展示最近交易时段分时"),
        ("2026-11-24T17:00:00+08:00", "2026-11-24T15:30:00+08:00", "已收盘 · 收盘价 11/24 15:30", "已收盘 · 展示最近交易时段分时"),
        ("2026-11-25T04:00:00+08:00", "2026-11-25T02:30:00+08:00", "已收盘 · 收盘价 11/25 02:30", "已收盘 · 展示最近交易时段分时"),
        ("2026-10-01T10:30:00+08:00", "2026-09-30T15:30:00+08:00", "当前休市 · 最近报价 09/30 15:30", "当前休市 · 展示最近交易时段分时"),
        ("2026-11-21T02:15:00+08:00", "2026-11-21T02:04:00+08:00", "暂无新成交 · 最近报价 11/21 02:04", "暂无新成交 · 本交易时段分时")
    ]

    for item in cases {
        let now = parse(item.now)
        let quote = parse(item.quote)
        let fixture = StatusCopyFixture(basis: .domestic, quoteDate: quote, sessionSpan: 2 * 3600)
        let model = MarketHomeViewModel(
            basis: .domestic,
            dailyService: fixture,
            quoteService: fixture,
            realtimeService: fixture,
            historyService: fixture,
            nowProvider: { now },
            calendar: calendar
        )
        model.range = .realtime
        await model.refresh()
        #expect(model.message == item.expectedMessage)
        #expect(model.realtimeTiming.caption == item.expectedCaption)
        #expect(model.message?.contains("更新暂停") == false)

        // Switching to non-realtime ranges keeps clear closed/break context under the headline price.
        model.range = .month
        #expect(model.message == item.expectedMessage)
        #expect(model.message?.contains("更新暂停") == false)
    }
}

@MainActor @Test func internationalViewModelMessagesReflectWeekendDailyBreakDSTHolidayAndStaleQuote() async {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let parse = { (iso: String) in BackendGoldPriceService.parseRFC3339(iso)! }

    let cases: [(now: String, quote: String, expectedMessage: String, expectedCaption: String)] = [
        ("2026-11-22T10:38:00+08:00", "2026-11-20T16:59:00-05:00", "周末休市 · 收盘价 11/21 05:59", "周末休市 · 展示最近交易时段分时"),
        ("2026-07-16T05:30:00+08:00", "2026-07-16T04:59:00+08:00", "每日结算休盘 · 最近报价 07/16 04:59", "每日结算休盘 · 展示最近交易时段分时"),
        ("2026-11-19T06:30:00+08:00", "2026-11-19T05:59:00+08:00", "每日结算休盘 · 最近报价 11/19 05:59", "每日结算休盘 · 展示最近交易时段分时"),
        ("2026-11-19T05:30:00+08:00", "2026-11-19T05:20:00+08:00", "报价暂未刷新 · 最近报价 11/19 05:20", "报价暂未刷新 · 本交易时段分时"),
        ("2026-12-25T10:00:00-05:00", "2026-12-24T13:30:00-05:00", "当前休市 · 最近报价 12/25 02:30", "当前休市 · 展示最近交易时段分时")
    ]

    for item in cases {
        let now = parse(item.now)
        let quote = parse(item.quote)
        let fixture = StatusCopyFixture(basis: .international, quoteDate: quote, sessionSpan: 2 * 3600)
        let model = MarketHomeViewModel(
            basis: .international,
            dailyService: fixture,
            quoteService: fixture,
            realtimeService: fixture,
            historyService: fixture,
            nowProvider: { now },
            calendar: calendar
        )
        model.range = .realtime
        await model.refresh()
        #expect(model.message == item.expectedMessage)
        #expect(model.realtimeTiming.caption == item.expectedCaption)
        #expect(model.message?.contains("更新暂停") == false)

        model.range = .quarter
        #expect(model.message == item.expectedMessage)
        #expect(model.message?.contains("更新暂停") == false)
    }
}
