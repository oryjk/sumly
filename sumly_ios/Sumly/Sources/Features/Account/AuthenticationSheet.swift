import SwiftUI
import AuthenticationServices

struct AuthenticationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: AuthFormModel
    init(session: AuthSession, reauthentication: AccountDeletionIntent? = nil) {
        _model = State(initialValue: AuthFormModel(session: session, reauthentication: reauthentication))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("欢迎来到记金")).font(.largeTitle.bold())
                        Text(L10n.tr("登录后，账户持仓可在设备间同步。"))
                            .font(.subheadline).foregroundStyle(GoldTheme.textSecondary)
                    }
                    if model.loadingCapabilities { ProgressView(L10n.tr("正在获取登录方式…")) }
                    if let intent = model.reauthentication {
                        Text(L10n.fmt("请验证待注销账户：%@ · %@。验证成功后仍需再次确认注销。", intent.provider.title, intent.maskedIdentifier))
                            .font(.subheadline).foregroundStyle(GoldTheme.goldSoft)
                    }
                    if model.capabilities.apple && model.allowsProvider(.apple) { appleSection }
                    if model.reauthentication?.provider != .apple &&
                        (model.capabilities.phone || model.capabilities.email || !model.capabilities.apple || model.reauthentication != nil) {
                        HStack(spacing: 12) {
                            if model.capabilities.phone && model.allowsProvider(.phone) {
                                Button(L10n.tr("手机号")) { model.changeMode(.phone) }
                                    .buttonStyle(GoldCapsuleStyle(isSelected: model.mode == .phone))
                            }
                            if model.capabilities.email && model.allowsProvider(.email) {
                                Button(L10n.tr("邮箱")) { model.changeMode(.email) }
                                    .buttonStyle(GoldCapsuleStyle(isSelected: model.mode != .phone))
                            }
                        }.disabled(model.busy)
                        if model.modeEnabled {
                            form
                        } else if !model.loadingCapabilities {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.tr("当前没有可用的验证方式")).font(.headline)
                                Text(L10n.tr("请稍后重试。你可以继续使用游客模式记录持仓。"))
                                    .font(.subheadline).foregroundStyle(GoldTheme.textSecondary)
                                Button(L10n.tr("重新获取登录方式")) { Task { await model.load() } }
                            }.goldCard()
                        }
                    }
                    if model.reauthentication?.provider == .apple && !model.capabilities.apple && !model.loadingCapabilities {
                        Text(L10n.tr("Apple 登录暂未开放，请稍后重新获取登录方式。"))
                            .foregroundStyle(GoldTheme.textSecondary)
                        Button(L10n.tr("重新获取登录方式")) { Task { await model.load() } }
                    }
                    if let error = model.error {
                        Text(error).foregroundStyle(GoldTheme.up).font(.footnote)
                            .accessibilityLabel(L10n.fmt("错误：%@", error))
                    }
                    if let message = model.message { Text(message).font(.footnote).foregroundStyle(GoldTheme.goldSoft) }
                    Text(L10n.tr("账户持仓与账本会保存至服务端，本机保留离线缓存。游客记录仅在你明确导入后上传。不同登录方式的账户不会自动合并。"))
                        .font(.caption).foregroundStyle(GoldTheme.textSecondary).lineSpacing(4)
                }.padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(GoldTheme.background)
            .foregroundStyle(GoldTheme.text)
            .navigationTitle(model.reauthentication == nil ? model.mode.title : L10n.tr("验证待注销账户")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L10n.tr("完成")) { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .tint(GoldTheme.gold)
        .task { await model.load() }
        .onChange(of: model.authenticated) { _, done in if done { dismiss() } }
        .onDisappear { model.cancel() }
    }
    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.mode == .phone {
                Text(L10n.tr("首次验证成功将自动注册。当前仅支持中国大陆 +86 手机号。"))
                    .font(.footnote).foregroundStyle(GoldTheme.textSecondary)
                HStack {
                    Text("+86").foregroundStyle(GoldTheme.gold)
                    TextField(L10n.tr("手机号"), text: $model.phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                        .accessibilityLabel(L10n.tr("中国大陆手机号"))
                }.authField()
            } else {
                TextField(L10n.tr("邮箱地址"), text: $model.email).keyboardType(.emailAddress).textContentType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().authField()
                SecureField(model.mode == .reset ? L10n.tr("新密码") : L10n.tr("密码"), text: $model.password)
                    .textContentType(model.mode == .email ? .password : .newPassword).authField()
                if model.mode == .register || model.mode == .reset {
                    Text(L10n.tr("密码需 12–128 个 Unicode 字符，最多 512 字节；空格会保留。"))
                        .font(.caption).foregroundStyle(GoldTheme.textSecondary)
                    SecureField(L10n.tr("再次输入密码"), text: $model.confirmation).textContentType(.newPassword).authField()
                    if !model.confirmation.isEmpty && model.confirmation != model.password {
                        Text(L10n.tr("两次密码不一致")).font(.caption).foregroundStyle(GoldTheme.up)
                    }
                }
            }
            if model.mode != .email {
                HStack(spacing: 12) {
                    TextField(L10n.tr("6 位验证码"), text: $model.code).keyboardType(.numberPad).textContentType(.oneTimeCode).authField()
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = model.remaining(at: context.date)
                        Button(seconds > 0 ? L10n.fmt("%d 秒后重发", seconds) : L10n.tr("获取验证码")) { Task { await model.sendCode() } }
                            .font(.subheadline).foregroundStyle(GoldTheme.gold)
                            .disabled(!model.canSend || seconds > 0)
                    }
                }
            }
            Button { Task { await model.submit() } } label: {
                HStack {
                    if model.busy { ProgressView().tint(GoldTheme.onGold) }
                    Text(model.mode == .reset ? L10n.tr("确认重设密码") : model.mode == .register ? L10n.tr("验证并注册") : L10n.tr("登录"))
                }
            }.buttonStyle(GoldPrimaryButtonStyle()).disabled(!model.canSubmit || model.busy)
                .opacity(model.canSubmit && !model.busy ? 1 : 0.5)
            if model.mode != .phone && model.reauthentication == nil {
                HStack {
                    Button(model.mode == .register ? L10n.tr("已有账户，去登录") : L10n.tr("注册邮箱账户")) {
                        model.changeMode(model.mode == .register ? .email : .register)
                    }
                    Spacer()
                    Button(model.mode == .reset ? L10n.tr("返回登录") : L10n.tr("忘记密码")) { model.changeMode(model.mode == .reset ? .email : .reset) }
                }.font(.footnote).foregroundStyle(GoldTheme.gold)
            }
        }.disabled(model.busy)
    }
    private var appleSection: some View {
        VStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let ready = model.appleAttempt.map { $0.expiresAt > context.date } ?? false
                SignInWithAppleButton(.continue) { request in
                    guard let attempt = model.beginApple() else { return }
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = attempt.nonce
                    request.state = attempt.state
                } onCompletion: { result in
                    Task { await completeApple(result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .clipShape(GoldTheme.rangeShape)
                .disabled(!ready || model.busy)
                .opacity(ready && !model.busy ? 1 : 0.5)
                .accessibilityIdentifier("auth.appleSignIn")
                if !ready && !model.appleInProgress {
                    Button(L10n.tr("准备 Apple 安全登录")) { Task { await model.prepareApple() } }
                        .font(.footnote).foregroundStyle(GoldTheme.gold)
                }
            }
            Text(L10n.tr("首次 Apple 登录将创建账户")).font(.caption).foregroundStyle(GoldTheme.textSecondary)
        }
    }
    private func completeApple(_ result: Result<ASAuthorization, any Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8),
                  let codeData = credential.authorizationCode, let code = String(data: codeData, encoding: .utf8) else {
                model.appleFailed(AuthError.malformed)
                await model.prepareApple()
                return
            }
            let nickname = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
            await model.completeApple(state: credential.state, token: token, authorizationCode: code, userID: credential.user, nickname: nickname)
        case .failure(let error):
            let cancelled = (error as? ASAuthorizationError)?.code == .canceled
            model.appleFailed(cancelled ? nil : error)
        }
        if !model.authenticated { await model.prepareApple() }
    }
}
extension View {
    func authField() -> some View {
        padding(14).background(GoldTheme.card, in: GoldTheme.rangeShape)
            .overlay(GoldTheme.rangeShape.strokeBorder(GoldTheme.cardStroke))
    }
}
