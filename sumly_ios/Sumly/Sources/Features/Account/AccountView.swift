import SwiftUI
import SwiftData

struct AccountView: View {
    @Bindable var session: AuthSession
    var cloud: HoldingsCloud? = nil
    var membership: MembershipStore? = nil
    var remoteConfig: RemoteAppConfigStore? = nil
    var onOpenMembership: (() -> Void)? = nil
    var onOpenChanlun: (() -> Void)? = nil
    var onOpenOnboarding: (() -> Void)? = nil

    @AppStorage("holdings.hideAmounts") private var hideAmounts = false
    @AppStorage(GoldMarketBasis.storageKey) private var marketBasisRaw = GoldMarketBasis.initialDefault().rawValue
    private let languageStore = AppLanguageStore.shared
    @State private var showSettings = false
    @State private var showFeedback = false
    @State private var showLogin = false
    @State private var showLocalPaywall = false
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
        let _ = languageStore.revision
        NavigationStack {
            accountContent
                .goldTabBarContentSafeArea()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: $showSettings) {
                    AccountSettingsView(session: session, cloud: cloud, languageStore: languageStore)
                        .goldTabBarContentSafeArea()
                }
                .navigationDestination(isPresented: $showFeedback) {
                    FeedbackCenterView(
                        session: session,
                        marketBasis: GoldMarketBasis(rawValue: marketBasisRaw) ?? GoldMarketBasis.initialDefault()
                    )
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
        .sheet(isPresented: $showLocalPaywall) {
            if let membership {
                MembershipPaywallSheet(
                    membership: membership,
                    onOpenChanlun: onOpenChanlun.map { action in
                        {
                            showLocalPaywall = false
                            action()
                        }
                    }
                )
            }
        }
        .onChange(of: session.user?.id) { _, _ in
            deletionConfirmation = nil
            confirmDelete = false
        }
        .confirmationDialog(L10n.tr("退出当前账户？"), isPresented: $confirmLogout, titleVisibility: .visible) {
            Button(L10n.tr("退出登录"), role: .destructive) { Task { await session.logout() } }
        } message: {
            Text(L10n.tr("未同步更改保留在此账户的设备缓存，重新登录可继续同步。退出后显示此设备的游客记录。"))
        }
        .confirmationDialog(L10n.tr("永久注销此账户？"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L10n.tr("永久注销账户"), role: .destructive) {
                if let intent = deletionConfirmation {
                    Task { await deleteAccount(confirming: intent) }
                }
            }
        } message: {
            if let intent = deletionConfirmation {
                Text(L10n.fmt("待注销账户：%@ · %@\n\n账户身份、云端持仓与账本、服务端登录会话将永久删除，无法恢复。需要最近 5 分钟内重新登录。此账户在本机的缓存也会清除；独立的游客记录保留。", intent.provider.title, intent.maskedIdentifier))
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
            .accessibilityLabel(L10n.tr("设置"))
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
        let badge = cloudBadge
        return AccountHeroCardSurface {
            if let user = session.user {
                AccountSignedInHeroHeader(
                    user: user,
                    badge: badge,
                    isCloudActionAvailable: badge.iconAction == .openConflictResolution || cloud != nil,
                    onTapCloudIcon: { handleCloudIconTap(badge: badge) }
                )
                if let guestHint = badge.guestImportHint {
                    AccountGuestImportCallout(text: guestHint) {
                        showSettings = true
                    }
                }
            } else {
                guestHeroHeader
            }

            GoldTheme.cardStroke.frame(height: 1)

            AccountGoldProfileArchiveStrip(summary: summary, hideAmounts: hideAmounts)
        }
    }

    private func handleCloudIconTap(badge: AccountCloudStatusBadge) {
        switch badge.iconAction {
        case .sync:
            guard let cloud else { return }
            Task { await cloud.sync() }
        case .openConflictResolution:
            showSettings = true
        case .none:
            break
        }
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

    // MARK: - 3. 「偏好与工具」分组卡片

    private var preferencesGroup: some View {
        let isMemberActive = membership?.isActive ?? false
        let chanlunRequiresMembership = remoteConfig?.chanlunRequiresMembership ?? true
        let membershipEntryVisible = remoteConfig?.membershipEntryVisible ?? true
        let freeAccessNotice = remoteConfig?.freeAccessNotice ?? ""
        let hasMembershipFeature = membership != nil || onOpenMembership != nil
        let showMembership = hasMembershipFeature && MembershipGate.shouldShowMembershipEntry(
            entryVisible: membershipEntryVisible,
            isMemberActive: isMemberActive
        )
        let showChanlun = ChanlunWebConfiguration.current != nil && onOpenChanlun != nil
        let showOnboarding = onOpenOnboarding != nil
        return VStack(alignment: .leading, spacing: 8) {
            AccountSectionHeader(title: AccountProfileCopy.preferencesSectionTitle)

            VStack(spacing: 0) {
                if showMembership {
                    Button {
                        if let onOpenMembership {
                            onOpenMembership()
                        } else if membership != nil {
                            showLocalPaywall = true
                        }
                    } label: {
                        membershipRowContent(isMemberActive: isMemberActive)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("account.membership")

                    rowDivider
                }

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
                        chanlunRowContent(
                            requiresMembership: chanlunRequiresMembership,
                            isMemberActive: isMemberActive,
                            freeAccessNotice: freeAccessNotice
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("account.chanlun")
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
            .clipShape(GoldTheme.holdingsCardShape)
            .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
    }

    // MARK: - 4. 「支持与合规」分组卡片

    private var supportGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccountSectionHeader(title: AccountProfileCopy.supportSectionTitle)

            VStack(spacing: 0) {
                Button { showFeedback = true } label: {
                    actionRowContent(
                        icon: "bubble.left.and.text.bubble.right.fill",
                        title: FeedbackCopy.entryTitle,
                        subtitle: FeedbackCopy.entrySubtitle
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("account.feedback")

                rowDivider

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
                .accessibilityHint(L10n.tr("打开工信部备案查询系统"))
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
            .accessibilityLabel(L10n.fmt("错误：%@", error))
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

    private func membershipRowContent(isMemberActive: Bool) -> some View {
        let subtitle = membership?.entitlement.statusSummary() ?? AccountProfileCopy.membershipSubtitle
        let priceBadge = membership?.entryPriceBadgeText ?? L10n.fmt("%@/年起", MembershipPlan.yearly.fallbackDisplayPrice)
        return HStack(spacing: 12) {
            AccountRowIconBadge(systemName: "crown.fill", style: .gold)
            VStack(alignment: .leading, spacing: 2) {
                Text(AccountProfileCopy.membershipTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GoldTheme.goldSoft)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 8)
            if isMemberActive {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(MembershipCopy.activeBadgeTitle)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                }
                .foregroundStyle(GoldTheme.down)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(GoldTheme.down.opacity(0.14), in: GoldTheme.capsuleShape)
                .overlay(
                    GoldTheme.capsuleShape.strokeBorder(GoldTheme.down.opacity(0.38), lineWidth: 0.8)
                )
                .fixedSize(horizontal: true, vertical: false)
            } else {
                Text(priceBadge)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(GoldTheme.goldSoft)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(GoldTheme.gold.opacity(0.16), in: GoldTheme.capsuleShape)
                    .overlay(
                        GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.42), lineWidth: 0.8)
                    )
                    .fixedSize(horizontal: true, vertical: false)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GoldTheme.textFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            LinearGradient(
                colors: [GoldTheme.gold.opacity(0.08), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .contentShape(Rectangle())
    }

    private func chanlunRowContent(
        requiresMembership: Bool,
        isMemberActive: Bool,
        freeAccessNotice: String
    ) -> some View {
        let showsLockBadge = MembershipGate.shouldShowChanlunLockBadge(
            requiresMembership: requiresMembership,
            isMemberActive: isMemberActive
        )
        let noticeBadge = freeAccessNotice.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(spacing: 12) {
            AccountRowIconBadge(systemName: "chart.line.uptrend.xyaxis")
            VStack(alignment: .leading, spacing: 2) {
                Text(AccountProfileCopy.chanlunTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GoldTheme.text)
                Text(AccountProfileCopy.chanlunSubtitle)
                    .font(.caption)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if showsLockBadge {
                HStack(spacing: 3) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(GoldTheme.gold)
                    Text(AccountProfileCopy.chanlunMemberBadge)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(GoldTheme.goldSoft)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(GoldTheme.gold.opacity(0.12), in: GoldTheme.capsuleShape)
                .overlay(
                    GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.32), lineWidth: 0.8)
                )
                .fixedSize(horizontal: true, vertical: false)
            } else if !requiresMembership && !noticeBadge.isEmpty {
                Text(noticeBadge)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(GoldTheme.goldSoft)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(GoldTheme.gold.opacity(0.12), in: GoldTheme.capsuleShape)
                    .overlay(
                        GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.32), lineWidth: 0.8)
                    )
                    .frame(maxWidth: 120, alignment: .trailing)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GoldTheme.textFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
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
            catch { session.notice = L10n.fmt("账户与云端数据已删除，清除设备缓存失败：%@", error.localizedDescription) }
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

struct AccountHeroCardSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
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
}

struct AccountSignedInHeroHeader: View {
    let user: NativeUser
    let badge: AccountCloudStatusBadge
    var isCloudActionAvailable: Bool = true
    let onTapCloudIcon: () -> Void

    var body: some View {
        let displayName = user.nickname.isEmpty ? L10n.tr("记金用户") : user.nickname
        HStack(alignment: .center, spacing: 14) {
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

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    Text(displayName)
                        .font(.title3.bold())
                        .foregroundStyle(GoldTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
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
                    Spacer(minLength: 4)
                    AccountCloudSyncIconButton(
                        badge: badge,
                        isActionAvailable: isCloudActionAvailable,
                        onTap: onTapCloudIcon
                    )
                    .padding(.vertical, -5)
                    .padding(.trailing, -5)
                }

                Text(user.maskedIdentifier)
                    .font(.footnote.monospaced())
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

struct AccountCloudSyncIconButton: View {
    let badge: AccountCloudStatusBadge
    var isActionAvailable: Bool = true
    let onTap: () -> Void

    @State private var hapticTrigger = 0

    private var isEnabled: Bool {
        badge.isIconInteractive && isActionAvailable
    }

    private var iconColor: Color {
        switch badge.tone {
        case .synced: GoldTheme.down
        case .syncing: GoldTheme.gold
        case .pending: GoldTheme.goldSoft
        case .failed: GoldTheme.gold
        case .conflict: GoldTheme.up
        case .guest: GoldTheme.textSecondary
        }
    }

    private var fillColor: Color {
        switch badge.tone {
        case .synced: GoldTheme.down.opacity(0.11)
        case .syncing: GoldTheme.gold.opacity(0.11)
        case .pending: GoldTheme.gold.opacity(0.12)
        case .failed: GoldTheme.tempWarm.opacity(0.14)
        case .conflict: GoldTheme.up.opacity(0.15)
        case .guest: GoldTheme.calendarCell
        }
    }

    private var strokeColor: Color {
        switch badge.tone {
        case .synced: GoldTheme.down.opacity(0.32)
        case .syncing: GoldTheme.gold.opacity(0.22)
        case .pending: GoldTheme.gold.opacity(0.36)
        case .failed: GoldTheme.tempWarm.opacity(0.45)
        case .conflict: GoldTheme.up.opacity(0.48)
        case .guest: GoldTheme.cardStroke
        }
    }

    var body: some View {
        Button {
            hapticTrigger += 1
            onTap()
        } label: {
            ZStack {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        GoldTheme.circleShape
                            .fill(fillColor)
                            .shadow(
                                color: badge.tone == .conflict ? GoldTheme.up.opacity(0.28) : .clear,
                                radius: 5,
                                x: 0,
                                y: 0
                            )

                        GoldTheme.circleShape
                            .strokeBorder(strokeColor, lineWidth: badge.tone == .conflict ? 1.0 : 0.9)

                        if badge.showsSyncSpinner {
                            AccountCloudSyncSpinnerArc()
                        }

                        Image(systemName: badge.iconSystemName)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(iconColor)
                            .symbolRenderingMode(.monochrome)
                    }
                    .frame(width: 34, height: 34)

                    if let conflictText = badge.conflictBadgeText {
                        Text(conflictText)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(GoldTheme.text)
                            .padding(.horizontal, conflictText.count > 1 ? 4 : 0)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(GoldTheme.up, in: GoldTheme.capsuleShape)
                            .overlay(
                                GoldTheme.capsuleShape.strokeBorder(GoldTheme.card, lineWidth: 1.5)
                            )
                            .offset(x: 4, y: -3)
                    } else if badge.showsFailedIndicatorDot {
                        GoldTheme.circleShape
                            .fill(GoldTheme.up)
                            .frame(width: 8.5, height: 8.5)
                            .overlay(
                                GoldTheme.circleShape.strokeBorder(GoldTheme.card, lineWidth: 1.5)
                            )
                            .offset(x: 1, y: -1)
                    }
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(GoldTheme.circleShape)
        }
        .buttonStyle(AccountCloudIconButtonStyle())
        .disabled(!isEnabled)
        .fixedSize()
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
        .accessibilityIdentifier("account.cloudSyncIcon")
        .accessibilityLabel(badge.accessibilityLabel)
        .accessibilityHint(badge.detail)
    }
}

private struct AccountCloudSyncSpinnerArc: View {
    @State private var isSpinning = false

    var body: some View {
        GoldTheme.circleShape
            .inset(by: 0.9)
            .trim(from: 0, to: 0.34)
            .stroke(
                AngularGradient(
                    stops: [
                        .init(color: GoldTheme.gold.opacity(0.08), location: 0.0),
                        .init(color: GoldTheme.gold, location: 0.24),
                        .init(color: GoldTheme.goldSoft, location: 0.34)
                    ],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
            )
            .rotationEffect(.degrees(-75))
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 1.05).repeatForever(autoreverses: false)) {
                    isSpinning = true
                }
            }
    }
}

private struct AccountCloudIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct AccountGuestImportCallout: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
                Text(L10n.tr("去导入"))
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
}

struct AccountGoldProfileArchiveStrip: View {
    let summary: AccountGoldProfileSummary
    let hideAmounts: Bool

    var body: some View {
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
                metricCell(
                    label: AccountProfileCopy.activeGramsLabel,
                    value: summary.formattedActiveGrams(hideAmounts: hideAmounts),
                    valueColor: GoldTheme.gold
                )
                GoldTheme.cardStroke
                    .frame(width: 1, height: 28)
                metricCell(
                    label: AccountProfileCopy.activeCountLabel,
                    value: summary.formattedActiveCount(hideAmounts: hideAmounts),
                    valueColor: GoldTheme.text
                )
                GoldTheme.cardStroke
                    .frame(width: 1, height: 28)
                metricCell(
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

    private func metricCell(label: String, value: String, valueColor: Color) -> some View {
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
}

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
        case .failed:
            GoldTheme.circleShape
                .fill(GoldTheme.tempWarm)
                .frame(width: 8, height: 8)
                .overlay(
                    GoldTheme.circleShape.strokeBorder(GoldTheme.up.opacity(0.45), lineWidth: 2)
                        .frame(width: 12, height: 12)
                )
        case .guest:
            GoldTheme.circleShape
                .fill(GoldTheme.textFaint)
                .frame(width: 7, height: 7)
        }
    }
}
