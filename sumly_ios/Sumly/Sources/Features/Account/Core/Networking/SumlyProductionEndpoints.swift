import Foundation

enum SumlyProductionEndpoints {
    private static let siteURL = URL(string: "https://oryjk.cn/sumly")!
    static let apiBaseURL = siteURL.appendingPathComponent("api").appendingPathComponent("v1")
    static let backupAPIBaseURL = URL(string: "https://backup.oryjk.cn:19443/sumly/api/v1")!
    static let homeAPIBaseURL = URL(string: "https://home.oryjk.cn:18443/sumly/api/v1")!
    static let privacyPolicyURL = siteURL.appendingPathComponent("privacy")

    static func marketCacheScope(for baseURL: URL) -> String {
        // Preserve existing offline snapshots and cursors after moving the production API to port 443.
        baseURL == apiBaseURL ? "https://oryjk.cn:18443/sumly/api/v1" : baseURL.absoluteString
    }
}
