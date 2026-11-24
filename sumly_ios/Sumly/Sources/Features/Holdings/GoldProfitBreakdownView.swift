import SwiftUI

struct GoldProfitBreakdownCard: View {
    let breakdown: GoldProfitBreakdown?
    var records: [HoldingRecord] = []
    var hidden = false
    var actual = false
    var showTotal = true
    var unconfiguredRecovery = false
    @State private var selected: GoldProfitBreakdown.Kind?

    private func color(_ amount: Double) -> Color {
        hidden ? GoldTheme.text : (amount > 0 ? GoldTheme.up : amount < 0 ? GoldTheme.down : GoldTheme.textSecondary)
    }
    private var narrative: String {
        guard let breakdown else { return L10n.tr("获取参考金价后，显示各项来源与盈亏。") }
        if hidden { return L10n.tr("金额已隐藏，显示金额后可查看盈亏明细。") }
        if actual { return L10n.tr("根据已记录的实际到手与总投入计算。") }
        let largest = breakdown.components.max { $0.cents.magnitude < $1.cents.magnitude }
        guard let largest, largest.cents != 0 else { return L10n.tr("当前估算刚好保本。") }
        let cents = Decimal(largest.cents)
        let formatted = GoldReturnPresentation.centsMoney(cents < 0 ? -cents : cents, signed: false)
        return largest.cents > 0
            ? L10n.fmt("影响最大的是%@，带来收益 %@。", largest.kind.title, formatted)
            : L10n.fmt("影响最大的是%@，使收益减少了 %@。", largest.kind.title, formatted)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(L10n.tr("盈亏来源"), systemImage: "list.bullet.rectangle").font(.headline)
                Spacer()
                Text(actual ? L10n.tr("实际卖出") : L10n.tr("预计卖出")).font(.caption).foregroundStyle(GoldTheme.textSecondary)
            }
            if showTotal {
                Text(GoldReturnPresentation.centsMoney(breakdown.map { Decimal($0.profitCents) }, hidden: hidden))
                    .font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit()
                    .foregroundStyle(color(breakdown?.profit ?? 0)).lineLimit(1).minimumScaleFactor(0.6)
            }
            Text(narrative).font(.subheadline).foregroundStyle(GoldTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
            if breakdown?.hasUnconfiguredRecovery == true || (breakdown == nil && unconfiguredRecovery) {
                Label(L10n.tr("尚未计入回收费用"), systemImage: "info.circle")
                    .font(.subheadline.weight(.medium)).foregroundStyle(GoldTheme.gold)
            }
            if let breakdown {
                if hidden || actual {
                    sourceList(breakdown.components)
                } else {
                    Text(L10n.tr("每项金额代表它对收益的影响，点选可查看逐笔明细"))
                        .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(breakdown.groups) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                groupHeading(group)
                                sourceList(group.components)
                            }
                        }
                    }
                }
                Text(L10n.tr("各项影响相加，即为上方盈亏。"))
                    .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                HStack(alignment: .top, spacing: 16) {
                    referenceMetric(L10n.tr("总投入"), amount: breakdown.totalCost)
                    referenceMetric(actual ? L10n.tr("实际到手") : L10n.tr("预计到手"), amount: breakdown.proceeds)
                }
                Text(actual ? L10n.tr("实际到手 − 总投入 = 实际盈亏") : L10n.tr("预计到手 − 总投入 = 预计盈亏"))
                    .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                if breakdown.hasUnconfiguredRecovery {
                    Text(L10n.tr("部分持仓尚未设置回收费用，这些记录未计入扣费；其余按已设规则估算。实际到手可能更低。"))
                        .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                }
                if breakdown.hasUnitemizedCost && !actual {
                    Text(L10n.tr("仅录总价的持仓合并展示差额，无法判断其中的金价、工费等具体影响。"))
                        .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                }
                if !actual {
                    Text(L10n.tr("当前为估算，成交以实际渠道报价为准。"))
                        .font(.caption2).foregroundStyle(GoldTheme.textSecondary)
                }
            }
        }.foregroundStyle(GoldTheme.text).frame(maxWidth: .infinity, alignment: .leading).goldCard()
    }

    private func referenceMetric(_ title: String, amount: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(GoldTheme.textSecondary)
            Text(GoldReturnPresentation.money(amount, hidden: hidden)).font(.system(.subheadline, design: .rounded))
                .monospacedDigit().foregroundStyle(GoldTheme.text).lineLimit(1).minimumScaleFactor(0.5)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func groupHeading(_ group: GoldProfitBreakdown.Group) -> some View {
        let tone = group.direction == .increase ? GoldTheme.up : group.direction == .decrease ? GoldTheme.down : GoldTheme.textSecondary
        let icon = group.direction == .increase ? "arrow.up.right" : group.direction == .decrease ? "arrow.down.right" : "equal"
        let amount = GoldReturnPresentation.centsMoney(group.totalCents)
        return ViewThatFits(in: .horizontal) {
            HStack {
                Label(group.direction.title, systemImage: icon)
                Spacer(minLength: 12)
                Text(amount).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 6) {
                Label(group.direction.title, systemImage: icon)
                Text(amount).monospacedDigit()
            }
        }.font(.subheadline.weight(.semibold)).foregroundStyle(tone)
            .padding(.bottom, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.fmt("%@合计，%@", group.direction.title, amount))
    }

    private func sourceList(_ components: [GoldProfitBreakdown.Component]) -> some View {
        VStack(spacing: 0) {
            ForEach(components) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Button { selected = selected == item.kind ? nil : item.kind } label: {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(item.kind.title).foregroundStyle(GoldTheme.text).fixedSize()
                                Spacer(minLength: 8)
                                sourceAmount(item)
                                disclosureIcon(item)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.kind.title).foregroundStyle(GoldTheme.text)
                                HStack {
                                    sourceAmount(item)
                                    Spacer()
                                    disclosureIcon(item)
                                }
                            }.padding(.vertical, 10)
                        }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 52).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(L10n.fmt("%@，%@", item.kind.title, GoldReturnPresentation.centsMoney(Decimal(item.cents), hidden: hidden)))
                        .accessibilityHint(L10n.tr("展开或收起逐笔明细与来源说明"))
                    if selected == item.kind {
                        GoldProfitSourceDetails(component: item, records: records, hidden: hidden)
                            .padding(.bottom, 12)
                    }
                }
                Divider().overlay(GoldTheme.cardStroke)
            }
        }
    }

    private func sourceAmount(_ item: GoldProfitBreakdown.Component) -> some View {
        Text(GoldReturnPresentation.centsMoney(Decimal(item.cents), hidden: hidden))
            .monospacedDigit().fontWeight(.medium).foregroundStyle(color(item.amount)).fixedSize()
    }

    private func disclosureIcon(_ item: GoldProfitBreakdown.Component) -> some View {
        Image(systemName: selected == item.kind ? "chevron.up" : "chevron.down")
            .font(.caption2).foregroundStyle(GoldTheme.textSecondary)
    }

}

