import SwiftUI
import SwiftData

struct AccountView: View {
    @Bindable var session: AuthSession
    var cloud: HoldingsCloud? = nil
    var onOpenChanlun: (() -> Void)? = nil
    var onOpenOnboarding: (() -> Void)? = nil

    @AppStorage("holdings.hideAmounts") private var hideAmounts = false
    @State private var showSettings = false
    @State private var showLogin = false
    @State private var reauthentication: AccountDeletionIntent?
    @State private var deletionConfirmation: AccountDeletionIntent?
    @State private var confirmLogout = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var error: String?

    private var cloudBadge: AccountCloudStatusBadge {
        AccountCloudStatusBadge.from(session: session, cloud: cloud)
    }

    var body: some View {
        NavigationStack {
            accountContent
                .goldTabBarContentSafeArea()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: $showSettings) {
                    AccountSettingsView(session: session, cloud: cloud)
                        .goldTabBarContentSafeArea()
                }
        }
        .tint(GoldTheme.gold)
    }

    private var accountContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerBar
                profileHeroSection
                preferencesGroup
                supportGroup
                if session.user != nil {
                    securityGroup
                }
                feedbackSection
                footerSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 26)
        }
        .background(GoldTheme.background)
        .foregroundStyle(GoldTheme.text)
        .sensoryFeedback(.selection, trigger: hideAmounts)
        .sheet(isPresented: $showLogin) {
            AuthenticationSheet(session: session, reauthentication: reauthentication)
        }
        .onChange(of: session.user?.id) { _, _ in
            deletionConfirmation = nil
            confirmDelete = false
        }
        .confirmationDialog("退出当前账户？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { Task { await session.logout() } }
        } message: {
            Text("未同步更改保留在此账户的设备缓存，重新登录可继续同步。退出后显示此设备的游客记录。")
        }
        .confirmationDialog("永久注销此账户？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("永久注销账户", role: .destructive) {
                if let intent = deletionConfirmation {
                    Task { await deleteAccount(confirming: intent) }
                }
            }
        } message: {
            if let intent = deletionConfirmation {
                Text("待注销账户：\(intent.provider.title) · \(intent.maskedIdentifier)\n\n账户身份、云端持仓与账本、服务端登录会话将永久删除，无法恢复。需要最近 5 分钟内重新登录。此账户在本机的缓存也会清除；独立的游客记录保留。")
            }
        }
    }

    // MARK: - 1. 顶部标题栏

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(AccountProfileCopy.pageTitle)
                    .font(.title2.bold())
                    .foregroundStyle(GoldTheme.text)
                Text(AccountProfileCopy.pageSubtitle)
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
            }
            Spacer(minLength: 8)
            Button { showSettings = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GoldTheme.goldSoft)
                        .frame(width: 44, height: 44)
                        .background(GoldTheme.card, in: GoldTheme.circleShape)
                        .overlay(
                            GoldTheme.circleShape.strokeBorder(
                                GoldTheme.gold.opacity(0.32),
                                lineWidth: 1
                            )
                        )
                    if let attention = cloudBadge.settingsAttention {
                        GoldTheme.circleShape
                            .fill(attention.isUrgent ? GoldTheme.up : GoldTheme.gold)
                            .frame(width: 9, height: 9)
                            .overlay(
                                GoldTheme.circleShape.strokeBorder(GoldTheme.background, lineWidth: 1.5)
                            )
                            .offset(x: -2, y: 2)
                    }
                }
                .contentShape(GoldTheme.circleShape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
            .accessibilityIdentifier("account.settings")
        }
    }

    // MARK: - 2. 暗黑金「个人攒金名片」Hero 卡片

    @ViewBuilder
    private var profileHeroSection: some View {
        if let cloud {
            AccountHoldingsProfileBridge { summary in
                heroCard(summary: summary)
            }
            .modelContainer(cloud.container)
        } else {
            heroCard(summary: .empty)
        }
    }

    private func heroCard(summary: AccountGoldProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let user = session.user {
                signedInHeroHeader(user: user)
                signedInCloudStrip
                if let guestHint = cloudBadge.guestImportHint {
                    guestImportCallout(text: guestHint)
                }
            } else {
                guestHeroHeader
            }

            GoldTheme.cardStroke.frame(height: 1)

            goldProfileArchiveStrip(summary: summary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                LinearGradient(
                    colors: [GoldTheme.card, GoldTheme.card, GoldTheme.background.opacity(0.94)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [GoldTheme.gold.opacity(0.11), .clear],
                    center: .topLeading,
                    startRadius: 8,
                    endRadius: 200
                )
            }
            .clipShape(GoldTheme.cardShape)
        )
        .overlay(
            GoldTheme.cardShape.strokeBorder(
                LinearGradient(
                    colors: [GoldTheme.gold.opacity(0.38), GoldTheme.goldSoft.opacity(0.14), GoldTheme.cardStroke],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        )
    }

    private func signedInHeroHeader(user: NativeUser) -> some View {
        let displayName = user.nickname.isEmpty ? "记金用户" : user.nickname
        return HStack(spacing: 14) {
            ZStack {
                GoldTheme.circleShape
                    .fill(
                        LinearGradient(
                            colors: [GoldTheme.goldSoft, GoldTheme.gold, GoldTheme.tempWarm],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                GoldTheme.circleShape
                    .strokeBorder(GoldTheme.goldSoft.opacity(0.65), lineWidth: 1)
                    .padding(2)
                if let monogram = AccountAvatarPresentation.monogram(for: user.nickname) {
                    Text(monogram)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(GoldTheme.onGold)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(GoldTheme.onGold)
                }
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(displayName)
                        .font(.title3.bold())
                        .foregroundStyle(GoldTheme.text)
                        .lineLimit(1)
                    Text(user.provider.loginPillTitle)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(GoldTheme.goldSoft)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(GoldTheme.gold.opacity(0.16), in: GoldTheme.capsuleShape)
                        .overlay(
                            GoldTheme.capsuleShape.strokeBorder(
                                GoldTheme.gold.opacity(0.34),
                                lineWidth: 0.8
                            )
                        )
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(user.maskedIdentifier)
                    .font(.footnote.monospaced())
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var signedInCloudStrip: some View {
        let badge = cloudBadge
        return HStack(spacing: 10) {
            AccountCloudToneIndicator(tone: badge.tone)

            VStack(alignment: .leading, spacing: 2) {
                Text(badge.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(badge.tone == .conflict ? GoldTheme.up : GoldTheme.text)
                    .lineLimit(1)
                Text(badge.detail)
                    .font(.caption2)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 6)

            if badge.conflictCount > 0 {
                Button {
                    showSettings = true
                } label: {
                    Text("去处理")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(GoldTheme.up)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(GoldTheme.up.opacity(0.14), in: GoldTheme.capsuleShape)
                        .overlay(
                            GoldTheme.capsuleShape.strokeBorder(GoldTheme.up.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            } else if let cloud {
                Button {
                    Task { await cloud.sync() }
                } label: {
                    HStack(spacing: 4) {
                        if badge.isSyncing {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(GoldTheme.gold)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10.5, weight: .bold))
                        }
                        Text(badge.isSyncing ? "同步中" : "同步")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(GoldTheme.goldSoft)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(GoldTheme.card, in: GoldTheme.capsuleShape)
                    .overlay(
                        GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.32), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(badge.isSyncing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(GoldTheme.background, in: GoldTheme.subCardShape)
        .overlay(
            GoldTheme.subCardShape.strokeBorder(
                badge.tone == .conflict ? GoldTheme.up.opacity(0.35) : GoldTheme.cardStroke,
                lineWidth: 1
            )
        )
    }

    private func guestImportCallout(text: String) -> some View {
        Button {
            showSettings = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GoldTheme.gold)
                Text(text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.goldSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Text("去导入")
                    .font(.caption2.bold())
                    .foregroundStyle(GoldTheme.gold)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(GoldTheme.gold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(GoldTheme.gold.opacity(0.12), in: GoldTheme.subCardShape)
            .overlay(
                GoldTheme.subCardShape.strokeBorder(GoldTheme.gold.opacity(0.36), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var guestHeroHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    GoldTheme.circleShape
                        .fill(GoldTheme.gold.opacity(0.14))
                    GoldTheme.circleShape
                        .strokeBorder(GoldTheme.gold.opacity(0.42), lineWidth: 1)
                    GoldMoneyBagShape()
                        .fill(
                            LinearGradient(
                                colors: [GoldTheme.goldSoft, GoldTheme.gold],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 22, height: 24)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text(AccountProfileCopy.guestHeadline)
                        .font(.headline.bold())
                        .foregroundStyle(GoldTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        AccountCloudToneIndicator(tone: .guest)
                        Text(AccountProfileCopy.guestModeLabel)
                            .font(.caption)
                            .foregroundStyle(GoldTheme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                ForEach(AccountProfileCopy.guestValueTags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        GoldTheme.circleShape
                            .fill(GoldTheme.gold)
                            .frame(width: 4, height: 4)
                        Text(tag)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(GoldTheme.goldSoft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(GoldTheme.background, in: GoldTheme.capsuleShape)
                    .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
                }
            }

            Button(AccountProfileCopy.loginActionTitle) { openLogin() }
                .buttonStyle(GoldPrimaryButtonStyle())
                .accessibilityIdentifier("account.login")
        }
    }

    private func goldProfileArchiveStrip(summary: AccountGoldProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(GoldTheme.gold)
                Text(AccountProfileCopy.profileSectionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GoldTheme.textSecondary)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    if summary.hasUnlockedMilestone {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(GoldTheme.gold)
                    }
                    Text(summary.milestoneTitle)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(summary.hasUnlockedMilestone ? GoldTheme.goldSoft : GoldTheme.textSecondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    summary.hasUnlockedMilestone ? GoldTheme.gold.opacity(0.16) : GoldTheme.calendarCell,
                    in: GoldTheme.capsuleShape
                )
                .overlay(
                    GoldTheme.capsuleShape.strokeBorder(
                        summary.hasUnlockedMilestone ? GoldTheme.gold.opacity(0.45) : GoldTheme.cardStroke,
                        lineWidth: 0.9
                    )
                )
            }

            HStack(spacing: 0) {
                profileMetricCell(
                    label: AccountProfileCopy.activeGramsLabel,
                    value: summary.formattedActiveGrams(hideAmounts: hideAmounts),
                    valueColor: GoldTheme.gold
                )
                GoldTheme.cardStroke
                    .frame(width: 1, height: 28)
                profileMetricCell(
                    label: AccountProfileCopy.activeCountLabel,
                    value: summary.formattedActiveCount(hideAmounts: hideAmounts),
                    valueColor: GoldTheme.text
                )
                GoldTheme.cardStroke
                    .frame(width: 1, height: 28)
                profileMetricCell(
                    label: AccountProfileCopy.companionDaysLabel,
                    value: summary.formattedCompanionDays(),
                    valueColor: GoldTheme.goldSoft
                )
            }
            .padding(.vertical, 11)
            .background(GoldTheme.background, in: GoldTheme.subCardShape)
            .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
    }

    private func profileMetricCell(label: String, value: String, valueColor: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.subheadline, design: .rounded).bold())
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption2)
                .foregroundStyle(GoldTheme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 3. 「偏好与工具」分组卡片

    private var preferencesGroup: some View {
        let showChanlun = ChanlunWebConfiguration.current != nil && onOpenChanlun != nil
        let showOnboarding = onOpenOnboarding != nil
        return VStack(alignment: .leading, spacing: 8) {
            AccountSectionHeader(title: AccountProfileCopy.preferencesSectionTitle)

            VStack(spacing: 0) {
                // 隐私遮罩开关
                HStack(spacing: 12) {
                    AccountRowIconBadge(systemName: hideAmounts ? "eye.slash.fill" : "eye.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AccountProfileCopy.privacyMaskTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GoldTheme.text)
                        Text(AccountProfileCopy.privacyMaskSubtitle)
                            .font(.caption)
                            .foregroundStyle(GoldTheme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: $hideAmounts)
                        .labelsHidden()
                        .tint(GoldTheme.gold)
                        .accessibilityLabel(AccountProfileCopy.privacyMaskTitle)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)

                if showChanlun, let onOpenChanlun {
                    rowDivider
                    Button(action: onOpenChanlun) {
                        actionRowContent(
                            icon: "chart.line.uptrend.xyaxis",
                            title: AccountProfileCopy.chanlunTitle,
                            subtitle: AccountProfileCopy.chanlunSubtitle
                        )
                    }
                    .buttonStyle(.plain)
                }

                if showOnboarding, let onOpenOnboarding {
                    rowDivider
                    Button(action: onOpenOnboarding) {
                        actionRowContent(
                            icon: "sparkles",
                            title: AccountProfileCopy.onboardingTitle,
                            subtitle: AccountProfileCopy.onboardingSubtitle
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("account.onboarding")
                }

                rowDivider

                Button { showSettings = true } label: {
                    HStack(spacing: 12) {
                        AccountRowIconBadge(systemName: "icloud")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AccountProfileCopy.cloudSettingsTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(GoldTheme.text)
                            Text(AccountProfileCopy.cloudSettingsSubtitle)
                                .font(.caption)
                                .foregroundStyle(GoldTheme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        Spacer(minLength: 8)
                        if let attention = cloudBadge.settingsAttention {
                            Text(attention.text)
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(attention.isUrgent ? GoldTheme.up : GoldTheme.goldSoft)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    attention.isUrgent ? GoldTheme.up.opacity(0.14) : GoldTheme.gold.opacity(0.14),
                                    in: GoldTheme.capsuleShape
                                )
                                .overlay(
                                    GoldTheme.capsuleShape.strokeBorder(
                                        attention.isUrgent ? GoldTheme.up.opacity(0.38) : GoldTheme.gold.opacity(0.34),
                                        lineWidth: 0.8
                                    )
                                )
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GoldTheme.textFaint)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
            .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
    }

    // MARK: - 4. 「支持与合规」分组卡片

    private var supportGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccountSectionHeader(title: AccountProfileCopy.supportSectionTitle)

            VStack(spacing: 0) {
                Link(destination: URL(string: "https://oryjk.cn/sumly/privacy")!) {
                    actionRowContent(
                        icon: "hand.raised.fill",
                        title: AccountProfileCopy.privacyPolicyTitle,
                        subtitle: AccountProfileCopy.privacyPolicySubtitle,
                        trailingSymbol: "arrow.up.right"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("account.privacyPolicy")

                rowDivider

                Link(destination: URL(string: "mailto:oryjk@qq.com")!) {
                    actionRowContent(
                        icon: "envelope.fill",
                        title: AccountProfileCopy.supportTitle,
                        subtitle: AccountProfileCopy.supportSubtitle,
                        trailingSymbol: "arrow.up.right"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("account.support")

                rowDivider

                Link(destination: URL(string: "https://beian.miit.gov.cn/")!) {
                    actionRowContent(
                        icon: "checkmark.shield.fill",
                        title: AccountProfileCopy.icpTitle,
                        subtitle: AccountProfileCopy.icpNumber,
                        trailingSymbol: "arrow.up.right"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开工信部备案查询系统")
            }
            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
            .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
    }

    // MARK: - 5. 账号安全操作卡（仅登录态）

    private var securityGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccountSectionHeader(title: AccountProfileCopy.securitySectionTitle)

            VStack(spacing: 0) {
                Button { confirmLogout = true } label: {
                    HStack(spacing: 12) {
                        AccountRowIconBadge(systemName: "rectangle.portrait.and.arrow.right", style: .neutral)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AccountProfileCopy.logoutTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(GoldTheme.text)
                            Text(AccountProfileCopy.logoutSubtitle)
                                .font(.caption)
                                .foregroundStyle(GoldTheme.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GoldTheme.textFaint)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                rowDivider

                Button(role: .destructive) {
                    deletionConfirmation = session.beginAccountDeletion()
                    confirmDelete = deletionConfirmation != nil
                } label: {
                    HStack(spacing: 12) {
                        AccountRowIconBadge(systemName: "trash.fill", style: .destructive)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AccountProfileCopy.deleteAccountTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(GoldTheme.up)
                            Text(AccountProfileCopy.deleteAccountSubtitle)
                                .font(.caption)
                                .foregroundStyle(GoldTheme.textSecondary)
                        }
                        Spacer(minLength: 8)
                        if deleting {
                            ProgressView()
                                .tint(GoldTheme.up)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(GoldTheme.up.opacity(0.75))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
            .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
            .disabled(deleting)
        }
    }

    // MARK: - 6. 通知/错误与柔和尾标

    @ViewBuilder
    private var feedbackSection: some View {
        if let notice = session.notice {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.goldSoft)
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GoldTheme.card, in: GoldTheme.subCardShape)
            .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
        if let error {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.up)
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.up)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GoldTheme.up.opacity(0.1), in: GoldTheme.subCardShape)
            .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.up.opacity(0.32), lineWidth: 1))
            .accessibilityLabel("错误：" + error)
        }
    }

    private var footerSection: some View {
        VStack(spacing: 5) {
            Text(AccountProfileCopy.disclaimer)
                .font(.caption2)
                .foregroundStyle(GoldTheme.textFaint)
                .multilineTextAlignment(.center)
            Text(AccountAppVersionFormatter.format())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(GoldTheme.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    // MARK: - 辅助组件与逻辑

    private var rowDivider: some View {
        GoldTheme.cardStroke
            .frame(height: 1)
            .padding(.leading, 60)
    }

    private func actionRowContent(
        icon: String,
        title: String,
        subtitle: String,
        trailingSymbol: String = "chevron.right"
    ) -> some View {
        HStack(spacing: 12) {
            AccountRowIconBadge(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GoldTheme.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: trailingSymbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(GoldTheme.textFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func openLogin() {
        session.cancelAccountDeletion()
        deletionConfirmation = nil
        reauthentication = nil
        showLogin = true
    }

    private func deleteAccount(confirming intent: AccountDeletionIntent) async {
        deleting = true
        error = nil
        defer { deleting = false }
        do {
            try await session.deleteAccount(confirming: intent)
            do { try cloud?.eraseDeletedAccountCache() }
            catch { session.notice = "账户与云端数据已删除，清除设备缓存失败：" + error.localizedDescription }
        } catch AuthError.reauthenticate {
            error = AuthError.reauthenticate.localizedDescription
            reauthentication = intent
            showLogin = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 轻量 SwiftData 持仓桥接（仅在存在 ModelContainer 时挂载）

private struct AccountHoldingsProfileBridge<Content: View>: View {
    @Query private var records: [HoldingRecord]
    let content: (AccountGoldProfileSummary) -> Content

    var body: some View {
        content(AccountGoldProfileSummary(records: records))
    }
}

// MARK: - 账户与设置页共享暗黑金组件

struct AccountSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(GoldTheme.textSecondary)
            .padding(.leading, 4)
    }
}

struct AccountRowIconBadge: View {
    enum Style {
        case gold
        case neutral
        case destructive
    }

    let systemName: String
    var style: Style = .gold

    private var iconColor: Color {
        switch style {
        case .gold: GoldTheme.gold
        case .neutral: GoldTheme.textSecondary
        case .destructive: GoldTheme.up
        }
    }

    private var fillColor: Color {
        switch style {
        case .gold: GoldTheme.gold.opacity(0.12)
        case .neutral: GoldTheme.background
        case .destructive: GoldTheme.up.opacity(0.12)
        }
    }

    private var strokeColor: Color {
        switch style {
        case .gold: GoldTheme.gold.opacity(0.24)
        case .neutral: GoldTheme.cardStroke
        case .destructive: GoldTheme.up.opacity(0.28)
        }
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(iconColor)
            .frame(width: 34, height: 34)
            .background(fillColor, in: GoldTheme.badgeShape)
            .overlay(GoldTheme.badgeShape.strokeBorder(strokeColor, lineWidth: 0.8))
    }
}

struct AccountCloudToneIndicator: View {
    let tone: AccountCloudStatusBadge.Tone

    var body: some View {
        switch tone {
        case .syncing:
            ProgressView()
                .controlSize(.mini)
                .tint(GoldTheme.gold)
                .frame(width: 12, height: 12)
        case .synced:
            GoldTheme.circleShape
                .fill(GoldTheme.down)
                .frame(width: 8, height: 8)
                .overlay(
                    GoldTheme.circleShape.strokeBorder(GoldTheme.down.opacity(0.35), lineWidth: 2)
                        .frame(width: 12, height: 12)
                )
        case .conflict:
            GoldTheme.circleShape
                .fill(GoldTheme.up)
                .frame(width: 8, height: 8)
                .overlay(
                    GoldTheme.circleShape.strokeBorder(GoldTheme.up.opacity(0.35), lineWidth: 2)
                        .frame(width: 12, height: 12)
                )
        case .pending:
            GoldTheme.circleShape
                .fill(GoldTheme.goldSoft)
                .frame(width: 8, height: 8)
        case .guest:
            GoldTheme.circleShape
                .fill(GoldTheme.textFaint)
                .frame(width: 7, height: 7)
        }
    }
}
