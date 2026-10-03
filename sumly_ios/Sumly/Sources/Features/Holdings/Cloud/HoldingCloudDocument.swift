import Foundation

/// Device notification baselines never travel with account configuration.
struct HoldingCloudAlert: Codable, Equatable, Sendable {
    var id: UUID
    var kind: HoldingAlertKind
    var threshold: Double
    var enabled: Bool
    var basis: GoldMarketBasis
    init(_ alert: HoldingAlert) {
        id = alert.id; kind = alert.kind; threshold = alert.threshold
        enabled = alert.enabled; basis = alert.basis
    }
    var localAlert: HoldingAlert { .init(id: id, kind: kind, threshold: threshold, enabled: enabled, basis: basis) }
}

struct HoldingCloudRecord: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var grams: Double
    var unitPriceCNY: Double
    var timestamp: Date
    var note: String
    var createdAt: Date
    var brand: String
    var bookName: String
    var disposition: String
    var disposedAt: Date?
    var disposalAmount: Double
    var purchaseID: UUID?
    var extraFee: Double
    var purchaseChannel: String
    var counterparty: String
    var assetType: String
    var purity: Double
    var laborFee: Double
    var purchaseTotalOverride: Double?
    var recoveryDeduction: Double
    var recoveryDiscount: Double
    var recoveryFixedFee: Double
    var alerts: [HoldingCloudAlert]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id &&
        lhs.grams == rhs.grams &&
        lhs.unitPriceCNY == rhs.unitPriceCNY &&
        lhs.note == rhs.note &&
        lhs.brand == rhs.brand &&
        lhs.bookName == rhs.bookName &&
        lhs.disposition == rhs.disposition &&
        lhs.disposalAmount == rhs.disposalAmount &&
        lhs.purchaseID == rhs.purchaseID &&
        lhs.extraFee == rhs.extraFee &&
        lhs.purchaseChannel == rhs.purchaseChannel &&
        lhs.counterparty == rhs.counterparty &&
        lhs.assetType == rhs.assetType &&
        lhs.purity == rhs.purity &&
        lhs.laborFee == rhs.laborFee &&
        lhs.purchaseTotalOverride == rhs.purchaseTotalOverride &&
        lhs.recoveryDeduction == rhs.recoveryDeduction &&
        lhs.recoveryDiscount == rhs.recoveryDiscount &&
        lhs.recoveryFixedFee == rhs.recoveryFixedFee &&
        lhs.alerts == rhs.alerts &&
        sameDate(lhs.timestamp, rhs.timestamp) && sameDate(lhs.createdAt, rhs.createdAt) && sameDate(lhs.disposedAt, rhs.disposedAt)
    }
    private static func sameDate(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case (let l?, let r?): abs(l.timeIntervalSince(r)) < 0.000001
        default: false
        }
    }

    @MainActor init(_ record: HoldingRecord) {
        id = record.id
        grams = record.grams
        unitPriceCNY = record.unitPriceCNY
        timestamp = record.timestamp
        note = record.note
        createdAt = record.createdAt
        brand = record.brand
        bookName = record.bookName
        disposition = record.disposition
        disposedAt = record.disposedAt
        disposalAmount = record.disposalAmount
        purchaseID = record.purchaseID
        extraFee = record.extraFee
        purchaseChannel = record.purchaseChannel
        counterparty = record.counterparty
        assetType = record.assetType
        purity = record.purity
        laborFee = record.laborFee
        purchaseTotalOverride = record.purchaseTotalOverride
        recoveryDeduction = record.recoveryDeduction
        recoveryDiscount = record.recoveryDiscount
        recoveryFixedFee = record.recoveryFixedFee
        alerts = record.alerts.map(HoldingCloudAlert.init).sorted { $0.id.uuidString < $1.id.uuidString }
    }
    @MainActor func makeRecord() -> HoldingRecord {
        let record = HoldingRecord(grams: grams, unitPriceCNY: unitPriceCNY, timestamp: timestamp)
        apply(to: record)
        return record
    }
    @MainActor func apply(to record: HoldingRecord) {
        let unchangedInput = record.returnInput == GoldReturnInput(grams: grams, purity: purity, unitPrice: unitPriceCNY,
            laborFee: laborFee, otherCost: extraFee, totalCostOverride: purchaseTotalOverride,
            rule: .init(perGramDeduction: recoveryDeduction, discountRate: recoveryDiscount, fixedFee: recoveryFixedFee))
        let previousAlerts = record.alerts
        record.id = id
        record.grams = grams
        record.unitPriceCNY = unitPriceCNY
        if !Self.sameDate(record.timestamp, timestamp) { record.timestamp = timestamp }
        record.note = note
        if !Self.sameDate(record.createdAt, createdAt) { record.createdAt = createdAt }
        record.brand = brand
        record.bookName = bookName
        record.disposition = disposition
        if !Self.sameDate(record.disposedAt, disposedAt) { record.disposedAt = disposedAt }
        record.disposalAmount = disposalAmount
        record.purchaseID = purchaseID
        record.extraFee = extraFee
        record.purchaseChannel = purchaseChannel
        record.counterparty = counterparty
        record.assetType = assetType
        record.purity = purity
        record.laborFee = laborFee
        record.purchaseTotalOverride = purchaseTotalOverride
        record.recoveryDeduction = recoveryDeduction
        record.recoveryDiscount = recoveryDiscount
        record.recoveryFixedFee = recoveryFixedFee
        let merged = alerts.map { configuration in
            if unchangedInput, let prior = previousAlerts.first(where: { $0.id == configuration.id }),
               HoldingCloudAlert(prior) == configuration { return prior }
            return configuration.localAlert
        }
        // Configurations contain finite numeric values validated by the backend.
        if let data = try? JSONEncoder().encode(merged) { record.alertsJSON = String(decoding: data, as: UTF8.self) }
    }
}