/// Read-only child rows deliberately have no chevron or button styling.
struct GoldProfitSourceDetails: View {
    let component: GoldProfitBreakdown.Component
    let records: [HoldingRecord]
    var hidden = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(component.kind.explanation).font(.caption).foregroundStyle(GoldTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !component.contributions.isEmpty && !records.isEmpty {
                Text(L10n.tr("逐笔明细 · 对本项的影响")).font(.caption.weight(.semibold)).foregroundStyle(GoldTheme.gold)
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(component.contributions) { contribution in
                        if records.indices.contains(contribution.recordIndex) {
                            recordRow(records[contribution.recordIndex], contribution: contribution)
                            if contribution.id != component.contributions.last?.id {
                                Divider().overlay(GoldTheme.cardStroke)
                            }
                        }
                    }
                }
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(GoldTheme.calendarCell, in: GoldTheme.holdingsCardShape)
    }

    private func recordRow(_ record: HoldingRecord, contribution: GoldProfitBreakdown.Contribution) -> some View {
        let amount = GoldReturnPresentation.centsMoney(Decimal(contribution.cents), hidden: hidden)
        let tone = hidden ? GoldTheme.text : contribution.cents > 0 ? GoldTheme.up : contribution.cents < 0 ? GoldTheme.down : GoldTheme.textSecondary
        return VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(record.displayName).fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    Text(amount).monospacedDigit().foregroundStyle(tone).fixedSize()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(record.displayName).fixedSize(horizontal: false, vertical: true)
                    Text(amount).monospacedDigit().foregroundStyle(tone)
                }
            }.font(.subheadline.weight(.medium))
            Text(L10n.fmt("第%lld笔 · %@ 购入 · %@ g", Int64(contribution.recordIndex + 1), HoldingsSelection.dateText(record.timestamp), hidden ? "••••" : record.grams.moneyText))
                .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if record.purchaseTotalOverride != nil && component.kind == .unitemized {
                Text(L10n.tr("按录入总价计算")).font(.caption2).foregroundStyle(GoldTheme.textSecondary)
            }
        }.foregroundStyle(GoldTheme.text).accessibilityElement(children: .combine)
    }
}

struct GoldProfitBreakdownSheet: View {
    let records: [HoldingRecord]
    let quote: GoldQuote?
    let basis: GoldMarketBasis
    var hidden = false
    var quoteFailed = false
    @Environment(\.dismiss) private var dismiss
    @State private var calculation = false
    private var holdingRecords: [HoldingRecord] { records.filter { $0.disposition == "holding" } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.tr("看清收益从哪里来，又被哪些因素拉低。"))
                        .font(.subheadline).foregroundStyle(GoldTheme.textSecondary)
                    GoldProfitBreakdownCard(breakdown: GoldProfitBreakdown.estimate(holdingRecords.map(\.returnInput), referencePrice: quote?.cnyPerGram), records: holdingRecords, hidden: hidden, unconfiguredRecovery: holdingRecords.contains { $0.returnInput.rule.isDefault })
                    Text(GoldReturnPresentation.quoteStatus(quote, basis: basis, failed: quoteFailed))
                        .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                    Button(L10n.tr("查看计算参数与公式"), systemImage: "info.circle") { calculation = true }
                        .font(.subheadline).foregroundStyle(GoldTheme.gold).frame(minHeight: 44)
                }.padding(16)
            }.background(GoldTheme.background)
                .navigationTitle(L10n.tr("盈亏来源")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("完成")) { dismiss() } } }
        }.presentationBackground(GoldTheme.background).presentationDragIndicator(.visible)
            .sheet(isPresented: $calculation) { GoldCalculationSheet(records: records, quote: quote, basis: basis, hideAmounts: hidden, quoteFailed: quoteFailed) }
    }
}
