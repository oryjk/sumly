import Foundation

enum SumlyProductionEndpoints {
    private static let siteURL = URL(string: "https://oryjk.cn:82/sumly")!
    static let apiBaseURL = siteURL.appendingPathComponent("api").appendingPathComponent("v1")
    static let privacyPolicyURL = siteURL.appendingPathComponent("privacy")
}
