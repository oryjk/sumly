import Foundation
import SwiftData
import Testing
@testable import Sumly

@MainActor @Test func cloudThreeWayMergePreservesIndependentChangesAndDeletion() throws {
    let a = HoldingRecord(grams: 10, unitPriceCNY: 800, timestamp: .now)
    let b = HoldingRecord(grams: 20, unitPriceCNY: 810, timestamp: .now)
    let base = HoldingDocument(books: ["默认账本"], records: [HoldingCloudRecord(a), HoldingCloudRecord(b)])
    var local = base; local.records[0].note = "本机编辑"
    var remote = base; remote.records.removeLast()
    let result = HoldingCloudMerge.merge(base: base, local: local, remote: remote)
    #expect(result.conflicts.isEmpty)
    #expect(result.document.records.count == 1)
    #expect(result.document.records.first?.note == "本机编辑")
}
@MainActor @Test func cloudConcurrentEditDeleteRequiresExplicitChoice() throws {
    let record = HoldingRecord(grams: 10, unitPriceCNY: 800, timestamp: .now)
    let base = HoldingDocument(books: ["默认账本"], records: [HoldingCloudRecord(record)])
    var local = base; local.records[0].note = "尚未上传"
    let remote = HoldingDocument.empty
    #expect(HoldingCloudMerge.merge(base: base, local: local, remote: remote).conflicts == [record.id])
    #expect(HoldingCloudMerge.merge(base: base, local: local, remote: remote, choice: .local).document.records.count == 1)
    #expect(HoldingCloudMerge.merge(base: base, local: local, remote: remote, choice: .remote).document.records.isEmpty)
}
@MainActor @Test func cloudRoundTripPreservesCostDisposalAndOnlyAlertConfiguration() throws {
    let record = HoldingRecord(grams: 3, unitPriceCNY: 780, timestamp: Date(timeIntervalSince1970: 1_700_000_000.123))
    record.laborFee = 240; record.purity = 0.9999; record.purchaseTotalOverride = 2600
    record.disposition = "sold"; record.disposedAt = .now; record.disposalAmount = 2700
    var alert = HoldingAlert(kind: .price, threshold: 900, enabled: true, basis: .domestic)
    alert.previousPrice = 850; alert.previousAsOf = .now; alert.lastTriggeredAt = .now
    try record.setAlerts([alert])
    let wire = HoldingCloudRecord(record)
    let decoded = try HoldingCloudCoding.decode(HoldingCloudRecord.self, from: HoldingCloudCoding.encode(wire))
    #expect(decoded == wire)
    let copy = decoded.makeRecord()
    #expect(copy.id == record.id && copy.timestamp == record.timestamp)
    #expect(copy.totalPurchaseCost == 2600 && copy.disposalAmount == 2700)
    #expect(copy.alerts.first?.previousPrice == nil)
    #expect(copy.alerts.first?.lastTriggeredAt == nil)
    wire.apply(to: record)
    #expect(record.alerts.first?.lastTriggeredAt == alert.lastTriggeredAt)
}

