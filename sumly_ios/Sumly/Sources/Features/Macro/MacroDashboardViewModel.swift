import Foundation
import Observation

@MainActor @Observable
final class MacroDashboardViewModel {
    var selectedTab: MacroDashboardTab = .temperature
    var selectedSectionID: String? = nil

    private(set) var temperatureRange: MacroHistoryRange = .threeYears
    private(set) var treasuryRange: MacroExtendedRange = .fiveYears
    private(set) var cotRange: MacroHistoryRange = .threeYears

    private(set) var temperatureGoldPriceScale: MacroChartScale = .linear
    private(set) var treasuryDebtScale: MacroChartScale = .linear
    private(set) var treasuryYieldScale: MacroChartScale = .linear
    private(set) var cotScale: MacroChartScale = .linear

    private(set) var temperature: MacroTemperatureReport?
    private(set) var temperatureHistory: MacroTemperatureHistory?
    private(set) var treasury: MacroTreasuryReport?
    private(set) var catalog: MacroIndicatorsCatalog?
    private(set) var cot: MacroCotReport?

    private(set) var isLoadingTemperature = false
    private(set) var isLoadingHistory = false
    private(set) var isLoadingTreasury = false
    private(set) var isLoadingCatalog = false
    private(set) var isLoadingCot = false

    private(set) var temperatureError: String?
    private(set) var historyError: String?
    private(set) var treasuryError: String?
    private(set) var catalogError: String?
    private(set) var cotError: String?

    @ObservationIgnored private let service: any MacroServicing
    @ObservationIgnored private var temperatureRequestID: UUID?
    @ObservationIgnored private var historyRequestID: UUID?
    @ObservationIgnored private var treasuryRequestID: UUID?
    @ObservationIgnored private var catalogRequestID: UUID?
    @ObservationIgnored private var cotRequestID: UUID?

    init(service: any MacroServicing = BackendMacroService()) {
        self.service = service
    }

    var isSummaryLoading: Bool {
        isLoadingTemperature && temperature == nil
    }

    var filteredSections: [MacroIndicatorSection] {
        guard let sections = catalog?.sections else { return [] }
        guard let selectedSectionID else { return sections }
        return sections.filter { $0.id == selectedSectionID }
    }

    var isRefreshingCurrentTab: Bool {
        switch selectedTab {
        case .temperature:
            isLoadingTemperature || isLoadingHistory
        case .treasury:
            isLoadingTreasury
        case .panorama:
            isLoadingCatalog || isLoadingCot
        }
    }

    // MARK: - 图表纵轴刻度上下文与自动校核

    var temperatureGoldPriceValues: [Double] {
        (temperatureHistory?.points ?? []).compactMap(\.goldPriceUSD)
    }

    var treasuryDebtValues: [Double] {
        (treasury?.debtSeries ?? []).map(\.value)
    }

    var treasuryYieldValues: [Double] {
        (treasury?.realYieldSeries ?? []).map(\.value)
            + (treasury?.nominalYieldSeries ?? []).map(\.value)
    }

    var treasuryYieldPointCount: Int {
        Set(
            (treasury?.realYieldSeries ?? []).map(\.date)
                + (treasury?.nominalYieldSeries ?? []).map(\.date)
        ).count
    }

    var cotValues: [Double] {
        (cot?.points ?? []).flatMap { [$0.mmNet, $0.swapNet] }
    }

    var cotPointCount: Int {
        cot?.points.count ?? 0
    }

    var temperatureGoldPriceScaleContext: MacroChartScaleContext {
        MacroChartScaleContext.make(
            values: temperatureGoldPriceValues,
            requestedScale: temperatureGoldPriceScale,
            unit: "usd/oz",
            minLinearPadding: 10,
            desiredTickCount: 3
        )
    }

    var treasuryDebtScaleContext: MacroChartScaleContext {
        MacroChartScaleContext.make(
            values: treasuryDebtValues,
            requestedScale: treasuryDebtScale,
            unit: "trillion_usd",
            minLinearPadding: 0.2,
            desiredTickCount: 4
        )
    }

