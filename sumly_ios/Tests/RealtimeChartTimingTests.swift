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
    let close = timingDate("2026-11-21T02:30:00+08:00")
    let sunday = timingDate("2026-11-22T10:38:00+08:00")
    let service = FrozenMarketFixture(end: close)
    let model = MarketHomeViewModel(
        basis: .domestic,
        dailyService: service,
        quoteService: service,
        realtimeService: service,
        nowProvider: { sunday },
        calendar: timingCalendar()
    )
    model.range = .realtime
    await model.refresh()
    #expect(model.realtimeTiming.state == .paused)
    #expect(model.message == "周末休市 · 收盘价 11/21 02:30")
    #expect(model.message?.contains("更新暂停") == false)
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
    #expect(timing.sessionStatus == .holidayClosed)
    #expect(timing.caption == "当前休市 · 展示收盘前走势")
    #expect(!timing.caption.contains("更新暂停"))
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

@Test func sessionIntradayCaptionsSwitchAtThirtyMinuteThreshold() {
    let now = timingDate("2026-11-21T02:30:00+08:00")
    let calendar = timingCalendar()

    // <= 30 minutes keeps compact 20-minute copy.
    let shortLive = RealtimeChartTiming(latestSample: now, latestQuote: now, basis: .domestic, intervalSeconds: 5, windowSpan: 1800, now: now, calendar: calendar)
    let shortPaused = RealtimeChartTiming(latestSample: now.addingTimeInterval(-3600), latestQuote: now.addingTimeInterval(-3600), basis: .domestic, intervalSeconds: 60, windowSpan: 1800, now: now, calendar: calendar)
    #expect(shortLive.caption == "交易中 · 最近 20 分钟")
    #expect(shortPaused.caption == "周末休市 · 展示收盘前走势")
    #expect(!shortPaused.caption.contains("更新暂停"))

    // > 30 minutes switches to full trading-session intraday copy.
    let sessionLive = RealtimeChartTiming(latestSample: now, latestQuote: now, basis: .domestic, intervalSeconds: 60, windowSpan: 23400, now: now, calendar: calendar)
    let sessionPaused = RealtimeChartTiming(latestSample: now.addingTimeInterval(-3600), latestQuote: now.addingTimeInterval(-3600), basis: .domestic, intervalSeconds: 60, windowSpan: 23400, now: now, calendar: calendar)
    let sessionEmpty = RealtimeChartTiming(latestSample: nil, latestQuote: nil, basis: .domestic, intervalSeconds: 60, windowSpan: 23400, now: now, calendar: calendar)
    #expect(sessionLive.state == .live)
    #expect(sessionLive.caption == "交易中 · 本交易时段分时")
    #expect(sessionPaused.state == .paused)
    #expect(sessionPaused.caption == "周末休市 · 展示最近交易时段分时")
    #expect(!sessionPaused.caption.contains("更新暂停"))
    #expect(sessionEmpty.caption == "暂无实时走势")
}

