import Foundation
import CryptoKit

/// 黄金温度历史日频数据本地缓存（内存 + 磁盘持久化，30 分钟 TTL）。
/// 默认加载近 3 年（`3y`），用户切换至更早年份时按需扩展为全量（`all`）。
actor MacroTemperatureHistoryCache {
    static let shared = MacroTemperatureHistoryCache(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "SumlyMacroTemperatureHistory")
    )

    static let defaultTTL: TimeInterval = 1800

    private struct Snapshot: Codable {
        let schema: Int
        let scope: String
        let range: String
        let fetchedAt: Date
        let points: [MacroTemperatureHistoryPoint]
    }

    private struct Flight {
        let id: UUID
        let task: Task<[MacroTemperatureHistoryPoint], Error>
    }

    private let directory: URL
    private let ttl: TimeInterval
    private var snapshots: [String: Snapshot] = [:]
    private var flights: [String: Flight] = [:]
    private var generation: UInt = 0

    init(directory: URL, ttl: TimeInterval = defaultTTL) {
        self.directory = directory
        self.ttl = ttl
    }

    /// 决定查看 `focusedYear` 时建议请求的温度历史范围（近 3 年走 `3y`，更早年份按需扩 `all`）。
    nonisolated static func preferredRange(for focusedYear: Int, now: Date = .now, calendar: Calendar = .current) -> MacroHistoryRange {
        let currentYear = calendar.component(.year, from: now)
        return focusedYear < currentYear - 2 ? .all : .threeYears
    }

    func cached(scope: String, range: MacroHistoryRange) -> [MacroTemperatureHistoryPoint]? {
        if let allSnap = loadSnapshot(scope: scope, range: .all) {
            return allSnap.points
        }
        return loadSnapshot(scope: scope, range: range)?.points
    }

    func fetch(
        scope: String,
        range: MacroHistoryRange,
        service: any MacroServicing,
        now: Date = .now
    ) async throws -> [MacroTemperatureHistoryPoint] {
        let expectedGeneration = generation

        // 若已缓存新鲜全量数据，直接复用，避免冗余请求。
        if range != .all,
           let freshAll = loadSnapshot(scope: scope, range: .all),
           isFresh(freshAll, now: now) {
            return freshAll.points
        }

        let cacheKey = key(scope: scope, range: range)
        while true {
            try Task.checkCancellation()
            guard generation == expectedGeneration else { throw CancellationError() }

            let previous = loadSnapshot(scope: scope, range: range)
            if let previous, isFresh(previous, now: now) {
                return previous.points
            }

            let flight: Flight
            if let existing = flights[cacheKey] {
                flight = existing
            } else {
                flight = Flight(
                    id: UUID(),
                    task: Task {
                        try await self.download(
                            scope: scope,
                            range: range,
                            previous: previous,
                            service: service,
                            now: now,
                            expectedGeneration: expectedGeneration
                        )
                    }
                )
                flights[cacheKey] = flight
            }

            do {
                let points = try await withTaskCancellationHandler {
                    let result = try await flight.task.value
                    try Task.checkCancellation()
                    return result
                } onCancel: {
                    flight.task.cancel()
                }
                if flights[cacheKey]?.id == flight.id {
                    flights[cacheKey] = nil
                }
                return points
            } catch {
                if flights[cacheKey]?.id == flight.id {
                    flights[cacheKey] = nil
                }
                if error is CancellationError, !Task.isCancelled, generation == expectedGeneration {
                    continue
                }
                throw error
            }
        }
    }

    func clear() {
        generation &+= 1
        for flight in flights.values {
            flight.task.cancel()
        }
        flights.removeAll()
        snapshots.removeAll()
        if FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: - 内部实现

    private func download(
        scope: String,
        range: MacroHistoryRange,
        previous: Snapshot?,
        service: any MacroServicing,
        now: Date,
        expectedGeneration: UInt
    ) async throws -> [MacroTemperatureHistoryPoint] {
        let history: MacroTemperatureHistory
        do {
            history = try await service.fetchTemperatureHistory(range: range)
        } catch {
            guard expectedGeneration == generation, !Task.isCancelled else {
                throw CancellationError()
            }
            if let previous {
                return previous.points
            }
            throw error
        }

        try Task.checkCancellation()
        guard expectedGeneration == generation else { throw CancellationError() }

        let snapshot = Snapshot(
            schema: 1,
            scope: scope,
            range: range.rawValue,
            fetchedAt: now,
            points: history.points
        )
        let cacheKey = key(scope: scope, range: range)
        snapshots[cacheKey] = snapshot

        if let data = try? JSONEncoder().encode(snapshot) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: fileURL(for: cacheKey), options: .atomic)
        }
        return history.points
    }

    private func isFresh(_ snapshot: Snapshot, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(snapshot.fetchedAt)
        return elapsed >= 0 && elapsed < ttl
    }

    private func loadSnapshot(scope: String, range: MacroHistoryRange) -> Snapshot? {
        let cacheKey = key(scope: scope, range: range)
        if let memory = snapshots[cacheKey] {
            return memory
        }
        guard let data = try? Data(contentsOf: fileURL(for: cacheKey)),
              let decoded = try? JSONDecoder().decode(Snapshot.self, from: data),
              decoded.schema == 1,
              decoded.scope == scope,
              decoded.range == range.rawValue
        else {
            return nil
        }
        snapshots[cacheKey] = decoded
        return decoded
    }

    private func key(scope: String, range: MacroHistoryRange) -> String {
        let raw = scope + "\n" + range.rawValue
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func fileURL(for cacheKey: String) -> URL {
        directory.appending(path: cacheKey + ".json")
    }
}
