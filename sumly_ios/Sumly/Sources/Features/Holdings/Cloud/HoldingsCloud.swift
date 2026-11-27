import CoreData
import Foundation
import Observation
import SwiftData

extension Notification.Name {
    static let holdingsLocalDataDidChange = Notification.Name("com.oryjk.sumly.holdingsLocalDataDidChange")
}

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
    private(set) var hasPendingLocalChanges = false
    private(set) var guestRecordCount = 0
    private var retryAfter = Date.distantPast
    private var lastRemoteCheck = Date.distantPast
    private var retired = false
    private var conflictSnapshot: HoldingCloudSnapshot?
    private var conflictLocal: HoldingDocument?
    @ObservationIgnored private var lastObservedBooksRaw: String?
    @ObservationIgnored private var isApplyingInternalSave = false
    @ObservationIgnored private var pendingRefreshTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var notificationObservers: [NSObjectProtocol] = []

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
        refreshLocalStatus()
        installObservers()
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var status: String {
        if userID == nil { return L10n.tr("游客记录仅保存在此设备，登录后可导入账户。") }
        if isSyncing { return L10n.tr("正在同步云端…") }
        if conflictCount > 0 { return L10n.fmt("%lld 条记录在两台设备上都有更改，请选择保留哪一份。", Int64(conflictCount)) }
        if let notice { return notice }
        if hasPendingLocalChanges { return L10n.tr("有更改等待同步，记录已保存在本机。") }
        if let lastSyncedAt { return L10n.fmt("已同步 · %@", lastSyncedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguage.currentLocale))) }
        return L10n.tr("已开启云同步，本机缓存支持离线记录。")
    }

    /// Recomputes cached local dirty flag and guest record count outside SwiftUI `body` evaluation.
    func refreshLocalStatus() {
        guard !retired else { return }
        lastObservedBooksRaw = defaults.string(forKey: "holdings.books")
        let nextGuestCount = (try? guestContainer.mainContext.fetchCount(FetchDescriptor<HoldingRecord>())) ?? 0
        if guestRecordCount != nextGuestCount {
            guestRecordCount = nextGuestCount
        }
        if userID != nil {
            let nextPending = (try? document()) != base.document
            if hasPendingLocalChanges != nextPending {
                hasPendingLocalChanges = nextPending
            }
        } else if hasPendingLocalChanges {
            hasPendingLocalChanges = false
        }
    }

    private func installObservers() {
        let localChangeObserver = NotificationCenter.default.addObserver(
            forName: .holdingsLocalDataDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.handleLocalDataNotification() }
            } else {
                Task { @MainActor [weak self] in self?.handleLocalDataNotification() }
            }
        }

        let storeSaveObserver = NotificationCenter.default.addObserver(
            forName: NSManagedObjectContext.didSaveObjectsNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.scheduleLocalStatusRefresh() }
            } else {
                Task { @MainActor [weak self] in self?.scheduleLocalStatusRefresh() }
            }
        }

        let defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: nil
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.handleDefaultsChange() }
            } else {
                Task { @MainActor [weak self] in self?.handleDefaultsChange() }
            }
        }

        notificationObservers = [localChangeObserver, storeSaveObserver, defaultsObserver]
    }

    private func removeObservers() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }

    private func handleLocalDataNotification() {
        guard !retired, !isApplyingInternalSave else { return }
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil
        refreshLocalStatus()
    }

    private func scheduleLocalStatusRefresh() {
        guard !retired, !isApplyingInternalSave else { return }
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, !self.retired else { return }
            self.pendingRefreshTask = nil
            self.refreshLocalStatus()
        }
    }

    private func handleDefaultsChange() {
        guard !retired, !isApplyingInternalSave else { return }
        let currentBooks = defaults.string(forKey: "holdings.books")
        guard currentBooks != lastObservedBooksRaw else { return }
        refreshLocalStatus()
    }

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
        isApplyingInternalSave = true
        defer { isApplyingInternalSave = false }
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
        refreshLocalStatus()
        return true
    }
    func sync(choice: HoldingCloudMerge.Choice? = nil) async {
        guard userID != nil, !isSyncing, !retired else { return }
        isSyncing = true; notice = nil
        defer {
            isSyncing = false
            refreshLocalStatus()
        }
        do {
            isApplyingInternalSave = true
            do {
                try container.mainContext.save()
            } catch {
                isApplyingInternalSave = false
                throw error
            }
            isApplyingInternalSave = false
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
        catch { notice = L10n.fmt("%@ 更改保留在本机，稍后重试。", error.localizedDescription); retryAfter = .now.addingTimeInterval(60) }
    }
    func run() async {
        guard userID != nil else { return }
        refreshLocalStatus()
        await sync()
        while !Task.isCancelled && !retired {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard session.user?.id == userID else { return }
            refreshLocalStatus()
            if Date() >= retryAfter, conflictCount == 0,
               (Date().timeIntervalSince(lastRemoteCheck) >= 60 || hasPendingLocalChanges) { await sync() }
        }
    }
    func importGuestRecords() async {
        guard userID != nil, !retired, !isSyncing else { return }
        do {
            let context = container.mainContext
            let existing = Set(try context.fetch(FetchDescriptor<HoldingRecord>()).map(\.id))
            let guest = try guestContainer.mainContext.fetch(FetchDescriptor<HoldingRecord>())
            isApplyingInternalSave = true
            do {
                for record in guest where !existing.contains(record.id) { context.insert(HoldingCloudRecord(record).makeRecord()) }
                try context.save()
                let books = (UserDefaults.standard.string(forKey: "holdings.books") ?? "默认账本").components(separatedBy: "\n")
                defaults.set(Array(Set(try document().books + books)).sorted().joined(separator: "\n"), forKey: "holdings.books")
            } catch {
                isApplyingInternalSave = false
                throw error
            }
            isApplyingInternalSave = false
            refreshLocalStatus()
            await sync()
        } catch { container.mainContext.rollback(); notice = error.localizedDescription; refreshLocalStatus() }
    }
    /// Called only after confirmed server account deletion, using this old workspace's context.
    func eraseDeletedAccountCache() throws {
        guard let userID else { return }
        retired = true
        removeObservers()
        let context = container.mainContext
        for record in try context.fetch(FetchDescriptor<HoldingRecord>()) { context.delete(record) }
        try context.save()
        if let metadataURL, FileManager.default.fileExists(atPath: metadataURL.path) { try FileManager.default.removeItem(at: metadataURL) }
        defaults.removePersistentDomain(forName: "com.oryjk.sumly.holdings.user-\(userID)")
        base = .empty
        hasPendingLocalChanges = false
    }
}
