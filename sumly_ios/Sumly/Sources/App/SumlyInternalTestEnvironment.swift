import Foundation

enum SumlyInternalTestEnvironment {
    #if SUMLY_CHANLUN_INTERNAL_TEST
    static let chanlunURL: URL? = URL(string: "https://ai.oryjk.cn:82/sumly-chanlun-dev/")!
    static let storageSuffix = ".chanlun-internal"
    #else
    static let chanlunURL: URL? = nil
    static let storageSuffix = ""
    #endif

    static let apiBaseURL = chanlunURL?.appendingPathComponent("sumly/api/v1")

    @MainActor static var defaults: UserDefaults {
        guard chanlunURL != nil else { return .standard }
        return UserDefaults(suiteName: "com.oryjk.sumly" + storageSuffix)!
    }
}
