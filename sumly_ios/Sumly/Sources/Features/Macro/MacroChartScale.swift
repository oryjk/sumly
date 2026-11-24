import Foundation

/// 宏观走势图纵轴刻度模式（对齐首页「线性 / 对数」交互习惯）。
enum MacroChartScale: String, CaseIterable, Identifiable, Sendable, Equatable, Hashable {
    case linear = "线性"
    case logarithmic = "对数"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .linear: L10n.tr("线性")
        case .logarithmic: L10n.tr("对数")
        }
    }

    /// 只有当当前可视区间内至少有 2 个时间点且全部观测值有限并严格 > 0 时，才允许启用对数刻度。
    static func supportsLogScale(_ values: [Double], pointCount: Int? = nil) -> Bool {
        let effectiveCount = pointCount ?? values.count
        guard effectiveCount >= 2, !values.isEmpty else { return false }
        return values.allSatisfy { $0.isFinite && $0 > 0 }
    }

    /// 不可启用对数刻度时的具体原因；可用时返回 nil。
    static func logScaleDisabledReason(for values: [Double], pointCount: Int? = nil) -> MacroChartLogScaleDisabledReason? {
        if values.contains(where: { !$0.isFinite || $0 <= 0 }) {
            return .nonPositiveValues
        }
        let effectiveCount = pointCount ?? values.count
        if effectiveCount < 2 || values.isEmpty {
            return .insufficientPoints
        }
        return nil
    }

    /// 解析实际生效的刻度：当请求对数但数据不满足严格正值条件时，安全回退为线性。
    static func effectiveScale(requested: MacroChartScale, for values: [Double], pointCount: Int? = nil) -> MacroChartScale {
        guard requested == .logarithmic, supportsLogScale(values, pointCount: pointCount) else {
            return .linear
        }
        return .logarithmic
    }

    /// 将原始业务数值映射到绘图坐标空间（线性原值 / 对数 log10）。
    func plotValue(_ raw: Double) -> Double? {
        guard raw.isFinite else { return nil }
        switch self {
        case .linear:
            return raw
        case .logarithmic:
            guard raw > 0 else { return nil }
            let logged = log10(raw)
            return logged.isFinite ? logged : nil
        }
    }

    /// 将绘图坐标空间数值还原为真实业务数值（线性原值 / 对数 pow(10, y)）。
    func originalValue(fromPlotValue plotValue: Double) -> Double? {
        guard plotValue.isFinite else { return nil }
        switch self {
        case .linear:
            return plotValue
        case .logarithmic:
            let restored = pow(10.0, plotValue)
            return (restored.isFinite && restored > 0) ? restored : nil
        }
    }

    /// 计算带留白的绘图纵轴范围（确保有限且 lowerBound < upperBound）。
    func domain(
        for values: [Double],
        includeZeroInLinear: Bool = false,
        minLinearPadding: Double = 0.01
    ) -> ClosedRange<Double> {
        switch self {
        case .linear:
            let finite = values.filter(\.isFinite)
            guard var low = finite.min(), var high = finite.max() else {
                return 0...1
            }
            if includeZeroInLinear {
                low = min(low, 0)
                high = max(high, 0)
            }
            let span = high - low
            let pad = max(span * 0.08, max(abs(high), abs(low)) * 0.01, minLinearPadding)
            let lower = low - pad
            let upper = high + pad
            guard lower.isFinite, upper.isFinite, lower < upper else {
                return 0...1
            }
            return lower...upper

        case .logarithmic:
            let logged = values.compactMap { plotValue($0) }
            guard let low = logged.min(), let high = logged.max() else {
                return 0...1
            }
            let span = high - low
            let pad = span > 1e-6 ? span * 0.08 : 0.04
            let lower = low - pad
            let upper = high + pad
            guard lower.isFinite, upper.isFinite, lower < upper else {
                return 0...1
            }
            return lower...upper
        }
    }

    /// 格式化还原后的 Y 轴真实业务数值（兼顾极小跨度、极大跨度与 `< 1` 小数）。
    static func formatAxisValue(_ value: Double, unit: String, span: Double? = nil) -> String {
        guard value.isFinite else { return "—" }
        let cleanValue = abs(value) < 1e-12 ? 0.0 : value
        let normalized = unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sign = cleanValue < 0 ? "-" : ""
        let absVal = abs(cleanValue)
        let validSpan = span.flatMap { ($0.isFinite && $0 > 0) ? $0 : nil }

        switch normalized {
        case "%", "pct", "percent", "percentage":
            let digits = percentAxisDigits(absVal: absVal, span: validSpan)
            return "\(sign)\(formatFixed(absVal, digits: digits))%"

        case "trillion_usd", "usd_trillion":
            let digits = trillionAxisDigits(absVal: absVal, span: validSpan)
            return L10n.fmt("%@ 万亿", "\(sign)$\(formatGrouped(absVal, digits: digits))")

        case "billion_usd", "usd_billion":
            if absVal >= 1_000 {
                let tVal = absVal / 1_000
                let tSpan = validSpan.map { $0 / 1_000 }
                let digits = trillionAxisDigits(absVal: tVal, span: tSpan)
                return L10n.fmt("%@ 万亿", "\(sign)$\(formatGrouped(tVal, digits: digits))")
            }
            let digits = compactMagnitudeDigits(absVal: absVal, span: validSpan)
            return "\(sign)$\(formatGrouped(absVal, digits: digits))B"

        case "million_usd", "usd_million":
            if absVal >= 1_000_000 {
                let tVal = absVal / 1_000_000
                let tSpan = validSpan.map { $0 / 1_000_000 }
                let digits = trillionAxisDigits(absVal: tVal, span: tSpan)
                return L10n.fmt("%@ 万亿", "\(sign)$\(formatGrouped(tVal, digits: digits))")
            }
            if absVal >= 1_000 {
                let bVal = absVal / 1_000
                let bSpan = validSpan.map { $0 / 1_000 }
                let digits = compactMagnitudeDigits(absVal: bVal, span: bSpan)
                return "\(sign)$\(formatGrouped(bVal, digits: digits))B"
            }
            let digits = compactMagnitudeDigits(absVal: absVal, span: validSpan)
            return "\(sign)$\(formatGrouped(absVal, digits: digits))M"

        case "usd", "usd/oz", "usd_oz", "usd/troy_oz", "usd/bbl":
            return "\(sign)$\(formatCurrencyMagnitude(absVal, span: validSpan, allowCompactK: true))"

        case "cny/g", "cny_g":
            return "\(sign)¥\(formatCurrencyMagnitude(absVal, span: validSpan, allowCompactK: false))"

        case "tons", "tonnes":
            let digits = compactMagnitudeDigits(absVal: absVal, span: validSpan)
            return L10n.fmt("%@ 吨", "\(sign)\(formatGrouped(absVal, digits: digits))")

        case "contracts":
            if MacroLocalization.usesTenThousandScale {
                if absVal >= 10_000 {
                    let wVal = absVal / 10_000
                    let wSpan = validSpan.map { $0 / 10_000 }
                    let digits = scaledCompactDigits(scaledSpan: wSpan)
                    return L10n.fmt("%@万", "\(sign)\(formatGrouped(wVal, digits: digits))")
                }
                return "\(sign)\(formatGrouped(absVal, digits: 0))"
            } else {
                if absVal >= 1_000 {
                    let kVal = absVal / 1_000
                    let kSpan = validSpan.map { $0 / 1_000 }
                    let digits = scaledCompactDigits(scaledSpan: kSpan)
                    return "\(sign)\(formatGrouped(kVal, digits: digits))k"
                }
                return "\(sign)\(formatGrouped(absVal, digits: 0))"
            }

        default:
            return "\(sign)\(formatGenericMagnitude(absVal, span: validSpan))"
        }
    }

    // MARK: - 格式化辅助

    private static func percentAxisDigits(absVal: Double, span: Double?) -> Int {
        if let span {
            let step = span / 3.0
            if step < 0.005 { return 4 }
            if step < 0.05 { return 3 }
            if step < 0.5 { return 2 }
        }
        if absVal > 0 && absVal < 0.01 { return 3 }
        if absVal < 10 || (span ?? 10) < 5 { return 2 }
        if absVal < 100 { return 1 }
        return 0
    }

    private static func trillionAxisDigits(absVal: Double, span: Double?) -> Int {
        if let span {
            let step = span / 3.0
            if step < 0.005 { return 4 }
            if step < 0.05 { return 3 }
            if step < 0.5 { return 2 }
            if step < 2.5 { return 1 }
        }
        if absVal > 0 && absVal < 0.1 { return 3 }
        if absVal < 1 { return 2 }
        if absVal < 100 { return 1 }
        return 0
    }

    private static func compactMagnitudeDigits(absVal: Double, span: Double?) -> Int {
        if let span {
            let step = span / 3.0
            if step < 0.005 { return 4 }
            if step < 0.05 { return 3 }
            if step < 0.5 { return 2 }
            if step < 2.5 { return 1 }
        }
        if absVal > 0 && absVal < 0.1 { return 3 }
        if absVal < 1 { return 2 }
        if absVal < 100 { return 1 }
        return 0
    }

    private static func scaledCompactDigits(scaledSpan: Double?) -> Int {
        guard let scaledSpan, scaledSpan.isFinite, scaledSpan > 0 else { return 0 }
        let step = scaledSpan / 3.0
        if step < 0.005 { return 4 }
        if step < 0.05 { return 3 }
        if step < 0.5 { return 2 }
        if step < 2.5 { return 1 }
        return 0
    }

    private static func formatCurrencyMagnitude(_ absVal: Double, span: Double?, allowCompactK: Bool) -> String {
        if allowCompactK && absVal >= 1_000_000 {
            let mVal = absVal / 1_000_000
            let mSpan = span.map { $0 / 1_000_000 }
            let digits = scaledCompactDigits(scaledSpan: mSpan)
            return "\(formatGrouped(mVal, digits: digits))M"
        }
        if allowCompactK && absVal >= 10_000 {
            let kVal = absVal / 1_000
            let kSpan = span.map { $0 / 1_000 }
            let digits = scaledCompactDigits(scaledSpan: kSpan)
            return "\(formatGrouped(kVal, digits: digits))k"
        }
        let digits: Int
        if let span {
            let step = span / 3.0
            if step < 0.005 {
                digits = 4
            } else if step < 0.05 {
                digits = 3
            } else if step < 0.5 {
                digits = 2
            } else if step < 5 && absVal < 1_000 {
                digits = 1
            } else if absVal < 1 {
                digits = smallPositiveDigits(absVal)
            } else if absVal < 100 {
                digits = 1
            } else {
                digits = 0
            }
        } else if absVal > 0 && absVal < 1 {
            digits = smallPositiveDigits(absVal)
        } else if absVal < 100 {
            digits = 2
        } else {
            digits = 0
        }
        return formatGrouped(absVal, digits: digits)
    }

    private static func formatGenericMagnitude(_ absVal: Double, span: Double?) -> String {
        if absVal >= 1_000_000 {
            let mVal = absVal / 1_000_000
            let mSpan = span.map { $0 / 1_000_000 }
            let digits = scaledCompactDigits(scaledSpan: mSpan)
            return "\(formatGrouped(mVal, digits: digits))M"
        }
        if absVal >= 10_000 {
            let kVal = absVal / 1_000
            let kSpan = span.map { $0 / 1_000 }
            let digits = scaledCompactDigits(scaledSpan: kSpan)
            return "\(formatGrouped(kVal, digits: digits))k"
        }
        let digits: Int
        if let span {
            let step = span / 3.0
            if step < 0.005 {
                digits = 4
            } else if step < 0.05 {
                digits = 3
            } else if step < 0.5 {
                digits = 2
            } else if step < 2.5 {
                digits = 1
            } else if absVal > 0 && absVal < 1 {
                digits = smallPositiveDigits(absVal)
            } else {
                digits = 0
            }
        } else if absVal > 0 && absVal < 1 {
            digits = smallPositiveDigits(absVal)
        } else if absVal < 10 {
            digits = 2
        } else if absVal < 100 {
            digits = 1
        } else {
            digits = 0
        }
        return formatGrouped(absVal, digits: digits)
    }

    private static func smallPositiveDigits(_ absVal: Double) -> Int {
        if absVal < 0.001 { return 4 }
        if absVal < 0.01 { return 3 }
        if absVal < 0.1 { return 3 }
        return 2
    }

    private static func formatFixed(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }

    private static func formatGrouped(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }
}

