import Foundation
import WidgetKit

struct GoldWidgetEntry: TimelineEntry, Sendable {
    let date: Date
    let basis: GoldWidgetBasis
    let snapshot: GoldWidgetSnapshot?
    let isPlaceholder: Bool
}

struct GoldWidgetTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = GoldWidgetEntry
    typealias Intent = SelectGoldMarketIntent

    private let service: GoldWidgetSnapshotService

    init(service: GoldWidgetSnapshotService = .shared) {
        self.service = service
    }

    func placeholder(in context: Context) -> GoldWidgetEntry {
        GoldWidgetEntry(
            date: Date(),
            basis: .domestic,
            snapshot: .previewPlaceholder(basis: .domestic),
            isPlaceholder: true
        )
    }

    func snapshot(for configuration: SelectGoldMarketIntent, in context: Context) async -> GoldWidgetEntry {
        let basis = configuration.market.basis
        let now = Date()
        if context.isPreview {
            let preview = service.cachedSnapshot(for: basis) ?? .previewPlaceholder(basis: basis)
            return GoldWidgetEntry(date: now, basis: basis, snapshot: preview, isPlaceholder: false)
        }
        let snapshot = await service.loadSnapshot(for: basis, now: now)
        return GoldWidgetEntry(date: now, basis: basis, snapshot: snapshot, isPlaceholder: false)
    }

    func timeline(for configuration: SelectGoldMarketIntent, in context: Context) async -> Timeline<GoldWidgetEntry> {
        let basis = configuration.market.basis
        let now = Date()
        let snapshot = await service.loadSnapshot(for: basis, now: now)
        let entry = GoldWidgetEntry(date: now, basis: basis, snapshot: snapshot, isPlaceholder: false)
        let nextRefresh = service.nextRefreshDate(from: now, snapshot: snapshot)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
}
