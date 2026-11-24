import SwiftUI

/// 暗黑金风格的应用内语言选择页：列出「跟随系统」与 6 种支持语言，点击即刻热切生效。
struct LanguageSelectionView: View {
    @Bindable var languageStore: AppLanguageStore

    init(languageStore: AppLanguageStore = .shared) {
        self.languageStore = languageStore
    }

    var body: some View {
        let _ = languageStore.revision
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    AccountSectionHeader(title: L10n.tr("应用语言"))

                    VStack(spacing: 0) {
                        ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element.id) { index, language in
                            languageRow(language)

                            if index < AppLanguage.allCases.count - 1 {
                                GoldTheme.cardStroke
                                    .frame(height: 1)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
                    .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
                }

                Text(L10n.tr("选择界面显示语言，切换后立即生效，无需重启应用。"))
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textFaint)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(GoldTheme.background)
        .foregroundStyle(GoldTheme.text)
        .navigationTitle(L10n.tr("语言"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: languageStore.selected)
    }

    private func languageRow(_ language: AppLanguage) -> some View {
        let isSelected = languageStore.selected == language
        return Button {
            languageStore.select(language)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.nativeDisplayName)
                        .font(.subheadline.weight(isSelected ? .bold : .semibold))
                        .foregroundStyle(isSelected ? GoldTheme.goldSoft : GoldTheme.text)
                    Text(language.localizedSubtitle)
                        .font(.caption)
                        .foregroundStyle(GoldTheme.textSecondary)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GoldTheme.gold)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(GoldTheme.textFaint.opacity(0.6))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(language.nativeDisplayName), \(language.localizedSubtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings.language.\(language.rawValue)")
    }
}
