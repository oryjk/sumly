import Foundation

/// `Account/Core` 独立本地化助手：零外部模块依赖，兼容 `swift test` 独立包编译。
/// 与 `AppLanguage` 共享同一 `UserDefaults.standard` 键 `"app.language"` 与主 Bundle `.lproj` 资源。
enum AuthL10n {
    private static let storageKey = "app.language"
    private static let missingSentinel = "__SUMLY_AUTH_L10N_MISSING__"

    static var resolvedLanguageCode: String {
        let raw = UserDefaults.standard.string(forKey: storageKey)
        if let raw, !raw.isEmpty, raw != "system" {
            return raw
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return "zh-Hans"
        }
        for preferred in Locale.preferredLanguages {
            let lower = preferred.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lower.hasPrefix("zh") { return "zh-Hans" }
            if lower.hasPrefix("en") { return "en" }
            if lower.hasPrefix("es") { return "es" }
            if lower.hasPrefix("fr") { return "fr" }
            if lower.hasPrefix("pt") { return "pt" }
            if lower.hasPrefix("ja") { return "ja" }
        }
        return "en"
    }

    static func tr(_ key: String) -> String {
        let code = resolvedLanguageCode
        let candidates = candidateLprojNames(for: code)
        for candidate in candidates {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                let value = bundle.localizedString(forKey: key, value: missingSentinel, table: "Localizable")
                if value != missingSentinel {
                    return value
                }
                return key
            }
        }
        return key
    }

    private static func candidateLprojNames(for code: String) -> [String] {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        var list = [trimmed]
        if lower != trimmed { list.append(lower) }
        if lower.hasPrefix("zh") {
            list.append(contentsOf: ["zh-Hans", "zh-hans", "zh"])
        } else if lower.hasPrefix("pt") {
            list.append(contentsOf: ["pt", "pt-BR", "pt-PT"])
        } else if let primary = lower.split(whereSeparator: { $0 == "-" || $0 == "_" }).first {
            let prefix = String(primary)
            if !list.contains(prefix) { list.append(prefix) }
        }
        return list
    }
}
