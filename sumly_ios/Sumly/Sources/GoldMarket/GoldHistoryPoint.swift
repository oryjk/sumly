import Foundation

enum GoldPointGranularity: String, Codable, Sendable {
    case annual, daily, realtime
    var label: String {
        switch self {
        case .annual: L10n.tr("年度均价参考")
        case .daily: L10n.tr("日线收盘")
        case .realtime: L10n.tr("实时报价")
        }
    }
}
struct GoldHistoryPoint: Sendable, Equatable {
    let date: Date
    let price: Double // USD per troy ounce
    let granularity: GoldPointGranularity
    let source: String
}
protocol GoldHistoryServicing: Sendable {
    func fetchHistory() async throws -> [GoldHistoryPoint]
    func cachedHistory() async -> [GoldHistoryPoint]?
}

extension GoldHistoryServicing {
    func cachedHistory() async -> [GoldHistoryPoint]? { nil }
}
