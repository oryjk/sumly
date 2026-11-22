import SwiftUI

/// 嵌入在持仓页顶部的「3 步开启记金」轻量任务引导卡：
/// 严格遵循暗黑金视觉令牌，紧凑克制不霸屏，完成全部 3 步或主动收起后优雅隐藏。
struct OnboardingQuickStartCard: View {
    let state: QuickStartChecklistState
    let onSelectAction: (QuickStartAction) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            progressTrack
            stepsList
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(
            GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.gold.opacity(0.24), lineWidth: 1)
        )
        // 避免 List 行默认整行点击吞掉单个按钮事件。
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.quickStart.card")
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(GoldTheme.gold)

            Text("3 步开启记金")
                .font(.subheadline.bold())
                .foregroundStyle(GoldTheme.text)

            Text(state.progressBadgeText)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(GoldTheme.goldSoft)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(GoldTheme.gold.opacity(0.15), in: GoldTheme.capsuleShape)
                .overlay(
                    GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.30), lineWidth: 0.8)
                )
                .accessibilityLabel("已完成 \(state.completedCount) 项，共 \(state.totalCount) 项")

            Spacer(minLength: 4)

            Button {
                onDismiss()
            } label: {
                Text("收起")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(GoldTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 44, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起新手引导任务卡")
            .accessibilityIdentifier("onboarding.quickStart.dismiss")
        }
    }

    private var progressTrack: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                GoldTheme.capsuleShape
                    .fill(GoldTheme.calendarCell)

                GoldTheme.capsuleShape
                    .fill(
                        LinearGradient(
                            colors: [GoldTheme.gold, GoldTheme.goldSoft],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(state.completedCount > 0 ? 10 : 0, geo.size.width * state.progressFraction))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: state.progressFraction)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private var stepsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                stepRow(item)

                if index < state.items.count - 1 {
                    GoldTheme.cardStroke
                        .frame(height: 1)
                        .padding(.leading, 34)
                }
            }
        }
    }

    private func stepRow(_ item: QuickStartTaskItem) -> some View {
        Button {
            onSelectAction(item.action)
        } label: {
            HStack(spacing: 10) {
                if item.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GoldTheme.gold)
                        .frame(width: 24, height: 24)
                } else {
                    ZStack {
                        GoldTheme.circleShape
                            .strokeBorder(GoldTheme.gold.opacity(0.65), lineWidth: 1.4)
                            .frame(width: 20, height: 20)
                        Text("\(item.stepNumber)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.goldSoft)
                    }
                    .frame(width: 24, height: 24)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.footnote.weight(item.isCompleted ? .medium : .semibold))
                        .foregroundStyle(item.isCompleted ? GoldTheme.textSecondary : GoldTheme.text)
                        .lineLimit(1)

                    if !item.isCompleted {
                        Text(item.subtitle)
                            .font(.caption2)
                            .foregroundStyle(GoldTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                if item.isCompleted {
                    Text("已完成")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(GoldTheme.gold.opacity(0.82))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(GoldTheme.goldSoft)
                }
            }
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title)，\(item.isCompleted ? "已完成" : "待完成")")
        .accessibilityHint(item.isCompleted ? "点击可再次前往" : item.subtitle)
        .accessibilityIdentifier("onboarding.quickStart.step.\(item.action.rawValue)")
    }
}
