import Foundation
import Observation
import Testing
@testable import Sumly

@Test func marketQuoteSnapshotConvertsDomesticAndInternationalCorrectly() throws {
    let domesticQuote = GoldQuote(
        symbol: "AU9999", price: 620.5, open: 615.0, high: 625.0, low: 612.0,
        prevClose: 610.0, usdCNY: 0, cnyPerGram: 620.5, asOf: .now
    )
    let domestic = try #require(MarketQuoteSnapshot.make(from: domesticQuote, basis: .domestic))
    #expect(abs((domestic.changeCNY ?? 0) - 10.5) < 0.001)
    #expect(abs((domestic.changePercent ?? 0) - (10.5 / 610.0 * 100)) < 0.001)
    #expect(domestic.openCNY == 615.0)
    #expect(domestic.highCNY == 625.0)
    #expect(domestic.lowCNY == 612.0)
    #expect(domestic.usdPerOz == nil)

    let intlQuote = GoldQuote(
        symbol: "XAUUSD", price: 2700, open: 2680, high: 2710, low: 2670,
        prevClose: 2650, usdCNY: 7.2, cnyPerGram: 625.0, asOf: .now
    )
    let intl = try #require(MarketQuoteSnapshot.make(from: intlQuote, basis: .international))
    let expectedPrev = 2650 * (625.0 / 2700.0)
    #expect(abs((intl.prevCloseCNY ?? 0) - expectedPrev) < 0.001)
    #expect(abs((intl.changeCNY ?? 0) - (625.0 - expectedPrev)) < 0.001)
    #expect(intl.usdPerOz == 2700)
    #expect(intl.usdCNY == 7.2)
}

@Test func goldMarketSpreadCalculatesPremiumAndDiscount() throws {
    let d = GoldQuote(symbol: "AU9999", price: 630, open: 628, high: 631, low: 627, prevClose: 628, usdCNY: 0, cnyPerGram: 630, asOf: .now)
    let i = GoldQuote(symbol: "XAUUSD", price: 2700, open: 2690, high: 2710, low: 2680, prevClose: 2690, usdCNY: 7.2, cnyPerGram: 625, asOf: .now)
    let spread = try #require(GoldMarketSpread.calculate(domestic: d, international: i))
    #expect(abs(spread.spreadCNY - 5.0) < 0.001)
    #expect(abs(spread.spreadPercent - (5.0 / 625.0 * 100)) < 0.001)
}

@MainActor @Test func liveGoldQuoteStoreIngestsAndPreventsOlderOverwrite() {
    let store = LiveGoldQuoteStore()
    let now = Date.now
    let newer = GoldQuote(symbol: "AU9999", price: 632, open: 630, high: 635, low: 629, prevClose: 630, usdCNY: 0, cnyPerGram: 632, asOf: now)
    let older = GoldQuote(symbol: "AU9999", price: 620, open: 618, high: 622, low: 617, prevClose: 618, usdCNY: 0, cnyPerGram: 620, asOf: now.addingTimeInterval(-60))
    let intl = GoldQuote(symbol: "XAUUSD", price: 2700, open: 2700, high: 2700, low: 2700, prevClose: 2700, usdCNY: 7.2, cnyPerGram: 625, asOf: now)

    store.ingest(newer, for: .domestic)
    store.ingest(older, for: .domestic)
    store.ingest(intl, for: .international)

    #expect(store.quote(for: .domestic)?.cnyPerGram == 632)
    #expect(abs((store.spread?.spreadCNY ?? 0) - 7.0) < 0.001)
    store.clearCache()
    #expect(store.quote(for: .domestic) == nil)
}

private actor MutableQuoteFixture: GoldQuoteServicing {
    var result: Result<GoldQuote, Error>
    init(_ result: Result<GoldQuote, Error>) { self.result = result }
    func set(_ next: Result<GoldQuote, Error>) { result = next }
    func fetchQuote() async throws -> GoldQuote { try result.get() }
}

