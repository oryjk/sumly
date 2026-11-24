import Foundation

enum SumlyProductionEndpoints {
    private static let siteURL = URL(string: "https://oryjk.cn:18443/sumly")!
    static let apiBaseURL = siteURL.appendingPathComponent("api").appendingPathComponent("v1")
    static let privacyPolicyURL = siteURL.appendingPathComponent("privacy")
}
