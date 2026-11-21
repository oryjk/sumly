import SwiftUI
import UIKit

/// 黄金温度计科普与区间说明弹窗（纯客观方法论与可选公众号同步说明）。
struct MacroTemperatureGuideSheet: View {
    let help: MacroTemperatureGuideHelp
    var disclaimer: String = MacroPresentation.defaultDisclaimer
    var currentLevel: MacroTemperatureLevel? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var copiedOfficialAccount = false
    @State private var copyFeedbackCount = 0
    @State private var copyResetTask: Task<Void, Never>?

    private var resolvedDisclaimer: String {
        let trimmed = disclaimer.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? MacroPresentation.defaultDisclaimer : trimmed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    dualHorizonOverviewCard
                    methodologyCard
                    levelsCard

                    if help.hasOfficialAccount {
                        officialAccountCard
                    }

                    disclaimerFooter
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 22)
            }
            .scrollIndicators(.hidden)
            .background(GoldTheme.background)
            .foregroundStyle(GoldTheme.text)
            .navigationTitle(help.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(GoldTheme.gold)
                    .accessibilityIdentifier("macro.guideSheet.doneButton")
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(GoldTheme.gold)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: copyFeedbackCount)
        .onDisappear {
            copyResetTask?.cancel()
            copyResetTask = nil
        }
    }

    // MARK: - 两套指标如何区分

    private var dualHorizonOverviewCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("两套指标如何区分", systemImage: "rectangle.split.2x1")
                .font(.subheadline.bold())
                .foregroundStyle(GoldTheme.gold)

            VStack(alignment: .leading, spacing: 7) {
                horizonGuideRow(
                    dotColor: GoldTheme.tempCool,
                    title: "短期 · 交易热度（0~100°）",
                    detail: "衡量近期交易冷热、趋势偏离与市场拥挤度。"
                )

                horizonGuideRow(
                    dotColor: GoldTheme.gold,
                    title: "长期 · 宏观背景（0~100分）",
                    detail: "衡量美债规模、财政压力、央行购金与实际利率等大环境强弱。"
                )
            }

            Text("两者衡量不同时间尺度，走势可能同向也可能错位。")
                .font(.caption2)
                .foregroundStyle(GoldTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .goldCard(padding: 14)
        .accessibilityIdentifier("macro.guideSheet.dualHorizonOverviewCard")
    }

    private func horizonGuideRow(dotColor: Color, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.text)
            }
            Text(detail)
                .font(.caption2)
                .foregroundStyle(GoldTheme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(GoldTheme.background, in: GoldTheme.subCardShape)
        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    // MARK: - 计算方法论

    private var methodologyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("计算方法论", systemImage: "slider.horizontal.3")
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.gold)
                Spacer(minLength: 4)
                Text("5 维度 · 3 年分位 · 0°~100°")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.goldSoft)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(GoldTheme.gold.opacity(0.12), in: GoldTheme.capsuleShape)
            }

            Text(help.displayMethodology)
                .font(.caption)
                .foregroundStyle(GoldTheme.text)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .goldCard(padding: 14)
    }

    // MARK: - 五档温度区间含义

    private var levelsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("短期温度五档区间", systemImage: "thermometer.medium")
                    .font(.subheadline.bold())
                    .foregroundStyle(GoldTheme.gold)
                Spacer()
                Text("仅反映市场冷热与拥挤度")
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textFaint)
            }

            VStack(spacing: 7) {
                ForEach(help.displayLevels) { item in
                    levelRow(item)
                }
            }
        }
        .goldCard(padding: 14)
    }

    private func levelRow(_ item: MacroTemperatureGuideLevel) -> some View {
        let tint = MacroPresentation.temperatureColor(for: item.level)
        let isCurrent = currentLevel == item.level
        let labelText = item.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? item.level.defaultLabel
            : item.label

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)

                Text(labelText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(GoldTheme.text)

                if !item.range.isEmpty {
                    Text(item.range)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.14), in: GoldTheme.capsuleShape)
                }

                Spacer(minLength: 4)

                if isCurrent {
                    Text("当前区间")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(GoldTheme.onGold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(tint, in: GoldTheme.capsuleShape)
                }
            }

            if !item.description.isEmpty {
                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(GoldTheme.background, in: GoldTheme.subCardShape)
        .overlay(
            GoldTheme.subCardShape.strokeBorder(
                isCurrent ? tint.opacity(0.45) : GoldTheme.cardStroke,
                lineWidth: 1
            )
        )
    }

    // MARK: - 公众号同步说明（仅当配置了公众号名称时展示）

    private var officialAccountCard: some View {
        let accountName = help.trimmedOfficialAccountName
        let accountNote = help.trimmedOfficialAccountNote

        return VStack(alignment: .leading, spacing: 8) {
            Label("宏观数据笔记同步", systemImage: "doc.text.magnifyingglass")
                .font(.subheadline.bold())
                .foregroundStyle(GoldTheme.gold)

            if !accountNote.isEmpty {
                Text(accountNote)
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("微信公众号")
                        .font(.caption2)
                        .foregroundStyle(GoldTheme.textFaint)
                    Text(accountName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GoldTheme.text)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    copyOfficialAccountName(accountName)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedOfficialAccount ? "checkmark" : "doc.on.doc")
                            .font(.caption2.weight(.semibold))
                        Text(copiedOfficialAccount ? "已复制" : "复制公众号名称")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(copiedOfficialAccount ? GoldTheme.down : GoldTheme.onGold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        copiedOfficialAccount ? GoldTheme.down.opacity(0.14) : GoldTheme.gold,
                        in: GoldTheme.capsuleShape
                    )
                    .overlay(
                        GoldTheme.capsuleShape.strokeBorder(
                            copiedOfficialAccount ? GoldTheme.down.opacity(0.35) : Color.clear,
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("macro.guideSheet.copyOfficialAccountButton")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(GoldTheme.background, in: GoldTheme.subCardShape)
            .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
        .goldCard(padding: 14)
        .accessibilityIdentifier("macro.guideSheet.officialAccountCard")
    }

    // MARK: - 底部免责声明

    private var disclaimerFooter: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.caption2)
                .foregroundStyle(GoldTheme.textFaint)
                .padding(.top, 2)
            Text(resolvedDisclaimer)
                .font(.caption2)
                .foregroundStyle(GoldTheme.textFaint)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private func copyOfficialAccountName(_ name: String) {
        UIPasteboard.general.string = name
        copyFeedbackCount += 1
        withAnimation(.easeInOut(duration: 0.18)) {
            copiedOfficialAccount = true
        }
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                copiedOfficialAccount = false
            }
        }
    }
}
