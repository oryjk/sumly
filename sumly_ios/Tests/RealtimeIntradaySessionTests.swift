import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Sumly

@Suite(.serialized)
struct RealtimeIntradaySessionTests {
    private static let shanghaiTZ = TimeZone(identifier: "Asia/Shanghai")!

    private static func bjDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = shanghaiTZ
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func domesticAxisCoversContinuousDayAndNightWithoutLunchFolding() {
        let nightNow = Self.bjDate(2026, 11, 27, 22, 30)
        let axis = RealtimeIntradayAxis.make(basis: .domestic, anchorDate: nightNow)

        #expect(axis.totalSlots == 780)
        #expect(axis.dividers.count == 1)
        #expect(axis.dividers.first?.slot == 390)
        #expect(axis.ticks.map(\.label) == ["09:00", "12:15", "15:30/20:00", "02:30"])

        // 连续日盘 09:00 -> 0，11:30 -> 150，12:15 -> 195，13:30 -> 270（不再折叠午休），15:30 -> 390
        #expect(axis.slot(for: Self.bjDate(2026, 11, 27, 9, 0)) == 0)
        #expect(axis.slot(for: Self.bjDate(2026, 11, 27, 11, 30)) == 150)
        #expect(axis.slot(for: Self.bjDate(2026, 11, 27, 12, 15)) == 195)
        #expect(axis.slot(for: Self.bjDate(2026, 11, 27, 13, 30)) == 270)
        #expect(axis.slot(for: Self.bjDate(2026, 11, 27, 15, 30)) == 390)
        // 夜盘 20:00 无缝衔接在 390，22:30 -> 540，次日 02:30 -> 780
        #expect(axis.slot(for: Self.bjDate(2026, 11, 27, 20, 0)) == 390)
        #expect(axis.slot(for: Self.bjDate(2026, 11, 27, 22, 30)) == 540)
        #expect(axis.slot(for: Self.bjDate(2026, 11, 28, 2, 30)) == 780)

        // 跨午夜 01:00 锚定仍归属于前一日 09:00 开始的完整自然交易日
        let postMidnightAxis = RealtimeIntradayAxis.make(basis: .domestic, anchorDate: Self.bjDate(2026, 11, 28, 1, 0))
        #expect(postMidnightAxis == axis)
        #expect(postMidnightAxis.slot(for: Self.bjDate(2026, 11, 28, 1, 0)) == 690)

        // 11:31~13:29 连续日盘点投影后全部保留，不被午休折叠去重
        let middayPoints = [
            MarketChartPoint(date: Self.bjDate(2026, 11, 27, 11, 30), price: 778.0, intervalSeconds: 60),
            MarketChartPoint(date: Self.bjDate(2026, 11, 27, 12, 0), price: 780.5, intervalSeconds: 60),
            MarketChartPoint(date: Self.bjDate(2026, 11, 27, 12, 30), price: 782.0, intervalSeconds: 60),
            MarketChartPoint(date: Self.bjDate(2026, 11, 27, 13, 30), price: 784.5, intervalSeconds: 60)
        ]
        let projected = axis.project(middayPoints)
        #expect(projected.count == 4)
        #expect(projected.map(\.slot) == [150, 180, 210, 270])
    }

    @Test func domesticNightOnlyFallbackUsesNightSessionAxisWithoutBlankLeftHalf() {
        let nightPoints = [
            MarketChartPoint(date: Self.bjDate(2026, 11, 27, 20, 2), price: 785.0, intervalSeconds: 60),
            MarketChartPoint(date: Self.bjDate(2026, 11, 27, 22, 0), price: 781.2, intervalSeconds: 60),
            MarketChartPoint(date: Self.bjDate(2026, 11, 27, 23, 14), price: 779.0, intervalSeconds: 60)
        ]
        let axis = RealtimeIntradayAxis.make(
            basis: .domestic,
            anchorDate: Self.bjDate(2026, 11, 27, 23, 14),
            points: nightPoints
        )

        #expect(axis.totalSlots == 390)
        #expect(axis.dividers.isEmpty)
        #expect(axis.ticks.map(\.label) == ["20:00", "22:00", "00:00", "02:30"])
        #expect(axis.slot(for: Self.bjDate(2026, 11, 27, 20, 0)) == 0)
        #expect(axis.slot(for: Self.bjDate(2026, 11, 27, 20, 2)) == 2)
        #expect(axis.slot(for: Self.bjDate(2026, 11, 27, 22, 0)) == 120)
        #expect(axis.slot(for: Self.bjDate(2026, 11, 27, 23, 14)) == 194)
        #expect(axis.slot(for: Self.bjDate(2026, 11, 28, 0, 0)) == 240)
        #expect(axis.slot(for: Self.bjDate(2026, 11, 28, 2, 30)) == 390)

        // 若包含日盘点（window=day），自动回到全天 780 槽位轴
        let fullDayPoints = [
            MarketChartPoint(date: Self.bjDate(2026, 11, 27, 9, 0), price: 765.8, intervalSeconds: 60)
        ] + nightPoints
        let fullAxis = RealtimeIntradayAxis.make(
            basis: .domestic,
            anchorDate: Self.bjDate(2026, 11, 27, 23, 14),
            points: fullDayPoints
        )
        #expect(fullAxis.totalSlots == 780)
        #expect(fullAxis.ticks.map(\.label) == ["09:00", "12:15", "15:30/20:00", "02:30"])
    }

