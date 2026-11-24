import SwiftUI

/// 宏观走势图「线性 / 对数」坐标刻度切换条（严格使用 GoldTheme 令牌，与首页胶囊风格一致）。
struct MacroChartScaleBar: View {
    let context: MacroChartScaleContext
    var leadingLabel: String? = nil
    var accessibilityPrefix: String = "macro.chart"
    let onSelect: (MacroChartScale) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                statusLabel
                Spacer(minLength: 4)
                segmentedPill
            }
            VStack(alignment: .leading, spacing: 6) {
                statusLabel
                segmentedPill
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let reason = context.disabledReason {
            HStack(spacing: 4) {
                if let leadingLabel, !leadingLabel.isEmpty {
                    Text(leadingLabel)
                        .foregroundStyle(GoldTheme.textSecondary)
                    Text("·")
                        .foregroundStyle(GoldTheme.textFaint)
                }
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textFaint)
                Text(reason.message)
                    .foregroundStyle(GoldTheme.textFaint)
            }
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityLabel(reason.message)
        } else if context.effectiveScale == .logarithmic {
            HStack(spacing: 4) {
                if let leadingLabel, !leadingLabel.isEmpty {
                    Text(leadingLabel)
                        .foregroundStyle(GoldTheme.goldSoft)
                    Text("·")
                        .foregroundStyle(GoldTheme.textFaint)
                }
                Text(L10n.tr("对数刻度 · 等比观察趋势"))
                    .foregroundStyle(GoldTheme.goldSoft)
            }
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        } else if let leadingLabel, !leadingLabel.isEmpty {
            Text(leadingLabel)
                .font(.caption2)
                .foregroundStyle(GoldTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            Text(L10n.tr("纵轴刻度"))
                .font(.caption2)
                .foregroundStyle(GoldTheme.textSecondary)
                .lineLimit(1)
        }
    }

    private var segmentedPill: some View {
        HStack(spacing: 2) {
            ForEach(MacroChartScale.allCases) { scale in
                let isSelected = context.effectiveScale == scale
                let isDisabled = scale == .logarithmic && !context.supportsLogScale
                Button {
                    onSelect(scale)
                } label: {
                    Text(scale.localizedTitle)
                        .font(.system(size: 11.5, weight: isSelected ? .bold : .semibold, design: .rounded))
                        .padding(.horizontal, 10)
                        .frame(minWidth: 42, minHeight: 26)
                        .foregroundStyle(
                            isSelected
                                ? GoldTheme.onGold
                                : (isDisabled ? GoldTheme.textFaint : GoldTheme.textSecondary)
                        )
                        .background(
                            isSelected ? GoldTheme.gold : Color.clear,
                            in: GoldTheme.capsuleShape
                        )
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .opacity(isDisabled ? 0.65 : 1)
                .accessibilityLabel(L10n.fmt("%@纵轴刻度", scale.localizedTitle))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(isDisabled ? (context.disabledReason?.message ?? "") : "")
                .accessibilityIdentifier("\(accessibilityPrefix).scale.\(scale == .linear ? "linear" : "log")")
            }
        }
        .padding(2)
        .background(GoldTheme.background, in: GoldTheme.capsuleShape)
        .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        .fixedSize()
    }
}