/// 对数刻度禁用原因，供 UI 给出清晰且 C 端友好的轻量提示。
enum MacroChartLogScaleDisabledReason: Equatable, Sendable {
    case nonPositiveValues
    case insufficientPoints

    var message: String {
        switch self {
        case .nonPositiveValues:
            return L10n.tr("含零或负值，仅支持线性")
        case .insufficientPoints:
            return L10n.tr("数据点不足，仅支持线性")
        }
    }
}

/// 单个宏观图表的完整纵轴刻度上下文（纯数据、Sendable、可单测）。
struct MacroChartScaleContext: Sendable, Equatable {
    let requestedScale: MacroChartScale
    let effectiveScale: MacroChartScale
    let supportsLogScale: Bool
    let disabledReason: MacroChartLogScaleDisabledReason?
    let unit: String
    let domain: ClosedRange<Double>
    let yAxisTicks: [Double]
    let originalSpan: Double

    /// 将原始业务值映射到当前生效刻度的绘图值。
    func plotValue(_ raw: Double) -> Double? {
        effectiveScale.plotValue(raw)
    }

    /// 安全绘图值（保证不返回 nil，用于 AreaMark / LineMark / PointMark）。
    func clampedPlotValue(_ raw: Double) -> Double {
        plotValue(raw) ?? domain.lowerBound
    }

