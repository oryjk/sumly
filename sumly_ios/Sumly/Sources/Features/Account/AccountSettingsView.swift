import SwiftUI

struct AccountSettingsView: View {
    @Bindable var session: AuthSession
    var cloud: HoldingsCloud? = nil
    @AppStorage("market.basis") private var marketBasisRaw = GoldMarketBasis.domestic.rawValue
    @State private var confirmImport = false
    @State private var confirmConflict = false
    @State private var clearingCache = false
    @State private var cacheNotice: String?
    @State private var allowedEmailLink: AppleEmailLinkScope?
    @State private var selectedEmailLink: AppleEmailLinkScope?

    private var marketBasis: GoldMarketBasis {
        GoldMarketBasis(rawValue: marketBasisRaw) ?? .domestic
    }

    private var cloudBadge: AccountCloudStatusBadge {
        AccountCloudStatusBadge.from(session: session, cloud: cloud)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                cloudSyncSection
                if let scope = session.appleEmailLinkScope, allowedEmailLink == scope {
                    crossDeviceLoginSection(scope: scope)
                }
                storageCacheSection
                feedbackSection
                aboutAndComplianceSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(GoldTheme.background)
        .foregroundStyle(GoldTheme.text)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: session.appleEmailLinkScope) { await loadEmailLink() }
        .sheet(item: $selectedEmailLink, onDismiss: { Task { await loadEmailLink() } }) { scope in
            AppleEmailLinkSheet(session: session, scope: scope)
        }
        .confirmationDialog("将游客记录导入当前账户？", isPresented: $confirmImport, titleVisibility: .visible) {
            Button("导入并同步") { Task { await cloud?.importGuestRecords() } }
        } message: {
            Text("导入到 \(session.user?.maskedIdentifier ?? "")。记录使用原有 ID，重复导入跳过相同记录。游客原记录会保留。")
        }
        .confirmationDialog("处理多设备修改冲突", isPresented: $confirmConflict, titleVisibility: .visible) {
            Button("冲突记录保留本机版本") { Task { await cloud?.sync(choice: .local) } }
            Button("冲突记录使用云端版本", role: .destructive) { Task { await cloud?.sync(choice: .remote) } }
        } message: {
            Text("同一购入记录及其部分处置记录作为整体选择，其他记录自动合并。选择某一版本将放弃这些冲突记录在另一端的更改（包括删除）。")
        }
    }

    // MARK: - 1. 账户持仓云同步

    private var cloudSyncSection: some View {
        let badge = cloudBadge
        let signedIn = session.user != nil
        return VStack(alignment: .leading, spacing: 8) {
            AccountSectionHeader(title: signedIn ? "账户持仓云同步" : "游客持仓")

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    AccountRowIconBadge(systemName: signedIn ? "icloud.fill" : "iphone")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(signedIn ? "云端同步状态" : "本机游客持仓")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GoldTheme.text)
                        Text(signedIn ? "离线可记录，联网自动合并" : "记录保存在当前设备")
                            .font(.caption)
                            .foregroundStyle(GoldTheme.textSecondary)
                    }
                    Spacer(minLength: 6)
                    statusCapsule(badge: badge)
                }

                Text(cloud?.status ?? "登录后持仓与账本保存到服务端，本机保留离线缓存。")
                    .font(.footnote)
                    .foregroundStyle(GoldTheme.textSecondary)
                    .lineSpacing(4)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GoldTheme.background, in: GoldTheme.subCardShape)
                    .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))

                if let cloud, signedIn {
                    VStack(spacing: 10) {
                        Button { Task { await cloud.sync() } } label: {
                            HStack(spacing: 8) {
                                if cloud.isSyncing {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(GoldTheme.onGold)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.footnote.bold())
                                }
                                Text(cloud.isSyncing ? "正在同步…" : "立即同步")
                            }
                        }
                        .buttonStyle(GoldPrimaryButtonStyle())
                        .disabled(cloud.isSyncing)

                        if cloud.conflictCount > 0 {
                            Button { confirmConflict = true } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.footnote.weight(.semibold))
                                    Text("处理同步冲突（\(cloud.conflictCount) 条）")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(GoldTheme.up)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(GoldTheme.up.opacity(0.13), in: GoldTheme.subCardShape)
                                .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.up.opacity(0.38), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }

                        if cloud.guestRecordCount > 0 {
                            VStack(alignment: .leading, spacing: 8) {
                                Button { confirmImport = true } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "tray.and.arrow.down.fill")
                                            .font(.footnote.weight(.semibold))
                                        Text("导入此设备的游客记录（\(cloud.guestRecordCount) 条）")
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.85)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .foregroundStyle(GoldTheme.goldSoft)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .background(GoldTheme.gold.opacity(0.12), in: GoldTheme.subCardShape)
                                    .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.gold.opacity(0.36), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .disabled(cloud.isSyncing)

                                Text("游客记录不会自动归入账户；导入后原记录仍保留，重复导入会跳过相同记录。")
                                    .font(.caption)
                                    .foregroundStyle(GoldTheme.textFaint)
                                    .lineSpacing(3)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
            .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
    }

    // MARK: - 2. 跨设备登录（Apple 绑定邮箱）

    private func crossDeviceLoginSection(scope: AppleEmailLinkScope) -> some View {
        let linked = session.user?.email != nil
        return VStack(alignment: .leading, spacing: 8) {
            AccountSectionHeader(title: "跨设备登录")

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    AccountRowIconBadge(systemName: "envelope.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple 账户绑定邮箱")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GoldTheme.text)
                        Text("支持在 Android 等其他设备登录")
                            .font(.caption)
                            .foregroundStyle(GoldTheme.textSecondary)
                    }
                    Spacer(minLength: 6)
                    Text(linked ? "已绑定" : "未绑定")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(linked ? GoldTheme.down : GoldTheme.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            linked ? GoldTheme.down.opacity(0.14) : GoldTheme.calendarCell,
                            in: GoldTheme.capsuleShape
                        )
                        .overlay(
                            GoldTheme.capsuleShape.strokeBorder(
                                linked ? GoldTheme.down.opacity(0.35) : GoldTheme.cardStroke,
                                lineWidth: 0.8
                            )
                        )
                }

                if linked {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(GoldTheme.down)
                        Text("已绑定邮箱 \(session.user?.maskedIdentifier ?? "")")
                            .font(.footnote.monospaced())
                            .foregroundStyle(GoldTheme.text)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GoldTheme.background, in: GoldTheme.subCardShape)
                    .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
                } else {
                    Button { selectedEmailLink = scope } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .font(.footnote.weight(.semibold))
                            Text("绑定邮箱登录")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(GoldTheme.goldSoft)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(GoldTheme.gold.opacity(0.12), in: GoldTheme.subCardShape)
                        .overlay(GoldTheme.subCardShape.strokeBorder(GoldTheme.gold.opacity(0.36), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.appleEmailLink")

                    Text("在 Android 使用绑定的邮箱，即可打开此账户的持仓和账本。")
                        .font(.caption)
                        .foregroundStyle(GoldTheme.textSecondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
            .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
    }

    // MARK: - 3. 存储与缓存

    private var storageCacheSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccountSectionHeader(title: "存储与缓存")

            VStack(alignment: .leading, spacing: 12) {
                Button {
                    Task {
                        clearingCache = true
                        defer { clearingCache = false }
                        do {
                            try await MarketHistoryCache.shared.clear()
                            cacheNotice = "行情缓存已清除，下次查看时重新下载。"
                        } catch {
                            cacheNotice = "清除失败，请重试。"
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        AccountRowIconBadge(systemName: "trash.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("清除行情缓存")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(GoldTheme.text)
                            Text("仅清理本地行情历史")
                                .font(.caption)
                                .foregroundStyle(GoldTheme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if clearingCache {
                            ProgressView()
                                .tint(GoldTheme.gold)
                        } else {
                            Text("清除")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(GoldTheme.goldSoft)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(GoldTheme.background, in: GoldTheme.capsuleShape)
                                .overlay(GoldTheme.capsuleShape.strokeBorder(GoldTheme.gold.opacity(0.32), lineWidth: 1))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(clearingCache)
                .accessibilityIdentifier("settings.clearMarketCache")

                Text(cacheNotice ?? "清除已下载的行情数据，保留持仓记录和登录状态。")
                    .font(.caption)
                    .foregroundStyle(cacheNotice == nil ? GoldTheme.textFaint : GoldTheme.goldSoft)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
            .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
    }

    // MARK: - 4. 意见与反馈

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccountSectionHeader(title: FeedbackCopy.entryTitle)

            NavigationLink {
                FeedbackCenterView(session: session, marketBasis: marketBasis)
                    .goldTabBarContentSafeArea()
            } label: {
                HStack(spacing: 12) {
                    AccountRowIconBadge(systemName: "bubble.left.and.text.bubble.right.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(FeedbackCopy.entryTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GoldTheme.text)
                        Text(FeedbackCopy.entrySubtitle)
                            .font(.caption)
                            .foregroundStyle(GoldTheme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
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
            .accessibilityIdentifier("settings.feedback")
            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
            .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))
        }
    }

    // MARK: - 5. 关于与备案

    private var aboutAndComplianceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccountSectionHeader(title: "关于与备案")

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    AccountRowIconBadge(systemName: "info.circle.fill")
                    Text("应用版本")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GoldTheme.text)
                    Spacer()
                    Text(AccountAppVersionFormatter.format(includeBuild: true))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(GoldTheme.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)

                GoldTheme.cardStroke
                    .frame(height: 1)
                    .padding(.leading, 60)

                Link(destination: URL(string: "https://beian.miit.gov.cn/")!) {
                    HStack(spacing: 12) {
                        AccountRowIconBadge(systemName: "checkmark.shield.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AccountProfileCopy.icpTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(GoldTheme.text)
                            Text(AccountProfileCopy.icpNumber)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(GoldTheme.goldSoft)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GoldTheme.textFaint)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开工信部备案查询系统")
            }
            .background(GoldTheme.card, in: GoldTheme.holdingsCardShape)
            .overlay(GoldTheme.holdingsCardShape.strokeBorder(GoldTheme.cardStroke, lineWidth: 1))

            Text(AccountProfileCopy.disclaimer)
                .font(.caption2)
                .foregroundStyle(GoldTheme.textFaint)
                .padding(.horizontal, 4)
                .padding(.top, 2)
        }
    }

    // MARK: - 辅助组件与能力校验

    private func statusCapsule(badge: AccountCloudStatusBadge) -> some View {
        let foreground: Color = {
            switch badge.tone {
            case .synced: GoldTheme.down
            case .syncing: GoldTheme.gold
            case .pending: GoldTheme.goldSoft
            case .failed: GoldTheme.tempWarm
            case .conflict: GoldTheme.up
            case .guest: GoldTheme.textSecondary
            }
        }()
        let bg: Color = {
            switch badge.tone {
            case .synced: GoldTheme.down.opacity(0.14)
            case .syncing: GoldTheme.gold.opacity(0.14)
            case .pending: GoldTheme.gold.opacity(0.12)
            case .failed: GoldTheme.tempWarm.opacity(0.14)
            case .conflict: GoldTheme.up.opacity(0.14)
            case .guest: GoldTheme.calendarCell
            }
        }()
        let stroke: Color = {
            switch badge.tone {
            case .synced: GoldTheme.down.opacity(0.35)
            case .syncing: GoldTheme.gold.opacity(0.36)
            case .pending: GoldTheme.gold.opacity(0.3)
            case .failed: GoldTheme.tempWarm.opacity(0.42)
            case .conflict: GoldTheme.up.opacity(0.38)
            case .guest: GoldTheme.cardStroke
            }
        }()

        return HStack(spacing: 5) {
            AccountCloudToneIndicator(tone: badge.tone)
            Text(badge.title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(foreground)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(bg, in: GoldTheme.capsuleShape)
        .overlay(GoldTheme.capsuleShape.strokeBorder(stroke, lineWidth: 0.8))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func loadEmailLink() async {
        allowedEmailLink = nil
        guard let scope = session.appleEmailLinkScope,
              let capabilities = try? await session.service.fetch(AuthCapabilities.self, .capabilities),
              capabilities.canLinkAppleEmail, scope == session.appleEmailLinkScope,
              (try? await session.loadAppleEmailProfile(scope)) != nil,
              !Task.isCancelled, scope == session.appleEmailLinkScope else { return }
        allowedEmailLink = scope
    }
}
