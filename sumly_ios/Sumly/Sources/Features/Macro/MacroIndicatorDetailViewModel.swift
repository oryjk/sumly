import Foundation
import Observation

@MainActor @Observable
final class MacroIndicatorDetailViewModel {
    let seriesID: String
    let initialSummary: MacroIndicatorSummary?

    private(set) var range: MacroExtendedRange = .fiveYears
    private(set) var chartScale: MacroChartScale = .linear
    private(set) var detail: MacroIndicatorDetail?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var selectedPoint: MacroTimePoint?

    @ObservationIgnored private let service: any MacroServicing
    @ObservationIgnored private var activeRequestID: UUID?

    init(
        seriesID: String,
        initialSummary: MacroIndicatorSummary? = nil,
        service: any MacroServicing = BackendMacroService()
    ) {
        self.seriesID = seriesID
        self.initialSummary = initialSummary
        self.service = service
    }

    var displayTitle: String {
        detail?.nameZh ?? initialSummary?.nameZh ?? seriesID
    }

    var displayUnit: String {
        detail?.unit ?? initialSummary?.unit ?? ""
    }

    var displayFrequency: String {
        detail?.frequency ?? initialSummary?.frequency ?? ""
    }

    var displaySource: String {
        detail?.source ?? initialSummary?.source ?? ""
    }

    var displayGoldRelation: String {
        detail?.goldRelation ?? initialSummary?.goldRelation ?? ""
    }

    var displayPlainNote: String {
        detail?.plainNote ?? initialSummary?.plainNote ?? ""
    }

    var latestValue: Double? {
        detail?.latestValue ?? initialSummary?.latestValue
    }

    var latestDate: String? {
        detail?.latestDate ?? initialSummary?.latestDate
    }

    var change5d: Double? { detail?.change5d ?? initialSummary?.change5d }
    var change20d: Double? { detail?.change20d ?? initialSummary?.change20d }
    var change3m: Double? { detail?.change3m ?? initialSummary?.change3m }
    var changeYoY: Double? { detail?.changeYoY ?? initialSummary?.changeYoY }
    var percentile3y: Double? { detail?.percentile3y ?? initialSummary?.percentile3y }

    var observations: [MacroTimePoint] {
        detail?.observations ?? []
    }

    var supportsLogScale: Bool {
        MacroChartScale.supportsLogScale(observations.map(\.value))
    }

    var effectiveChartScale: MacroChartScale {
        MacroChartScale.effectiveScale(requested: chartScale, for: observations.map(\.value))
    }

    var chartScaleContext: MacroChartScaleContext {
        MacroChartScaleContext.make(
            values: observations.map(\.value),
            requestedScale: chartScale,
            unit: displayUnit,
            desiredTickCount: 4
        )
    }

    var periodMin: MacroTimePoint? {
        observations.min { $0.value < $1.value }
    }

    var periodMax: MacroTimePoint? {
        observations.max { $0.value < $1.value }
    }

    func setChartScale(_ scale: MacroChartScale) {
        chartScale = MacroChartScale.effectiveScale(requested: scale, for: observations.map(\.value))
    }

    func load() async {
        await fetch(range: range)
    }

    func selectRange(_ newRange: MacroExtendedRange) async {
        guard newRange != range || detail == nil else { return }
        range = newRange
        selectedPoint = nil
        await fetch(range: newRange)
    }

    func selectPoint(near date: Date) {
        guard !observations.isEmpty else {
            selectedPoint = nil
            return
        }
        selectedPoint = observations.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private func fetch(range targetRange: MacroExtendedRange) async {
        let requestID = UUID()
        activeRequestID = requestID
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await service.fetchIndicatorDetail(seriesID: seriesID, range: targetRange)
            guard !Task.isCancelled, activeRequestID == requestID else { return }
            detail = loaded
            selectedPoint = nil
            reconcileChartScale()
            isLoading = false
        } catch is CancellationError {
            if activeRequestID == requestID { isLoading = false }
        } catch {
            guard !Task.isCancelled, activeRequestID == requestID else { return }
            errorMessage = MacroDashboardViewModel.userFacingError(error)
            isLoading = false
        }
    }

    private func reconcileChartScale() {
        chartScale = MacroChartScale.effectiveScale(requested: chartScale, for: observations.map(\.value))
    }
}
