import SwiftUI

/// 新版暗黑金「补充细节」折叠抽屉，随所选黄金形态深度联动。
struct HoldingDetailsDrawerView: View {
    @Binding var draft: HoldingDraft
    @Binding var isExpanded: Bool
    @Binding var timestamp: Date
    @Binding var selectedBook: String
    @Binding var selectedSubPreset: HoldingAssetSubPreset?

    let isEditing: Bool
    let legacyPresence: HoldingAssetFormLegacyPresence
    let availableBooks: [String]
    let recentBrands: [String]
    let recentChannels: [String]
    let onDateChanged: (Date) -> Void

    private var profile: HoldingAssetFormProfile {
        HoldingAssetFormProfile.profile(
            for: draft.assetType,
            draft: draft,
            legacy: legacyPresence
        )
    }

    private var hasCustomRecovery: Bool {
        let deduction = Double(draft.deductionText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let discount = Double(draft.discountText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let fixed = Double(draft.fixedFeeText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return deduction > 0 || discount > 0 || fixed > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            drawerHeader

            if isExpanded {
                Divider()
                    .overlay(GoldTheme.cardStroke)
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 18) {
                    if !isEditing && !profile.subPresets.isEmpty {
                        subPresetSection
                        sectionDivider
                    }

                    parametersSection
                    sectionDivider
                    metadataSection
                    sectionDivider
                    recoverySection
                    sectionDivider
                    noteSection
                }
                .padding(16)
            }
        }
        .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
        .overlay(
            GoldTheme.holdingsCardShape.strokeBorder(
                isExpanded
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [GoldTheme.gold.opacity(0.24), GoldTheme.cardStroke],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(GoldTheme.cardStroke),
                lineWidth: 1
            )
        )
    }

    // MARK: - Header

    private var drawerHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(L10n.tr("补充细节"))
                            .font(.subheadline.bold())
                            .foregroundStyle(GoldTheme.text)
                        Text(draft.assetType.displayName)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(GoldTheme.goldSoft)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(GoldTheme.background, in: GoldTheme.capsuleShape)
                            .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.28), lineWidth: 1))
                    }
                    Text(profile.drawerSubtitle)
                        .font(.caption2)
                        .foregroundStyle(GoldTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 6)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(GoldTheme.goldSoft)
                    .frame(width: 26, height: 26)
                    .background(GoldTheme.background, in: GoldTheme.circleShape)
                    .overlay(GoldTheme.circleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - ① 场景快捷微调

    private var subPresetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: L10n.tr("场景快捷微调"),
                symbol: "wand.and.stars",
                badge: L10n.fmt("%@专属", draft.assetType.displayName)
            )

            HStack(spacing: 10) {
                ForEach(profile.subPresets) { preset in
                    let isSelected = selectedSubPreset == preset
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selectedSubPreset = preset
                            preset.apply(to: &draft)
                        }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: preset.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isSelected ? GoldTheme.onGold : GoldTheme.goldSoft)
                                .frame(width: 28, height: 28)
                                .background(
                                    isSelected ? GoldTheme.onGold.opacity(0.14) : GoldTheme.gold.opacity(0.12),
                                    in: GoldTheme.badgeShape
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.title)
                                    .font(.caption.bold())
                                    .foregroundStyle(isSelected ? GoldTheme.onGold : GoldTheme.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Text(preset.subtitle)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(isSelected ? GoldTheme.onGold.opacity(0.82) : GoldTheme.textSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            isSelected ? GoldTheme.gold : GoldTheme.background,
                            in: GoldTheme.subCardShape
                        )
                        .overlay(
                            GoldTheme.subCardShape.strokeBorder(
                                isSelected ? GoldTheme.gold : GoldTheme.cardStroke,
                                lineWidth: isSelected ? 1.5 : 1
                            )
                        )
                        .shadow(color: isSelected ? GoldTheme.addButtonShadow.opacity(0.4) : .clear, radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - ② 形态专属参数

    private var parametersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: profile.parameterSectionTitle,
                symbol: "slider.horizontal.3"
            )

            if profile.showsPurity {
                VStack(alignment: .leading, spacing: 8) {
                    GoldFormNumberField(
                        title: L10n.tr("黄金纯度"),
                        unit: "%",
                        placeholder: "99.99",
                        text: $draft.purityText
                    )

                    HStack(spacing: 6) {
                        ForEach(profile.purityPresets, id: \.self) { value in
                            let isChosen = isPurityMatched(value)
                            Button {
                                withAnimation(.easeInOut(duration: 0.14)) {
                                    draft.purityText = value
                                }
                            } label: {
                                Text("\(value)%")
                                    .font(.system(size: 12, weight: isChosen ? .bold : .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(isChosen ? GoldTheme.onGold : GoldTheme.goldSoft)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 30)
                                    .background(
                                        isChosen ? GoldTheme.gold : GoldTheme.calendarCell,
                                        in: GoldTheme.capsuleShape
                                    )
                                    .overlay(
                                        GoldTheme.capsuleShape.strokeBorder(
                                            isChosen ? GoldTheme.gold : GoldTheme.cardStroke,
                                            lineWidth: 1
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if profile.showsLabor {
                HStack(spacing: 10) {
                    Text(profile.laborModeTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(GoldTheme.textSecondary)
                    Spacer(minLength: 6)
                    GoldFormCapsuleToggle(
                        selection: $draft.laborPerGram,
                        trueLabel: profile.laborPerGramOptionLabel,
                        falseLabel: profile.laborTotalOptionLabel
                    )
                }

                HStack(spacing: 10) {
                    GoldFormNumberField(
                        title: draft.laborPerGram ? profile.laborPerGramFieldTitle : profile.laborTotalFieldTitle,
                        unit: draft.laborPerGram ? L10n.tr("元/克") : L10n.tr("元"),
                        placeholder: "0",
                        text: $draft.laborText
                    )
                    GoldFormNumberField(
                        title: profile.otherCostFieldTitle,
                        unit: L10n.tr("元"),
                        placeholder: "0",
                        text: $draft.otherText
                    )
                }
            } else if profile.showsOtherCost {
                GoldFormInlineNumberField(
                    title: profile.otherCostFieldTitle,
                    unit: L10n.tr("元"),
                    placeholder: "0",
                    text: $draft.otherText
                )
            }
        }
    }

    // MARK: - ③ 渠道 / 品牌与日期账本

    private var metadataSection: some View {
        let brandTags = HoldingAssetFormProfile.mergedTags(
            recent: recentBrands,
            suggested: profile.suggestedBrands
        )
        let channelTags = HoldingAssetFormProfile.mergedTags(
            recent: recentChannels,
            suggested: profile.suggestedChannels
        )

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: profile.metadataSectionTitle,
                symbol: "building.columns"
            )

            if profile.showsBrand {
                VStack(alignment: .leading, spacing: 8) {
                    GoldFormTextField(
                        title: profile.brandFieldTitle,
                        placeholder: profile.brandPlaceholder,
                        text: $draft.brand
                    )
                    if !brandTags.isEmpty {
                        GoldFormTagStrip(tags: brandTags, selected: draft.brand) { tag in
                            draft.brand = tag
                        }
                    }
                }
            }

            if profile.showsChannel {
                VStack(alignment: .leading, spacing: 8) {
                    GoldFormTextField(
                        title: profile.channelFieldTitle,
                        placeholder: profile.channelPlaceholder,
                        text: $draft.channel
                    )
                    if !channelTags.isEmpty {
                        GoldFormTagStrip(tags: channelTags, selected: draft.channel) { tag in
                            draft.channel = tag
                        }
                    }
                }
            }

            // 购买日期与归属账本统一收口在深底细描边分组卡片内
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GoldTheme.goldSoft)
                        .frame(width: 16)
                    Text(L10n.tr("购买日期"))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(GoldTheme.text)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 4)
                    DatePicker(
                        L10n.tr("购买日期"),
                        selection: Binding(
                            get: { timestamp },
                            set: { newDate in
                                timestamp = newDate
                                onDateChanged(newDate)
                            }
                        ),
                        in: ...Date.now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .environment(\.locale, AppLanguage.currentLocale)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)

                Divider()
                    .overlay(GoldTheme.cardStroke)
                    .padding(.horizontal, 12)

                HStack(spacing: 6) {
                    Image(systemName: "book.closed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GoldTheme.goldSoft)
                        .frame(width: 16)
                    Text(L10n.tr("归属账本"))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(GoldTheme.text)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer()
                    Menu {
                        ForEach(availableBooks, id: \.self) { name in
                            Button {
                                selectedBook = name
                            } label: {
                                Label(HoldingRecord.localizedBookName(name), systemImage: name == selectedBook ? "checkmark" : "book.closed")
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(HoldingRecord.localizedBookName(selectedBook))
                                .font(.caption.weight(.semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(GoldTheme.goldSoft)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(GoldTheme.card, in: GoldTheme.capsuleShape)
                        .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .background(GoldTheme.background, in: GoldTheme.subCardShape)
            .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
    }

    // MARK: - ④ 回收 / 赎回规则

    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: profile.recoverySectionTitle,
                symbol: "arrow.triangle.2.circlepath",
                badge: hasCustomRecovery ? L10n.tr("已自定义") : L10n.tr("默认 0 费用"),
                badgeHighlighted: hasCustomRecovery
            )

            if profile.showsPerGramDeduction {
                HStack(spacing: 10) {
                    GoldFormNumberField(
                        title: profile.deductionFieldTitle,
                        unit: L10n.tr("元/克"),
                        placeholder: "0",
                        text: $draft.deductionText
                    )
                    GoldFormNumberField(
                        title: profile.discountFieldTitle,
                        unit: "%",
                        placeholder: "0",
                        text: $draft.discountText
                    )
                }

                GoldFormInlineNumberField(
                    title: profile.fixedFeeFieldTitle,
                    unit: L10n.tr("元/次"),
                    placeholder: "0",
                    text: $draft.fixedFeeText
                )
            } else {
                HStack(spacing: 10) {
                    GoldFormNumberField(
                        title: profile.discountFieldTitle,
                        unit: "%",
                        placeholder: "0",
                        text: $draft.discountText
                    )
                    GoldFormNumberField(
                        title: profile.fixedFeeFieldTitle,
                        unit: L10n.tr("元/次"),
                        placeholder: "0",
                        text: $draft.fixedFeeText
                    )
                }
            }

            Text(profile.recoverySectionHint)
                .font(.caption2)
                .foregroundStyle(GoldTheme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - ⑤ 备注

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: L10n.tr("备注"), symbol: "note.text")

            TextField(
                "",
                text: $draft.note,
                prompt: Text(profile.notePlaceholder).foregroundStyle(GoldTheme.textFaint),
                axis: .vertical
            )
            .lineLimit(2...4)
            .font(.subheadline)
            .foregroundStyle(GoldTheme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(GoldTheme.background, in: GoldTheme.subCardShape)
            .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
    }

    // MARK: - Helpers

    private var sectionDivider: some View {
        Divider()
            .overlay(GoldTheme.cardStroke)
    }

    private func sectionHeader(
        title: String,
        symbol: String,
        badge: String? = nil,
        badgeHighlighted: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GoldTheme.goldSoft)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(GoldTheme.textSecondary)
            Spacer(minLength: 4)
            if let badge {
                Text(badge)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(badgeHighlighted ? GoldTheme.goldSoft : GoldTheme.textFaint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        badgeHighlighted ? GoldTheme.gold.opacity(0.14) : GoldTheme.background,
                        in: GoldTheme.capsuleShape
                    )
                    .overlay(
                        GoldTheme.capsuleShape.strokeBorder(
                            badgeHighlighted ? GoldTheme.gold.opacity(0.32) : GoldTheme.cardStroke,
                            lineWidth: 1
                        )
                    )
            }
        }
    }

    private func isPurityMatched(_ preset: String) -> Bool {
        let current = Double(draft.purityText.trimmingCharacters(in: .whitespacesAndNewlines))
        let target = Double(preset)
        if let current, let target {
            return abs(current - target) < 0.0001
        }
        return draft.purityText.trimmingCharacters(in: .whitespacesAndNewlines) == preset
    }
}

// MARK: - 暗黑金统一表单原子组件

/// 顶标签 + 数值输入 + 后缀单位的深底细描边输入框，与 coreInputCard 视觉 100% 统一。
struct GoldFormNumberField: View {
    let title: String
    let unit: String
    var placeholder = "0"
    @Binding var text: String

    private var hasValue: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(GoldTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField(
                    "",
                    text: $text,
                    prompt: Text(placeholder).foregroundStyle(GoldTheme.textFaint)
                )
                .keyboardType(.decimalPad)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(GoldTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(unit)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(GoldTheme.textFaint)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(GoldTheme.background, in: GoldTheme.subCardShape)
        .overlay(
            GoldTheme.subCardShape.strokeBorder(
                hasValue ? GoldTheme.gold.opacity(0.28) : GoldTheme.cardStroke,
                lineWidth: 1
            )
        )
    }
}

/// 单行紧凑数值输入框（用于孤立项，避免拉长表单高度）。
struct GoldFormInlineNumberField: View {
    let title: String
    let unit: String
    var placeholder = "0"
    @Binding var text: String

    private var hasValue: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(GoldTheme.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 6)

            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundStyle(GoldTheme.textFaint)
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(GoldTheme.text)
            .frame(minWidth: 72, maxWidth: 120)

            Text(unit)
                .font(.caption2.weight(.medium))
                .foregroundStyle(GoldTheme.textFaint)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(GoldTheme.background, in: GoldTheme.subCardShape)
        .overlay(
            GoldTheme.subCardShape.strokeBorder(
                hasValue ? GoldTheme.gold.opacity(0.28) : GoldTheme.cardStroke,
                lineWidth: 1
            )
        )
    }
}

/// 顶标签 + 文本输入的深底细描边输入框，支持一键清空。
struct GoldFormTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    private var hasValue: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(GoldTheme.textSecondary)

            HStack(spacing: 6) {
                TextField(
                    "",
                    text: $text,
                    prompt: Text(placeholder).foregroundStyle(GoldTheme.textFaint)
                )
                .font(.subheadline)
                .foregroundStyle(GoldTheme.text)

                if hasValue {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(GoldTheme.textFaint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.fmt("清除%@", title))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(GoldTheme.background, in: GoldTheme.subCardShape)
        .overlay(
            GoldTheme.subCardShape.strokeBorder(
                hasValue ? GoldTheme.gold.opacity(0.28) : GoldTheme.cardStroke,
                lineWidth: 1
            )
        )
    }
}

/// 暗黑金双态胶囊切换控件，替代原生灰条 SegmentedPicker。
struct GoldFormCapsuleToggle: View {
    @Binding var selection: Bool
    let trueLabel: String
    let falseLabel: String

    var body: some View {
        HStack(spacing: 3) {
            optionButton(label: trueLabel, value: true)
            optionButton(label: falseLabel, value: false)
        }
        .padding(3)
        .background(GoldTheme.background, in: GoldTheme.capsuleShape)
        .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
    }

    private func optionButton(label: String, value: Bool) -> some View {
        let isSelected = selection == value
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selection = value
            }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? GoldTheme.onGold : GoldTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    isSelected ? GoldTheme.gold : Color.clear,
                    in: GoldTheme.capsuleShape
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 胶囊快捷标签条（常用品牌、银行平台、渠道）。
struct GoldFormTagStrip: View {
    let tags: [String]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    let isChosen = selected.trimmingCharacters(in: .whitespacesAndNewlines) == tag
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            onSelect(tag)
                        }
                    } label: {
                        Text(tag)
                            .font(.system(size: 11, weight: isChosen ? .bold : .medium, design: .rounded))
                            .foregroundStyle(isChosen ? GoldTheme.onGold : GoldTheme.goldSoft)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                isChosen ? GoldTheme.gold : GoldTheme.calendarCell,
                                in: GoldTheme.capsuleShape
                            )
                            .overlay(
                                GoldTheme.capsuleShape.strokeBorder(
                                    isChosen ? GoldTheme.gold : GoldTheme.cardStroke,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
