import SwiftUI
import SwiftData

struct HoldingsHistorySheet: View {
    let records: [HoldingRecord]
    let hideAmounts: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if records.isEmpty { ContentUnavailableView(L10n.tr("暂无赠卖记录"), systemImage: "gift", description: Text(L10n.tr("在持仓卡片上左滑，可记录赠送或卖出。"))) }
                    ForEach(records.sorted { ($0.disposedAt ?? .distantPast) > ($1.disposedAt ?? .distantPast) }) { record in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text(record.brand.isEmpty ? L10n.tr("未知") : record.brand); Spacer(); Text(record.disposition == "sold" ? L10n.tr("卖出") : L10n.tr("赠送")).foregroundStyle(GoldTheme.gold) }
                            HStack {
                                Text(hideAmounts ? "••••" : (record.disposition == "sold" ? L10n.fmt("%@克 · 实收 %@元", record.grams.moneyText, record.disposalAmount.moneyText) : L10n.fmt("%@克", record.grams.moneyText)))
                                Spacer()
                                if let date = record.disposedAt { Text(HoldingsSelection.dateText(date)) }
                            }.font(.caption).foregroundStyle(GoldTheme.textSecondary)
                        }.padding(16).background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
                    }
                }.padding(16)
            }.background(GoldTheme.background).navigationTitle(L10n.tr("赠卖记录")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("完成")) { dismiss() } } }
        }.presentationBackground(GoldTheme.background)
    }
}

struct DisposeHoldingSheet: View {
    let record: HoldingRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var kind = "sold"
    @State private var grams = ""
    @State private var amount = ""
    @State private var counterparty = ""
    @State private var date = Date.now
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.tr("操作"), selection: $kind) { Text(L10n.tr("卖出")).tag("sold"); Text(L10n.tr("赠送")).tag("gift") }.pickerStyle(.segmented)
                    LabeledContent(L10n.tr("当前持仓"), value: L10n.fmt("%@ 克", record.grams.moneyText))
                    TextField(L10n.tr("本次克数"), text: $grams).keyboardType(.decimalPad)
                    if kind == "sold" { TextField(L10n.tr("实际收到的总金额（元）"), text: $amount).keyboardType(.decimalPad) }
                    TextField(kind == "gift" ? L10n.tr("受赠人（可选）") : L10n.tr("买家（可选）"), text: $counterparty)
                    DatePicker(L10n.tr("日期"), selection: $date, in: record.timestamp...Date.now, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, AppLanguage.currentLocale)
                } footer: { Text(L10n.tr("可以操作部分克数，剩余黄金继续保留在本账本。")) }
                if let error { Text(error).foregroundStyle(GoldTheme.up) }
            }.goldKeyboardDismissable(showToolbar: false)
                .navigationTitle(L10n.tr("赠卖黄金")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("取消")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("保存")) { save() } }
                }
        }.onAppear { grams = String(record.grams) }
    }
    private func save() {
        guard let quantity = Double(grams), quantity.isFinite, quantity > 0, quantity <= record.grams else { error = L10n.tr("请输入有效克数，且不能超过当前持仓。"); return }
        let proceeds = kind == "gift" ? 0 : Double(amount)
        guard let proceeds, proceeds.isFinite, proceeds >= 0 else { error = L10n.tr("请输入有效的实收金额。"); return }
        do {
            try HoldingDisposal.apply(record: record, grams: quantity, proceeds: proceeds, kind: kind, date: date, context: context, counterparty: counterparty.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch { context.rollback(); self.error = L10n.tr("未能保存，请检查填写内容后重试。") }
    }
}