@Test func domesticSessionStatusCoversWeekendMiddayClosedHolidayAndAwaitingTrade() {
    let calendar = timingCalendar()

    // 周末休市：周六 02:35 / 周日 10:38 / 周一 08:50
    let satClosed = timingDate("2026-11-21T02:35:00+08:00")
    let sunClosed = timingDate("2026-11-22T10:38:00+08:00")
    let monBeforeOpen = timingDate("2026-11-23T08:50:00+08:00")
    let friNightClose = timingDate("2026-11-21T02:30:00+08:00")
    for now in [satClosed, sunClosed, monBeforeOpen] {
        let status = GoldMarketSessionStatus.resolve(basis: .domestic, now: now, latestQuote: friNightClose)
        #expect(status == .weekendClosed)
        #expect(status.shortTitle(for: .domestic) == "周末休市")
        let timing = RealtimeChartTiming(latestSample: friNightClose, latestQuote: friNightClose, basis: .domestic, intervalSeconds: 60, windowSpan: 23400, now: now, calendar: calendar)
        #expect(timing.pausedMessage(for: friNightClose) == "周末休市 · 收盘价 11/21 02:30")
        #expect(timing.caption == "周末休市 · 展示最近交易时段分时")
    }

    // 连续日盘 11:30–13:30（无午休）：周二 12:00 属于正常交易时段，短暂无新价时按暂无新成交处理，不再误报午间休盘
    let tueMidday = timingDate("2026-11-24T12:00:00+08:00")
    let tueMorningLast = timingDate("2026-11-24T11:29:45+08:00")
    let middayTiming = RealtimeChartTiming(latestSample: tueMorningLast, latestQuote: tueMorningLast, basis: .domestic, intervalSeconds: 60, windowSpan: 9000, now: tueMidday, calendar: calendar)
    #expect(middayTiming.sessionStatus == .awaitingTrade)
    #expect(middayTiming.pausedMessage(for: tueMorningLast) == "暂无新成交 · 最近报价 11/24 11:29")
    #expect(middayTiming.caption == "暂无新成交 · 本交易时段分时")

    // 日盘收盘后：周二 17:00
    let tueAfterDay = timingDate("2026-11-24T17:00:00+08:00")
    let tueDayClose = timingDate("2026-11-24T15:30:00+08:00")
    let dayClosedTiming = RealtimeChartTiming(latestSample: tueDayClose, latestQuote: tueDayClose, basis: .domestic, intervalSeconds: 60, windowSpan: 23400, now: tueAfterDay, calendar: calendar)
    #expect(dayClosedTiming.sessionStatus == .closed)
    #expect(dayClosedTiming.pausedMessage(for: tueDayClose) == "已收盘 · 收盘价 11/24 15:30")
    #expect(dayClosedTiming.caption == "已收盘 · 展示最近交易时段分时")

    // 夜盘收盘后：周三 04:00
    let wedAfterNight = timingDate("2026-11-25T04:00:00+08:00")
    let wedNightClose = timingDate("2026-11-25T02:30:00+08:00")
    let nightClosedTiming = RealtimeChartTiming(latestSample: wedNightClose, latestQuote: wedNightClose, basis: .domestic, intervalSeconds: 60, windowSpan: 23400, now: wedAfterNight, calendar: calendar)
    #expect(nightClosedTiming.sessionStatus == .closed)
    #expect(nightClosedTiming.pausedMessage(for: wedNightClose) == "已收盘 · 收盘价 11/25 02:30")
    #expect(nightClosedTiming.caption == "已收盘 · 展示最近交易时段分时")

    // 工作日法定节假日（>6h 无新价）：10 月 1 日周四 10:30，距前一日收盘 > 6h
    let holidayNow = timingDate("2026-10-01T10:30:00+08:00")
    let preHolidayClose = timingDate("2026-09-30T15:30:00+08:00")
    let holidayTiming = RealtimeChartTiming(latestSample: preHolidayClose, latestQuote: preHolidayClose, basis: .domestic, intervalSeconds: 60, windowSpan: 23400, now: holidayNow, calendar: calendar)
    #expect(holidayTiming.sessionStatus == .holidayClosed)
    #expect(holidayTiming.pausedMessage(for: preHolidayClose) == "当前休市 · 最近报价 09/30 15:30")
    #expect(holidayTiming.caption == "当前休市 · 展示最近交易时段分时")

    // 盘中深夜零成交：周六 02:15 距 02:04 仅 11 分钟（仍在周五夜盘 00:00–02:30 内且 ≤ 6h）
    let satLateNight = timingDate("2026-11-21T02:15:00+08:00")
    let satQuietQuote = timingDate("2026-11-21T02:04:00+08:00")
    let quietSession = RealtimeChartTiming(latestSample: satQuietQuote, latestQuote: satQuietQuote, basis: .domestic, intervalSeconds: 60, windowSpan: 21600, now: satLateNight, calendar: calendar)
    let quietShort = RealtimeChartTiming(latestSample: satQuietQuote, latestQuote: satQuietQuote, basis: .domestic, intervalSeconds: 5, windowSpan: 1200, now: satLateNight, calendar: calendar)
    #expect(quietSession.sessionStatus == .awaitingTrade)
    #expect(quietSession.pausedMessage(for: satQuietQuote) == "暂无新成交 · 最近报价 11/21 02:04")
    #expect(quietSession.caption == "暂无新成交 · 本交易时段分时")
    #expect(quietShort.caption == "暂无新成交 · 最近可用走势")
}

