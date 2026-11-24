import Foundation
import SwiftUI
import Testing
@testable import Sumly

@Suite(.serialized)
struct LocalizationCoreTests {

    // MARK: - 1. 系统语种映射（含地区变体与未知语种回退英文）

    @Test func systemLanguageResolutionMapsRegionsAndFallsBackToEnglish() {
        #expect(AppLanguage.resolveSystemLanguage(preferredLanguages: ["zh-Hans-CN"]) == "zh-Hans")
        #expect(AppLanguage.resolveSystemLanguage(preferredLanguages: ["zh-Hant-TW"]) == "zh-Hans")
        #expect(AppLanguage.resolveSystemLanguage(preferredLanguages: ["zh-HK"]) == "zh-Hans")
        #expect(AppLanguage.resolveSystemLanguage(preferredLanguages: ["en-US"]) == "en")
        #expect(AppLanguage.resolveSystemLanguage(preferredLanguages: ["en-GB"]) == "en")
        #expect(AppLanguage.resolveSystemLanguage(preferredLanguages: ["es-MX"]) == "es")
        #expect(AppLanguage.resolveSystemLanguage(preferredLanguages: ["es-ES"]) == "es")
        #expect(AppLanguage.resolveSystemLanguage(preferredLanguages: ["fr-CA"]) == "fr")
        #expect(AppLanguage.resolveSystemLanguage(preferredLanguages: ["pt-BR"]) == "pt")
        #expect(AppLanguage.resolveSystemLanguage(preferredLanguages: ["pt-PT"]) == "pt")
        #expect(AppLanguage.resolveSystemLanguage(preferredLanguages: ["ja-JP"]) == "ja")

        // 非支持语种默认回退英文而非中文，保障海外用户体验
        #expect(AppLanguage.resolveSystemLanguage(preferredLanguages: ["de-DE"]) == "en")
        #expect(AppLanguage.resolveSystemLanguage(preferredLanguages: ["ko-KR", "ru-RU"]) == "en")
        #expect(AppLanguage.resolveSystemLanguage(preferredLanguages: []) == "en")

        // 首选语种不支持但次选语种支持时按顺序匹配
        #expect(AppLanguage.resolveSystemLanguage(preferredLanguages: ["de-DE", "ja-JP"]) == "ja")
    }

    // MARK: - 2. 6 种语言切换、母语展示名与测试环境中文默认回退

