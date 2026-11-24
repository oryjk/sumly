import SwiftUI
import SwiftData
import UserNotifications

struct HoldingAlertSheet: View {
    let record: HoldingRecord
    let basis: GoldMarketBasis
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var alerts: [HoldingAlert] = []
    @State private var values: [String] = []
    @State private var error: String?
    @State private var saving = false
    @State private var saveTask: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.fmt("仅在你主动开启后提醒，使用%@参考金价。", basis.title))
                        .font(.subheadline).foregroundStyle(GoldTheme.textSecondary)
                    ForEach(alerts.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(alerts[i].kind.title, isOn: $alerts[i].enabled).tint(GoldTheme.gold)
                            if alerts[i].kind == .breakEven {
                                Text(L10n.tr("这笔黄金达到预计真实保本线。")).font(.caption).foregroundStyle(GoldTheme.textSecondary)
                            } else if alerts[i].enabled {
                                GoldInputField(title: alerts[i].kind == .returnPercent ? L10n.tr("收益率目标（%）") : alerts[i].kind == .price ? L10n.tr("参考金价（元/克）") : L10n.tr("预计盈利（元）"), text: $values[i])
                            }
                        }.goldCard()
                    }
                    Text(L10n.tr("提醒在 App 打开且处于前台、获得有效新行情时检查。持续后台监控尚未接入；提醒不会承诺锁屏期间实时触发。"))
                        .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                    Text(L10n.tr("首次开启先建立基线；仅从目标下方越过时通知。同一提醒冷却24小时，过时、异常或缺失行情不触发。"))
                        .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(GoldTheme.up)
                        Button(L10n.tr("打开通知设置")) {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                        }.foregroundStyle(GoldTheme.gold)
                    }
                }.padding(16).foregroundStyle(GoldTheme.text)
            }.background(GoldTheme.background)
                .goldKeyboardDismissable(showToolbar: false)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    GoldKeyboardActionBar {
                        Button(saving ? L10n.tr("正在保存…") : L10n.tr("保存提醒")) { saveTask = Task { await save() } }
                            .buttonStyle(GoldPrimaryButtonStyle())
                            .disabled(saving)
                    }
                }
                .navigationTitle(L10n.tr("持仓提醒")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("取消")) { dismiss() } } }
        }.onAppear { load() }.onDisappear { saveTask?.cancel() }.presentationBackground(GoldTheme.background)
    }
    private func load() {
        alerts = HoldingAlertKind.allCases.map { kind in
            record.alerts.first { $0.kind == kind } ?? HoldingAlert(kind: kind,
                threshold: kind == .returnPercent ? 10 : kind == .profitAmount ? 3000 : kind == .price ? 900 : 0,
                enabled: false, basis: basis)
        }
        values = alerts.map { $0.threshold.moneyText }
    }
    private func save() async {
        guard record.disposition == "holding" else { error = L10n.tr("这笔持仓已处置，不能开启提醒。"); return }
        guard let candidate = HoldingAlertForm.merge(edited: alerts, values: values, latest: record.alerts, basis: basis) else {
            error = L10n.tr("请填写有效目标，参考金价应大于0。"); return
        }
        saving = true; defer { saving = false }
        if candidate.contains(where: \.enabled) {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                guard granted else { error = L10n.tr("通知权限未开启。请在系统设置中允许通知后再保存。"); return }
            } catch { self.error = L10n.tr("暂时无法获得通知权限，请重试。"); return }
        }
        guard !Task.isCancelled, record.disposition == "holding" else { return }
        guard let updated = HoldingAlertForm.merge(edited: alerts, values: values, latest: record.alerts, basis: basis) else { return }
        do { try record.setAlerts(updated); try context.save(); dismiss() }
        catch { context.rollback(); self.error = L10n.tr("提醒保存失败，请重试。") }
    }
}
