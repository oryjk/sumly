import SwiftUI

struct AccountSettingsView: View {
    @Bindable var session: AuthSession
    var cloud: HoldingsCloud? = nil
    @State private var confirmImport = false
    @State private var confirmConflict = false
    @State private var clearingCache = false
    @State private var cacheNotice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                        .accessibilityIdentifier("settings.clearMarketCache")
                    Text(cacheNotice ?? "清除已下载的行情数据，保留持仓记录和登录状态。")
                        .font(.footnote).foregroundStyle(GoldTheme.textSecondary)
                }.goldCard(padding: 20)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
        }
        .background(GoldTheme.background)
        .foregroundStyle(GoldTheme.text)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog("将游客记录导入当前账户？", isPresented: $confirmImport, titleVisibility: .visible) {
            Button("导入并同步") { Task { await cloud?.importGuestRecords() } }
        } message: { Text("导入到 \(session.user?.maskedIdentifier ?? "")。记录使用原有 ID，重复导入跳过相同记录。游客原记录会保留。") }
        .confirmationDialog("处理多设备修改冲突", isPresented: $confirmConflict, titleVisibility: .visible) {
            Button("冲突记录保留本机版本") { Task { await cloud?.sync(choice: .local) } }
            Button("冲突记录使用云端版本", role: .destructive) { Task { await cloud?.sync(choice: .remote) } }
        } message: { Text("同一购入记录及其部分处置记录作为整体选择，其他记录自动合并。选择某一版本将放弃这些冲突记录在另一端的更改（包括删除）。") }
    }
}