    private struct UnifiedReferenceFixture: GoldPriceServicing, GoldQuoteServicing, GoldRealtimeServicing, GoldHistoryServicing {
        let quote: GoldQuote
        let realtime: [MarketChartPoint]
        let daily: [GoldDailyPrice]
        func fetchQuote() async throws -> GoldQuote { quote }
        func fetchDailyPrices() async throws -> [GoldDailyPrice] { daily }
        func fetchRealtime() async throws -> [MarketChartPoint] { realtime }
        func fetchHistory() async throws -> [GoldHistoryPoint] { [] }
    }

    @MainActor @Test func domesticHeadlineAndIntradayShareUnifiedReferenceCloseAfterNightOpen() async throws {
        let now = Self.bjDate(2026, 11, 27, 22, 30)
        // 新浪在 20:00 后把 prevClose 切换为今日 15:30 日盘收盘 784.0
        let nightQuote = GoldQuote(
            symbol: "AU9999", price: 779.0, open: 785.0, high: 787.5, low: 778.0,
            prevClose: 784.0, usdCNY: 6.6547, cnyPerGram: 779.0, asOf: now
        )
        let daily = [
            GoldDailyPrice(date: Self.bjDate(2026, 11, 26, 12, 0), open: 760, high: 766, low: 758, close: 764.5)
        ]

        // 1. 全天（日盘 + 夜盘）：顶部今日涨跌与分时图较昨收统一使用前一日收盘 764.5（均显示红涨 +14.50）
        let fullDayPoints = [
            MarketChartPoint(date: Self.bjDate(2026, 11, 27, 9, 0), price: 765.8, intervalSeconds: 60),
            MarketChartPoint(date: Self.bjDate(2026, 11, 27, 15, 30), price: 784.0, intervalSeconds: 60),
            MarketChartPoint(date: Self.bjDate(2026, 11, 27, 20, 0), price: 785.0, intervalSeconds: 60),
            MarketChartPoint(date: now, price: 779.0, intervalSeconds: 60)
        ]
        let fullFixture = UnifiedReferenceFixture(quote: nightQuote, realtime: fullDayPoints, daily: daily)
        let fullModel = MarketHomeViewModel(
            basis: .domestic,
            dailyService: fullFixture,
            quoteService: fullFixture,
            realtimeService: fullFixture,
            historyService: fullFixture,
            nowProvider: { now }
        )
        fullModel.range = .realtime
        await fullModel.refresh()

        let fullSnapshot = try #require(fullModel.quoteSnapshot)
        #expect(fullModel.realtimeReferenceClose == 764.5)
        #expect(fullSnapshot.prevCloseCNY == 764.5)
        #expect(abs((fullSnapshot.changeCNY ?? 0) - 14.5) < 1e-6)
        #expect(fullModel.realtimeIntradayAxis.totalSlots == 780)

        // 2. 降级仅夜盘（window=session）：两者统一使用夜盘昨收 784.0（均显示 -5.00），轴切为 20:00–02:30
        let nightOnlyPoints = [
            MarketChartPoint(date: Self.bjDate(2026, 11, 27, 20, 2), price: 785.0, intervalSeconds: 60),
            MarketChartPoint(date: now, price: 779.0, intervalSeconds: 60)
        ]
        let nightFixture = UnifiedReferenceFixture(quote: nightQuote, realtime: nightOnlyPoints, daily: daily)
        let nightModel = MarketHomeViewModel(
            basis: .domestic,
            dailyService: nightFixture,
            quoteService: nightFixture,
            realtimeService: nightFixture,
            historyService: nightFixture,
            nowProvider: { now }
        )
        nightModel.range = .realtime
        await nightModel.refresh()

        let nightSnapshot = try #require(nightModel.quoteSnapshot)
        #expect(nightModel.realtimeReferenceClose == 784.0)
        #expect(nightSnapshot.prevCloseCNY == 784.0)
        #expect(abs((nightSnapshot.changeCNY ?? 0) - (-5.0)) < 1e-6)
        #expect(nightModel.realtimeIntradayAxis.totalSlots == 390)
    }