@MainActor private final class ObservationFlag {
    var triggered = false
}

@MainActor @Test func liveGoldQuoteStoreIsolatesBasisObservationAndDeduplicatesUnchangedQuotes() async {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let domesticQuote = GoldQuote(symbol: "AU9999", price: 632, open: 630, high: 635, low: 629, prevClose: 630, usdCNY: 0, cnyPerGram: 632, asOf: now)
    let domesticUpdated = GoldQuote(symbol: "AU9999", price: 633.5, open: 630, high: 635, low: 629, prevClose: 630, usdCNY: 0, cnyPerGram: 633.5, asOf: now.addingTimeInterval(5))
    let intlQuote = GoldQuote(symbol: "XAUUSD", price: 2700, open: 2700, high: 2700, low: 2700, prevClose: 2700, usdCNY: 7.2, cnyPerGram: 625, asOf: now)

    let domesticService = MutableQuoteFixture(.success(domesticQuote))
    let intlService = MutableQuoteFixture(.success(intlQuote))
    let store = LiveGoldQuoteStore { basis in
        basis == .domestic ? domesticService : intlService
    }

    await store.refresh(basis: .domestic)
    #expect(store.domesticQuote == domesticQuote)
    #expect(!store.isFailed(for: .domestic))

    // 1. 仅订阅国内口径时，国际口径更新或失败不应触发国内观察者重绘
    let domesticInvalidated = ObservationFlag()
    withObservationTracking {
        _ = store.quote(for: .domestic)
        _ = store.isFailed(for: .domestic)
    } onChange: {
        MainActor.assumeIsolated { domesticInvalidated.triggered = true }
    }

    store.ingest(intlQuote, for: .international)
    await intlService.set(.failure(URLError(.notConnectedToInternet)))
    await store.refresh(basis: .international)
    #expect(!domesticInvalidated.triggered)
    #expect(store.isFailed(for: .international))

    // 2. 相同国内报价重复 ingest / refresh 必须短路，不触发观察者
    store.ingest(domesticQuote, for: .domestic)
    await store.refresh(basis: .domestic)
    #expect(!domesticInvalidated.triggered)

    // 3. 真正的新国内报价应准确触发国内观察者
    await domesticService.set(.success(domesticUpdated))
    await store.refresh(basis: .domestic)
    #expect(domesticInvalidated.triggered)
    #expect(store.domesticQuote == domesticUpdated)

    // 4. 连续失败去重：第二次失败不再触发 isFailed 观察者
    await domesticService.set(.failure(URLError(.timedOut)))
    await store.refresh(basis: .domestic)
    #expect(store.isFailed(for: .domestic))
    let repeatedFailInvalidated = ObservationFlag()
    withObservationTracking {
        _ = store.isFailed(for: .domestic)
    } onChange: {
        MainActor.assumeIsolated { repeatedFailInvalidated.triggered = true }
    }
    await store.refresh(basis: .domestic)
    #expect(!repeatedFailInvalidated.triggered)
}

@MainActor @Test func holdingsViewModelDeduplicatesIdenticalExternalQuotes() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let quoteA = GoldQuote(symbol: "AU9999", price: 632, open: 630, high: 635, low: 629, prevClose: 630, usdCNY: 0, cnyPerGram: 632, asOf: now)
    let quoteB = GoldQuote(symbol: "AU9999", price: 634, open: 630, high: 635, low: 629, prevClose: 630, usdCNY: 0, cnyPerGram: 634, asOf: now.addingTimeInterval(5))
    let vm = HoldingsViewModel(quoteService: nil)
    vm.applyExternalQuote(quoteA, failed: false)
    #expect(vm.quote == quoteA)
    #expect(!vm.quoteFailed)

    let invalidated = ObservationFlag()
    withObservationTracking {
        _ = vm.quote
        _ = vm.quoteFailed
    } onChange: {
        MainActor.assumeIsolated { invalidated.triggered = true }
    }

    vm.applyExternalQuote(quoteA, failed: false)
    #expect(!invalidated.triggered)

    vm.applyExternalQuote(quoteB, failed: false)
    #expect(invalidated.triggered)
    #expect(vm.quote == quoteB)

    vm.applyExternalQuote(nil, failed: true)
    #expect(vm.quoteFailed)
    let repeatedFailInvalidated = ObservationFlag()
    withObservationTracking {
        _ = vm.quoteFailed
    } onChange: {
        MainActor.assumeIsolated { repeatedFailInvalidated.triggered = true }
    }
    vm.applyExternalQuote(nil, failed: true)
    #expect(!repeatedFailInvalidated.triggered)
}

