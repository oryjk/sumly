import Foundation

/// 纯逻辑交易时段状态判断，按交易所真实时区区分休市、休盘、收盘与盘中暂无新成交。
enum GoldMarketSessionStatus: Sendable, Equatable {
    case weekendClosed
    case middayBreak
    case dailyBreak
    case closed
    case holidayClosed
    case awaitingTrade

    static let holidayThreshold: TimeInterval = 6 * 3600

    private static let shanghaiTimeZone = TimeZone(identifier: "Asia/Shanghai")!
    private static let newYorkTimeZone = TimeZone(identifier: "America/New_York")!

    func shortTitle(for basis: GoldMarketBasis) -> String {
        switch self {
        case .weekendClosed: L10n.tr("周末休市")
        case .middayBreak: L10n.tr("午间休盘")
        case .dailyBreak: L10n.tr("每日结算休盘")
        case .closed: L10n.tr("已收盘")
        case .holidayClosed: L10n.tr("当前休市")
        case .awaitingTrade: basis == .domestic ? L10n.tr("暂无新成交") : L10n.tr("报价暂未刷新")
        }
    }

    static func resolve(
        basis: GoldMarketBasis,
        now: Date,
        latestQuote: Date?
    ) -> GoldMarketSessionStatus {
        switch basis {
        case .domestic:
            return resolveDomestic(now: now, latestQuote: latestQuote)
        case .international:
            return resolveInternational(now: now, latestQuote: latestQuote)
        }
    }

    /// 上金所 Au99.99（北京时间 Asia/Shanghai）：
    /// - 周末休市：周六 02:30 起至周一 09:00 前（含周日全天）
    /// - 午间休盘：周一至周五 11:30 起至 13:30 前
    /// - 已收盘：周一至周五 15:30 起至 20:00 前，或周二至周五 02:30 起至 09:00 前
    /// - 其余时段为常规交易时段（含周六 00:00–02:30 夜盘尾段）；若距最近有效报价 > 6 小时判为法定节假日休市
    private static func resolveDomestic(now: Date, latestQuote: Date?) -> GoldMarketSessionStatus {
        let calendar = exchangeCalendar(for: shanghaiTimeZone)
        let weekday = calendar.component(.weekday, from: now) // 1 = Sun ... 7 = Sat
        let minuteOfDay = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

        if weekday == 1
            || (weekday == 7 && minuteOfDay >= 150)
            || (weekday == 2 && minuteOfDay < 540) {
            return .weekendClosed
        }
        if (2...6).contains(weekday), minuteOfDay >= 690, minuteOfDay < 810 {
            return .middayBreak
        }
        if (2...6).contains(weekday), minuteOfDay >= 930, minuteOfDay < 1200 {
            return .closed
        }
        if (3...6).contains(weekday), minuteOfDay >= 150, minuteOfDay < 540 {
            return .closed
        }
        if let latestQuote, now.timeIntervalSince(latestQuote) > holidayThreshold {
            return .holidayClosed
        }
        return .awaitingTrade
    }

    /// 国际伦敦金（美东 America/New_York，自动兼容夏冬令时）：
    /// - 周末休市：美东周五 17:00 起至周日 18:00 前
    /// - 每日结算休盘：美东周一至周四 17:00 起至 18:00 前
    /// - 其余时段为常规交易时段；若距最近有效报价 > 6 小时判为节假日休市
    private static func resolveInternational(now: Date, latestQuote: Date?) -> GoldMarketSessionStatus {
        let calendar = exchangeCalendar(for: newYorkTimeZone)
        let weekday = calendar.component(.weekday, from: now) // 1 = Sun ... 7 = Sat
        let minuteOfDay = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

        if (weekday == 6 && minuteOfDay >= 1020)
            || weekday == 7
            || (weekday == 1 && minuteOfDay < 1080) {
            return .weekendClosed
        }
        if (2...5).contains(weekday), minuteOfDay >= 1020, minuteOfDay < 1080 {
            return .dailyBreak
        }
        if let latestQuote, now.timeIntervalSince(latestQuote) > holidayThreshold {
            return .holidayClosed
        }
        return .awaitingTrade
    }