    /// 将绘图坐标还原为原始业务数值。
    func originalValue(fromPlotValue plotValue: Double) -> Double? {
        effectiveScale.originalValue(fromPlotValue: plotValue)
    }

    /// 将绘图坐标格式化为展示在 Y 轴上的真实业务标签（绝不裸露 log10 原值）。
    func axisLabel(forPlotValue plotValue: Double) -> String {
        guard let original = originalValue(fromPlotValue: plotValue) else { return "" }
        return MacroChartScale.formatAxisValue(original, unit: unit, span: originalSpan)
    }

    /// 构造宏观图表的刻度上下文。
    static func make(
        values: [Double],
        pointCount: Int? = nil,
        requestedScale: MacroChartScale,
        unit: String,
        includeZeroInLinear: Bool = false,
        minLinearPadding: Double = 0.01,
        desiredTickCount: Int = 4
    ) -> MacroChartScaleContext {
        let supportsLog = MacroChartScale.supportsLogScale(values, pointCount: pointCount)
        let disabledReason = MacroChartScale.logScaleDisabledReason(for: values, pointCount: pointCount)
        let effective = MacroChartScale.effectiveScale(requested: requestedScale, for: values, pointCount: pointCount)
        let domain = effective.domain(
            for: values,
            includeZeroInLinear: includeZeroInLinear,
            minLinearPadding: minLinearPadding
        )
        let origSpan = computeOriginalSpan(domain: domain, scale: effective)
        let clampedCount = max(2, desiredTickCount)
        let rawTicks: [Double]
        switch effective {
        case .linear:
            rawTicks = generateLinearTicks(domain: domain, desiredCount: clampedCount)
        case .logarithmic:
            rawTicks = generateLogTicks(domain: domain, desiredCount: clampedCount)
        }
        let ticks = deduplicateTicks(
            rawTicks,
            scale: effective,
            unit: unit,
            originalSpan: origSpan
        )

        return MacroChartScaleContext(
            requestedScale: requestedScale,
            effectiveScale: effective,
            supportsLogScale: supportsLog,
            disabledReason: disabledReason,
            unit: unit,
            domain: domain,
            yAxisTicks: ticks,
            originalSpan: origSpan
        )
    }