@Test func holdingsAllocationGroupsByTypeAndBrand() {
    let t = Date.now
    let entries = [
        HoldingsInsights.Entry(assetType: "金条", brand: "工商银行", channel: "银行", grams: 30, totalCost: 18000, unitPrice: 600, timestamp: t, input: GoldReturnInput(grams: 30, unitPrice: 600)),
        HoldingsInsights.Entry(assetType: "金饰", brand: "周大福", channel: "门店", grams: 10, totalCost: 7000, unitPrice: 650, timestamp: t.addingTimeInterval(-100), input: GoldReturnInput(grams: 10, unitPrice: 650, laborFee: 500)),
        HoldingsInsights.Entry(assetType: "金条", brand: "工商银行", channel: "银行", grams: 10, totalCost: 6200, unitPrice: 620, timestamp: t.addingTimeInterval(-200), input: GoldReturnInput(grams: 10, unitPrice: 620))
    ]
    let byType = HoldingsInsights.allocations(from: entries, grouping: .assetType)
    #expect(byType.count == 2)
    #expect(byType[0].label == "金条")
    #expect(abs(byType[0].gramShare - 0.8) < 0.001)
    #expect(abs(byType.reduce(0) { $0 + $1.gramShare } - 1.0) < 0.001)

    let tags = HoldingsInsights.recentTags(from: entries, keyPath: \.brand)
    #expect(tags == ["工商银行", "周大福"])
}

@Test func savingGoalProgressHandlesPartialAndAchievedTargets() throws {
    let partial = try #require(GoldSavingGoalProgress.make(targetGrams: 100, currentGrams: 40, referencePrice: 620))
    #expect(!partial.isAchieved)
    #expect(abs(partial.remainingGrams - 60) < 0.001)
    #expect(abs(partial.clampedProgress - 0.4) < 0.001)
    #expect(abs((partial.estimatedRemainingCost ?? 0) - 37200) < 0.001)

    let achieved = try #require(GoldSavingGoalProgress.make(targetGrams: 50, currentGrams: 65, referencePrice: 620))
    #expect(achieved.isAchieved)
    #expect(achieved.remainingGrams == 0)
    #expect(achieved.clampedProgress == 1.0)
    #expect(achieved.estimatedRemainingCost == nil)
    #expect(GoldSavingGoalProgress.make(targetGrams: 0, currentGrams: 10, referencePrice: 620) == nil)
}

@Test func quickPresetPreservesUserGramsAndPrice() {
    var draft = HoldingDraft()
    draft.gramsText = "25.5"
    draft.priceText = "612.80"
    draft.note = "生日礼物"

    HoldingQuickPreset.brandJewelry.apply(to: &draft)
    #expect(draft.assetType == .jewelry)
    #expect(draft.purityText == "99.9")
    #expect(draft.gramsText == "25.5")
    #expect(draft.priceText == "612.80")
    #expect(draft.note == "生日礼物")
}

