import SwiftUI
import Charts

/// 持仓洞察区：攒金目标进度 + 持仓结构分布（Swift Charts 环形图）。
struct HoldingsInsightsSection: View {
    let records: [HoldingRecord]
    let currentGrams: Double
    let referencePrice: Double?
    let hideAmounts: Bool

    @AppStorage("holdings.savingGoalGrams") private var goalGrams: Double = 0
    @AppStorage("holdings.insightsExpanded") private var expanded: Bool = true
    @State private var grouping: HoldingsInsights.Grouping = .assetType
    @State private var showingGoalEditor = false
    @State private var goalInputText = ""

    private var entries: [HoldingsInsights.Entry] {
        records.map(\.insightEntry)
    }

    private var slices: [HoldingAllocationSlice] {
        HoldingsInsights.allocations(from: entries, grouping: grouping)
    }

    private var goalProgress: GoldSavingGoalProgress? {
        GoldSavingGoalProgress.make(targetGrams: goalGrams, currentGrams: currentGrams, referencePrice: referencePrice)
    }

    private static let palette: [Color] = [
        GoldTheme.gold,
        GoldTheme.goldSoft,
        GoldTheme.up,
        GoldTheme.down,
        GoldTheme.textSecondary
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            goalCard
            if !slices.isEmpty {
                allocationCard
            }
        }
        .alert(L10n.tr("设定攒金目标"), isPresented: $showingGoalEditor) {
            TextField(L10n.tr("目标克数（例如 100）"), text: $goalInputText)
                .keyboardType(.decimalPad)
            Button(L10n.tr("取消"), role: .cancel) {}
            if goalGrams > 0 {
                Button(L10n.tr("清除目标"), role: .destructive) { goalGrams = 0 }
            }
            Button(L10n.tr("保存")) {
                if let parsed = Double(goalInputText.trimmingCharacters(in: .whitespacesAndNewlines)),
                   parsed.isFinite, parsed > 0, parsed <= 1_000_000 {
                    goalGrams = parsed
                }
            }
        } message: {
            Text(L10n.tr("设定你想积累的黄金目标克重，随时查看达成进度。"))
        }
        .sensoryFeedback(.selection, trigger: grouping)
    }

    private var goalCard: some View {
        Button {
            goalInputText = goalGrams > 0 ? goalGrams.formatted(.number.grouping(.never).precision(.fractionLength(0...2))) : "100"
            showingGoalEditor = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(L10n.tr("攒金目标"), systemImage: "flag.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(GoldTheme.gold)
                    Spacer()
                    if let progress = goalProgress {
                        Text(hideAmounts ? "••••" : "\(Int((progress.rawProgress * 100).rounded()))%")
                            .font(.system(.subheadline, design: .rounded).bold())
                            .monospacedDigit()
                            .foregroundStyle(progress.isAchieved ? GoldTheme.down : GoldTheme.goldSoft)
                    } else {
                        Text(L10n.tr("去设定"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GoldTheme.goldSoft)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(GoldTheme.textSecondary)
                }

                if let progress = goalProgress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            GoldTheme.capsuleShape
                                .fill(GoldTheme.background)
                            GoldTheme.capsuleShape
                                .fill(progress.isAchieved ? GoldTheme.down : GoldTheme.gold)
                                .frame(width: max(6, geo.size.width * progress.clampedProgress))
                        }
                    }
                    .frame(height: 7)
                    .animation(.easeOut(duration: 0.25), value: progress.clampedProgress)

                    HStack {
                        Text(hideAmounts
                             ? L10n.tr("已攒 •••• g / 目标 •••• g")
                             : L10n.fmt("已攒 %@ g / 目标 %@ g", progress.currentGrams.moneyText, progress.targetGrams.moneyText))
                        Spacer()
                        if progress.isAchieved {
                            Text(L10n.tr("已达成目标"))
                                .foregroundStyle(GoldTheme.down)
                        } else if let budget = progress.estimatedRemainingCost {
                            Text(hideAmounts ? L10n.tr("还差 •••• g") : L10n.fmt("还差 %@ g ≈ ¥%@", progress.remainingGrams.moneyText, budget.moneyText))
                        } else {
                            Text(hideAmounts ? L10n.tr("还差 •••• g") : L10n.fmt("还差 %@ g", progress.remainingGrams.moneyText))
                        }
                    }
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.textSecondary)
                } else {
                    Text(L10n.tr("定个克重目标（如 50g / 100g），追踪攒金进度"))
                        .font(.caption)
                        .foregroundStyle(GoldTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, goalProgress == nil ? 12 : 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
            .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var allocationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Label(L10n.tr("持仓结构"), systemImage: "chart.pie.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(GoldTheme.text)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(GoldTheme.textSecondary)
                    }
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if expanded {
                    HStack(spacing: 4) {
                        ForEach(HoldingsInsights.Grouping.allCases) { mode in
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) { grouping = mode }
                            } label: {
                                Text(mode.localizedTitle)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(grouping == mode ? GoldTheme.onGold : GoldTheme.textSecondary)
                                    .padding(.horizontal, 9)
                                    .frame(height: 26)
                                    .background(grouping == mode ? GoldTheme.gold : GoldTheme.background, in: GoldTheme.capsuleShape)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if expanded {
                HStack(alignment: .center, spacing: 16) {
                    Chart(Array(slices.enumerated()), id: \.element.id) { index, slice in
                        SectorMark(
                            angle: .value(L10n.tr("克重"), slice.grams),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .cornerRadius(4)
                        .foregroundStyle(color(at: index))
                    }
                    .frame(width: 96, height: 96)
                    .overlay {
                        VStack(spacing: 2) {
                            Text(L10n.fmt("%lld类", Int64(slices.count)))
                                .font(.caption2.bold())
                                .foregroundStyle(GoldTheme.text)
                            Text(hideAmounts ? "••g" : "\(currentGrams.formatted(.number.precision(.fractionLength(0...1))))g")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(GoldTheme.goldSoft)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(slices.prefix(4).enumerated()), id: \.element.id) { index, slice in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(color(at: index))
                                    .frame(width: 8, height: 8)
                                Text(slice.label)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(GoldTheme.text)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(hideAmounts ? "••%" : "\(Int((slice.gramShare * 100).rounded()))%")
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(GoldTheme.goldSoft)
                                Text(hideAmounts ? "••g" : "\(slice.grams.formatted(.number.precision(.fractionLength(0...2))))g")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(GoldTheme.textSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    private func color(at index: Int) -> Color {
        Self.palette[index % Self.palette.count]
    }
}
