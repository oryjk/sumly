import Foundation
import Testing
import SwiftData
@testable import Sumly

private let alertNow = Date(timeIntervalSince1970: 1_800_000_000)
private let alertInput = GoldReturnInput(grams: 10, unitPrice: 800, rule: .init(perGramDeduction: 8))

@Test func holdingAlertUsesCrossingNotInitialAboveThreshold() {
    var alert = HoldingAlert(kind: .breakEven, threshold: 0, enabled: true, basis: .domestic)
    #expect(!HoldingAlertEngine.evaluate(&alert, input: alertInput, price: 820, asOf: alertNow, now: alertNow))
    #expect(!HoldingAlertEngine.evaluate(&alert, input: alertInput, price: 800, asOf: alertNow.addingTimeInterval(3), now: alertNow.addingTimeInterval(3)))
    #expect(HoldingAlertEngine.evaluate(&alert, input: alertInput, price: 808, asOf: alertNow.addingTimeInterval(6), now: alertNow.addingTimeInterval(6)))
    #expect(!HoldingAlertEngine.evaluate(&alert, input: alertInput, price: 820, asOf: alertNow.addingTimeInterval(9), now: alertNow.addingTimeInterval(9)))
}
@Test func allFourAlertTargetsUseRealProceeds() {
    for (kind, threshold, below, above) in [(HoldingAlertKind.breakEven, 0.0, 800.0, 808.0),
        (.returnPercent, 10.0, 880.0, 888.0), (.profitAmount, 1000.0, 900.0, 908.0), (.price, 900.0, 890.0, 900.0)] {
        var alert = HoldingAlert(kind: kind, threshold: threshold, enabled: true, basis: .domestic)
        #expect(!HoldingAlertEngine.evaluate(&alert, input: alertInput, price: below, asOf: alertNow, now: alertNow))
        #expect(HoldingAlertEngine.evaluate(&alert, input: alertInput, price: above, asOf: alertNow.addingTimeInterval(3), now: alertNow.addingTimeInterval(3)))
    }
}
@Test func cooldownAndHysteresisSuppressOscillation() {
    var alert = HoldingAlert(kind: .price, threshold: 900, enabled: true, basis: .domestic)
    func sample(_ price: Double, _ offset: TimeInterval) -> Bool {
        HoldingAlertEngine.evaluate(&alert, input: alertInput, price: price, asOf: alertNow.addingTimeInterval(offset), now: alertNow.addingTimeInterval(offset))
    }
    #expect(!sample(890, 0)); #expect(sample(900, 3))
    #expect(!sample(899.9, 6)); #expect(!sample(900.1, 9))
    #expect(!sample(890, 12)); #expect(!sample(900, 15))
    #expect(!sample(890, 86410)); #expect(sample(900, 86413))
}
@Test func staleLateInvalidAndAbnormalQuotesDoNotTrigger() {
    var alert = HoldingAlert(kind: .price, threshold: 900, enabled: true, basis: .domestic)
    #expect(!HoldingAlertEngine.evaluate(&alert, input: alertInput, price: 800, asOf: alertNow, now: alertNow))
    let baseline = alert
    #expect(!HoldingAlertEngine.evaluate(&alert, input: alertInput, price: 900, asOf: alertNow.addingTimeInterval(-1), now: alertNow))
    #expect(alert == baseline)
    #expect(!HoldingAlertEngine.evaluate(&alert, input: alertInput, price: 1000, asOf: alertNow.addingTimeInterval(3), now: alertNow.addingTimeInterval(3)))
    #expect(alert == baseline)
    #expect(!HoldingAlertEngine.evaluate(&alert, input: alertInput, price: .nan, asOf: alertNow, now: alertNow))
    #expect(!HoldingAlertEngine.evaluate(&alert, input: alertInput, price: 900, asOf: alertNow.addingTimeInterval(3), now: alertNow.addingTimeInterval(400)))
    #expect(!HoldingAlertEngine.evaluate(&alert, input: alertInput, price: 900, asOf: alertNow.addingTimeInterval(90), now: alertNow))
    #expect(alert == baseline)
}
@Test func disabledAlertNeverRecordsOrTriggersAndStateSurvivesEncoding() throws {
    var disabled = HoldingAlert(kind: .breakEven, threshold: 0, enabled: false, basis: .domestic)
    #expect(!HoldingAlertEngine.evaluate(&disabled, input: alertInput, price: 800, asOf: alertNow, now: alertNow))
    #expect(disabled.previousPrice == nil)
    var alert = HoldingAlert(kind: .breakEven, threshold: 0, enabled: true, basis: .domestic)
    _ = HoldingAlertEngine.evaluate(&alert, input: alertInput, price: 800, asOf: alertNow, now: alertNow)
    let restored = try JSONDecoder().decode([HoldingAlert].self, from: JSONEncoder().encode([alert]))
    var saved = try #require(restored.first)
    #expect(HoldingAlertEngine.evaluate(&saved, input: alertInput, price: 810, asOf: alertNow.addingTimeInterval(3), now: alertNow.addingTimeInterval(3)))
}

