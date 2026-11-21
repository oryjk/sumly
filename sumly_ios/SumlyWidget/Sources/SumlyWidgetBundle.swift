import SwiftUI
import WidgetKit

struct SumlyGoldWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GoldWidgetEntry

    var body: some View {
        contentView
            .containerBackground(for: .widget) {
                backgroundView
            }
            .widgetURL(URL(string: "sumly://market"))
    }

    @ViewBuilder
    private var contentView: some View {
        switch family {
        case .systemSmall:
            GoldSmallWidgetView(basis: entry.basis, snapshot: entry.snapshot, now: entry.date)
        case .systemMedium:
            GoldMediumWidgetView(basis: entry.basis, snapshot: entry.snapshot, now: entry.date)
        case .accessoryCircular:
            GoldAccessoryCircularView(basis: entry.basis, snapshot: entry.snapshot)
        case .accessoryRectangular:
            GoldAccessoryRectangularView(basis: entry.basis, snapshot: entry.snapshot)
        default:
            GoldSmallWidgetView(basis: entry.basis, snapshot: entry.snapshot, now: entry.date)
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular:
            Color.clear
        default:
            GoldWidgetBackground()
        }
    }
}

struct SumlyGoldWidget: Widget {
    let kind = "SumlyGoldWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectGoldMarketIntent.self,
            provider: GoldWidgetTimelineProvider()
        ) { entry in
            SumlyGoldWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("记金 · 实时金价")
        .description("桌面与锁屏实时查看国内 Au99.99 / 国际伦敦金克价、近一月走势与黄金温度。")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular
        ])
        .contentMarginsDisabled()
    }
}

@main
struct SumlyWidgetBundle: WidgetBundle {
    var body: some Widget {
        SumlyGoldWidget()
    }
}
