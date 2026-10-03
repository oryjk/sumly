import Foundation

enum HoldingAlertKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case breakEven, returnPercent, profitAmount, price
    var id: String { rawValue }
    var title: String {
        switch self {
        case .breakEven: "达到真实保本"
        case .returnPercent: "真实收益率目标"
        case .profitAmount: "预计盈利金额目标"
        case .price: "参考金价目标"
        }
    }
}

struct HoldingAlert: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var kind: HoldingAlertKind
    var threshold: Double
    var enabled: Bool
    var basis: GoldMarketBasis
    var previousPrice: Double?
    var previousAsOf: Date?
    var armed = false
    var lastTriggeredAt: Date?
    var isValid: Bool {
        threshold.isFinite && threshold >= 0 && (kind != .price || threshold > 0)
    }
    mutating func resetBaseline() { previousPrice = nil; previousAsOf = nil; armed = false }
}

extension HoldingRecord {
    var alerts: [HoldingAlert] {
        guard let data = alertsJSON.data(using: .utf8), let alerts = try? JSONDecoder().decode([HoldingAlert].self, from: data) else { return [] }
        return alerts
    }
    func setAlerts(_ alerts: [HoldingAlert]) throws {
        alertsJSON = String(decoding: try JSONEncoder().encode(alerts), as: UTF8.self)
    }
    func resetAlertBaselines() {
        var values = alerts
        for i in values.indices { values[i].resetBaseline() }
        if let data = try? JSONEncoder().encode(values) { alertsJSON = String(decoding: data, as: UTF8.self) }
    }
}

enum HoldingAlertEngine {
    static func evaluate(_ alert: inout HoldingAlert, input: GoldReturnInput, price: Double, asOf: Date, now: Date) -> Bool {
        guard alert.enabled, alert.isValid, price.isFinite, price > 0,
              now.timeIntervalSince(asOf) >= -60, now.timeIntervalSince(asOf) <= 300,
              let result = GoldReturnCalculator.calculate(input, referencePrice: price) else { return false }
        if let previous = alert.previousAsOf, asOf <= previous { return false }
        let recovering = alert.previousAsOf.map { asOf.timeIntervalSince($0) > 300 } ?? false
        if recovering { alert.resetBaseline() }
        if let previous = alert.previousPrice, abs(price / previous - 1) > 0.2 { return false }
        let target: Double
        switch alert.kind {
        case .breakEven: target = result.breakEvenPrice
        case .price: target = alert.threshold
        case .profitAmount:
            guard let value = GoldReturnCalculator.referencePrice(input, targetProceeds: input.totalCost + alert.threshold) else { return false }
            target = value
        case .returnPercent:
            guard input.totalCost > 0 else { return false }
            guard let value = GoldReturnCalculator.referencePrice(input, targetProceeds: input.totalCost * (1 + alert.threshold / 100)) else { return false }
            target = value
        }
        guard target.isFinite else { return false }
        let wasArmed = alert.armed
        alert.previousPrice = price; alert.previousAsOf = asOf
        if price < target - max(0.01, target * 0.001) { alert.armed = true }
        guard wasArmed, price >= target else { return false }
        alert.armed = false
        if let last = alert.lastTriggeredAt, now.timeIntervalSince(last) < 86400 { return false }
        alert.lastTriggeredAt = now
        return true
    }
}

/// 表单仅编辑配置；保存时与最新运行状态合并，避免倒退正在更新的冷却/基线。
enum HoldingAlertForm {
    static func merge(edited: [HoldingAlert], values: [String], latest: [HoldingAlert], basis: GoldMarketBasis) -> [HoldingAlert]? {
        guard edited.count == values.count else { return nil }
        var result: [HoldingAlert] = []
        for i in edited.indices {
            let desired = edited[i]
            let current = latest.first { $0.id == desired.id } ?? desired
            var threshold = current.threshold
            if desired.kind != .breakEven {
                let parsed = Double(values[i].trimmingCharacters(in: .whitespacesAndNewlines))
                if let parsed, parsed.isFinite, parsed >= 0, desired.kind != .price || parsed > 0 {
                    threshold = parsed
                } else if desired.enabled { return nil }
            } else { threshold = 0 }
            var merged = current
            merged.enabled = desired.enabled; merged.threshold = threshold; merged.basis = basis
            guard !merged.enabled || merged.isValid else { return nil }
            if current.enabled != merged.enabled || current.threshold != threshold || current.basis != basis {
                merged.resetBaseline()
            }
            result.append(merged)
        }
        return result
    }
}
