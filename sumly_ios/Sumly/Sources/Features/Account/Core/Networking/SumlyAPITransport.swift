import Foundation

/// Shared by the app's backend clients and compiled into the widget as well.
actor SumlyAPITransport {
    static let shared = SumlyAPITransport()

    typealias Transfer = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private enum Origin: CaseIterable {
        case primary, backup, home

        var baseURL: URL {
            switch self {
            case .primary: SumlyProductionEndpoints.apiBaseURL
            case .backup: SumlyProductionEndpoints.backupAPIBaseURL
            case .home: SumlyProductionEndpoints.homeAPIBaseURL
            }
        }
    }

    private let uptime: @Sendable () -> TimeInterval
    private let probeInterval: TimeInterval = 60
    private var preferred: Origin = .primary
    private var nextProbe: TimeInterval = 0
    private var generation: UInt64 = 0

    init(uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.uptime = uptime
    }

    func send(_ request: URLRequest, baseURL: URL, using transfer: Transfer) async throws -> (Data, URLResponse) {
        let primary = SumlyProductionEndpoints.apiBaseURL
        guard baseURL == primary,
              let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == primary.scheme, components.host == primary.host, components.port == primary.port,
              components.user == nil, components.password == nil,
              components.percentEncodedPath.hasPrefix(primary.path + "/") else {
            return try await transfer(request)
        }

        let safeRead = request.httpMethod == "GET"
        let active = preferred
        let origins = chooseOrigins(safeRead: safeRead)
        let startedAtGeneration = generation

        func routedRequest(to origin: Origin) throws -> URLRequest {
            var routed = request
            if origin != .primary {
                var target = components
                target.host = origin.baseURL.host
                target.port = origin.baseURL.port
                guard let targetURL = target.url else { throw URLError(.badURL) }
                routed.url = targetURL
            }
            // A cached response cannot establish that another origin is accepting requests.
            if safeRead, origin != active { routed.cachePolicy = .reloadIgnoringLocalCacheData }
            return routed
        }

        guard safeRead else { return try await Self.perform(routedRequest(to: active), using: transfer) }

        for (index, origin) in origins.enumerated() {
            let hasNext = index < origins.count - 1
            do {
                let result = try await Self.perform(routedRequest(to: origin), using: transfer)
                if hasNext, Self.isGatewayFailure(result.1) { continue }
                noteResponse(from: origin, response: result.1, generation: startedAtGeneration)
                return result
            } catch {
                guard hasNext, Self.isConnectivityFailure(error) else { throw error }
            }
        }
        preconditionFailure("The production API requires at least one origin")
    }

    private func chooseOrigins(safeRead: Bool) -> [Origin] {
        if !safeRead { return [preferred] }
        if preferred == .primary { return Origin.allCases }
        let now = uptime()
        guard now >= nextProbe else { return [preferred] + Origin.allCases.filter { $0 != preferred } }
        // While this probe runs, other requests keep using the last responding origin.
        nextProbe = now + probeInterval
        return Origin.allCases
    }

    private func noteResponse(from origin: Origin, response: URLResponse, generation startedAtGeneration: UInt64) {
        // A late response from an older route should not undo a more recent switch.
        guard generation == startedAtGeneration, preferred != origin,
              response is HTTPURLResponse, !Self.isGatewayFailure(response) else { return }
        preferred = origin
        generation &+= 1
        if origin != .primary { nextProbe = uptime() + probeInterval }
    }

    private static func perform(_ request: URLRequest, using transfer: Transfer) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        do {
            let result = try await transfer(request)
            try Task.checkCancellation()
            return result
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw error
        }
    }

    private static func isGatewayFailure(_ response: URLResponse) -> Bool {
        switch (response as? HTTPURLResponse)?.statusCode {
        case 502, 503, 504: true
        default: false
        }
    }

    private static func isConnectivityFailure(_ error: any Error) -> Bool {
        switch (error as? URLError)?.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed,
             .notConnectedToInternet, .secureConnectionFailed, .serverCertificateHasBadDate,
             .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            true
        default: false
        }
    }
}

extension URLSession {
    func sumlyData(for request: URLRequest, baseURL: URL) async throws -> (Data, URLResponse) {
        try await SumlyAPITransport.shared.send(request, baseURL: baseURL) { request in
            try await data(for: request)
        }
    }

    func sumlyData(
        for request: URLRequest, baseURL: URL, delegate: any URLSessionTaskDelegate,
        maxBytes: Int, oversized: any Error
    ) async throws -> (Data, URLResponse) {
        try await SumlyAPITransport.shared.send(request, baseURL: baseURL) { request in
            let (bytes, response) = try await self.bytes(for: request, delegate: delegate)
            guard response is HTTPURLResponse else { return (Data(), response) }
            var data = Data()
            for try await byte in bytes {
                guard data.count < maxBytes else {
                    bytes.task.cancel()
                    throw oversized
                }
                data.append(byte)
            }
            return (data, response)
        }
    }
}