    @Test func sixLanguagesSwitchAndUnitTestDefaultsToSimplifiedChinese() {
        let previousStored = UserDefaults.standard.object(forKey: AppLanguage.storageKey)
        defer {
            AppLanguage.overrideForTesting = nil
            if let previousStored {
                UserDefaults.standard.set(previousStored, forKey: AppLanguage.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
            }
        }

        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        AppLanguage.overrideForTesting = nil
        #expect(AppLanguage.isRunningUnitTests)
        #expect(AppLanguage.resolvedLanguageCode == "zh-Hans")

        #expect(AppLanguage.zhHans.nativeDisplayName == "简体中文")
        #expect(AppLanguage.en.nativeDisplayName == "English")
        #expect(AppLanguage.es.nativeDisplayName == "Español")
        #expect(AppLanguage.fr.nativeDisplayName == "Français")
        #expect(AppLanguage.pt.nativeDisplayName == "Português")
        #expect(AppLanguage.ja.nativeDisplayName == "日本語")

        let expectedTabTitles: [(AppLanguage, String)] = [
            (.zhHans, "行情"),
            (.en, "Market"),
            (.es, "Mercado"),
            (.fr, "Marché"),
            (.pt, "Mercado"),
            (.ja, "相場")
        ]

        for (language, expectedMarketTitle) in expectedTabTitles {
            AppLanguage.overrideForTesting = language
            #expect(AppLanguage.resolvedLanguageCode == language.rawValue)
            #expect(L10n.tr("行情") == expectedMarketTitle)
            #expect(GoldPrimaryTab.market.title == expectedMarketTitle)
        }
    }

    // MARK: - 3. `.lproj` Bundle 加载、`pt-BR` 回退与缺失键回退

    @Test func lprojBundleLookupAndMissingKeyFallback() {
        for code in AppLanguage.supportedCodes {
            let bundle = L10n.bundle(for: code)
            #expect(bundle.bundlePath.hasSuffix(".lproj"), "Expected .lproj bundle for \(code), got \(bundle.bundlePath)")
        }

        // pt-BR / pt-PT 回退到 pt.lproj
        let ptBRBundle = L10n.bundle(for: "pt-BR")
        #expect(ptBRBundle.bundlePath.hasSuffix("pt.lproj"))
        #expect(L10n.tr("设置", languageCode: "pt-BR") == "Ajustes")

        // 大小写兼容 zh-hans -> zh-Hans.lproj
        let zhLowerBundle = L10n.bundle(for: "zh-hans")
        #expect(zhLowerBundle.bundlePath.hasSuffix("zh-Hans.lproj"))

        // 缺失键回退原 key
        let unknownKey = "__missing_localization_key_12345__"
        #expect(L10n.tr(unknownKey, languageCode: "en") == unknownKey)

        // 格式化方法验证
        let previousOverride = AppLanguage.overrideForTesting
        defer { AppLanguage.overrideForTesting = previousOverride }
        AppLanguage.overrideForTesting = .en
        #expect(L10n.fmt("当前系统：%@", "English") == "System: English")
    }

    // MARK: - 4. `InfoPlist.strings` 与 `Localizable.strings` 6 语打包与语法校验

    @Test func allSixLprojInfoPlistAndLocalizableStringsArePackagedAndValid() throws {
        let expectedDisplayNames: [String: String] = [
            "zh-Hans": "记金",
            "en": "Sumly",
            "es": "Sumly",
            "fr": "Sumly",
            "pt": "Sumly",
            "ja": "Sumly"
        ]

        for (code, expectedName) in expectedDisplayNames {
            let bundle = L10n.bundle(for: code)

            let infoPlistURL = try #require(bundle.url(forResource: "InfoPlist", withExtension: "strings"))
            let infoDict = try #require(NSDictionary(contentsOf: infoPlistURL) as? [String: String])
            #expect(infoDict["CFBundleDisplayName"] == expectedName)

            let localizableURL = try #require(bundle.url(forResource: "Localizable", withExtension: "strings"))
            let localizableDict = try #require(NSDictionary(contentsOf: localizableURL) as? [String: String])
            #expect(!localizableDict.isEmpty)
            #expect(localizableDict["跟随系统"] != nil)
            #expect(localizableDict["语言"] != nil)
            #expect(localizableDict["行情"] != nil)
        }
    }

    // MARK: - 5. `AppLanguageStore` 持久化与 revision 递增

    @MainActor
    @Test func languageStorePersistsSelectionAndIncrementsRevision() {
        let previousStored = UserDefaults.standard.object(forKey: AppLanguage.storageKey)
        defer {
            AppLanguage.overrideForTesting = nil
            if let previousStored {
                UserDefaults.standard.set(previousStored, forKey: AppLanguage.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
            }
            AppLanguageStore.shared.syncFromStorage()
        }

        UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
        let store = AppLanguageStore(initial: .system)
        let initialRevision = store.revision

        store.select(.ja)
        #expect(store.selected == .ja)
        #expect(store.revision == initialRevision + 1)
        #expect(AppLanguage.current == .ja)
        #expect(store.resolvedLanguageCode == "ja")
        #expect(!store.isChinese)

        // 重复选择同一语言不冗余递增 revision
        store.select(.ja)
        #expect(store.revision == initialRevision + 1)

        store.select(.zhHans)
        #expect(store.revision == initialRevision + 2)
        #expect(store.isChinese)
    }

    // MARK: - 6. 非中文首启默认 `.international` 市场口径逻辑

    @Test func firstLaunchDefaultMarketBasisRespectsLanguageAndExistingPreference() throws {
        let suiteName = "com.oryjk.sumly.tests.marketBasis.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // 首次启动（未保存 market.basis）：中文 -> .domestic，非中文 -> .international
        #expect(GoldMarketBasis.resolveInitialBasis(in: defaults, languageCode: "zh-Hans") == .domestic)
        #expect(GoldMarketBasis.resolveInitialBasis(in: defaults, languageCode: "en") == .international)
        #expect(GoldMarketBasis.resolveInitialBasis(in: defaults, languageCode: "es") == .international)
        #expect(GoldMarketBasis.resolveInitialBasis(in: defaults, languageCode: "fr") == .international)
        #expect(GoldMarketBasis.resolveInitialBasis(in: defaults, languageCode: "pt") == .international)
        #expect(GoldMarketBasis.resolveInitialBasis(in: defaults, languageCode: "ja") == .international)

        // 已有中国用户配置完全不受影响
        defaults.set(GoldMarketBasis.domestic.rawValue, forKey: GoldMarketBasis.storageKey)
        #expect(GoldMarketBasis.resolveInitialBasis(in: defaults, languageCode: "en") == .domestic)
        #expect(GoldMarketBasis.resolveInitialBasis(in: defaults, languageCode: "zh-Hans") == .domestic)

        // 已有国际口径配置同样保留
        defaults.set(GoldMarketBasis.international.rawValue, forKey: GoldMarketBasis.storageKey)
        #expect(GoldMarketBasis.resolveInitialBasis(in: defaults, languageCode: "zh-Hans") == .international)
    }
}
