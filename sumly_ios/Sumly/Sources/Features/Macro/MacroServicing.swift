import Foundation

/// 黄金温度、美国国债与宏观指标只读数据协议。
protocol MacroServicing: Sendable {
    func fetchTemperature() async throws -> MacroTemperatureReport
    func fetchTemperatureHistory(range: MacroHistoryRange) async throws -> MacroTemperatureHistory
    func fetchTreasury(range: MacroExtendedRange) async throws -> MacroTreasuryReport
    func fetchIndicators(section: String?) async throws -> MacroIndicatorsCatalog
    func fetchIndicatorDetail(seriesID: String, range: MacroExtendedRange) async throws -> MacroIndicatorDetail
    func fetchGoldCot(range: MacroHistoryRange) async throws -> MacroCotReport
}

extension MacroServicing {
    func fetchIndicators() async throws -> MacroIndicatorsCatalog {
        try await fetchIndicators(section: nil)
    }
}