    private static func exchangeCalendar(for timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

/// Anchors realtime / session intraday captions and time labels to real observations rather than wall-clock today.
struct RealtimeChartTiming: Sendable {
    enum State: Sendable { case live, paused, empty }

    static let sessionCaptionThreshold: TimeInterval = 30 * 60

    let latestSample: Date?
    let latestQuote: Date?
    var basis: GoldMarketBasis = .domestic
    var intervalSeconds: Int = 5
    var windowSpan: TimeInterval = 0
    var now: Date = .now
    var calendar: Calendar = .current

    var state: State {
        guard let latestSample else { return .empty }
        let sampleTolerance = max(20, Double(intervalSeconds) * 2)
        if now.timeIntervalSince(latestSample) > sampleTolerance || latestQuote.map({ now.timeIntervalSince($0) > 180 }) == true {
            return .paused
        }
        return .live
    }

    var isSessionWindow: Bool { windowSpan > Self.sessionCaptionThreshold }

    var sessionStatus: GoldMarketSessionStatus {
        GoldMarketSessionStatus.resolve(basis: basis, now: now, latestQuote: latestQuote ?? latestSample)
    }

    var caption: String {
        switch state {
        case .live:
            return isSessionWindow ? L10n.tr("交易中 · 本交易时段分时") : L10n.tr("交易中 · 最近 20 分钟")
        case .paused:
            let status = sessionStatus
            let title = status.shortTitle(for: basis)
            switch status {
            case .awaitingTrade:
                return isSessionWindow
                    ? L10n.fmt("%@ · 本交易时段分时", title)
                    : L10n.fmt("%@ · 最近可用走势", title)
            case .weekendClosed, .middayBreak, .dailyBreak, .closed, .holidayClosed:
                return isSessionWindow
                    ? L10n.fmt("%@ · 展示最近交易时段分时", title)
                    : L10n.fmt("%@ · 展示收盘前走势", title)
            }
        case .empty:
            return L10n.tr("暂无实时走势")
        }
    }

    func pausedMessage(for date: Date) -> String {
        let shortTime = shortTimestamp(date)
        let status = sessionStatus
        let title = status.shortTitle(for: basis)
        switch status {
        case .weekendClosed, .closed:
            return L10n.fmt("%@ · 收盘价 %@", title, shortTime)
        case .middayBreak, .dailyBreak, .holidayClosed, .awaitingTrade:
            return L10n.fmt("%@ · 最近报价 %@", title, shortTime)
        }
    }

    func timestamp(_ date: Date) -> String { day(date) + " " + time(date, seconds: true) }

    func shortTimestamp(_ date: Date) -> String { shortDay(date) + " " + time(date, seconds: false) }

    func windowLabel(_ window: ClosedRange<Date>) -> String {
        let start = window.lowerBound
        let end = window.upperBound
        let span = end.timeIntervalSince(start)
        if span > Self.sessionCaptionThreshold {
            if !calendar.isDate(start, inSameDayAs: end) {
                return shortDay(start) + " " + time(start, seconds: false)
                    + " — "
                    + shortDay(end) + " " + time(end, seconds: false)
            }
            let prefix = calendar.isDate(end, inSameDayAs: now) ? "" : shortDay(start) + " "
            return prefix + time(start, seconds: false) + " — " + time(end, seconds: false)
        }
        if !calendar.isDate(start, inSameDayAs: end) {
            return timestamp(start) + " — " + timestamp(end)
        }
        let prefix = calendar.isDate(end, inSameDayAs: now) ? "" : day(start) + " "
        return prefix + time(start, seconds: true) + " — " + time(end, seconds: true)
    }

    func axisLabel(_ date: Date, window: ClosedRange<Date>) -> String {
        let span = window.upperBound.timeIntervalSince(window.lowerBound)
        let needsDate = !calendar.isDate(date, inSameDayAs: now)
            || !calendar.isDate(window.lowerBound, inSameDayAs: window.upperBound)
        let prefix: String
        if needsDate {
            prefix = (span > Self.sessionCaptionThreshold ? shortDay(date) : dottedMonthDay(date)) + "\n"
        } else {
            prefix = ""
        }
        return prefix + time(date, seconds: false)
    }

    /// Single-line boundary label for the overview navigator and accessibility text.
    func boundaryLabel(_ date: Date, window: ClosedRange<Date>) -> String {
        let span = window.upperBound.timeIntervalSince(window.lowerBound)
        let needsDate = !calendar.isDate(date, inSameDayAs: now)
            || !calendar.isDate(window.lowerBound, inSameDayAs: window.upperBound)
        guard needsDate else { return time(date, seconds: false) }
        let datePrefix = span > Self.sessionCaptionThreshold ? shortDay(date) : dottedMonthDay(date)
        return datePrefix + " " + time(date, seconds: false)
    }

    private func day(_ date: Date) -> String {
        String(format: "%04d.%02d.%02d", calendar.component(.year, from: date), calendar.component(.month, from: date), calendar.component(.day, from: date))
    }

    private func shortDay(_ date: Date) -> String {
        String(format: "%02d/%02d", calendar.component(.month, from: date), calendar.component(.day, from: date))
    }

    private func dottedMonthDay(_ date: Date) -> String {
        String(format: "%02d.%02d", calendar.component(.month, from: date), calendar.component(.day, from: date))
    }

    private func time(_ date: Date, seconds: Bool) -> String {
        let value = String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
        return seconds ? value + String(format: ":%02d", calendar.component(.second, from: date)) : value
    }
}
