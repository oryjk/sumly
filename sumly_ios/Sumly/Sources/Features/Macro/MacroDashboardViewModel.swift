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

    private(set) var temperature: MacroTemperatureReport? {
        didSet { rebuildTemperatureDerivedState() }
    }
    private(set) var temperatureHistory: MacroTemperatureHistory? {
        didSet { rebuildTemperatureHistoryDerivedState() }
    }
    private(set) var treasury: MacroTreasuryReport? {
        didSet { rebuildTreasuryDerivedState() }
    }
    private(set) var catalog: MacroIndicatorsCatalog? {
        didSet { rebuildPanoramaDerivedState() }
    }
    private(set) var cot: MacroCotReport? {
        didSet { rebuildCotDerivedState() }
    }

    // 预计算的绘制序列与图表刻度上下文，避免 SwiftUI 每次 body 重绘 / 手指选点都 O(N) 扫描上千点
    private(set) var displayTemperatureHistoryPoints: [MacroTemperatureHistoryPoint] = []
    private(set) var hasTemperatureHistoryGoldPrices: Bool = false
    private(set) var displayTreasuryDebtSeries: [MacroTimePoint] = []
    private(set) var displayTreasuryRealYieldSeries: [MacroTimePoint] = []
    private(set) var displayTreasuryNominalYieldSeries: [MacroTimePoint] = []
    private(set) var displayCotPoints: [MacroCotPoint] = []

    private(set) var cachedDualHorizonSummary: MacroDualHorizonSummary?
    private(set) var cachedTreasuryPressureModel: MacroTreasuryPressureModel?
    private(set) var cachedPanoramaThermometerModel: MacroPanoramaThermometerModel = MacroPanoramaThermometerModel.make(temperature: nil, catalog: nil)
    private(set) var cachedTemperatureGoldPriceScaleContext: MacroChartScaleContext = MacroChartScaleContext.make(values: [], requestedScale: .linear, unit: "usd/oz", minLinearPadding: 10, desiredTickCount: 3)
    private(set) var cachedTreasuryDebtScaleContext: MacroChartScaleContext = MacroChartScaleContext.make(values: [], requestedScale: .linear, unit: "trillion_usd", minLinearPadding: 0.2, desiredTickCount: 4)
    private(set) var cachedTreasuryYieldScaleContext: MacroChartScaleContext = MacroChartScaleContext.make(values: [], requestedScale: .linear, unit: "%", includeZeroInLinear: true, minLinearPadding: 0.25, desiredTickCount: 4)
    private(set) var cachedCotScaleContext: MacroChartScaleContext = MacroChartScaleContext.make(values: [], requestedScale: .linear, unit: "contracts", includeZeroInLinear: true, minLinearPadding: 10_000, desiredTickCount: 4)

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

    var treasuryPressureModel: MacroTreasuryPressureModel? {
        cachedTreasuryPressureModel
    }

    var panoramaThermometerModel: MacroPanoramaThermometerModel {
        cachedPanoramaThermometerModel
    }

    func toggleSectionSelection(_ sectionID: String) {
        selectedSectionID = (selectedSectionID == sectionID) ? nil : sectionID
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
        cachedTemperatureGoldPriceScaleContext
    }

    var treasuryDebtScaleContext: MacroChartScaleContext {
        cachedTreasuryDebtScaleContext
    }

    var treasuryYieldScaleContext: MacroChartScaleContext {
        cachedTreasuryYieldScaleContext
    }

    var cotScaleContext: MacroChartScaleContext {
        cachedCotScaleContext
    }

    func setTemperatureGoldPriceScale(_ scale: MacroChartScale) {
        temperatureGoldPriceScale = MacroChartScale.effectiveScale(
            requested: scale,
            for: temperatureGoldPriceValues
        )
        rebuildTemperatureGoldScaleContext()
    }

    func setTreasuryDebtScale(_ scale: MacroChartScale) {
        treasuryDebtScale = MacroChartScale.effectiveScale(
            requested: scale,
            for: treasuryDebtValues
        )
        rebuildTreasuryScaleContexts()
    }

    func setTreasuryYieldScale(_ scale: MacroChartScale) {
        treasuryYieldScale = MacroChartScale.effectiveScale(
            requested: scale,
            for: treasuryYieldValues,
            pointCount: treasuryYieldPointCount
        )
        rebuildTreasuryScaleContexts()
    }

    func setCotScale(_ scale: MacroChartScale) {
        cotScale = MacroChartScale.effectiveScale(
            requested: scale,
            for: cotValues,
            pointCount: cotPointCount
        )
        rebuildCotScaleContext()
    }

    // MARK: - 派生缓存与极值保留降采样

    private func rebuildTemperatureDerivedState() {
        cachedDualHorizonSummary = temperature.map(MacroPresentation.dualHorizonSummary(for:))
        rebuildPanoramaDerivedState()
    }

    private func rebuildPanoramaDerivedState() {
        cachedPanoramaThermometerModel = MacroPanoramaThermometerModel.make(temperature: temperature, catalog: catalog)
    }

    private func rebuildTemperatureHistoryDerivedState() {
        let raw = temperatureHistory?.points ?? []
        displayTemperatureHistoryPoints = MacroChartDownsampler.downsample(
            raw,
            maxPoints: 180,
            primaryValue: \.score,
            secondaryValue: \.goldPriceUSD
        )
        hasTemperatureHistoryGoldPrices = raw.contains { $0.goldPriceUSD != nil }
        rebuildTemperatureGoldScaleContext()
    }

    private func rebuildTemperatureGoldScaleContext() {
        cachedTemperatureGoldPriceScaleContext = MacroChartScaleContext.make(
            values: temperatureGoldPriceValues,
            requestedScale: temperatureGoldPriceScale,
            unit: "usd/oz",
            minLinearPadding: 10,
            desiredTickCount: 3
        )
    }

    private func rebuildTreasuryDerivedState() {
        cachedTreasuryPressureModel = treasury.map(MacroTreasuryPressureModel.make(from:))
        displayTreasuryDebtSeries = MacroChartDownsampler.downsample(
            treasury?.debtSeries ?? [],
            maxPoints: 180,
            primaryValue: \.value
        )
        displayTreasuryRealYieldSeries = MacroChartDownsampler.downsample(
            treasury?.realYieldSeries ?? [],
            maxPoints: 180,
            primaryValue: \.value
        )
        displayTreasuryNominalYieldSeries = MacroChartDownsampler.downsample(
            treasury?.nominalYieldSeries ?? [],
            maxPoints: 180,
            primaryValue: \.value
        )
        rebuildTreasuryScaleContexts()
    }

    private func rebuildTreasuryScaleContexts() {
        cachedTreasuryDebtScaleContext = MacroChartScaleContext.make(
            values: treasuryDebtValues,
            requestedScale: treasuryDebtScale,
            unit: "trillion_usd",
            minLinearPadding: 0.2,
            desiredTickCount: 4
        )
        cachedTreasuryYieldScaleContext = MacroChartScaleContext.make(
            values: treasuryYieldValues,
            pointCount: treasuryYieldPointCount,
            requestedScale: treasuryYieldScale,
            unit: "%",
            includeZeroInLinear: true,
            minLinearPadding: 0.25,
            desiredTickCount: 4
        )
    }

    private func rebuildCotDerivedState() {
        displayCotPoints = MacroChartDownsampler.downsample(
            cot?.points ?? [],
            maxPoints: 180,
            primaryValue: \.mmNet,
            secondaryValue: \.swapNet
        )
        rebuildCotScaleContext()
    }

    private func rebuildCotScaleContext() {
        cachedCotScaleContext = MacroChartScaleContext.make(
            values: cotValues,
            pointCount: cotPointCount,
            requestedScale: cotScale,
            unit: "contracts",
            includeZeroInLinear: true,
            minLinearPadding: 10_000,
            desiredTickCount: 4
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

    /// 进场或切换 Tab 时按需加载当前 Tab 依赖，避免首帧并发拉取 5 个接口并礼让导航转场动画。
    func loadActiveTab(deferAfterTransition: Bool = false) async {
        if deferAfterTransition, selectedTab == .temperature, temperature != nil, temperatureHistory == nil {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
        }

        switch selectedTab {
        case .temperature:
            let needTemp = temperature == nil && !isLoadingTemperature
            let needHistory = temperatureHistory == nil && !isLoadingHistory
            guard needTemp || needHistory else { return }
            await withTaskGroup(of: Void.self) { group in
                if needTemp {
                    group.addTask { await self.loadTemperature() }
                }
                if needHistory {
                    group.addTask { await self.loadTemperatureHistory() }
                }
            }
        case .treasury:
            if treasury == nil && !isLoadingTreasury {
                await loadTreasury()
            }
        case .panorama:
            let needTemp = temperature == nil && !isLoadingTemperature && temperatureError == nil
            let needCatalog = catalog == nil && !isLoadingCatalog
            let needCot = cot == nil && !isLoadingCot
            guard needTemp || needCatalog || needCot else { return }
            await withTaskGroup(of: Void.self) { group in
                if needTemp {
                    group.addTask { await self.loadTemperature() }
                }
                if needCatalog {
                    group.addTask { await self.loadCatalog() }
                }
                if needCot {
                    group.addTask { await self.loadCot() }
                }
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

    /// 切换至「宏观全景」Tab 时温和补拉缺失的温度或目录数据（不打断进行中请求，也不重复刷失败接口）。
    func ensurePanoramaDependenciesLoaded() async {
        let needTemp = temperature == nil && !isLoadingTemperature && temperatureError == nil
        let needCatalog = catalog == nil && !isLoadingCatalog && catalogError == nil
        guard needTemp || needCatalog else { return }

        await withTaskGroup(of: Void.self) { group in
            if needTemp {
                group.addTask { await self.loadTemperature() }
            }
            if needCatalog {
                group.addTask { await self.loadCatalog() }
            }
        }
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
            rebuildTemperatureGoldScaleContext()
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
            rebuildTreasuryScaleContexts()
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
            rebuildCotScaleContext()
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
                return L10n.tr("网络连接不可用，请检查网络后重试")
            case .timedOut:
                return L10n.tr("请求超时，请稍后重试")
            default:
                return L10n.tr("宏观数据获取失败，请稍后重试")
            }
        }
        return L10n.tr("宏观数据暂时不可用，请稍后重试")
    }
}

/// 极值保留视觉抽稀器：保留首尾点与每个桶内的主序列最小/最大值（按时间顺序去重），
/// 在肉眼无损的前提下把上千个 Swift Charts `.monotone` 样条节点压缩到 ~180 点以内。
enum MacroChartDownsampler {
    static func downsample<T>(
        _ items: [T],
        maxPoints: Int = 180,
        primaryValue: (T) -> Double,
        secondaryValue: ((T) -> Double?)? = nil
    ) -> [T] {
        guard maxPoints >= 4, items.count > maxPoints else { return items }
        let interiorCount = items.count - 2
        let bucketCount = max(1, (maxPoints - 2) / 2)
        var pickedIndices: [Int] = []
        pickedIndices.reserveCapacity(maxPoints)
        pickedIndices.append(0)

        for bucket in 0..<bucketCount {
            let start = 1 + (bucket * interiorCount) / bucketCount
            let end = 1 + ((bucket + 1) * interiorCount) / bucketCount
            guard start < end else { continue }

            var minIdx = start
            var maxIdx = start
            var minVal = primaryValue(items[start])
            var maxVal = minVal

            if let secondaryValue {
                var secMinIdx = start
                var secMaxIdx = start
                var secMin = secondaryValue(items[start]) ?? minVal
                var secMax = secMin

                for idx in (start + 1)..<end {
                    let v = primaryValue(items[idx])
                    if v < minVal { minVal = v; minIdx = idx }
                    if v > maxVal { maxVal = v; maxIdx = idx }
                    if let sv = secondaryValue(items[idx]) {
                        if sv < secMin { secMin = sv; secMinIdx = idx }
                        if sv > secMax { secMax = sv; secMaxIdx = idx }
                    }
                }
                // 如果主序列只选中 1 个点且次序列极值不同，附带次序列最显著点
                if minIdx == maxIdx && secMaxIdx != minIdx {
                    maxIdx = secMaxIdx
                } else if minIdx == maxIdx && secMinIdx != minIdx {
                    maxIdx = secMinIdx
                }
            } else {
                for idx in (start + 1)..<end {
                    let v = primaryValue(items[idx])
                    if v < minVal { minVal = v; minIdx = idx }
                    if v > maxVal { maxVal = v; maxIdx = idx }
                }
            }

            if minIdx <= maxIdx {
                if pickedIndices.last != minIdx { pickedIndices.append(minIdx) }
                if pickedIndices.last != maxIdx { pickedIndices.append(maxIdx) }
            } else {
                if pickedIndices.last != maxIdx { pickedIndices.append(maxIdx) }
                if pickedIndices.last != minIdx { pickedIndices.append(minIdx) }
            }
        }

        let lastIdx = items.count - 1
        if pickedIndices.last != lastIdx {
            pickedIndices.append(lastIdx)
        }
        return pickedIndices.map { items[$0] }
    }
}