private struct CloudAuthFixture: AuthServicing {
    let userID: Int64
    func execute(_ request: AuthRequest) async throws -> Data {
        try JSONEncoder().encode(LoginResult(token: "fixture-access", refreshToken: "fixture-refresh", expiresIn: 3600,
            user: NativeUser(id: userID, nickname: "测试", avatarURL: "", email: "fixture@example.invalid", phoneNumber: nil, status: "active", provider: .email)))
    }
}
@MainActor private final class CloudCredentials: CredentialStoring {
    func load() throws -> StoredSession? { nil }
    func save(_ session: StoredSession) throws {}
    func clear() throws {}
}
private actor CloudServerFixture: HoldingCloudServicing {
    var snapshot: HoldingCloudSnapshot
    var offline = false
    var pauseFetch = false
    var pausePut = false
    var hasEntered = false
    var entered: CheckedContinuation<Void, Never>?
    var release: CheckedContinuation<Void, Never>?
    init(_ snapshot: HoldingCloudSnapshot = .empty) { self.snapshot = snapshot }
    func configure(offline: Bool = false, fetch: Bool = false, put: Bool = false) { self.offline = offline; pauseFetch = fetch; pausePut = put }
    func waitUntilRequest() async { if hasEntered { return }; await withCheckedContinuation { entered = $0 } }
    func resume() { release?.resume(); release = nil }
    func state() -> HoldingCloudSnapshot { snapshot }
    func replace(_ value: HoldingCloudSnapshot) { snapshot = value }
    func fetch(token: String) async throws -> HoldingCloudSnapshot {
        if offline { throw AuthError.network }
        if pauseFetch { await withCheckedContinuation { release = $0; hasEntered = true; entered?.resume(); entered = nil } }
        return snapshot
    }
    func put(_ document: HoldingDocument, revision: Int64, token: String) async throws -> HoldingCloudSnapshot {
        if pausePut { await withCheckedContinuation { release = $0; hasEntered = true; entered?.resume(); entered = nil } }
        guard snapshot.revision == revision else { throw HoldingCloudError.conflict }
        snapshot = .init(revision: revision + 1, document: document)
        return snapshot
    }
}
@MainActor private func cloudFixture(server: CloudServerFixture) async throws -> (AuthSession, ModelContainer, HoldingsCloud, URL) {
    let userID = Int64.random(in: 1_000_000...9_999_999_999)
    let session = AuthSession(service: CloudAuthFixture(userID: userID), store: CloudCredentials())
    try await session.login(.emailLogin(email: "fixture@example.invalid", password: "fixture-only-password"))
    let guest = try ModelContainer(for: HoldingRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-tests-" + UUID().uuidString)
    let cloud = try HoldingsCloud(session: session, guestContainer: guest, service: server, directory: directory)
    return (session, guest, cloud, directory)
}
@MainActor @Test func cloudOfflineChangesSurviveReopenAndGuestImportIsIdempotent() async throws {
    let server = CloudServerFixture()
    let (session, guest, cloud, directory) = try await cloudFixture(server: server)
    guest.mainContext.insert(HoldingRecord(grams: 10, unitPriceCNY: 800, timestamp: .now))
    try guest.mainContext.save()
    await server.configure(offline: true)
    await cloud.importGuestRecords()
    #expect(cloud.base.revision == 0)
    #expect(try cloud.document().records.count == 1)
    #expect(try guest.mainContext.fetchCount(FetchDescriptor<HoldingRecord>()) == 1)
    let reopened = try HoldingsCloud(session: session, guestContainer: guest, service: server, directory: directory)
    #expect(try reopened.document().records.count == 1)
    await server.configure()
    await reopened.importGuestRecords()
    #expect(try reopened.document().records.count == 1)
    #expect(await server.state().document.records.count == 1)
    #expect(reopened.base.revision == 1)
    try reopened.eraseDeletedAccountCache()
    #expect(try guest.mainContext.fetchCount(FetchDescriptor<HoldingRecord>()) == 1)
}
@MainActor @Test func cloudLateResponseAfterLogoutCannotApply() async throws {
    let record = HoldingRecord(grams: 3, unitPriceCNY: 800, timestamp: .now)
    let server = CloudServerFixture(.init(revision: 1, document: .init(books: ["默认账本"], records: [HoldingCloudRecord(record)])))
    let (session, _, cloud, _) = try await cloudFixture(server: server)
    await server.configure(fetch: true)
    let waiting = Task { await server.waitUntilRequest() }
    await Task.yield()
    let operation = Task { await cloud.sync() }
    await waiting.value
    session.clearLocal()
    await server.resume()
    await operation.value
    #expect(try cloud.document().records.isEmpty)
    #expect(cloud.base.revision == 0)
}
@MainActor @Test func cloudEditsDuringUploadRemainPendingAndReachServerNextSync() async throws {
    let server = CloudServerFixture()
    let (_, _, cloud, _) = try await cloudFixture(server: server)
    let record = HoldingRecord(grams: 5, unitPriceCNY: 800, timestamp: .now)
    record.note = "上传前"; cloud.container.mainContext.insert(record); try cloud.container.mainContext.save()
    await server.configure(put: true)
    let waiting = Task { await server.waitUntilRequest() }; await Task.yield()
    let operation = Task { await cloud.sync() }
    await waiting.value
    record.note = "上传中修改"; try cloud.container.mainContext.save()
    await server.resume(); await operation.value
    #expect(cloud.conflictCount == 0)
    #expect(try cloud.document().records.first?.note == "上传中修改")
    #expect(cloud.base.document.records.first?.note == "上传前")
    await server.configure(); await cloud.sync()
    #expect(await server.state().document.records.first?.note == "上传中修改")
    try cloud.eraseDeletedAccountCache()
}
@Test func cloudTransportKeepsBasePrefixAndRejectsOversizedOrDuplicateRecords() throws {
    let request = try HoldingCloudService.makeRequest(baseURL: URL(string: "https://example.invalid/sumly/api/v1")!, token: "fixture", body: nil)
    #expect(request.url?.path == "/sumly/api/v1/app/holdings")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
    #expect(throws: (any Error).self) { try HoldingCloudService.makeRequest(baseURL: URL(string: "http://example.invalid")!, token: "fixture", body: nil) }
    #expect(throws: (any Error).self) { try HoldingCloudService.unwrap(Data("{}".utf8), status: 409) }
}

@MainActor @Test func cloudConflictChoiceDoesNotDiscardNewUnseenConflicts() async throws {
    let a = HoldingRecord(grams: 1, unitPriceCNY: 800, timestamp: .now)
    let b = HoldingRecord(grams: 2, unitPriceCNY: 800, timestamp: .now)
    let original = HoldingDocument(books: ["默认账本"], records: [HoldingCloudRecord(a), HoldingCloudRecord(b)]).normalized
    let server = CloudServerFixture(.init(revision: 1, document: original))
    let (_, _, cloud, _) = try await cloudFixture(server: server)
    await cloud.sync()
    let records = try cloud.container.mainContext.fetch(FetchDescriptor<HoldingRecord>())
    for record in records { record.note = "本机编辑" }
    try cloud.container.mainContext.save()
    var remote = original; remote.records[0].note = "云端A编辑"
    await server.replace(.init(revision: 2, document: remote)); await cloud.sync()
    #expect(cloud.conflictCount == 1)
    remote.records[1].note = "云端B新编辑"
    await server.replace(.init(revision: 3, document: remote)); await cloud.sync(choice: .remote)
    #expect(cloud.conflictCount == 2)
    #expect(try cloud.document().records.allSatisfy { $0.note == "本机编辑" })
    await cloud.sync(choice: .remote)
    #expect(cloud.conflictCount == 0)
    #expect(try cloud.document().records == remote.records)
    try cloud.eraseDeletedAccountCache()
}

@MainActor @Test func cloudRejectsInvalidSuccessfulResponseBeforeCacheMutation() throws {
    struct Envelope: Encodable { let code = 0; let message = "ok"; let data: HoldingCloudSnapshot }
    let record = HoldingRecord(grams: 1, unitPriceCNY: 800, timestamp: .now)
    let valid = HoldingCloudRecord(record)
    var cases = [HoldingCloudRecord]()
    var bad = valid; bad.grams = -1; cases.append(bad)
    bad = valid; bad.purity = 0; cases.append(bad)
    bad = valid; bad.disposition = "unknown"; cases.append(bad)
    bad = valid; bad.disposition = "sold"; cases.append(bad)
    bad = valid; bad.note = String(repeating: "长", count: 2001); cases.append(bad)
    bad = valid
    let alert = HoldingCloudAlert(HoldingAlert(kind: .price, threshold: 900, enabled: true, basis: .domestic))
    bad.alerts = [alert, alert]; cases.append(bad)
    for invalid in cases {
        let data = try HoldingCloudCoding.encode(Envelope(data: .init(revision: 1, document: .init(books: ["默认账本"], records: [invalid]))))
        #expect(throws: (any Error).self) { try HoldingCloudService.unwrap(data, status: 200) }
    }
    let duplicate = try HoldingCloudCoding.encode(Envelope(data: .init(revision: 1, document: .init(books: ["默认账本"], records: [valid, valid]))))
    #expect(throws: (any Error).self) { try HoldingCloudService.unwrap(duplicate, status: 200) }
    let tooLarge = Data(repeating: 0, count: HoldingCloudService.maxBytes + 1)
    #expect(throws: (any Error).self) { try HoldingCloudService.makeRequest(baseURL: URL(string: "https://example.invalid")!, token: "fixture", body: tooLarge) }
}

@MainActor @Test func cloudConcurrentPartialDisposalCannotInflatePurchaseWeight() throws {
    let record = HoldingRecord(grams: 10, unitPriceCNY: 800, timestamp: .now)
    let original = HoldingCloudRecord(record)
    var localRemaining = original; localRemaining.grams = 7
    var localSale = original; localSale.id = UUID(); localSale.purchaseID = original.id
    localSale.grams = 3; localSale.disposition = "sold"; localSale.disposedAt = .now; localSale.disposalAmount = 2700
    var remoteRemaining = original; remoteRemaining.grams = 6
    var remoteSale = localSale; remoteSale.id = UUID(); remoteSale.grams = 4; remoteSale.disposalAmount = 3600
    let base = HoldingDocument(books: ["默认账本"], records: [original])
    let local = HoldingDocument(books: base.books, records: [localRemaining, localSale])
    let remote = HoldingDocument(books: base.books, records: [remoteRemaining, remoteSale])
    #expect(!HoldingCloudMerge.merge(base: base, local: local, remote: remote).conflicts.isEmpty)
    for choice in [HoldingCloudMerge.Choice.local, .remote] {
        let result = HoldingCloudMerge.merge(base: base, local: local, remote: remote, choice: choice)
        #expect(result.document.records.count == 2)
        #expect(result.document.records.reduce(0) { $0 + $1.grams } == 10)
    }
}

@MainActor @Test func cloudChangingPurchaseFamilyCannotDuplicateRecordIDs() throws {
    let record = HoldingRecord(grams: 10, unitPriceCNY: 800, timestamp: .now)
    let original = HoldingCloudRecord(record)
    var localRecord = original; localRecord.purchaseID = UUID(); localRecord.note = "本机"
    var remoteRecord = original; remoteRecord.note = "云端"
    let base = HoldingDocument(books: ["默认账本"], records: [original])
    let local = HoldingDocument(books: base.books, records: [localRecord])
    let remote = HoldingDocument(books: base.books, records: [remoteRecord])
    for choice in [HoldingCloudMerge.Choice.local, .remote] {
        let merged = HoldingCloudMerge.merge(base: base, local: local, remote: remote, choice: choice)
        #expect(merged.document.records.count == 1)
        #expect(merged.document.isValid)
        #expect(merged.document.records.first?.note == (choice == .local ? "本机" : "云端"))
    }
}
