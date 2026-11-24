import Foundation
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// 应用支持的语言选项（6 种语言 + 跟随系统），支持在主 App 与 `SumlyWidget` 扩展间共享。
enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case zhHans = "zh-Hans"
    case en
    case es
    case fr
    case pt
    case ja

    static let storageKey = "app.language"
    static let supportedCodes: [String] = ["zh-Hans", "en", "es", "fr", "pt", "ja"]

    /// 仅用于单元测试覆盖当前语种（推荐使用 `@TaskLocal taskOverrideForTesting` 避免并发测试互相干扰）。
    nonisolated(unsafe) static var overrideForTesting: AppLanguage? = nil
    @TaskLocal static var taskOverrideForTesting: AppLanguage? = nil

    var id: String { rawValue }

    /// 供语言选择列表展示的母语名称（`.system` 随当前语言本地化）。
    var nativeDisplayName: String {
        switch self {
        case .system: L10n.tr("跟随系统")
        case .zhHans: "简体中文"
        case .en: "English"
        case .es: "Español"
        case .fr: "Français"
        case .pt: "Português"
        case .ja: "日本語"
        }
    }

    /// 供语言选择列表展示的本地化副标题。
    var localizedSubtitle: String {
        switch self {
        case .system:
            let detected = Self.resolveSystemLanguage(preferredLanguages: Locale.preferredLanguages)
            let resolvedLang = AppLanguage(rawValue: detected) ?? .en
            return L10n.fmt("当前系统：%@", resolvedLang.nativeDisplayName)
        case .zhHans:
            return L10n.tr("简体中文")
        case .en:
            return L10n.tr("英语")
        case .es:
            return L10n.tr("西班牙语")
        case .fr:
            return L10n.tr("法语")
        case .pt:
            return L10n.tr("葡萄牙语")
        case .ja:
            return L10n.tr("日语")
        }
    }

    /// 当前是否处于 App Extension 进程中（不依赖 `UIApplication`，满足 `APPLICATION_EXTENSION_API_ONLY`）。
    static var isAppExtension: Bool {
        Bundle.main.bundlePath.hasSuffix(".appex")
            || Bundle.main.object(forInfoDictionaryKey: "NSExtension") != nil
    }

    /// 当前是否处于 Xcode 单元测试环境。
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// 读写 `UserDefaults.standard` 中的应用语言设置（默认 `.system`）。
    static var current: AppLanguage {
        get {
            guard let raw = UserDefaults.standard.string(forKey: storageKey),
                  let parsed = AppLanguage(rawValue: raw) else {
                return .system
            }
            return parsed
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }

    /// 解析当前实际生效的 `.lproj` 语言代码（必为 6 种支持语言之一）。
    static var resolvedLanguageCode: String {
        if let override = taskOverrideForTesting ?? overrideForTesting {
            if override == .system {
                return resolveSystemLanguage(preferredLanguages: Locale.preferredLanguages)
            }
            return override.rawValue
        }

        let storedRaw = UserDefaults.standard.string(forKey: storageKey)
        if let storedRaw,
           let explicit = AppLanguage(rawValue: storedRaw),
           explicit != .system {
            return explicit.rawValue
        }

        // 单元测试环境未显式指定语种时默认回退简体中文，保证既有中文断言单测不受模拟器语言影响。
        if isRunningUnitTests {
            return AppLanguage.zhHans.rawValue
        }

        return resolveSystemLanguage(preferredLanguages: Locale.preferredLanguages)
    }

    /// 将系统首选语言列表映射为应用支持的 6 种语言代码；未匹配语种统一回退 `"en"`。
    static func resolveSystemLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        for raw in preferredLanguages {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { continue }
            if normalized.hasPrefix("zh") { return AppLanguage.zhHans.rawValue }
            if normalized.hasPrefix("en") { return AppLanguage.en.rawValue }
            if normalized.hasPrefix("es") { return AppLanguage.es.rawValue }
            if normalized.hasPrefix("fr") { return AppLanguage.fr.rawValue }
            if normalized.hasPrefix("pt") { return AppLanguage.pt.rawValue }
            if normalized.hasPrefix("ja") { return AppLanguage.ja.rawValue }
        }
        return AppLanguage.en.rawValue
    }

    /// 当前生效的 `Locale`。
    static var currentLocale: Locale {
        Locale(identifier: resolvedLanguageCode)
    }
}

/// 统一本地化读取入口：实时读取当前语言对应 `.lproj` 的 `Localizable.strings`，支持应用内热切。
enum L10n {
    private static let missingSentinel = "__SUMLY_L10N_MISSING__"