    // MARK: - 刻度生成与去重

    private static func computeOriginalSpan(domain: ClosedRange<Double>, scale: MacroChartScale) -> Double {
        switch scale {
        case .linear:
            let span = domain.upperBound - domain.lowerBound
            return (span.isFinite && span > 0) ? span : 1
        case .logarithmic:
            guard let low = scale.originalValue(fromPlotValue: domain.lowerBound),
                  let high = scale.originalValue(fromPlotValue: domain.upperBound) else {
                return 1
            }
            let span = high - low
            return (span.isFinite && span > 0) ? span : 1
        }
    }

    private static func deduplicateTicks(
        _ ticks: [Double],
        scale: MacroChartScale,
        unit: String,
        originalSpan: Double
    ) -> [Double] {
        var seen = Set<String>()
        var result: [Double] = []
        for tick in ticks {
            guard tick.isFinite,
                  let original = scale.originalValue(fromPlotValue: tick) else { continue }
            let label = MacroChartScale.formatAxisValue(original, unit: unit, span: originalSpan)
            if seen.insert(label).inserted {
                result.append(tick)
            }
        }
        return result
    }

    private static func generateLogTicks(domain: ClosedRange<Double>, desiredCount: Int) -> [Double] {
        let low = domain.lowerBound
        let high = domain.upperBound
        let logSpan = high - low
        guard low.isFinite, high.isFinite, logSpan > 0 else { return [] }

        let edgeMargin = logSpan * 0.03
        let innerLow = low + edgeMargin
        let innerHigh = high - edgeMargin
        let minGap = logSpan / Double(max(desiredCount, 2)) * 0.52

        let ladders: [[Double]]
        if logSpan >= 4.0 {
            ladders = [[1.0], [1.0, 3.0], [1.0, 2.0, 5.0]]
        } else if logSpan >= 2.0 {
            ladders = [[1.0, 3.0], [1.0, 2.0, 5.0], [1.0]]
        } else if logSpan >= 0.7 {
            ladders = [[1.0, 2.0, 5.0], [1.0, 1.5, 2.0, 3.0, 5.0, 7.0]]
        } else {
            ladders = [[1.0, 2.0, 5.0], [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0]]
        }

        let minExp = Int(floor(innerLow)) - 1
        let maxExp = Int(ceil(innerHigh)) + 1
        var bestTicks: [Double] = []

        if maxExp - minExp <= 600 {
            for multipliers in ladders {
                var candidates: [Double] = []
                for exp in minExp...maxExp {
                    for m in multipliers {
                        let plotY = Double(exp) + log10(m)
                        if plotY >= innerLow && plotY <= innerHigh {
                            candidates.append(plotY)
                        }
                    }
                }
                candidates.sort()
                let thinned = thinTicks(candidates, targetCount: desiredCount, minGap: minGap)
                if thinned.count >= min(desiredCount, 3) {
                    return thinned
                }
                if thinned.count > bestTicks.count {
                    bestTicks = thinned
                }
            }
        }

        // 窄跨度回退：在原始数值空间按整洁步长取点再映射回 log10，避免相邻刻度过疏或全为空。
        let origLow = pow(10.0, innerLow)
        let origHigh = pow(10.0, innerHigh)
        if origLow.isFinite, origHigh.isFinite, origHigh > origLow {
            let linearCandidates = niceStepsInRange(low: origLow, high: origHigh, desiredCount: desiredCount)
                .compactMap { v -> Double? in
                    guard v > 0 else { return nil }
                    let y = log10(v)
                    return (y.isFinite && y >= innerLow && y <= innerHigh) ? y : nil
                }
                .sorted()
            let thinned = thinTicks(linearCandidates, targetCount: desiredCount, minGap: minGap)
            if thinned.count > bestTicks.count {
                bestTicks = thinned
            }
        }

        if bestTicks.count >= 2 {
            return bestTicks
        }

        // 终极兜底：在绘图空间内均匀取点。
        return evenlySpacedTicks(low: low, high: high, count: desiredCount)
    }

