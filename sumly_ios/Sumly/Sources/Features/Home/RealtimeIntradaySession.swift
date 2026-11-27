import Foundation

/// 投影到连续交易日时间轴上的单个分时点：保留原始 `Date` 与 `price`，同时提供无断档的 `slot`（单位：交易分钟）。
struct ProjectedIntradayPoint: Sendable, Equatable {
    let slot: Double
    let date: Date
    let price: Double
    let intervalSeconds: Int
}

/// 分时横轴刻度标签（用于固定交易日进度展示）。
struct IntradayAxisTick: Sendable, Equatable, Identifiable {
    let slot: Double
    let label: String
    var id: Double { slot }
}

/// 国内交易日时段切换分界线（如午休 11:30/13:30、夜盘 20:00）。
struct IntradaySessionDivider: Sendable, Equatable, Identifiable {
    let slot: Double
    let label: String
    var id: Double { slot }
}

/// 按昨收基准价切分后的连续涨/跌分段（交点经线性插值对齐昨收价，保证红绿填充零缝隙）。
struct IntradaySplitSegment: Sendable, Equatable {
    struct Vertex: Sendable, Equatable {
        let slot: Double
        let price: Double
    }
    let isAboveOrEqual: Bool
    let vertices: [Vertex]
}

/// 完整当日分时连续压缩时间轴（纯逻辑、`Sendable`）：
/// - 国内 Au99.99：将当日早盘（09:00–11:30，150m）、午盘（13:30–15:30，120m）与当晚夜盘（20:00–次日 02:30，390m）
///   无缝拼接为 `0...660` 连续交易分钟轴，整天走势零断档。
/// - 国际 XAUUSD：按美东 `America/New_York` 18:00 交易日切换点（自动适配夏/冬令时，对应北京时间 06:00/07:00）
///   映射为 `0...1380`（23 小时）连续进度轴。
struct RealtimeIntradayAxis: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        /// `dayAnchor` 为该交易日北京时间 00:00。
        case domestic(dayAnchor: Date)
        /// `sessionOpen` 为该交易日美东 18:00 对应的绝对时刻。
        case international(sessionOpen: Date)
    }

    static let shanghaiTimeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 3600)!
    static let newYorkTimeZone = TimeZone(identifier: "America/New_York") ?? TimeZone(secondsFromGMT: -5 * 3600)!

    static let domesticMorningMinutes: Double = 150  // 09:00 - 11:30
    static let domesticAfternoonMinutes: Double = 120 // 13:30 - 15:30
    static let domesticNightMinutes: Double = 390     // 20:00 - 次日 02:30
    static let domesticTotalSlots: Double = 660       // 11 小时
    static let internationalTotalSlots: Double = 1380 // 23 小时

    let kind: Kind

    var totalSlots: Double {
        switch kind {
        case .domestic: Self.domesticTotalSlots
        case .international: Self.internationalTotalSlots
        }
    }

    var dividers: [IntradaySessionDivider] {
        switch kind {
        case .domestic:
            return [
                IntradaySessionDivider(slot: Self.domesticMorningMinutes, label: L10n.tr("午休")),
                IntradaySessionDivider(slot: Self.domesticMorningMinutes + Self.domesticAfternoonMinutes, label: L10n.tr("20:00 夜盘"))
            ]
        case .international:
            return []
        }
    }

    var ticks: [IntradayAxisTick] {
        switch kind {
        case .domestic:
            return [
                IntradayAxisTick(slot: 0, label: "09:00"),
                IntradayAxisTick(slot: Self.domesticMorningMinutes, label: "11:30/13:30"),
                IntradayAxisTick(slot: Self.domesticMorningMinutes + Self.domesticAfternoonMinutes, label: "20:00"),
                IntradayAxisTick(slot: Self.domesticTotalSlots, label: "02:30")
            ]
        case .international(let sessionOpen):
            let cal = Self.calendar(for: Self.shanghaiTimeZone)
            func clockLabel(_ minutesOffset: Double) -> String {
                let d = sessionOpen.addingTimeInterval(minutesOffset * 60)
                let h = cal.component(.hour, from: d)
                let m = cal.component(.minute, from: d)
                return String(format: "%02d:%02d", h, m)
            }
            return [
                IntradayAxisTick(slot: 0, label: clockLabel(0)),
                IntradayAxisTick(slot: 420, label: clockLabel(420)),
                IntradayAxisTick(slot: 900, label: clockLabel(900)),
                IntradayAxisTick(slot: Self.internationalTotalSlots, label: clockLabel(Self.internationalTotalSlots))
            ]
        }
    }

    /// 按行情口径与锚定时刻（优先最新成交点，其次当前时间）构造当日连续时间轴。
    static func make(basis: GoldMarketBasis, anchorDate: Date) -> RealtimeIntradayAxis {
        switch basis {
        case .domestic:
            let cal = calendar(for: shanghaiTimeZone)
            let hour = cal.component(.hour, from: anchorDate)
            let base = hour < 9 ? (cal.date(byAdding: .day, value: -1, to: anchorDate) ?? anchorDate) : anchorDate
            let comps = cal.dateComponents([.year, .month, .day], from: base)
            let dayAnchor = cal.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 0, minute: 0)) ?? base
            return RealtimeIntradayAxis(kind: .domestic(dayAnchor: dayAnchor))
        case .international:
            let nyCal = calendar(for: newYorkTimeZone)
            let hour = nyCal.component(.hour, from: anchorDate)
            let base = hour < 18 ? (nyCal.date(byAdding: .day, value: -1, to: anchorDate) ?? anchorDate) : anchorDate
            let comps = nyCal.dateComponents([.year, .month, .day], from: base)
            let open = nyCal.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 18, minute: 0)) ?? base
            return RealtimeIntradayAxis(kind: .international(sessionOpen: open))
        }
    }

    /// 将真实时间戳映射到无断档连续交易分钟槽位 `[0, totalSlots]`。
    func slot(for date: Date) -> Double {
        switch kind {
        case .domestic(let dayAnchor):
            // 相对 dayAnchor 00:00 的分钟数（09:00 = 540, 11:30 = 690, 13:30 = 810, 15:30 = 930, 20:00 = 1200, 次日 02:30 = 1590）
            let minute = date.timeIntervalSince(dayAnchor) / 60.0
            if minute <= 540 { return 0 }
            if minute <= 690 { return minute - 540 }
            if minute < 810 { return 150 }
            if minute <= 930 { return 150 + (minute - 810) }
            if minute < 1200 { return 270 }
            if minute <= 1590 { return 270 + (minute - 1200) }
            return Self.domesticTotalSlots
        case .international(let sessionOpen):
            let minute = date.timeIntervalSince(sessionOpen) / 60.0
            return min(max(minute, 0), Self.internationalTotalSlots)
        }
    }

    /// 投影有序分时点并保证槽位严格非递减（同一槽位保留最新点）。
    func project(_ points: [MarketChartPoint]) -> [ProjectedIntradayPoint] {
        guard !points.isEmpty else { return [] }
        var result: [ProjectedIntradayPoint] = []
        result.reserveCapacity(points.count)
        for p in points where p.price.isFinite && p.price > 0 {
            let s = slot(for: p.date)
            let projected = ProjectedIntradayPoint(slot: s, date: p.date, price: p.price, intervalSeconds: p.intervalSeconds)
            if let last = result.last, abs(last.slot - s) < 1e-6 {
                result[result.count - 1] = projected
            } else {
                result.append(projected)
            }
        }
        return result
    }

    /// 二分查找距离目标槽位最近的实际投影点。
    static func nearestPoint(in points: [ProjectedIntradayPoint], toSlot target: Double) -> ProjectedIntradayPoint? {
        guard !points.isEmpty else { return nil }
        var low = 0
        var high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].slot < target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        if low == 0 { return points[0] }
        if low >= points.count { return points[points.count - 1] }
        let prev = points[low - 1]
        let next = points[low]
        return abs(prev.slot - target) <= abs(next.slot - target) ? prev : next
    }

    /// 解析用于当日分时图 `0.00%` 水平虚线与红涨绿跌分色的昨收基准价。
    static func resolveReferenceClose(
        basis: GoldMarketBasis,
        quote: GoldQuote?,
        points: [MarketChartPoint],
        daily: [GoldDailyPrice]
    ) -> Double? {
        switch basis {
        case .international:
            guard let quote, quote.prevClose.isFinite, quote.prevClose > 0,
                  quote.usdCNY.isFinite, quote.usdCNY > 0 else {
                return points.first?.price
            }
            return quote.prevClose * quote.usdCNY / 31.1034768
        case .domestic:
            // 当国内当日曲线同时包含今天白天日盘（09:00–15:30）与当晚夜盘（>=20:00 或次日 <=02:30）时，
            // 新浪实时报价在 20:00 后已把 prevClose 切换为今日日盘收盘价；
            // 为保证整条日+夜连贯曲线的「昨收基准线」与今日白天涨势一致，优先采用日盘前一个交易日的收盘价。
            if let first = points.first, let last = points.last {
                let cal = calendar(for: shanghaiTimeZone)
                let firstHour = cal.component(.hour, from: first.date)
                let lastHour = cal.component(.hour, from: last.date)
                let hasDaySession = (9..<16).contains(firstHour)
                let hasNightSession = lastHour >= 20 || lastHour < 9
                if hasDaySession && hasNightSession {
                    let dayAnchor = cal.startOfDay(for: first.date)
                    if let priorBar = daily
                        .filter({ cal.startOfDay(for: $0.date) < dayAnchor && $0.close.isFinite && $0.close > 0 })
                        .max(by: { $0.date < $1.date }) {
                        return priorBar.close
                    }
                }
            }
            if let quote, quote.prevClose.isFinite, quote.prevClose > 0 {
                return quote.prevClose
            }
            return points.first?.price
        }
    }

    /// 方案 A 当日分时纵轴范围：强制包住昨收价并设定 ±0.5% 最小振幅地板，避免微幅震荡被放大失真。
    static func intradayDomain(
        prices: [Double],
        referenceClose: Double?,
        scale: ChartPriceScale
    ) -> ClosedRange<Double> {
        var scaledValues = prices.compactMap(scale.value)
        if let ref = referenceClose, let scaledRef = scale.value(ref) {
            scaledValues.append(scaledRef)
        }
        guard let rawLow = scaledValues.min(), let rawHigh = scaledValues.max() else {
            return 0...1
        }
        let minSpan: Double = {
            if scale == .linear {
                let anchor = referenceClose ?? ((rawLow + rawHigh) / 2)
                return max(anchor * 0.01, 1.0) // 至少 ±0.5%（总跨度 1%）或 1 元/克
            } else {
                return 0.0044 // log10(1.01) ≈ 0.00432
            }
        }()
        let rawSpan = rawHigh - rawLow
        if rawSpan < minSpan {
            let center = referenceClose.flatMap(scale.value) ?? ((rawLow + rawHigh) / 2)
            let half = minSpan / 2
            let low = min(rawLow, center - half)
            let high = max(rawHigh, center + half)
            let span = high - low
            return (low - span * 0.14)...(high + span * 0.16)
        }
        return (rawLow - rawSpan * 0.14)...(rawHigh + rawSpan * 0.16)
    }

    /// 按昨收基准价精确拆分红涨/绿跌连续段，并在每次穿越基准价时线性插值精确交点。
    static func splitSegments(
        points: [ProjectedIntradayPoint],
        referenceClose: Double
    ) -> [IntradaySplitSegment] {
        guard !points.isEmpty else { return [] }
        if points.count == 1 {
            let p = points[0]
            return [IntradaySplitSegment(
                isAboveOrEqual: p.price >= referenceClose,
                vertices: [.init(slot: p.slot, price: p.price)]
            )]
        }

        var segments: [IntradaySplitSegment] = []
        var currentAbove = points[0].price >= referenceClose
        var currentVertices: [IntradaySplitSegment.Vertex] = [
            .init(slot: points[0].slot, price: points[0].price)
        ]

        for idx in 1..<points.count {
            let prev = points[idx - 1]
            let curr = points[idx]
            let prevAbove = prev.price >= referenceClose
            let currAbove = curr.price >= referenceClose

            if prevAbove == currAbove {
                currentVertices.append(.init(slot: curr.slot, price: curr.price))
            } else {
                let deltaP = curr.price - prev.price
                let ratio = abs(deltaP) > 1e-12 ? (referenceClose - prev.price) / deltaP : 0.5
                let clampedRatio = min(max(ratio, 0), 1)
                let crossSlot = prev.slot + (curr.slot - prev.slot) * clampedRatio
                let crossVertex = IntradaySplitSegment.Vertex(slot: crossSlot, price: referenceClose)

                currentVertices.append(crossVertex)
                segments.append(IntradaySplitSegment(isAboveOrEqual: currentAbove, vertices: currentVertices))

                currentAbove = currAbove
                currentVertices = [crossVertex, .init(slot: curr.slot, price: curr.price)]
            }
        }

        if !currentVertices.isEmpty {
            segments.append(IntradaySplitSegment(isAboveOrEqual: currentAbove, vertices: currentVertices))
        }
        return segments
    }

    private static func calendar(for timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }
}
