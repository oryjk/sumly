import AppIntents
import Foundation

/// 小组件行情口径选项（iOS 17+ AppIntents 配置）。
enum GoldWidgetMarketOption: String, AppEnum, Sendable {
    case domestic
    case international

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "金价口径"

    static let caseDisplayRepresentations: [GoldWidgetMarketOption: DisplayRepresentation] = [
        .domestic: DisplayRepresentation(title: "国内 Au99.99", subtitle: "上海黄金交易所人民币克价"),
        .international: DisplayRepresentation(title: "国际伦敦金", subtitle: "XAUUSD 实时折算人民币克价")
    ]

    var basis: GoldWidgetBasis {
        switch self {
        case .domestic: .domestic
        case .international: .international
        }
    }
}

/// 桌面与锁屏小组件配置意图：自由选择「国内 Au99.99」或「国际伦敦金」。
struct SelectGoldMarketIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "选择金价口径"
    static let description = IntentDescription("切换展示国内 Au99.99 或国际伦敦金实时克价与走势")

    @Parameter(title: "行情口径", default: .domestic)
    var market: GoldWidgetMarketOption

    init() {
        self.market = .domestic
    }

    init(market: GoldWidgetMarketOption) {
        self.market = market
    }
}