    var treasuryYieldScaleContext: MacroChartScaleContext {
        MacroChartScaleContext.make(
            values: treasuryYieldValues,
            pointCount: treasuryYieldPointCount,
            requestedScale: treasuryYieldScale,
            unit: "%",
            includeZeroInLinear: true,
            minLinearPadding: 0.25,
            desiredTickCount: 4
        )
    }

    var cotScaleContext: MacroChartScaleContext {
        MacroChartScaleContext.make(
            values: cotValues,
            pointCount: cotPointCount,
            requestedScale: cotScale,
            unit: "contracts",
            includeZeroInLinear: true,
            minLinearPadding: 10_000,
            desiredTickCount: 4
        )
    }

    func setTemperatureGoldPriceScale(_ scale: MacroChartScale) {
        temperatureGoldPriceScale = MacroChartScale.effectiveScale(
            requested: scale,
            for: temperatureGoldPriceValues
        )
    }

    func setTreasuryDebtScale(_ scale: MacroChartScale) {
        treasuryDebtScale = MacroChartScale.effectiveScale(
            requested: scale,
            for: treasuryDebtValues
        )
    }

    func setTreasuryYieldScale(_ scale: MacroChartScale) {
        treasuryYieldScale = MacroChartScale.effectiveScale(
            requested: scale,
            for: treasuryYieldValues,
            pointCount: treasuryYieldPointCount
        )
    }

    func setCotScale(_ scale: MacroChartScale) {
        cotScale = MacroChartScale.effectiveScale(
            requested: scale,
            for: cotValues,
            pointCount: cotPointCount
        )
    }

    // MARK: - 组合加载

    /// 首页摘要卡片调用：并发加载温度与美债摘要。
    func loadSummary(force: Bool = false) async {
        let shouldLoadTemp = force || (temperature == nil && !isLoadingTemperature)
        let shouldLoadTreasury = force || (treasury == nil && !isLoadingTreasury)
        await withTaskGroup(of: Void.self) { group in
            if shouldLoadTemp {
                group.addTask { await self.loadTemperature() }
            }
            if shouldLoadTreasury {
                group.addTask { await self.loadTreasury() }
            }
        }
    }

    /// 宏观看板全量加载：各板块独立并发请求，单项失败不影响其他板块呈现。
    func loadDashboard(force: Bool = false) async {
        let needTemp = force || (temperature == nil && !isLoadingTemperature)
        let needHistory = force || (temperatureHistory == nil && !isLoadingHistory)
        let needTreasury = force || (treasury == nil && !isLoadingTreasury)
        let needCatalog = force || (catalog == nil && !isLoadingCatalog)
        let needCot = force || (cot == nil && !isLoadingCot)

        await withTaskGroup(of: Void.self) { group in
            if needTemp {
                group.addTask { await self.loadTemperature() }
            }
            if needHistory {
                group.addTask { await self.loadTemperatureHistory() }
            }
            if needTreasury {
                group.addTask { await self.loadTreasury() }
            }
            if needCatalog {
                group.addTask { await self.loadCatalog() }
            }
            if needCot {
                group.addTask { await self.loadCot() }
            }
        }
    }

    func refreshAll() async {
        await loadDashboard(force: true)
    }

    // MARK: - 分项加载

    func loadTemperature() async {
        guard !Task.isCancelled else { return }
        let requestID = UUID()
        temperatureRequestID = requestID
        isLoadingTemperature = true
        temperatureError = nil
        defer {
            if temperatureRequestID == requestID {
                isLoadingTemperature = false
            }
        }
        do {
            let report = try await service.fetchTemperature()
            guard !Task.isCancelled, temperatureRequestID == requestID else { return }
            temperature = report
        } catch {
            guard !Self.isCancellationError(error), temperatureRequestID == requestID else { return }
            temperatureError = Self.userFacingError(error)
        }
    }

    func selectTemperatureRange(_ range: MacroHistoryRange) async {
        guard range != temperatureRange || temperatureHistory == nil else { return }
        temperatureRange = range
        await loadTemperatureHistory(range: range)
    }

