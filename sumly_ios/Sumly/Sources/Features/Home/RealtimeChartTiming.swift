import Foundation

/// A frozen twenty-minute window is anchored to its real observations, not today.
struct RealtimeChartTiming {
    enum State { case live, paused, empty }
    let latestSample: Date?
    let latestQuote: Date?
    var intervalSeconds: Int = 5
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
    var caption: String {
        switch state {
        case .live: "最近 20 分钟"
        case .paused: "更新暂停 · 最近可用 20 分钟"
        case .empty: "暂无实时走势"
        }
    }
    func timestamp(_ date: Date) -> String { day(date) + " " + time(date, seconds: true) }
    func windowLabel(_ window: ClosedRange<Date>) -> String {
        let start = window.lowerBound
        let end = window.upperBound
        if !calendar.isDate(start, inSameDayAs: end) {
            return timestamp(start) + " — " + timestamp(end)
        }
        let prefix = calendar.isDate(end, inSameDayAs: now) ? "" : day(start) + " "
        return prefix + time(start, seconds: true) + " — " + time(end, seconds: true)
    }
    func axisLabel(_ date: Date, window: ClosedRange<Date>) -> String {
        let needsDate = !calendar.isDate(date, inSameDayAs: now)
            || !calendar.isDate(window.lowerBound, inSameDayAs: window.upperBound)
        let prefix = needsDate ? String(format: "%02d.%02d\n", calendar.component(.month, from: date), calendar.component(.day, from: date)) : ""
        return prefix + time(date, seconds: false)
    }
    private func day(_ date: Date) -> String {
        String(format: "%04d.%02d.%02d", calendar.component(.year, from: date), calendar.component(.month, from: date), calendar.component(.day, from: date))
    }
    private func time(_ date: Date, seconds: Bool) -> String {
        let value = String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
        return seconds ? value + String(format: ":%02d", calendar.component(.second, from: date)) : value
    }
}
