import AuthenticationServices
import SwiftUI

struct AppleEmailLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: AppleEmailLinkModel
    @State private var operation: Task<Void, Never>?

    init(session: AuthSession, scope: AppleEmailLinkScope) {
        _model = State(initialValue: AppleEmailLinkModel(session: session, scope: scope))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.completed {
                        Label(L10n.tr("邮箱已绑定"), systemImage: "checkmark.circle").font(.title2.bold())
                            .foregroundStyle(GoldTheme.goldSoft)
                        Text(L10n.tr("现在可在 Android 使用此邮箱登录同一个记金账户。"))
                            .foregroundStyle(GoldTheme.textSecondary)
                    } else if model.verified {
                        form
                    } else {
                        Text(L10n.tr("先验证当前记金账户使用的 Apple 账户，再绑定一个你能收信的邮箱。"))
                            .foregroundStyle(GoldTheme.textSecondary)
                        appleVerification
                    }
                    if let error = model.error {
                        Text(error).foregroundStyle(GoldTheme.up).font(.footnote)
                            .accessibilityLabel(L10n.fmt("错误：%@", error))
                    }
                    if let message = model.message {
                        Text(message).foregroundStyle(GoldTheme.goldSoft).font(.footnote)
                    }
                }.padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(GoldTheme.background)
            .foregroundStyle(GoldTheme.text)
            .navigationTitle(L10n.tr("绑定邮箱登录"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button(model.completed ? L10n.tr("完成") : L10n.tr("关闭")) { dismiss() }
            } }
        }
        .preferredColorScheme(.dark)
        .tint(GoldTheme.gold)
        .task { await model.prepareApple() }
        .onChange(of: model.shouldDismiss) { _, stale in if stale { dismiss() } }
        .onDisappear {
            operation?.cancel()
            model.cancel()
        }
    }

    private var appleVerification: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let ready = model.attempt.map { $0.expiresAt > context.date } ?? false
            SignInWithAppleButton(.continue) { request in
                guard let attempt = model.beginApple() else { return }
                request.nonce = attempt.nonce
                request.state = attempt.state
            } onCompletion: { result in
                operation = Task { await completeApple(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .clipShape(GoldTheme.rangeShape)
            .disabled(!ready || model.busy)
            .opacity(ready && !model.busy ? 1 : 0.5)
            .accessibilityIdentifier("settings.appleEmailLink.verify")
            if !ready && !model.busy {
                Button(L10n.tr("准备 Apple 验证")) { operation = Task { await model.prepareApple() } }
                    .foregroundStyle(GoldTheme.gold)
            }
            if model.busy { ProgressView() }
        }
    }

    private var form: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("绑定后，邮箱和 Apple 登录都会打开当前记金账户。"))
                .foregroundStyle(GoldTheme.textSecondary)
            TextField(L10n.tr("邮箱地址"), text: $model.email)
                .keyboardType(.emailAddress).textContentType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled().authField()
                .accessibilityIdentifier("settings.appleEmailLink.email")
            HStack(spacing: 12) {
                TextField(L10n.tr("6 位验证码"), text: $model.code)
                    .keyboardType(.numberPad).textContentType(.oneTimeCode).authField()
                    .accessibilityIdentifier("settings.appleEmailLink.code")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = model.remaining(at: context.date)
                    Button(seconds > 0 ? L10n.fmt("%d 秒后重发", seconds) : L10n.tr("获取验证码")) {
                        operation = Task { await model.sendCode() }
                    }
                    .disabled(!model.canSend || seconds > 0)
                    .accessibilityIdentifier("settings.appleEmailLink.send")
                }
            }
            SecureField(L10n.tr("设置邮箱登录密码"), text: $model.password).textContentType(.newPassword).authField()
                .accessibilityIdentifier("settings.appleEmailLink.password")
            Text(L10n.tr("密码需 12–128 个 Unicode 字符，最多 512 字节。"))
                .font(.caption).foregroundStyle(GoldTheme.textSecondary)
            SecureField(L10n.tr("再次输入密码"), text: $model.confirmation).textContentType(.newPassword).authField()
                .accessibilityIdentifier("settings.appleEmailLink.confirmation")
            if !model.confirmation.isEmpty && model.confirmation != model.password {
                Text(L10n.tr("两次密码不一致")).font(.caption).foregroundStyle(GoldTheme.up)
            }
            Button {
                operation = Task { await model.submit() }
            } label: {
                HStack {
                    if model.busy { ProgressView().tint(GoldTheme.onGold) }
                    Text(L10n.tr("验证并绑定"))
                }
            }.buttonStyle(GoldPrimaryButtonStyle())
                .disabled(!model.canSubmit).opacity(model.canSubmit ? 1 : 0.5)
                .accessibilityIdentifier("settings.appleEmailLink.submit")
        }.disabled(model.busy)
    }

    private func completeApple(_ result: Result<ASAuthorization, any Error>) async {
        switch result {
        case .success(let value):
            guard let credential = value.credential as? ASAuthorizationAppleIDCredential,
                  let identity = credential.identityToken, let token = String(data: identity, encoding: .utf8),
                  let authorization = credential.authorizationCode, let code = String(data: authorization, encoding: .utf8) else {
                model.appleFailed(AuthError.malformed)
                return
            }
            await model.completeApple(state: credential.state, token: token, authorizationCode: code, appleUserID: credential.user)
        case .failure(let error):
            model.appleFailed((error as? ASAuthorizationError)?.code == .canceled ? nil : error)
        }
    }
}
