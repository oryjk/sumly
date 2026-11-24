import Foundation

/// Shared by the app's backend clients and compiled into the widget as well.
actor SumlyAPITransport {
    static let shared = SumlyAPITransport()

    typealias Transfer = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private enum Origin {
        case primary, backup

        var alternate: Self { self == .primary ? .backup : .primary }
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
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == primary.scheme, components.host == primary.host, components.port == primary.port,
              components.user == nil, components.password == nil,
              components.percentEncodedPath.hasPrefix(primary.path + "/") else {
            return try await transfer(request)
        }

        let safeRead = request.httpMethod == "GET"
        let first = chooseOrigin(safeRead: safeRead)
        let startedAtGeneration = generation
        var primaryRequest = request
        var backupRequest = request
        let backup = SumlyProductionEndpoints.backupAPIBaseURL
        components.host = backup.host
        components.port = backup.port
        guard let backupURL = components.url else { return try await transfer(request) }
        backupRequest.url = backupURL
        // A cached response cannot establish that the other origin is accepting requests again.
        if safeRead {
            if preferred == .primary {
                backupRequest.cachePolicy = .reloadIgnoringLocalCacheData
            } else {
                primaryRequest.cachePolicy = .reloadIgnoringLocalCacheData
            }
        }

        let initial = first == .primary ? primaryRequest : backupRequest
        guard safeRead else { return try await Self.perform(initial, using: transfer) }

        do {
            let result = try await Self.perform(initial, using: transfer)
            if !Self.isGatewayFailure(result.1) {
                noteResponse(from: first, response: result.1, generation: startedAtGeneration)
                return result
            }
        } catch {
            guard Self.isConnectivityFailure(error) else { throw error }
        }

        let alternate = first.alternate
        let result = try await Self.perform(alternate == .primary ? primaryRequest : backupRequest, using: transfer)
        noteResponse(from: alternate, response: result.1, generation: startedAtGeneration)
        return result
    }

    private func chooseOrigin(safeRead: Bool) -> Origin {
        if preferred == .primary { return .primary }
        let now = uptime()
        guard safeRead, now >= nextProbe else { return .backup }
        // While this probe runs, other requests keep using the last responding origin.
        nextProbe = now + probeInterval
        return .primary
    }

    private func noteResponse(from origin: Origin, response: URLResponse, generation startedAtGeneration: UInt64) {
        // A late response from an older route should not undo a more recent switch.
        guard generation == startedAtGeneration, preferred != origin,
              response is HTTPURLResponse, !Self.isGatewayFailure(response) else { return }
        preferred = origin
        generation &+= 1
        if origin == .backup { nextProbe = uptime() + probeInterval }
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
