import Foundation

/// Display-only compression: keep both real endpoints of each horizontal run.
/// Removing the last flat sample would turn a flat period into an early ramp.
enum RealtimeChartCompaction {
    static func points(_ samples: [MarketChartPoint]) -> [MarketChartPoint] {
        guard samples.count > 2 else { return samples }
        var result = [samples[0]]
        result.reserveCapacity(samples.count)
        for index in 1..<(samples.count - 1) {
            let previous = samples[index - 1]
            let point = samples[index]
            let next = samples[index + 1]
            let before = point.date.timeIntervalSince(previous.date)
            let after = next.date.timeIntervalSince(point.date)
            // The API supports five-second samples and a real minute fallback.
            // Keep the observations bordering longer interruptions as well.
            let interior = point.price == previous.price && point.price == next.price
                && point.granularity == .realtime && previous.granularity == .realtime && next.granularity == .realtime
                && before > 0 && before <= 60 && after > 0 && after <= 60
            if !interior { result.append(point) }
        }
        result.append(samples[samples.count - 1])
        return result
    }
}
