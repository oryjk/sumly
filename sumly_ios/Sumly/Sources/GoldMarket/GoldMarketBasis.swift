import Foundation

enum GoldMarketBasis: String, CaseIterable, Identifiable, Sendable, Codable {
    case domestic
    case international

    static let storageKey = "market.basis"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .domestic: L10n.tr("国内")
        case .international: L10n.tr("国际")
        }
    }

    /// 首次启动默认市场口径：简体中文默认国内 Au99.99，非中文海外用户默认国际伦敦金。
    static func initialDefault(forLanguageCode code: String = AppLanguage.resolvedLanguageCode) -> GoldMarketBasis {
        code == AppLanguage.zhHans.rawValue ? .domestic : .international
    }

    /// 若 `defaults` 尚未保存 `"market.basis"`，按当前语言决定默认口径；已有用户配置则原样保留。
    static func resolveInitialBasis(
        in defaults: UserDefaults = .standard,
        key: String = storageKey,
        languageCode: String = AppLanguage.resolvedLanguageCode
    ) -> GoldMarketBasis {
        if let raw = defaults.string(forKey: key), let saved = GoldMarketBasis(rawValue: raw) {
            return saved
        }
        return initialDefault(forLanguageCode: languageCode)
    }

    /// 国内走 Au99.99 显式品种；国际沿用伦敦金默认链路。
    var instrumentID: String? {
        switch self {
        case .domestic: "au9999"
        case .international: nil
        }
    }
}