    /// 查找指定语言代码对应的 `.lproj` Bundle（兼容大小写与 `pt-BR`/`pt-PT` 回退），找不到时回退 `root`。
    static func bundle(
        for code: String = AppLanguage.resolvedLanguageCode,
        in root: Bundle = .main
    ) -> Bundle {
        let candidates = candidateLprojNames(for: code)
        for candidate in candidates {
            if let path = root.path(forResource: candidate, ofType: "lproj"),
               let localized = Bundle(path: path) {
                return localized
            }
        }
        if root == .main {
            let classBundle = Bundle(for: AppLanguageStore.self)
            if classBundle != root {
                for candidate in candidates {
                    if let path = classBundle.path(forResource: candidate, ofType: "lproj"),
                       let localized = Bundle(path: path) {
                        return localized
                    }
                }
            }
        }
        return root
    }

    /// 从当前语言 `.lproj` 的 `Localizable.strings` 获取翻译，缺失时回退原 `key`。
    static func tr(
        _ key: String,
        comment: String = "",
        languageCode: String = AppLanguage.resolvedLanguageCode,
        bundle root: Bundle = .main
    ) -> String {
        let targetBundle = Self.bundle(for: languageCode, in: root)
        let value = targetBundle.localizedString(forKey: key, value: missingSentinel, table: "Localizable")
        if value == missingSentinel {
            return key
        }
        return value
    }

    /// 格式化本地化模板字符串，使用当前生效 `Locale`。
    static func fmt(_ key: String, _ args: CVarArg...) -> String {
        let format = tr(key)
        return String(format: format, locale: AppLanguage.currentLocale, arguments: args)
    }

    private static func candidateLprojNames(for code: String) -> [String] {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        var list: [String] = [trimmed]
        if lower != trimmed {
            list.append(lower)
        }
        if lower.hasPrefix("zh") {
            list.append(contentsOf: ["zh-Hans", "zh-hans", "zh_CN", "zh"])
        } else if lower.hasPrefix("pt") {
            list.append(contentsOf: ["pt", "pt-BR", "pt-PT", "pt-br", "pt-pt"])
        } else if let primary = lower.split(whereSeparator: { $0 == "-" || $0 == "_" }).first {
            let prefix = String(primary)
            if !list.contains(prefix) {
                list.append(prefix)
            }
        }
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }
}

/// 主线程可观察语言状态仓库：负责持久化语言选择、驱动界面热刷新并通知小组件重载。
@MainActor
@Observable
final class AppLanguageStore {
    static let shared = AppLanguageStore()

    @ObservationIgnored private let defaults: UserDefaults

    var selected: AppLanguage {
        didSet {
            guard selected != oldValue else { return }
            defaults.set(selected.rawValue, forKey: AppLanguage.storageKey)
            revision &+= 1
            Self.reloadWidgetsIfMainApp()
        }
    }

    /// 语言每次变更递增，用于触发根视图及本地化文案实时刷新。
    private(set) var revision: Int = 0

    var effectiveLocale: Locale {
        _ = revision
        return Locale(identifier: resolvedLanguageCode)
    }

    var resolvedLanguageCode: String {
        _ = revision
        if defaults === UserDefaults.standard {
            return AppLanguage.resolvedLanguageCode
        }
        if selected != .system {
            return selected.rawValue
        }
        return AppLanguage.isRunningUnitTests
            ? AppLanguage.zhHans.rawValue
            : AppLanguage.resolveSystemLanguage(preferredLanguages: Locale.preferredLanguages)
    }

    var isChinese: Bool {
        resolvedLanguageCode == AppLanguage.zhHans.rawValue
    }

    init(initial: AppLanguage? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let initial {
            self.selected = initial
        } else if let raw = defaults.string(forKey: AppLanguage.storageKey),
                  let parsed = AppLanguage(rawValue: raw) {
            self.selected = parsed
        } else {
            self.selected = .system
        }
    }

    func select(_ language: AppLanguage) {
        selected = language
    }

    /// 同步外部对 `UserDefaults` 的更改（主要用于单测或系统语言变化后刷新）。
    func syncFromStorage() {
        let latest: AppLanguage
        if let raw = defaults.string(forKey: AppLanguage.storageKey),
           let parsed = AppLanguage(rawValue: raw) {
            latest = parsed
        } else {
            latest = .system
        }
        if selected != latest {
            selected = latest
        } else {
            revision &+= 1
        }
    }

    private static func reloadWidgetsIfMainApp() {
        guard !AppLanguage.isAppExtension else { return }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
