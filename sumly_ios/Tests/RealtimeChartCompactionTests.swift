import Foundation
import SwiftUI
import UIKit
import Testing
@testable import Sumly

private struct FlatRealtimeFixture: GoldPriceServicing, GoldQuoteServicing, GoldRealtimeServicing {
    let samples: [MarketChartPoint]
    func fetchDailyPrices() async throws -> [GoldDailyPrice] { [] }
    func fetchQuote() async throws -> GoldQuote {
        GoldQuote(symbol: "AU9999", price: 900, open: 900, high: 900, low: 900,
                  prevClose: 900, usdCNY: 0, cnyPerGram: 900, asOf: samples.last!.date)
    }
    func fetchRealtime() async throws -> [MarketChartPoint] { samples }
}

@MainActor @Test func realtimeRenderingMergesFlatRunWithoutLosingSelectableObservations() async throws {
    let start = Date.now.addingTimeInterval(-1200)
    let samples = (0...240).map { MarketChartPoint(date: start.addingTimeInterval(Double($0) * 5), price: 900) }
    let service = FlatRealtimeFixture(samples: samples)
    let model = MarketHomeViewModel(basis: .domestic, dailyService: service, quoteService: service, realtimeService: service)
    await model.refresh()
    #expect(model.visiblePoints == [samples[0], samples[240]])
    #expect(model.points == samples)
    #expect(model.windowPoints.count == 241)
    #expect(model.windowStatistics.high == samples[0])
    #expect(model.windowStatistics.last == samples[240])
    model.selectChart(at: 0.5)
    #expect(model.selectedPoint == samples[120])
    model.resetViewport()
    model.accessibleZoom(4)
    let window = model.xDomain
    #expect(model.visiblePoints.first?.date == samples.last { $0.date < window.lowerBound }?.date)
    #expect(model.visiblePoints.last?.date == samples.first { $0.date > window.upperBound }?.date)
    #expect(model.visiblePoints.count == 2)
    #expect(model.windowPoints.count > 2)
}

@Test func flatRunCompactionPreservesBothEndsOfEveryPriceChange() {
    let prices = [900.0, 900, 900, 901, 901, 899, 899, 899, 900]
    let samples = prices.enumerated().map { MarketChartPoint(date: Date(timeIntervalSince1970: Double($0.offset) * 5), price: $0.element) }
    let result = RealtimeChartCompaction.points(samples)
    #expect(result == [samples[0], samples[2], samples[3], samples[4], samples[5], samples[7], samples[8]])
    #expect(ChartWindowStatistics(points: result) == ChartWindowStatistics(points: samples))
    #expect(RealtimeChartCompaction.points(result) == result)
}

@Test func realtimeOverviewCannotDiscardPlateauEndpointDuringFurtherSampling() {
    let flat = (0...200).map { MarketChartPoint(date: Date(timeIntervalSince1970: Double($0) * 5), price: 900) }
    let changes = (1...1000).map { MarketChartPoint(date: Date(timeIntervalSince1970: 1000 + Double($0) * 5), price: 900 + Double($0)) }
    let samples = flat + changes
    let overview = ChartOverviewSampling.points(samples, daily: false)
    #expect(overview.contains(flat[200]))
    #expect(overview.first == flat.first)
    #expect(overview.last == changes.last)
    #expect(overview == RealtimeChartCompaction.points(samples))
    let history = ChartOverviewSampling.points(samples, daily: true)
    #expect(history.first == samples.first && history.last == samples.last)
    #expect(history.count < samples.count)
}

@Test func flatRunCompactionDoesNotRoundAwayTinyMovesOrJoinDataGaps() {
    let tiny = [900.0, 900, 900.000001, 900.000001, 900]
        .enumerated().map { MarketChartPoint(date: Date(timeIntervalSince1970: Double($0.offset) * 5), price: $0.element) }
    #expect(RealtimeChartCompaction.points(tiny) == tiny)
    let gap = [0.0, 5, 10, 610, 615, 620].map { MarketChartPoint(date: Date(timeIntervalSince1970: $0), price: 900) }
    #expect(RealtimeChartCompaction.points(gap) == [gap[0], gap[2], gap[3], gap[5]])
    let minute = [0.0, 60, 120, 180].map { MarketChartPoint(date: Date(timeIntervalSince1970: $0), price: 900) }
    #expect(RealtimeChartCompaction.points(minute) == [minute[0], minute[3]])
}

@Test func flatRunCompactionHandlesShortWindowsAndOnlyChangesRenderGeometry() {
    #expect(RealtimeChartCompaction.points([]).isEmpty)
    let samples = (0...2).map { MarketChartPoint(date: Date(timeIntervalSince1970: Double($0) * 5), price: 900) }
    for count in 1...2 { #expect(RealtimeChartCompaction.points(Array(samples.prefix(count))) == Array(samples.prefix(count))) }
    let changing = (0...240).map { MarketChartPoint(date: Date(timeIntervalSince1970: Double($0) * 5), price: Double($0 + 900)) }
    #expect(RealtimeChartCompaction.points(changing) == changing)
    var daily = samples
    daily[1].granularity = .daily
    #expect(RealtimeChartCompaction.points(daily) == daily)
}

/// Replay the observed domestic plateau prices using fresh fixture timestamps.
@MainActor @Test func renderCompactedRealtimeForVisualReview() async throws {
    let runs: [(Double, Int)] = [(907.5,12),(907.6,6),(907.9,6),(907.6,24),(907.5,6),
        (907.89,6),(907.6,6),(907.8,30),(907.89,6),(907.7,12),(907.68,6),(907.65,6),
        (907.8,6),(907.85,18),(908,6),(908.2,6),(908.6,6),(908.5,6),(908.7,12),
        (909,6),(908.6,12),(908.5,6),(907.7,6),(907,6),(907.6,6),(908.4,6),(907.61,7)]
    let prices = runs.flatMap { Array(repeating: $0.0, count: $0.1) }
    let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previous = scene.windows.first { $0.isKeyWindow }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sumly-realtime-ui-review")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for name in ["plateaus", "zoomed", "selected", "flat"] {
        let start = Date.now.addingTimeInterval(-1200)
        let values = name == "flat" ? Array(repeating: 900.0, count: 241) : prices
        let samples = values.enumerated().map { MarketChartPoint(date: start.addingTimeInterval(Double($0.offset) * 5), price: $0.element) }
        let service = FlatRealtimeFixture(samples: samples)
        let model = MarketHomeViewModel(basis: .domestic, dailyService: service, quoteService: service, realtimeService: service)
        await model.refresh()
        if name == "zoomed" { model.accessibleZoom(4) }
        if name == "selected" { model.selectChart(at: 0.5) }
        print("REALTIME_RENDER_POINTS: \(name), raw=\(model.windowPoints.count), drawn=\(model.visiblePoints.count)")
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: MarketHomeChartContent(model: model,
            availableHeight: window.bounds.height - 110,
            showingHistorySources: .constant(false), showingDates: .constant(false))
            .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity).background(GoldTheme.background)
            .preferredColorScheme(.dark).tint(GoldTheme.gold))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(400))
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let path = directory.appendingPathComponent(name + ".png")
        try #require(image.pngData()).write(to: path)
        print("REALTIME_RENDER_ARTIFACT: \(path.path)")
        model.resetViewport()
        window.isHidden = true
    }
    previous?.makeKey()
}
