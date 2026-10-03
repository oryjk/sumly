import Foundation
import SwiftData
import Testing
@testable import Sumly

/// 发布前 HoldingRecord 的实际字段，不与新模型共享定义以避免遗漏迁移问题。
private enum LegacyGoldSchema {
    @Model final class HoldingRecord {
        @Attribute(.unique) var id: UUID
        var grams: Double
        var unitPriceCNY: Double
        var timestamp: Date
        var note: String
        var createdAt: Date
        var brand: String = ""
        var bookName: String = "默认账本"
        var disposition: String = "holding"
        var disposedAt: Date?
        var disposalAmount: Double = 0
        var purchaseID: UUID?
        var extraFee: Double = 0
        var purchaseChannel: String = ""
        var counterparty: String = ""
        init() {
            id = UUID(); grams = 30; unitPriceCNY = 800; timestamp = Date(timeIntervalSince1970: 1_760_000_000)
            note = "旧记录"; createdAt = Date(timeIntervalSince1970: 1_760_000_000); extraFee = 100; brand = "银行"; bookName = "测试账本"
        }
    }
}

@MainActor @Test func oldDiskStoreMigratesWithoutLosingPurchaseOrDisposition() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = directory.appendingPathComponent("holdings.store")
    var identity: UUID?
    do {
        let old = try ModelContainer(for: LegacyGoldSchema.HoldingRecord.self, configurations: ModelConfiguration(url: store))
        let record = LegacyGoldSchema.HoldingRecord()
        identity = record.id
        old.mainContext.insert(record)
        let sale = LegacyGoldSchema.HoldingRecord()
        sale.disposition = "sold"; sale.disposedAt = record.timestamp.addingTimeInterval(100); sale.disposalAmount = 26000
        old.mainContext.insert(sale)
        try old.mainContext.save()
    }
    let migrated = try ModelContainer(for: HoldingRecord.self, configurations: ModelConfiguration(url: store))
    let records = try migrated.mainContext.fetch(FetchDescriptor<HoldingRecord>())
    #expect(records.count == 2)
    let record = try #require(records.first { $0.id == identity })
    #expect(record.totalPurchaseCost == 24100)
    #expect(record.timestamp == Date(timeIntervalSince1970: 1_760_000_000))
    #expect(record.brand == "银行")
    #expect(record.bookName == "测试账本")
    #expect(GoldReturnCalculator.calculate(record.returnInput, referencePrice: 900)?.profit == 2900)
    #expect(record.alerts.isEmpty)
    #expect(records.first { $0.disposition == "sold" }?.disposalAmount == 26000)
    var alert = HoldingAlert(kind: .breakEven, threshold: 0, enabled: true, basis: .domestic)
    alert.previousPrice = 790
    try record.setAlerts([alert]); record.laborFee = 500; record.purchaseTotalOverride = 25000
    try migrated.mainContext.save()
    let reopened = try ModelContainer(for: HoldingRecord.self, configurations: ModelConfiguration(url: store))
    let saved = try #require(reopened.mainContext.fetch(FetchDescriptor<HoldingRecord>()).first { $0.id == identity })
    #expect(saved.totalPurchaseCost == 25000)
    #expect(saved.laborFee == 500)
    #expect(saved.alerts.first?.previousPrice == 790)
}