@Test func marketOverlayComputesBreakEvenAndAggregatesDailyMarkers() throws {
    let calendar = Calendar(identifier: .gregorian)
    let day1 = ChartViewport.noon(calendar.date(byAdding: .day, value: -10, to: .now)!, calendar: calendar)
    let day2 = ChartViewport.noon(calendar.date(byAdding: .day, value: -5, to: .now)!, calendar: calendar)
    let outside = ChartViewport.noon(calendar.date(byAdding: .day, value: -90, to: .now)!, calendar: calendar)
    let window = calendar.date(byAdding: .day, value: -30, to: .now)!...Date.now

    let entries = [
        HoldingsInsights.Entry(assetType: "金条", brand: "A", channel: "", grams: 10, totalCost: 6000, unitPrice: 600, timestamp: day1, input: GoldReturnInput(grams: 10, unitPrice: 600)),
        HoldingsInsights.Entry(assetType: "金条", brand: "B", channel: "", grams: 10, totalCost: 6200, unitPrice: 620, timestamp: day1, input: GoldReturnInput(grams: 10, unitPrice: 620)),
        HoldingsInsights.Entry(assetType: "金条", brand: "C", channel: "", grams: 5, totalCost: 3250, unitPrice: 650, timestamp: day2, input: GoldReturnInput(grams: 5, unitPrice: 650)),
        HoldingsInsights.Entry(assetType: "金条", brand: "D", channel: "", grams: 5, totalCost: 2500, unitPrice: 500, timestamp: outside, input: GoldReturnInput(grams: 5, unitPrice: 500))
    ]

    let overlay = try #require(HoldingsInsights.marketOverlay(entries: entries, window: window, referencePrice: 640, calendar: calendar))
    #expect(overlay.markers.count == 2)
    #expect(overlay.markers[0].count == 2)
    #expect(abs(overlay.markers[0].totalGrams - 20) < 0.001)
    #expect(abs(overlay.markers[0].averageUnitPrice - 610) < 0.001)
    #expect(overlay.breakEvenPrice != nil)
}

@Test func binarySearchNearestPointMatchesEdgesAndInterior() {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    let points = [0, 10, 20, 30, 40].map {
        MarketChartPoint(date: base.addingTimeInterval(Double($0)), price: Double(600 + $0))
    }
    #expect(MarketHomeViewModel.nearestPoint(in: [], to: base) == nil)
    #expect(MarketHomeViewModel.nearestPoint(in: points, to: base.addingTimeInterval(-5))?.price == 600)
    #expect(MarketHomeViewModel.nearestPoint(in: points, to: base.addingTimeInterval(14))?.price == 610)
    #expect(MarketHomeViewModel.nearestPoint(in: points, to: base.addingTimeInterval(16))?.price == 620)
    #expect(MarketHomeViewModel.nearestPoint(in: points, to: base.addingTimeInterval(99))?.price == 640)
}

@Test func calendarDayBucketsAggregateByNaturalDay() {
    let calendar = Calendar.current
    let day = calendar.startOfDay(for: .now)
    let events = [
        HoldingCalendarEvent(id: "1", purchaseID: UUID(), date: day.addingTimeInterval(3600), kind: "buy", grams: 10, cost: 6000, fees: 0, proceeds: 0, title: "A"),
        HoldingCalendarEvent(id: "2", purchaseID: UUID(), date: day.addingTimeInterval(7200), kind: "buy", grams: 5, cost: 3100, fees: 0, proceeds: 0, title: "B"),
        HoldingCalendarEvent(id: "3", purchaseID: UUID(), date: day.addingTimeInterval(9000), kind: "sold", grams: 3, cost: 1800, fees: 0, proceeds: 2000, title: "C"),
        HoldingCalendarEvent(id: "4", purchaseID: UUID(), date: day.addingTimeInterval(9600), kind: "gift", grams: 2, cost: 1200, fees: 0, proceeds: 0, title: "D")
    ]
    let buckets = HoldingCalendarLogic.dayBuckets(events, calendar: calendar)
    let bucket = buckets[day]
    #expect(bucket?.purchaseGrams == 15)
    #expect(bucket?.saleGrams == 3)
    #expect(bucket?.giftGrams == 2)
}
