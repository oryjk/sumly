import Foundation

/// sumly_go 宏观与黄金温度只读接口适配（`/api/v1/app/macro/*`）。
struct BackendMacroService: MacroServicing, Sendable {
    var baseURL: URL = BackendGoldPriceService.defaultBaseURL
    var session: URLSession = .shared

    enum ServiceError: Error, Equatable, LocalizedError {
        case invalidURL
        case badResponse
        case httpStatus(Int)
        case envelope(Int, String)
        case emptyData

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                L10n.tr("宏观接口地址无效")
            case .badResponse:
                L10n.tr("服务端响应异常，请稍后重试")
            case .httpStatus(let code):
                L10n.fmt("服务暂时不可用（HTTP %lld），请稍后重试", Int64(code))
            case .envelope(_, let message):
                message.isEmpty ? L10n.tr("宏观数据加载失败，请稍后重试") : message
            case .emptyData:
                L10n.tr("服务端返回空数据")
            }
        }
    }

    private struct Envelope<T: Decodable>: Decodable {
        let code: Int
        let message: String
        let data: T?
    }

    // MARK: - MacroServicing

    func fetchTemperature() async throws -> MacroTemperatureReport {
        try await get(url: Self.temperatureURL(baseURL: baseURL))
    }

    func fetchTemperatureHistory(range: MacroHistoryRange) async throws -> MacroTemperatureHistory {
        try await get(url: Self.temperatureHistoryURL(baseURL: baseURL, range: range))
    }

    func fetchTreasury(range: MacroExtendedRange) async throws -> MacroTreasuryReport {
        try await get(url: Self.treasuryURL(baseURL: baseURL, range: range))
    }

    func fetchIndicators(section: String? = nil) async throws -> MacroIndicatorsCatalog {
        try await get(url: Self.indicatorsURL(baseURL: baseURL, section: section))
    }

    func fetchIndicatorDetail(seriesID: String, range: MacroExtendedRange) async throws -> MacroIndicatorDetail {
        try await get(url: Self.indicatorDetailURL(baseURL: baseURL, seriesID: seriesID, range: range))
    }

    func fetchGoldCot(range: MacroHistoryRange) async throws -> MacroCotReport {
        try await get(url: Self.goldCotURL(baseURL: baseURL, range: range))
    }

    // MARK: - URL 构造（纯函数，便于单测核对契约）

    static func temperatureURL(baseURL: URL) throws -> URL {
        try buildURL(baseURL: baseURL, pathSegments: ["app", "macro", "temperature"])
    }

    static func temperatureHistoryURL(baseURL: URL, range: MacroHistoryRange) throws -> URL {
        try buildURL(
            baseURL: baseURL,
            pathSegments: ["app", "macro", "temperature", "history"],
            queryItems: [URLQueryItem(name: "range", value: range.rawValue)]
        )
    }

    static func treasuryURL(baseURL: URL, range: MacroExtendedRange) throws -> URL {
        try buildURL(
            baseURL: baseURL,
            pathSegments: ["app", "macro", "treasury"],
            queryItems: [URLQueryItem(name: "range", value: range.rawValue)]
        )
    }

    static func indicatorsURL(baseURL: URL, section: String?) throws -> URL {
        let query: [URLQueryItem]
        if let section, !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            query = [URLQueryItem(name: "section", value: section)]
        } else {
            query = []
        }
        return try buildURL(baseURL: baseURL, pathSegments: ["app", "macro", "indicators"], queryItems: query)
    }

    static func indicatorDetailURL(baseURL: URL, seriesID: String, range: MacroExtendedRange) throws -> URL {
        let trimmed = seriesID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ServiceError.invalidURL }
        return try buildURL(
            baseURL: baseURL,
            pathSegments: ["app", "macro", "indicators", trimmed],
            queryItems: [URLQueryItem(name: "range", value: range.rawValue)]
        )
    }

    static func goldCotURL(baseURL: URL, range: MacroHistoryRange) throws -> URL {
        try buildURL(
            baseURL: baseURL,
            pathSegments: ["app", "macro", "cot", "gold"],
            queryItems: [URLQueryItem(name: "range", value: range.rawValue)]
        )
    }

    private static func buildURL(baseURL: URL, pathSegments: [String], queryItems: [URLQueryItem] = []) throws -> URL {
        var url = baseURL
        for segment in pathSegments {
            url = url.appending(component: segment)
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ServiceError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let built = components.url else {
            throw ServiceError.invalidURL
        }
        return built
    }

    // MARK: - Envelope 解码（纯函数，供单测）

    static func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard envelope.code == 0 else {
            throw ServiceError.envelope(envelope.code, envelope.message)
        }
        guard let payload = envelope.data else {
            throw ServiceError.emptyData
        }
        return payload
    }

    // MARK: - 网络请求

    private func get<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data), envelope.code != 0 {
                throw ServiceError.envelope(envelope.code, envelope.message)
            }
            throw ServiceError.httpStatus(http.statusCode)
        }
        return try Self.decodeEnvelope(T.self, from: data)
    }
}