struct HoldingDocument: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var books: [String]
    var records: [HoldingCloudRecord]
    static let empty = Self(books: ["默认账本"], records: [])
    var normalized: Self {
        var result = self
        result.books = Array(Set(books + records.map(\.bookName) + ["默认账本"])).sorted()
        result.records.sort { $0.id.uuidString < $1.id.uuidString }
        return result
    }
}
struct HoldingCloudSnapshot: Codable, Equatable, Sendable {
    var revision: Int64
    var document: HoldingDocument
    static let empty = Self(revision: 0, document: .empty)
}
enum HoldingCloudCoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }
}

enum HoldingCloudMerge {
    enum Choice { case local, remote }
    struct Result {
        var document: HoldingDocument
        var conflicts: Set<UUID>
    }
    /// nil represents deletion; distinct records can be merged without discarding either device's work.
    static func merge(base: HoldingDocument, local: HoldingDocument, remote: HoldingDocument, choice: Choice? = nil) -> Result {
        // A purchase and its partial-disposal records are one merge unit. Otherwise
        // picking one remaining holding while retaining both devices' disposal copies inflates weight.
        // Build one stable component map across all versions, including any changed
        // family link. Each record ID can therefore occur in only one resolved group.
        let all = base.records + local.records + remote.records
        var parents: [UUID: UUID] = [:]
        for record in all {
            parents[record.id] = record.id
            if let purchaseID = record.purchaseID { parents[purchaseID] = purchaseID }
        }
        func root(_ id: UUID) -> UUID {
            var current = id
            while let next = parents[current], next != current { current = next }
            return current
        }
        for record in all {
            if let purchaseID = record.purchaseID {
                let r = root(record.id), p = root(purchaseID)
                if r != p { parents[r] = p }
            }
        }
        func families(_ records: [HoldingCloudRecord]) -> [UUID: [HoldingCloudRecord]] {
            Dictionary(grouping: records, by: { root($0.id) })
                .mapValues { $0.sorted { $0.id.uuidString < $1.id.uuidString } }
        }
        let original = families(base.records), ours = families(local.records), theirs = families(remote.records)
        var records: [HoldingCloudRecord] = [], conflicts = Set<UUID>()
        for id in Set(original.keys).union(ours.keys).union(theirs.keys) {
            let b = original[id], l = ours[id], r = theirs[id]
            let value: [HoldingCloudRecord]?
            if l == r { value = l }
            else if l == b { value = r }
            else if r == b { value = l }
            else {
                conflicts.formUnion((b ?? []).map(\.id) + (l ?? []).map(\.id) + (r ?? []).map(\.id))
                value = choice == .remote ? r : l
            }
            if let value { records += value }
        }
        return Result(document: HoldingDocument(books: local.books + remote.books, records: records).normalized, conflicts: conflicts)
    }
}

extension HoldingCloudSnapshot {
    var isValid: Bool { revision >= 0 && revision < Int64.max && document.isValid }
}
extension HoldingDocument {
    /// Validate both network documents and durable merge bases before changing the cache.
    var isValid: Bool {
        guard schemaVersion == 1, (1...100).contains(books.count), records.count <= 1000,
              Set(books).count == books.count, Set(records.map(\.id)).count == records.count,
              books.allSatisfy({ Self.validText($0, max: 100) && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return false }
        let bookSet = Set(books)
        return records.allSatisfy { record in
            guard bookSet.contains(record.bookName), record.grams.isFinite, record.grams > 0,
                  record.unitPriceCNY.isFinite, record.unitPriceCNY >= 0,
                  record.unitPriceCNY > 0 || (record.purchaseTotalOverride ?? 0) > 0,
                  Self.validDate(record.timestamp), Self.validDate(record.createdAt),
                  ["holding", "sold", "gift"].contains(record.disposition),
                  record.purity.isFinite, record.purity > 0, record.purity <= 1,
                  record.recoveryDiscount.isFinite, record.recoveryDiscount >= 0, record.recoveryDiscount < 1,
                  Self.validText(record.note, max: 2000),
                  [record.brand, record.purchaseChannel, record.counterparty, record.assetType].allSatisfy({ Self.validText($0, max: 200) }),
                  [record.disposalAmount, record.extraFee, record.laborFee, record.recoveryDeduction, record.recoveryFixedFee].allSatisfy({ $0.isFinite && $0 >= 0 }),
                  record.alerts.count <= 4, Set(record.alerts.map(\.id)).count == record.alerts.count,
                  record.alerts.allSatisfy({ $0.threshold.isFinite && $0.threshold >= 0 }) else { return false }
            if let total = record.purchaseTotalOverride, !total.isFinite || total < 0 { return false }
            if record.disposition != "holding", record.disposedAt == nil { return false }
            if let disposedAt = record.disposedAt, !Self.validDate(disposedAt) || disposedAt < record.timestamp { return false }
            return true
        }
    }
    private static func validText(_ value: String, max: Int) -> Bool {
        value.unicodeScalars.count <= max && !value.contains("\0")
    }
    private static func validDate(_ value: Date) -> Bool {
        let milliseconds = value.timeIntervalSince1970 * 1000
        return milliseconds.isFinite && (-62_135_596_800_000...253_402_300_799_999).contains(milliseconds)
    }
}
