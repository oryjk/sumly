import Foundation

enum SumlyProductionEndpoints {
    private static let siteURL = URL(string: "https://oryjk.cn:18443/sumly")!
    static let apiBaseURL = siteURL.appendingPathComponent("api").appendingPathComponent("v1")
    static let backupAPIBaseURL = URL(string: "https://backup.oryjk.cn:19443/sumly/api/v1")!
    static let privacyPolicyURL = siteURL.appendingPathComponent("privacy")
}
