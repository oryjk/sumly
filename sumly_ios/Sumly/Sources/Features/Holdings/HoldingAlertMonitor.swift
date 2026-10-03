import Foundation
import Observation
import SwiftUI
import SwiftData
import UserNotifications

@MainActor protocol HoldingNotificationSending {
    func send(id: String, title: String, body: String) async throws
    func remove(id: String) async
}

/// 通知 OS 边界；真实授权只在用户保存开启提醒时请求。
@MainActor final class SystemHoldingNotifications: NSObject, HoldingNotificationSending, UNUserNotificationCenterDelegate {
    static let shared = SystemHoldingNotifications()
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    func send(id: String, title: String, body: String) async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            throw NotificationFailure.permissionDenied
        }
        try Task.checkCancellation()
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        try await center.add(UNNotificationRequest(identifier: id, content: content,
                                                  trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
        if Task.isCancelled { await remove(id: id); throw CancellationError() }
    }
    func remove(id: String) async { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
    private enum NotificationFailure: Error { case permissionDenied }
}

@MainActor @Observable final class HoldingAlertMonitor {
    private let notifications: any HoldingNotificationSending
    private let serviceFactory: (GoldMarketBasis) -> any GoldQuoteServicing
    private(set) var issue: String?

    init(notifications: any HoldingNotificationSending = SystemHoldingNotifications.shared,
         serviceFactory: @escaping (GoldMarketBasis) -> any GoldQuoteServicing = { BackendGoldPriceService(instrumentID: $0.instrumentID) }) {
        self.notifications = notifications; self.serviceFactory = serviceFactory
    }

    func check(records: [HoldingRecord], context: ModelContext, now: Date = .now) async {
        issue = nil
        for basis in GoldMarketBasis.allCases {
            let relevant = records.filter { $0.disposition == "holding" && $0.alerts.contains { $0.enabled && $0.basis == basis } }
            guard !relevant.isEmpty, !Task.isCancelled else { continue }
            let quote: GoldQuote
            do { quote = try await serviceFactory(basis).fetchQuote() }
            catch { continue }
            guard !Task.isCancelled else { return }
            for record in relevant where record.disposition == "holding" {
                guard record.modelContext === context else { continue }
                let originals = record.alerts
                let originalInput = record.returnInput
                var updated = originals
                for i in updated.indices where updated[i].basis == basis {
                    let triggered = HoldingAlertEngine.evaluate(&updated[i], input: record.returnInput,
                                                                price: quote.cnyPerGram, asOf: quote.asOf, now: now)
                    if triggered {
                        guard !Task.isCancelled, record.modelContext === context, record.disposition == "holding", record.alerts == originals, record.returnInput == originalInput else { return }
                        let id = "holding-\(record.id)-\(updated[i].id)"
                        do {
                            try await notifications.send(id: id, title: "记金 · 持仓提醒",
                                                         body: message(record: record, alert: updated[i]))
                            guard !Task.isCancelled, record.modelContext === context, record.disposition == "holding", record.alerts == originals, record.returnInput == originalInput else {
                                await notifications.remove(id: id)
                                return
                            }
                        } catch {
                            // 不消耗穿越基线或冷却，下一个有效报价可重试。
                            await notifications.remove(id: id)
                            guard !Task.isCancelled else { return }
                            updated[i] = originals[i]
                            issue = "持仓提醒暂未送达，请检查通知权限。"
                        }
                    }
                }
                guard !Task.isCancelled, record.modelContext === context, record.disposition == "holding", record.alerts == originals, record.returnInput == originalInput else { continue }
                if updated != originals {
                    do { try record.setAlerts(updated); try context.save() }
                    catch { context.rollback(); issue = "未能保存提醒状态，请重试。" }
                }
            }
        }
    }
    private func message(record: HoldingRecord, alert: HoldingAlert) -> String {
        let name = record.displayName
        switch alert.kind {
        case .breakEven: return "你的\(name)已达到预计真实保本线。结果为估算。"
        case .returnPercent: return "你的\(name)预计真实收益率已达到\(alert.threshold.moneyText)%。"
        case .profitAmount: return "你的\(name)现在回收预计盈利已达到 ¥\(alert.threshold.moneyText)。"
        case .price: return "\(alert.basis.title)参考金价已达到 ¥\(alert.threshold.moneyText) / g。"
        }
    }
}

/// 驻留在根视图，切换 Tab 时仍检查用户主动开启的提醒；进入后台自动取消。
struct HoldingAlertsLifecycle: ViewModifier {
    @Query private var records: [HoldingRecord]
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @State private var monitor = HoldingAlertMonitor()
    @State private var knownNotificationIDs: Set<String> = []
    private var notificationIDs: Set<String> {
        Set(records.filter { $0.disposition == "holding" }.flatMap { record in
            record.alerts.filter(\.enabled).map { "holding-\(record.id)-\($0.id)" }
        })
    }
    private var configuration: String {
        records.filter { $0.disposition == "holding" }.flatMap { record in
            record.alerts.filter(\.enabled).map { "\(record.id)-\($0.id)-\($0.basis.rawValue)-\($0.threshold)-\(record.grams)-\(record.totalPurchaseCost)-\(record.purity)-\(record.recoveryDeduction)-\(record.recoveryDiscount)-\(record.recoveryFixedFee)" }
        }.sorted().joined(separator: ",")
    }
    func body(content: Content) -> some View {
        content
            .task(id: "\(phase)-\(configuration)") {
                let current = notificationIDs
                let removed = Array(knownNotificationIDs.subtracting(current))
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: removed)
                knownNotificationIDs = current
                guard phase == .active, !current.isEmpty, !HoldingsDesignPreview.isEnabled else { return }
                while !Task.isCancelled {
                    await monitor.check(records: records, context: context)
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                }
            }
    }
}