@Test func internationalSessionStatusCoversWeekendDailyBreakDSTHolidayAndAwaitingTrade() {
    let calendar = timingCalendar()

    // 国际周末休市：美东周五 17:00 边界、周五 17:05、美东周六（北京周日 10:38）、美东周日 17:59
    let nyFriExactClose = timingDate("2026-11-20T17:00:00-05:00")
    let nyFriAfterClose = timingDate("2026-11-20T17:05:00-05:00")
    let beijingSunMorning = timingDate("2026-11-22T10:38:00+08:00") // 美东周六 21:38
    let nySunBeforeOpen = timingDate("2026-11-22T17:59:00-05:00")
    let lastIntlQuote = timingDate("2026-11-20T16:59:00-05:00") // 北京 11/21 05:59
    #expect(GoldMarketSessionStatus.resolve(basis: .international, now: nyFriExactClose, latestQuote: lastIntlQuote) == .weekendClosed)
    for now in [nyFriAfterClose, beijingSunMorning, nySunBeforeOpen] {
        let status = GoldMarketSessionStatus.resolve(basis: .international, now: now, latestQuote: lastIntlQuote)
        #expect(status == .weekendClosed)
        let timing = RealtimeChartTiming(latestSample: lastIntlQuote, latestQuote: lastIntlQuote, basis: .international, intervalSeconds: 60, windowSpan: 21600, now: now, calendar: calendar)
        #expect(timing.state == .paused)
        #expect(timing.pausedMessage(for: lastIntlQuote) == "周末休市 · 收盘价 11/21 05:59")
        #expect(timing.caption == "周末休市 · 展示最近交易时段分时")
    }

    // 美东每日 17:30 结算休盘（夏令时 EDT UTC-4 vs 冬令时 EST UTC-5）
    // 夏令时：2026-07-15（周三）美东 17:30 = 北京 07/16 05:30 -> dailyBreak；美东 18:05 = 北京 07/16 06:05 -> 已开盘
    let summerBreak = timingDate("2026-07-16T05:30:00+08:00")
    let summerQuote = timingDate("2026-07-16T04:59:00+08:00")
    let summerBreakTiming = RealtimeChartTiming(latestSample: summerQuote, latestQuote: summerQuote, basis: .international, intervalSeconds: 60, windowSpan: 21600, now: summerBreak, calendar: calendar)
    #expect(summerBreakTiming.sessionStatus == .dailyBreak)
    #expect(summerBreakTiming.pausedMessage(for: summerQuote) == "每日结算休盘 · 最近报价 07/16 04:59")
    #expect(summerBreakTiming.caption == "每日结算休盘 · 展示最近交易时段分时")

    let summerReopen = timingDate("2026-07-16T06:05:00+08:00")
    #expect(GoldMarketSessionStatus.resolve(basis: .international, now: summerReopen, latestQuote: summerQuote) == .awaitingTrade)

    // 冬令时：2026-11-18（周三）北京 11/19 05:30 是美东 16:30（仍在交易中），北京 11/19 06:30 是美东 17:30（结算休盘）
    let winterStillTrading = timingDate("2026-11-19T05:30:00+08:00")
    let winterQuote = timingDate("2026-11-19T05:20:00+08:00")
    #expect(GoldMarketSessionStatus.resolve(basis: .international, now: winterStillTrading, latestQuote: winterQuote) == .awaitingTrade)

    let winterBreak = timingDate("2026-11-19T06:30:00+08:00")
    let winterPreBreakQuote = timingDate("2026-11-19T05:59:00+08:00")
    let winterBreakTiming = RealtimeChartTiming(latestSample: winterPreBreakQuote, latestQuote: winterPreBreakQuote, basis: .international, intervalSeconds: 60, windowSpan: 21600, now: winterBreak, calendar: calendar)
    #expect(winterBreakTiming.sessionStatus == .dailyBreak)
    #expect(winterBreakTiming.pausedMessage(for: winterPreBreakQuote) == "每日结算休盘 · 最近报价 11/19 05:59")

    // 国际节假日休市（美东交易时段内但 > 6h 无新价）
    let intlHolidayNow = timingDate("2026-12-25T10:00:00-05:00")
    let intlPreHolidayQuote = timingDate("2026-12-24T13:30:00-05:00")
    let intlHolidayTiming = RealtimeChartTiming(latestSample: intlPreHolidayQuote, latestQuote: intlPreHolidayQuote, basis: .international, intervalSeconds: 60, windowSpan: 21600, now: intlHolidayNow, calendar: calendar)
    #expect(intlHolidayTiming.sessionStatus == .holidayClosed)
    #expect(intlHolidayTiming.pausedMessage(for: intlPreHolidayQuote).hasPrefix("当前休市 · 最近报价 "))
    #expect(intlHolidayTiming.caption == "当前休市 · 展示最近交易时段分时")

    // 国际交易时段内暂未刷新（≤ 6h）
    let intlOpenNow = timingDate("2026-11-22T18:10:00-05:00") // 美东周日 18:10 已开盘
    let intlRecentQuote = timingDate("2026-11-22T18:02:00-05:00")
    let intlAwaitingSession = RealtimeChartTiming(latestSample: intlRecentQuote, latestQuote: intlRecentQuote, basis: .international, intervalSeconds: 60, windowSpan: 21600, now: intlOpenNow, calendar: calendar)
    let intlAwaitingShort = RealtimeChartTiming(latestSample: intlRecentQuote, latestQuote: intlRecentQuote, basis: .international, intervalSeconds: 5, windowSpan: 1200, now: intlOpenNow, calendar: calendar)
    #expect(intlAwaitingSession.sessionStatus == .awaitingTrade)
    #expect(intlAwaitingSession.pausedMessage(for: intlRecentQuote) == "报价暂未刷新 · 最近报价 11/23 07:02")
    #expect(intlAwaitingSession.caption == "报价暂未刷新 · 本交易时段分时")
    #expect(intlAwaitingShort.caption == "报价暂未刷新 · 最近可用走势")
}