    func loadTemperatureHistory(range: MacroHistoryRange? = nil) async {
        guard !Task.isCancelled else { return }
        let targetRange = range ?? temperatureRange
        temperatureRange = targetRange
        let requestID = UUID()
        historyRequestID = requestID
        isLoadingHistory = true
        historyError = nil
        defer {
            if historyRequestID == requestID {
                isLoadingHistory = false
            }
        }
        do {
            let history = try await service.fetchTemperatureHistory(range: targetRange)
            guard !Task.isCancelled, historyRequestID == requestID else { return }
            temperatureHistory = history
            temperatureGoldPriceScale = MacroChartScale.effectiveScale(
                requested: temperatureGoldPriceScale,
                for: temperatureGoldPriceValues
            )
        } catch {
            guard !Self.isCancellationError(error), historyRequestID == requestID else { return }
            historyError = Self.userFacingError(error)
        }
    }

    func selectTreasuryRange(_ range: MacroExtendedRange) async {
        guard range != treasuryRange || treasury == nil else { return }
        treasuryRange = range
        await loadTreasury(range: range)
    }

    func loadTreasury(range: MacroExtendedRange? = nil) async {
        guard !Task.isCancelled else { return }
        let targetRange = range ?? treasuryRange
        treasuryRange = targetRange
        let requestID = UUID()
        treasuryRequestID = requestID
        isLoadingTreasury = true
        treasuryError = nil
        defer {
            if treasuryRequestID == requestID {
                isLoadingTreasury = false
            }
        }
        do {
            let report = try await service.fetchTreasury(range: targetRange)
            guard !Task.isCancelled, treasuryRequestID == requestID else { return }
            treasury = report
            treasuryDebtScale = MacroChartScale.effectiveScale(
                requested: treasuryDebtScale,
                for: treasuryDebtValues
            )
            treasuryYieldScale = MacroChartScale.effectiveScale(
                requested: treasuryYieldScale,
                for: treasuryYieldValues,
                pointCount: treasuryYieldPointCount
            )
        } catch {
            guard !Self.isCancellationError(error), treasuryRequestID == requestID else { return }
            treasuryError = Self.userFacingError(error)
        }
    }

    func loadCatalog() async {
        guard !Task.isCancelled else { return }
        let requestID = UUID()
        catalogRequestID = requestID
        isLoadingCatalog = true
        catalogError = nil
        defer {
            if catalogRequestID == requestID {
                isLoadingCatalog = false
            }
        }
        do {
            let result = try await service.fetchIndicators(section: nil)
            guard !Task.isCancelled, catalogRequestID == requestID else { return }
            catalog = result
        } catch {
            guard !Self.isCancellationError(error), catalogRequestID == requestID else { return }
            catalogError = Self.userFacingError(error)
        }
    }

    func selectCotRange(_ range: MacroHistoryRange) async {
        guard range != cotRange || cot == nil else { return }
        cotRange = range
        await loadCot(range: range)
    }

    func loadCot(range: MacroHistoryRange? = nil) async {
        guard !Task.isCancelled else { return }
        let targetRange = range ?? cotRange
        cotRange = targetRange
        let requestID = UUID()
        cotRequestID = requestID
        isLoadingCot = true
        cotError = nil
        defer {
            if cotRequestID == requestID {
                isLoadingCot = false
            }
        }
        do {
            let result = try await service.fetchGoldCot(range: targetRange)
            guard !Task.isCancelled, cotRequestID == requestID else { return }
            cot = result
            cotScale = MacroChartScale.effectiveScale(
                requested: cotScale,
                for: cotValues,
                pointCount: cotPointCount
            )
        } catch {
            guard !Self.isCancellationError(error), cotRequestID == requestID else { return }
            cotError = Self.userFacingError(error)
        }
    }

    nonisolated static func isCancellationError(_ error: Error) -> Bool {
        if Task.isCancelled || error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        return false
    }

    static func userFacingError(_ error: Error) -> String {
        if let serviceError = error as? BackendMacroService.ServiceError,
           let description = serviceError.errorDescription {
            return description
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "网络连接不可用，请检查网络后重试"
            case .timedOut:
                return "请求超时，请稍后重试"
            default:
                return "宏观数据获取失败，请稍后重试"
            }
        }
        return "宏观数据暂时不可用，请稍后重试"
    }
}