    private static func generateLinearTicks(domain: ClosedRange<Double>, desiredCount: Int) -> [Double] {
        let low = domain.lowerBound
        let high = domain.upperBound
        let span = high - low
        guard low.isFinite, high.isFinite, span > 0 else { return [] }

        let edgeMargin = span * 0.03
        let innerLow = low + edgeMargin
        let innerHigh = high - edgeMargin
        let minGap = span / Double(max(desiredCount, 2)) * 0.50

        let candidates = niceStepsInRange(low: innerLow, high: innerHigh, desiredCount: desiredCount)
            .map { abs($0) < 1e-12 ? 0.0 : $0 }
        let thinned = thinTicks(candidates, targetCount: desiredCount, minGap: minGap)
        if thinned.count >= 2 {
            return thinned
        }
        return evenlySpacedTicks(low: low, high: high, count: desiredCount)
    }

    private static func niceStepsInRange(low: Double, high: Double, desiredCount: Int) -> [Double] {
        let span = high - low
        guard span.isFinite, span > 0 else { return [] }
        let rawStep = span / Double(max(desiredCount - 1, 1))
        let candidateSteps = niceStepCandidates(around: rawStep)
        var best: [Double] = []
        var bestScore = Int.max

        for step in candidateSteps where step > 0 && step.isFinite {
            let start = ceil(low / step - 1e-9) * step
            var values: [Double] = []
            for i in 0..<24 {
                let v = start + Double(i) * step
                if v > high + step * 1e-6 { break }
                if v >= low - step * 1e-6 {
                    values.append(v)
                }
            }
            guard values.count >= 2 else { continue }
            let diff = abs(values.count - desiredCount)
            if diff < bestScore || (diff == bestScore && values.count > best.count) {
                bestScore = diff
                best = values
            }
        }
        return best
    }