@Test func allStatusCopyExcludesStiffPauseWordingAndInvestmentAdvice() {
    let calendar = timingCalendar()
    let forbiddenTerms = ["更新暂停", "建议买入", "建议卖出", "抄底", "加仓", "止盈", "止损", "必涨", "必跌"]
    let scenarios: [(GoldMarketBasis, String, String)] = [
        (.domestic, "2026-11-22T10:38:00+08:00", "2026-11-21T02:30:00+08:00"),
        (.domestic, "2026-11-24T12:00:00+08:00", "2026-11-24T11:29:00+08:00"),
        (.domestic, "2026-11-24T17:00:00+08:00", "2026-11-24T15:30:00+08:00"),
        (.domestic, "2026-10-01T10:30:00+08:00", "2026-09-30T15:30:00+08:00"),
        (.domestic, "2026-11-21T02:15:00+08:00", "2026-11-21T02:04:00+08:00"),
        (.international, "2026-11-22T10:38:00+08:00", "2026-11-20T16:59:00-05:00"),
        (.international, "2026-07-16T05:30:00+08:00", "2026-07-16T04:59:00+08:00"),
        (.international, "2026-12-25T10:00:00-05:00", "2026-12-24T13:30:00-05:00"),
        (.international, "2026-11-22T18:10:00-05:00", "2026-11-22T18:02:00-05:00")
    ]
    for (basis, nowISO, quoteISO) in scenarios {
        let now = timingDate(nowISO)
        let quote = timingDate(quoteISO)
        for span: TimeInterval in [1200, 23400] {
            let timing = RealtimeChartTiming(latestSample: quote, latestQuote: quote, basis: basis, intervalSeconds: 60, windowSpan: span, now: now, calendar: calendar)
            let texts = [timing.caption, timing.pausedMessage(for: quote)]
            for text in texts {
                for term in forbiddenTerms {
                    #expect(!text.contains(term), "Unexpected term \(term) in \(text)")
                }
            }
        }
    }
}

