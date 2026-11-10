import SwiftUI

struct AccountView: View {
    @Bindable var session: AuthSession
    var cloud: HoldingsCloud? = nil
    @State private var confirmImport = false
    @State private var confirmConflict = false
    @State private var showLogin = false
    @State private var reauthentication: AccountDeletionIntent?
    @State private var deletionConfirmation: AccountDeletionIntent?
    @State private var confirmLogout = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var error: String?
    @State private var clearingCache = false
    @State private var cacheNotice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("我的").font(.largeTitle.bold()).foregroundStyle(GoldTheme.text)
                    Text("记下每一克，积累每一天。")
                        .font(.subheadline).foregroundStyle(GoldTheme.textSecondary)
                }.padding(.top, 24)
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: session.user == nil ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
                        .font(.system(size: 44, weight: .light)).foregroundStyle(GoldTheme.gold)
                    if let user = session.user {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(user.nickname.isEmpty ? "记金用户" : user.nickname).font(.title2.bold())
                            Text(user.maskedIdentifier).font(.body.monospaced())
                            Text("通过 \(user.provider.title) 登录").font(.caption).foregroundStyle(GoldTheme.textSecondary)
                        }
                    } else {
                        Text("让积累，有自己的名字。")
                            .font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                        Text("登录或注册记金账户，继续记录你的黄金日常。")
                            .font(.subheadline).foregroundStyle(GoldTheme.textSecondary)
                        Button("登录 / 注册") { openLogin() }
                            .buttonStyle(GoldPrimaryButtonStyle())
                            .accessibilityIdentifier("account.login")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).goldCard(padding: 24)
                VStack(alignment: .leading, spacing: 12) {
                    Label(session.user == nil ? "游客持仓" : "账户持仓云同步", systemImage: session.user == nil ? "iphone" : "icloud")
                        .font(.headline).foregroundStyle(GoldTheme.goldSoft)
                    Text(cloud?.status ?? "登录后持仓与账本保存到服务端，本机保留离线缓存。")
                        .font(.subheadline).foregroundStyle(GoldTheme.textSecondary).lineSpacing(5)
                    if let cloud, session.user != nil {
                        Button { Task { await cloud.sync() } } label: {
                            HStack { Text("立即同步"); if cloud.isSyncing { ProgressView() } }
                        }.foregroundStyle(GoldTheme.gold).disabled(cloud.isSyncing)
                        if cloud.conflictCount > 0 {
                            Button("处理同步冲突") { confirmConflict = true }.foregroundStyle(GoldTheme.up)
                        }
                        if cloud.guestRecordCount > 0 {
                            Button("导入此设备的游客记录（\(cloud.guestRecordCount) 条）") { confirmImport = true }
                                .foregroundStyle(GoldTheme.gold).disabled(cloud.isSyncing)
                            Text("游客记录不会自动归入账户；导入后原记录仍保留，重复导入会跳过相同记录。")
                                .font(.footnote).foregroundStyle(GoldTheme.textSecondary)
                        }
                    }
                }.goldCard(padding: 20)
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        Task {
                            clearingCache = true
                            defer { clearingCache = false }
                            do {
                                try await MarketHistoryCache.shared.clear()
                                cacheNotice = "行情缓存已清除，下次查看时重新下载。"
                            } catch { cacheNotice = "清除失败，请重试。" }
                        }
                    } label: {
                        HStack {
                            Label("清除行情缓存", systemImage: "trash")
                            Spacer()
                            if clearingCache { ProgressView() }
                        }
                    }.foregroundStyle(GoldTheme.gold).disabled(clearingCache)
                        .accessibilityIdentifier("account.clearMarketCache")
                    Text(cacheNotice ?? "清除已下载的行情数据，保留持仓记录和登录状态。")
                        .font(.footnote).foregroundStyle(GoldTheme.textSecondary)
                }.goldCard(padding: 20)
                VStack(alignment: .leading, spacing: 16) {
                    Link(destination: URL(string: "https://oryjk.cn/sumly/privacy")!) {
                        Label("隐私政策", systemImage: "hand.raised")
                    }
                    .accessibilityIdentifier("account.privacyPolicy")
                    Link(destination: URL(string: "mailto:oryjk@qq.com")!) {
                        Label("联系支持", systemImage: "envelope")
                    }
                    .accessibilityIdentifier("account.support")
                    Text("记金用于个人记录与回收估算，不提供黄金交易或投资建议。")
                        .font(.footnote).foregroundStyle(GoldTheme.textSecondary)
                }
                .foregroundStyle(GoldTheme.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .goldCard(padding: 20)
                if let user = session.user {
                    VStack(spacing: 14) {
                        Button("重新验证 \(user.provider.title) 登录") { openLogin() }
                            .foregroundStyle(GoldTheme.gold)
                        Button("退出登录") { confirmLogout = true }
                            .foregroundStyle(GoldTheme.text)
                        Divider().overlay(GoldTheme.cardStroke)
                        Button(role: .destructive) {
                            deletionConfirmation = session.beginAccountDeletion()
                            confirmDelete = deletionConfirmation != nil
                        } label: {
                            if deleting { ProgressView() } else { Text("注销账户") }
                        }.foregroundStyle(GoldTheme.up)
                    }.frame(maxWidth: .infinity).goldCard(padding: 20).disabled(deleting)
                }
                if let notice = session.notice { Text(notice).font(.footnote).foregroundStyle(GoldTheme.textSecondary) }
                if let error { Text(error).font(.footnote).foregroundStyle(GoldTheme.up).accessibilityLabel("错误：" + error) }
            }.padding(.horizontal, 22).padding(.bottom, 30)
        }
        .background(GoldTheme.background)
        .foregroundStyle(GoldTheme.text)
        .sheet(isPresented: $showLogin) { AuthenticationSheet(session: session, reauthentication: reauthentication) }
        .onChange(of: session.user?.id) { _, _ in
            deletionConfirmation = nil
            confirmDelete = false
        }
        .confirmationDialog("将游客记录导入当前账户？", isPresented: $confirmImport, titleVisibility: .visible) {
            Button("导入并同步") { Task { await cloud?.importGuestRecords() } }
        } message: { Text("导入到 \(session.user?.maskedIdentifier ?? "")。记录使用原有 ID，重复导入跳过相同记录。游客原记录会保留。") }
        .confirmationDialog("处理多设备修改冲突", isPresented: $confirmConflict, titleVisibility: .visible) {
            Button("冲突记录保留本机版本") { Task { await cloud?.sync(choice: .local) } }
            Button("冲突记录使用云端版本", role: .destructive) { Task { await cloud?.sync(choice: .remote) } }
        } message: { Text("同一购入记录及其部分处置记录作为整体选择，其他记录自动合并。选择某一版本将放弃这些冲突记录在另一端的更改（包括删除）。") }
        .confirmationDialog("退出当前账户？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { Task { await session.logout() } }
        } message: { Text("未同步更改保留在此账户的设备缓存，重新登录可继续同步。退出后显示此设备的游客记录。") }
        .confirmationDialog("永久注销此账户？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("永久注销账户", role: .destructive) {
                if let intent = deletionConfirmation { Task { await deleteAccount(confirming: intent) } }
            }
        } message: {
            if let intent = deletionConfirmation {
                Text("待注销账户：\(intent.provider.title) · \(intent.maskedIdentifier)\n\n账户身份、云端持仓与账本、服务端登录会话将永久删除，无法恢复。需要最近 5 分钟内重新登录。此账户在本机的缓存也会清除；独立的游客记录保留。")
            }
        }
    }
    private func openLogin() {
        session.cancelAccountDeletion()
        deletionConfirmation = nil
        reauthentication = nil
        showLogin = true
    }
    private func deleteAccount(confirming intent: AccountDeletionIntent) async {
        deleting = true; error = nil
        defer { deleting = false }
        do {
            try await session.deleteAccount(confirming: intent)
            do { try cloud?.eraseDeletedAccountCache() }
            catch { session.notice = "账户与云端数据已删除，清除设备缓存失败：" + error.localizedDescription }
        }
        catch AuthError.reauthenticate {
            error = AuthError.reauthenticate.localizedDescription
            reauthentication = intent
            showLogin = true
        } catch { self.error = error.localizedDescription }
    }
}
