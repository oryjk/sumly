import Foundation

/// Anchors realtime / session intraday captions and time labels to real observations rather than wall-clock today.
struct RealtimeChartTiming: Sendable {
    enum State: Sendable { case live, paused, empty }

    static let sessionCaptionThreshold: TimeInterval = 30 * 60

    let latestSample: Date?
    let latestQuote: Date?
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

    var caption: String {
        switch state {
        case .live:
            isSessionWindow ? "实时更新 · 本交易时段分时" : "最近 20 分钟"
        case .paused:
            isSessionWindow ? "休市停盘 · 最近交易时段分时" : "更新暂停 · 最近可用 20 分钟"
        case .empty:
            "暂无实时走势"
        }
    }

    func timestamp(_ date: Date) -> String { day(date) + " " + time(date, seconds: true) }

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
