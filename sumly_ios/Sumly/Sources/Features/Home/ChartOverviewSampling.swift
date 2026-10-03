import Foundation

enum ChartOverviewSampling {
    static func points(_ samples: [MarketChartPoint], daily: Bool) -> [MarketChartPoint] {
        // Real-time windows are small; a second stride could discard run/gap
        // endpoints and stretch the next price change across a flat interval.
        guard daily else { return RealtimeChartCompaction.points(samples) }
        let render = samples
        let step = max(1, render.count / 500)
        var result = stride(from: 0, to: render.count, by: step).map { render[$0] }
        if let last = render.last, result.last != last { result.append(last) }
        return result
    }
}