    @Test func internationalAxisHandlesWinterAndSummerDSTFull23Hours() {
        // 冬令时：北京时间 07:00 开盘至次日 06:00（1380 分钟）
        let winterAxis = RealtimeIntradayAxis.make(basis: .international, anchorDate: Self.bjDate(2026, 11, 27, 22, 30))
        #expect(winterAxis.totalSlots == 1380)
        #expect(winterAxis.ticks.first?.label == "07:00")
        #expect(winterAxis.ticks.last?.label == "06:00")
        #expect(winterAxis.slot(for: Self.bjDate(2026, 11, 27, 7, 0)) == 0)
        #expect(winterAxis.slot(for: Self.bjDate(2026, 11, 27, 22, 30)) == 930)

        // 夏令时：北京时间 06:00 开盘至次日 05:00
        let summerAxis = RealtimeIntradayAxis.make(basis: .international, anchorDate: Self.bjDate(2026, 7, 15, 20, 0))
        #expect(summerAxis.ticks.first?.label == "06:00")
        #expect(summerAxis.ticks.last?.label == "05:00")
        #expect(summerAxis.slot(for: Self.bjDate(2026, 7, 15, 6, 0)) == 0)
        #expect(summerAxis.slot(for: Self.bjDate(2026, 7, 15, 20, 0)) == 840)
    }

    @Test func referenceCloseResolvesPriorDayCloseForDomesticDayPlusNight() {
        let dayPoints = [
            MarketChartPoint(date: Self.bjDate(2026, 11, 27, 9, 0), price: 765.8, intervalSeconds: 60),
            MarketChartPoint(date: Self.bjDate(2026, 11, 27, 15, 30), price: 784.0, intervalSeconds: 60),
            MarketChartPoint(date: Self.bjDate(2026, 11, 27, 22, 30), price: 779.0, intervalSeconds: 60)
        ]
        // 晚间 20:00 后新浪 quote.prevClose 已切换为今天 15:30 日盘收盘 784.0
        let nightQuote = GoldQuote(symbol: "AU9999", price: 779.0, open: 785.0, high: 787.5, low: 778.0, prevClose: 784.0, usdCNY: 6.6547, cnyPerGram: 779.0, asOf: Self.bjDate(2026, 11, 27, 22, 30))
        let daily = [
            GoldDailyPrice(date: Self.bjDate(2026, 11, 26, 12, 0), open: 760, high: 766, low: 758, close: 764.5)
        ]
        let resolved = RealtimeIntradayAxis.resolveReferenceClose(basis: .domestic, quote: nightQuote, points: dayPoints, daily: daily)
        #expect(resolved == 764.5)

        // 国际直接用 prevClose * usdCNY / 31.1034768
        let intlQuote = GoldQuote(symbol: "XAUUSD", price: 3636.88, open: 3566.84, high: 3685.11, low: 3557.8, prevClose: 3566.26, usdCNY: 6.6547, cnyPerGram: 778.12, asOf: Self.bjDate(2026, 11, 27, 22, 30))
        let intlRef = RealtimeIntradayAxis.resolveReferenceClose(basis: .international, quote: intlQuote, points: [], daily: [])
        #expect(abs((intlRef ?? 0) - 3566.26 * 6.6547 / 31.1034768) < 1e-6)
    }

    @Test func splitSegmentsInterpolatesExactReferenceCrossingsAndDomainEnforcesFloor() {
        let t0 = Self.bjDate(2026, 11, 27, 9, 0)
        let projected = [
            ProjectedIntradayPoint(slot: 0, date: t0, price: 760, intervalSeconds: 60),
            ProjectedIntradayPoint(slot: 10, date: t0.addingTimeInterval(600), price: 770, intervalSeconds: 60),
            ProjectedIntradayPoint(slot: 20, date: t0.addingTimeInterval(1200), price: 765, intervalSeconds: 60),
            ProjectedIntradayPoint(slot: 30, date: t0.addingTimeInterval(1800), price: 755, intervalSeconds: 60)
        ]
        // 昨收 765：0->10 在 slot=5 穿过 765 上行；20->30 在 slot=20 从 765 下行
        let segments = RealtimeIntradayAxis.splitSegments(points: projected, referenceClose: 765)
        #expect(segments.count == 3)
        #expect(segments[0].isAboveOrEqual == false)
        #expect(abs(segments[0].vertices.last!.slot - 5) < 1e-6)
        #expect(segments[0].vertices.last!.price == 765)
        #expect(segments[1].isAboveOrEqual == true)
        #expect(abs(segments[1].vertices.first!.slot - 5) < 1e-6)
        #expect(segments[2].isAboveOrEqual == false)

        // 微幅震荡（±0.05 元）应被最小振幅地板（≥1% 即 7.65 元）约束，避免横盘拉成过山车
        let flatDomain = RealtimeIntradayAxis.intradayDomain(prices: [765.01, 765.05], referenceClose: 765, scale: .linear)
        #expect(flatDomain.upperBound - flatDomain.lowerBound >= 7.65)
        #expect(flatDomain.contains(765))
    }