    private static func niceStepCandidates(around rawStep: Double) -> [Double] {
        guard rawStep.isFinite, rawStep > 0 else { return [] }
        let exponent = floor(log10(rawStep))
        let base = pow(10.0, exponent)
        guard base.isFinite, base > 0 else { return [] }
        let multipliers: [Double] = [0.5, 1.0, 2.0, 2.5, 5.0, 10.0]
        return multipliers.map { $0 * base }
    }

    private static func thinTicks(_ sorted: [Double], targetCount: Int, minGap: Double) -> [Double] {
        guard !sorted.isEmpty else { return [] }
        guard sorted.count > 1 else { return sorted }

        if sorted.count <= targetCount {
            var kept: [Double] = [sorted[0]]
            for value in sorted.dropFirst() {
                if let last = kept.last, value - last >= minGap {
                    kept.append(value)
                }
            }
            return kept
        }

        let first = sorted[0]
        let last = sorted[sorted.count - 1]
        var picked: [Double] = []
        for i in 0..<targetCount {
            let ratio = targetCount == 1 ? 0.5 : Double(i) / Double(targetCount - 1)
            let ideal = first + (last - first) * ratio
            let available = sorted.filter { candidate in
                if let prev = picked.last {
                    return candidate - prev >= minGap
                }
                return true
            }
            guard let closest = available.min(by: { abs($0 - ideal) < abs($1 - ideal) }) else {
                break
            }
            picked.append(closest)
        }
        return picked
    }

    private static func evenlySpacedTicks(low: Double, high: Double, count: Int) -> [Double] {
        let n = max(2, count)
        let span = high - low
        let inset = span * 0.12
        let start = low + inset
        let end = high - inset
        return (0..<n).map { i in
            let t = Double(i) / Double(n - 1)
            let val = start + (end - start) * t
            return abs(val) < 1e-12 ? 0.0 : val
        }
    }
}