@MainActor @Test func notificationFailureDoesNotConsumeCrossing() async throws {
    let container = try ModelContainer(for: HoldingRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let record = HoldingRecord(grams: 10, unitPriceCNY: 800, timestamp: alertNow.addingTimeInterval(-100))
    record.recoveryDeduction = 8
    try record.setAlerts([HoldingAlert(kind: .breakEven, threshold: 0, enabled: true, basis: .domestic)])
    container.mainContext.insert(record); try container.mainContext.save()
    let sender = AlertTestSender()
    let quotes = AlertTestQuotes()
    let monitor = HoldingAlertMonitor(notifications: sender, serviceFactory: { _ in quotes })
    await monitor.check(records: [record], context: container.mainContext, now: alertNow)
    #expect(record.alerts.first?.lastTriggeredAt == nil)
    sender.fail = true
    await monitor.check(records: [record], context: container.mainContext, now: alertNow.addingTimeInterval(3))
    #expect(record.alerts.first?.lastTriggeredAt == nil)
    #expect(record.alerts.first?.previousPrice == 800)
    sender.fail = false
    await monitor.check(records: [record], context: container.mainContext, now: alertNow.addingTimeInterval(4))
    #expect(record.alerts.first?.lastTriggeredAt == alertNow.addingTimeInterval(4))
    #expect(sender.delivered.count == 1)
    #expect(sender.delivered.first?.contains("预计真实保本线") == true)
}

private actor AlertTestQuotes: GoldQuoteServicing {
    var calls = 0
    func fetchQuote() async throws -> GoldQuote {
        calls += 1
        let first = calls == 1
        return .init(symbol: "AU9999", price: first ? 800 : 810, open: 800, high: 810, low: 800,
                     prevClose: 800, usdCNY: 0, cnyPerGram: first ? 800 : 810,
                     asOf: first ? alertNow : alertNow.addingTimeInterval(3))
    }
}
@MainActor private final class AlertTestSender: HoldingNotificationSending {
    var fail = false
    var delivered: [String] = []
    func send(id: String, title: String, body: String) async throws {
        if fail { throw NSError(domain: "notifications", code: 1) }
        delivered.append(body)
    }
    func remove(id: String) async {}
}

@Test func disabledHiddenTargetCannotBlockDisablingAnAlert() throws {
    let edited = [HoldingAlert(kind: .price, threshold: 900, enabled: false, basis: .domestic)]
    let merged = try #require(HoldingAlertForm.merge(edited: edited, values: [""], latest: edited, basis: .domestic))
    #expect(merged.first?.enabled == false)
    #expect(merged.first?.threshold == 900)
}
@Test func savingUnchangedFormPreservesCooldownThatAdvancedWhileOpen() throws {
    let edited = [HoldingAlert(kind: .price, threshold: 900, enabled: true, basis: .domestic)]
    var latest = edited
    latest[0].lastTriggeredAt = alertNow
    latest[0].previousPrice = 910; latest[0].previousAsOf = alertNow; latest[0].armed = false
    let merged = try #require(HoldingAlertForm.merge(edited: edited, values: ["900"], latest: latest, basis: .domestic))
    #expect(merged.first?.lastTriggeredAt == alertNow)
    #expect(merged.first?.previousPrice == 910)
    #expect(merged.first?.armed == false)
}

@Test func alertRecoversFromOldBaselineWithoutTriggeringOnFirstNewQuote() {
    var alert = HoldingAlert(kind: .price, threshold: 1050, enabled: true, basis: .domestic)
    alert.previousPrice = 800; alert.previousAsOf = alertNow.addingTimeInterval(-90 * 86400); alert.armed = true
    #expect(!HoldingAlertEngine.evaluate(&alert, input: alertInput, price: 1000, asOf: alertNow, now: alertNow))
    #expect(alert.previousPrice == 1000)
    #expect(HoldingAlertEngine.evaluate(&alert, input: alertInput, price: 1051, asOf: alertNow.addingTimeInterval(3), now: alertNow.addingTimeInterval(3)))
}

@MainActor @Test func cancellationDuringNotificationSendRemovesQueuedNotification() async throws {
    let container = try ModelContainer(for: HoldingRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let record = HoldingRecord(grams: 10, unitPriceCNY: 800, timestamp: alertNow.addingTimeInterval(-100))
    record.recoveryDeduction = 8
    var alert = HoldingAlert(kind: .breakEven, threshold: 0, enabled: true, basis: .domestic)
    _ = HoldingAlertEngine.evaluate(&alert, input: record.returnInput, price: 800, asOf: alertNow, now: alertNow)
    try record.setAlerts([alert]); container.mainContext.insert(record); try container.mainContext.save()
    let sender = SuspendedAlertSender()
    let monitor = HoldingAlertMonitor(notifications: sender, serviceFactory: { _ in AlertCrossingQuote() })
    let task = Task { await monitor.check(records: [record], context: container.mainContext, now: alertNow.addingTimeInterval(3)) }
    await sender.waitUntilSending()
    var disabled = record.alerts; disabled[0].enabled = false
    try record.setAlerts(disabled); try container.mainContext.save()
    task.cancel(); sender.resume()
    await task.value
    #expect(sender.pending.isEmpty)
    #expect(record.alerts.first?.enabled == false)
    #expect(record.alerts.first?.lastTriggeredAt == nil)
}

private struct AlertCrossingQuote: GoldQuoteServicing {
    func fetchQuote() async throws -> GoldQuote {
        .init(symbol: "AU9999", price: 810, open: 800, high: 810, low: 800, prevClose: 800, usdCNY: 0, cnyPerGram: 810, asOf: alertNow.addingTimeInterval(3))
    }
}
@MainActor private final class SuspendedAlertSender: HoldingNotificationSending {
    var pending: Set<String> = []
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func send(id: String, title: String, body: String) async throws {
        await withCheckedContinuation { continuation = $0; started?.resume(); started = nil }
        pending.insert(id)
    }
    func waitUntilSending() async { if continuation == nil { await withCheckedContinuation { started = $0 } } }
    func resume() { continuation?.resume(); continuation = nil }
    func remove(id: String) async { pending.remove(id) }
}
