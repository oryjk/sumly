import Foundation
import Observation
import SwiftData

/// A workspace owns exactly one account's cache. Guest storage is the preexisting container.
@MainActor @Observable final class HoldingsCloud {
    let id = UUID()
    let userID: Int64?
    let container: ModelContainer
    let defaults: UserDefaults
    private let guestContainer: ModelContainer
    private let session: AuthSession
    private let service: any HoldingCloudServicing
    private let metadataURL: URL?
    private(set) var base: HoldingCloudSnapshot
    private(set) var isSyncing = false
    private(set) var conflictCount = 0
    private(set) var notice: String?
    private(set) var lastSyncedAt: Date?
    private var retryAfter = Date.distantPast
    private var lastRemoteCheck = Date.distantPast
    private var retired = false
    private var conflictSnapshot: HoldingCloudSnapshot?
    private var conflictLocal: HoldingDocument?

    init(session: AuthSession, guestContainer: ModelContainer, service: any HoldingCloudServicing = HoldingCloudService(baseURL: BackendGoldPriceService.defaultBaseURL), directory: URL? = nil) throws {
        self.session = session; self.guestContainer = guestContainer; self.service = service
        userID = session.user?.id
        if let userID {
            let root = try directory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("AccountHoldings", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("user-\(userID).store")
            container = try ModelContainer(for: HoldingRecord.self, configurations: ModelConfiguration(url: file))
            guard let scoped = UserDefaults(suiteName: "com.oryjk.sumly.holdings.user-\(userID)") else { throw HoldingCloudError.malformed }
            defaults = scoped
            let metadata = root.appendingPathComponent("user-\(userID)-base.json")
            metadataURL = metadata
            if FileManager.default.fileExists(atPath: metadata.path) {
                base = try HoldingCloudCoding.decode(HoldingCloudSnapshot.self, from: Data(contentsOf: metadata))
                guard base.isValid else { throw HoldingCloudError.malformed }
            } else { base = .empty }
        } else {
            container = guestContainer; defaults = .standard; metadataURL = nil; base = .empty
        }
    }
    var status: String {
        if userID == nil { return "游客记录仅保存在此设备，登录后可导入账户。" }
        if isSyncing { return "正在同步云端…" }
        if conflictCount > 0 { return "\(conflictCount) 条记录在两台设备上都有更改，请选择保留哪一份。" }
        if let notice { return notice }
        if (try? document()) != base.document { return "有更改等待同步，记录已保存在本机。" }
        if let lastSyncedAt { return "已同步 · \(lastSyncedAt.formatted(date: .omitted, time: .shortened))" }
        return "已开启云同步，本机缓存支持离线记录。"
    }
    var guestRecordCount: Int { (try? guestContainer.mainContext.fetchCount(FetchDescriptor<HoldingRecord>())) ?? 0 }
    func document() throws -> HoldingDocument {
        let records = try container.mainContext.fetch(FetchDescriptor<HoldingRecord>())
        let books = (defaults.string(forKey: "holdings.books") ?? "默认账本").components(separatedBy: "\n").filter { !$0.isEmpty }
        return HoldingDocument(books: books, records: records.map(HoldingCloudRecord.init)).normalized
    }
    private func ensureCurrent(_ generation: Int) throws {
        guard !retired, !Task.isCancelled, session.user?.id == userID,
              session.sessionGeneration == generation else { throw AuthError.stale }
    }
    private func authorized<T: Sendable>(_ operation: (String) async throws -> T) async throws -> T {
        let generation = session.sessionGeneration
        try ensureCurrent(generation)
        guard let stored = session.stored else { throw AuthError.unauthorized }
        if stored.expiresAt <= .now { try await session.refresh() }
        try ensureCurrent(generation)
        guard let token = session.stored?.result.token else { throw AuthError.unauthorized }
        do {
            let result = try await operation(token)
            try ensureCurrent(generation)
            return result
        } catch AuthError.unauthorized {
            try ensureCurrent(generation)
            if session.stored?.result.token == token { try await session.refresh() }
            try ensureCurrent(generation)
            guard let next = session.stored?.result.token else { throw AuthError.unauthorized }
            do {
                let result = try await operation(next)
                try ensureCurrent(generation)
                return result
            } catch AuthError.unauthorized {
                try ensureCurrent(generation)
                session.clearLocal()
                throw AuthError.unauthorized
            }
        }
    }
    /// Apply cache first and then advance the merge base. Crashes cannot mark unsaved changes as synced.
    private func accept(_ remote: HoldingCloudSnapshot, against ancestor: HoldingDocument, choice: HoldingCloudMerge.Choice?) throws -> Bool {
        let merged = HoldingCloudMerge.merge(base: ancestor, local: try document(), remote: remote.document, choice: choice)
        if !merged.conflicts.isEmpty && choice == nil {
            conflictCount = merged.conflicts.count
            conflictSnapshot = remote; conflictLocal = try document()
            return false
        }
        guard merged.document.isValid else { throw HoldingCloudError.malformed }
        let context = container.mainContext
        do {
            let existing = try context.fetch(FetchDescriptor<HoldingRecord>())
            let incoming = Dictionary(uniqueKeysWithValues: merged.document.records.map { ($0.id, $0) })
            let known = Set(existing.map(\.id))
            for record in existing {
                if let value = incoming[record.id] { value.apply(to: record) } else { context.delete(record) }
            }
            for record in merged.document.records where !known.contains(record.id) { context.insert(record.makeRecord()) }
            try context.save()
        } catch { context.rollback(); throw error }
        defaults.set(merged.document.books.joined(separator: "\n"), forKey: "holdings.books")
        if let metadataURL { try HoldingCloudCoding.encode(remote).write(to: metadataURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        base = remote
        conflictCount = 0
        conflictSnapshot = nil; conflictLocal = nil
        return true
    }
    func sync(choice: HoldingCloudMerge.Choice? = nil) async {
        guard userID != nil, !isSyncing, !retired else { return }
        isSyncing = true; notice = nil
        defer { isSyncing = false }
        do {
            try container.mainContext.save()
            var resolution = choice
            // CAS conflicts re-read latest server state, preserving a local merge base.
            for _ in 0..<3 {
                var remote = try await authorized { try await service.fetch(token: $0) }
                guard remote.isValid else { throw HoldingCloudError.malformed }
                remote.document = remote.document.normalized
                lastRemoteCheck = .now
                // A choice applies only to the conflict state the user actually saw.
                let currentLocal = try document()
                if resolution != nil, conflictSnapshot != remote || conflictLocal != currentLocal { resolution = nil }
                guard try accept(remote, against: base.document, choice: resolution) else { return }
                resolution = nil
                let upload = try document()
                if upload != base.document {
                    do {
                        var saved = try await authorized { try await service.put(upload, revision: remote.revision, token: $0) }
                        guard saved.isValid, saved.revision == remote.revision + 1, saved.document.normalized == upload else { throw HoldingCloudError.malformed }
                        saved.document = saved.document.normalized
                        // Edits made during upload are compared with what was submitted, not an older base.
                        _ = try accept(saved, against: upload, choice: nil)
                    } catch HoldingCloudError.conflict { continue }
                }
                lastSyncedAt = .now; retryAfter = .distantPast
                return
            }
            throw HoldingCloudError.conflict
        } catch AuthError.stale { /* Old workspace requests never mutate another account. */ }
        catch is CancellationError { }
        catch { notice = "\(error.localizedDescription) 更改保留在本机，稍后重试。"; retryAfter = .now.addingTimeInterval(60) }
    }
    func run() async {
        guard userID != nil else { return }
        await sync()
        while !Task.isCancelled && !retired {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard session.user?.id == userID else { return }
            if Date() >= retryAfter, conflictCount == 0,
               (Date().timeIntervalSince(lastRemoteCheck) >= 60 || (try? document()) != base.document) { await sync() }
        }
    }
    func importGuestRecords() async {
        guard userID != nil, !retired, !isSyncing else { return }
        do {
            let context = container.mainContext
            let existing = Set(try context.fetch(FetchDescriptor<HoldingRecord>()).map(\.id))
            let guest = try guestContainer.mainContext.fetch(FetchDescriptor<HoldingRecord>())
            for record in guest where !existing.contains(record.id) { context.insert(HoldingCloudRecord(record).makeRecord()) }
            try context.save()
            let books = (UserDefaults.standard.string(forKey: "holdings.books") ?? "默认账本").components(separatedBy: "\n")
            defaults.set(Array(Set(try document().books + books)).sorted().joined(separator: "\n"), forKey: "holdings.books")
            await sync()
        } catch { container.mainContext.rollback(); notice = error.localizedDescription }
    }
    /// Called only after confirmed server account deletion, using this old workspace's context.
    func eraseDeletedAccountCache() throws {
        guard let userID else { return }
        retired = true
        let context = container.mainContext
        for record in try context.fetch(FetchDescriptor<HoldingRecord>()) { context.delete(record) }
        try context.save()
        if let metadataURL, FileManager.default.fileExists(atPath: metadataURL.path) { try FileManager.default.removeItem(at: metadataURL) }
        defaults.removePersistentDomain(forName: "com.oryjk.sumly.holdings.user-\(userID)")
        base = .empty
    }
}