@Test func crossMidnightAndMultiHourSessionLabelsFormatCleanly() {
    let calendar = timingCalendar()
    let nightStart = timingDate("2026-11-20T20:00:00+08:00")
    let nightEnd = timingDate("2026-11-21T02:30:00+08:00")
    let weekendNow = timingDate("2026-11-21T14:00:00+08:00")
    let nightWindow = nightStart...nightEnd
    let nightTiming = RealtimeChartTiming(
        latestSample: nightEnd,
        latestQuote: nightEnd,
        intervalSeconds: 60,
        windowSpan: nightEnd.timeIntervalSince(nightStart),
        now: weekendNow,
        calendar: calendar
    )
    #expect(nightTiming.windowLabel(nightWindow) == "11/20 20:00 — 11/21 02:30")
    #expect(nightTiming.axisLabel(nightStart, window: nightWindow) == "11/20\n20:00")
    #expect(nightTiming.axisLabel(nightEnd, window: nightWindow) == "11/21\n02:30")
    #expect(nightTiming.boundaryLabel(nightStart, window: nightWindow) == "11/20 20:00")
    #expect(nightTiming.boundaryLabel(nightEnd, window: nightWindow) == "11/21 02:30")

    // Same-day multi-hour session viewed on the same day omits redundant date prefix.
    let dayStart = timingDate("2026-11-20T09:00:00+08:00")
    let dayEnd = timingDate("2026-11-20T15:30:00+08:00")
    let dayWindow = dayStart...dayEnd
    let sameDayTiming = RealtimeChartTiming(
        latestSample: dayEnd,
        latestQuote: dayEnd,
        intervalSeconds: 60,
        windowSpan: dayEnd.timeIntervalSince(dayStart),
        now: dayEnd,
        calendar: calendar
    )
    #expect(sameDayTiming.windowLabel(dayWindow) == "09:00 — 15:30")
    #expect(sameDayTiming.axisLabel(dayStart, window: dayWindow) == "09:00")
    #expect(sameDayTiming.axisLabel(dayEnd, window: dayWindow) == "15:30")
    #expect(sameDayTiming.boundaryLabel(dayStart, window: dayWindow) == "09:00")

    // Same-day multi-hour session viewed on a later day shows compact MM/dd once in windowLabel.
    let nextDayTiming = RealtimeChartTiming(
        latestSample: dayEnd,
        latestQuote: dayEnd,
        intervalSeconds: 60,
        windowSpan: dayEnd.timeIntervalSince(dayStart),
        now: weekendNow,
        calendar: calendar
    )
    #expect(nextDayTiming.windowLabel(dayWindow) == "11/20 09:00 — 15:30")
    #expect(nextDayTiming.axisLabel(dayStart, window: dayWindow) == "11/20\n09:00")
    #expect(nextDayTiming.boundaryLabel(dayEnd, window: dayWindow) == "11/20 15:30")
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
        model.range = .realtime
        await model.refresh()
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: ScrollView {
            MarketHomeChartContent(model: model, availableHeight: window.bounds.height - 110,
                showingHistorySources: .constant(false), showingDates: .constant(false)).padding(18)
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