    @MainActor
    @Test func planAIntradayChartsRenderCleanlyForVisualReview() throws {
        // 1. 国际今日大涨（含早盘微跌破昨收绿段 + 午后大涨红段 + 右侧留白）
        let intlAxis = RealtimeIntradayAxis.make(basis: .international, anchorDate: Self.bjDate(2026, 11, 27, 22, 33))
        let intlSamples: [(Int, Int, Double)] = [
            (7, 0, 762.69), (8, 0, 764.17), (8, 53, 761.34), (9, 30, 765.30),
            (10, 10, 775.76), (11, 30, 775.67), (13, 30, 782.62), (15, 0, 782.46),
            (16, 20, 787.01), (17, 10, 788.37), (19, 30, 787.08), (21, 10, 784.78), (22, 33, 778.01)
        ]
        let intlProjected = intlAxis.project(intlSamples.map {
            MarketChartPoint(date: Self.bjDate(2026, 11, 27, $0.0, $0.1), price: $0.2, intervalSeconds: 60)
        })

        // 2. 国内日盘+夜盘无断档连贯走势
        let domAxis = RealtimeIntradayAxis.make(basis: .domestic, anchorDate: Self.bjDate(2026, 11, 27, 22, 34))
        let domSamples: [(Int, Int, Double)] = [
            (9, 0, 765.8), (10, 15, 776.1), (11, 30, 776.9),
            (13, 30, 781.8), (15, 30, 784.0),
            (20, 0, 785.0), (20, 15, 787.2), (21, 30, 780.4), (22, 34, 779.0)
        ]
        let domProjected = domAxis.project(domSamples.map {
            MarketChartPoint(date: Self.bjDate(2026, 11, 27, $0.0, $0.1), price: $0.2, intervalSeconds: 60)
        })

        let review = VStack(alignment: .leading, spacing: 18) {
            Text("方案 A · 国际当日大涨（07:00 → 22:33 / 次日 06:00）")
                .font(.caption.bold()).foregroundStyle(GoldTheme.goldSoft)
            RealtimeIntradayChartView(
                points: intlProjected,
                axis: intlAxis,
                referenceClose: 763.01,
                priceScale: .linear,
                isZoomed: false,
                isLive: true,
                selectedPoint: nil,
                breakEvenPrice: nil,
                onBeginGesture: {},
                onTransform: { _, _, _ in },
                onEndGesture: {},
                onSelectSlotFraction: { _ in },
                onReset: {},
                pointTimeLabel: { _ in "11/27 17:10" }
            )
            .frame(height: 220)
            .padding(10)
            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)

            Text("方案 A · 国内日盘 + 夜盘无断档连贯（09:00 → 22:34 / 02:30）")
                .font(.caption.bold()).foregroundStyle(GoldTheme.goldSoft)
            RealtimeIntradayChartView(
                points: domProjected,
                axis: domAxis,
                referenceClose: 764.50,
                priceScale: .linear,
                isZoomed: false,
                isLive: true,
                selectedPoint: domProjected[4],
                breakEvenPrice: nil,
                onBeginGesture: {},
                onTransform: { _, _, _ in },
                onEndGesture: {},
                onSelectSlotFraction: { _ in },
                onReset: {},
                pointTimeLabel: { _ in "2026.11.27 15:30:00" }
            )
            .frame(height: 220)
            .padding(10)
            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        }
        .padding(16)
        .frame(width: 393)
        .background(GoldTheme.background)
        .environment(\.colorScheme, .dark)

        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 560)
        let host = UIHostingController(rootView: review)
        host.view.backgroundColor = UIColor(GoldTheme.background)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previous?.makeKey()
        }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: window.bounds.size, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sumly-intraday-plan-a", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("intraday-plan-a-review.png")
        try #require(image.pngData()).write(to: url)
        print("INTRADAY_PLAN_A_ARTIFACT: \(url.path)")
    }
}
