import Foundation
import SwiftUI
import UIKit
import Testing
@testable import Sumly

private struct FrozenMarketFixture: GoldPriceServicing, GoldQuoteServicing, GoldRealtimeServicing {
    let end: Date
    func fetchDailyPrices() async throws -> [GoldDailyPrice] { [] }
    func fetchQuote() async throws -> GoldQuote {
        GoldQuote(symbol: "AU9999", price: 907.61, open: 899, high: 909, low: 897.5,
            prevClose: 897.53, usdCNY: 6.7061, cnyPerGram: 907.61, asOf: end)
    }
    func fetchRealtime() async throws -> [MarketChartPoint] {
        [.init(date: end.addingTimeInterval(-1197), price: 907.5), .init(date: end, price: 907.61)]
    }
}

@MainActor @Test func frozenDomesticWindowIsExplicitlyPausedWithoutChangingItsPrices() async {
    let service = FrozenMarketFixture(end: .now.addingTimeInterval(-86400))
    let model = MarketHomeViewModel(basis: .domestic, dailyService: service, quoteService: service, realtimeService: service)
    await model.refresh()
    #expect(model.message?.contains("更新暂停") == true)
    #expect(model.points.map(\.price) == [907.5, 907.61])
    #expect(model.fullDomain.upperBound == service.end)
}

private func timingCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}
private func timingDate(_ value: String) -> Date { BackendGoldPriceService.parseRFC3339(value)! }

@Test func currentRealtimeWindowKeepsCompactTimeLabels() {
    let now = timingDate("2026-10-01T15:05:00+08:00")
    let timing = RealtimeChartTiming(latestSample: now, latestQuote: now.addingTimeInterval(-60), now: now, calendar: timingCalendar())
    let window = now.addingTimeInterval(-1200)...now
    #expect(timing.state == .live)
    #expect(timing.windowLabel(window) == "14:45:00 — 15:05:00")
    #expect(timing.axisLabel(now, window: window) == "15:05")
}

@Test func previousDayAndMidnightWindowsExposeTheirActualDates() {
    let now = timingDate("2026-10-01T15:05:00+08:00")
    let last = timingDate("2026-09-30T15:29:59+08:00")
    let timing = RealtimeChartTiming(latestSample: last, latestQuote: last, now: now, calendar: timingCalendar())
    let window = last.addingTimeInterval(-1200)...last
    #expect(timing.state == .paused)
    #expect(timing.caption.contains("最近可用"))
    #expect(timing.windowLabel(window) == "2026.09.30 15:09:59 — 15:29:59")
    #expect(timing.axisLabel(last, window: window) == "09.30\n15:29")
    #expect(timing.timestamp(last) == "2026.09.30 15:29:59")
    let midnight = timingDate("2026-10-01T00:05:00+08:00")
    let crossing = midnight.addingTimeInterval(-1200)...midnight
    let live = RealtimeChartTiming(latestSample: midnight, latestQuote: midnight, now: midnight, calendar: timingCalendar())
    #expect(live.windowLabel(crossing) == "2026.09.30 23:45:00 — 2026.10.01 00:05:00")
    #expect(live.axisLabel(midnight, window: crossing) == "10.01\n00:05")
}

@Test func staleSourceCannotAppearLiveJustBecausePollingContinues() {
    let now = timingDate("2026-10-01T15:05:00+08:00")
    #expect(RealtimeChartTiming(latestSample: now, latestQuote: now.addingTimeInterval(-181), now: now).state == .paused)
    #expect(RealtimeChartTiming(latestSample: now.addingTimeInterval(-21), latestQuote: now, now: now).state == .paused)
    #expect(RealtimeChartTiming(latestSample: now.addingTimeInterval(-20), latestQuote: now.addingTimeInterval(-180), now: now).state == .live)
    #expect(RealtimeChartTiming(latestSample: nil, latestQuote: now, now: now).state == .empty)
}

@Test func minuteFallbackUsesItsRealSamplingCadence() {
    let now = timingDate("2026-10-01T15:05:45+08:00")
    let timing = RealtimeChartTiming(latestSample: now.addingTimeInterval(-45), latestQuote: now.addingTimeInterval(-1), intervalSeconds: 60, now: now)
    #expect(timing.state == .live)
    #expect(RealtimeChartTiming(latestSample: now.addingTimeInterval(-121), latestQuote: now, intervalSeconds: 60, now: now).state == .paused)
    #expect(RealtimeChartTiming(latestSample: now, latestQuote: now.addingTimeInterval(-181), intervalSeconds: 60, now: now).state == .paused)
}

@MainActor @Test func renderRealtimeDatesAndFreshnessForVisualReview() async throws {
    let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previous = scene.windows.first { $0.isKeyWindow }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sumly-realtime-timing-review")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let states: [(String, TimeInterval, GoldMarketBasis, DynamicTypeSize)] = [
        ("domestic-paused", -86400, .domestic, .large),
        ("domestic-paused-large-text", -86400, .domestic, .accessibility2),
        ("international-current", 0, .international, .large)
    ]
    for (name, offset, basis, size) in states {
        let service = FrozenMarketFixture(end: .now.addingTimeInterval(offset))
        let model = MarketHomeViewModel(basis: basis, dailyService: service, quoteService: service, realtimeService: service)
        await model.refresh()
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: ScrollView {
            MarketHomeChartContent(model: model, availableHeight: window.bounds.height - 110,
                showingNotice: .constant(false), showingHistorySources: .constant(false), showingDates: .constant(false)).padding(18)
        }.background(GoldTheme.background).environment(\.dynamicTypeSize, size).preferredColorScheme(.dark).tint(GoldTheme.gold))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(400))
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let path = directory.appendingPathComponent(name + ".png")
        try #require(image.pngData()).write(to: path)
        print("TIMING_RENDER_ARTIFACT: \(path.path)")
        window.isHidden = true
    }
    previous?.makeKey()
}
