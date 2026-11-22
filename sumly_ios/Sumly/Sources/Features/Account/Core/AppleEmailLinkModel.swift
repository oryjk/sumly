import Foundation
import Observation

@MainActor @Observable final class AppleEmailLinkModel {
    private let session: AuthSession
    private var scope: AppleEmailLinkScope
    private var active = true
    private var cooldowns: [String: Date] = [:]
    private var requestedFor: String?

    private(set) var attempt: AppleAttempt?
    private(set) var signingIn = false
    private(set) var busy = false
    private(set) var verified = false
    private(set) var completed = false
    private(set) var error: String?
    private(set) var message: String?
    var email = ""
    var password = ""
    var confirmation = ""
    var code = ""

    init(session: AuthSession, scope: AppleEmailLinkScope) {
        self.session = session
        self.scope = scope
    }

    var isCurrent: Bool { active && scope == session.appleEmailLinkScope }
    var shouldDismiss: Bool { scope.userID != session.appleEmailLinkScope?.userID || (!busy && !isCurrent) }
    private var destination: String { AuthValidation.email(email) }
    var canSend: Bool { isCurrent && verified && !busy && !completed && AuthValidation.validEmail(email) }
    var canSubmit: Bool {
        canSend && requestedFor == destination && AuthValidation.validPassword(password)
            && password == confirmation && AuthValidation.validCode(code)
    }

    func remaining(at now: Date) -> Int {
        max(0, Int(ceil((cooldowns[destination] ?? .distantPast).timeIntervalSince(now))))
    }

    func prepareApple() async {
        guard isCurrent, !verified, !busy, !completed else { return }
        busy = true
        defer { busy = false }
        attempt = nil
        do {
            let fresh = try await session.prepareAppleEmailLink(scope)
            if isCurrent, !Task.isCancelled { attempt = fresh }
        } catch {
            if isCurrent, !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    func beginApple() -> AppleAttempt? {
        guard isCurrent, !busy, let attempt, attempt.expiresAt > Date() else { return nil }
        signingIn = true
        busy = true
        error = nil
        return attempt
    }

    func completeApple(state: String?, token: String, authorizationCode: String, appleUserID: String) async {
        guard signingIn else { return }
        defer { signingIn = false; busy = false }
        guard isCurrent, let attempt else { return }
        self.attempt = nil
        do {
            let next = try await session.verifyAppleEmailLink(
                scope, attempt: attempt, state: state, identityToken: token, code: authorizationCode, appleUserID: appleUserID
            )
            scope = next
            guard isCurrent, !Task.isCancelled else { return }
            if session.user?.email != nil {
                completed = true
            } else {
                verified = true
            }
        } catch {
            if isCurrent, !Task.isCancelled {
                if case .server(409, _) = error as? AuthError {
                    self.error = AuthError.appleEmailAccountMismatch.localizedDescription
                } else {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    func appleFailed(_ failure: (any Error)?) {
        guard signingIn else { return }
        signingIn = false
        busy = false
        attempt = nil
        if let failure, isCurrent { error = failure.localizedDescription }
    }

    func sendCode() async {
        guard canSend, remaining(at: .now) == 0 else { return }
        let address = destination
        // The provider may deliver the code even if the HTTP reply never reaches this device.
        requestedFor = address
        code = ""
        busy = true
        error = nil
        message = nil
        defer { busy = false }
        do {
            let delivery = try await session.sendAppleEmailCode(address, scope: scope)
            guard isCurrent, !Task.isCancelled else { return }
            cooldowns[address] = Date().addingTimeInterval(Double(max(0, delivery.retryAfter)))
            message = "验证码已发送，请查看邮箱。"
        } catch {
            if isCurrent, !Task.isCancelled { handleEmailError(error) }
        }
    }

    func submit() async {
        guard canSubmit else { return }
        let address = destination
        busy = true
        error = nil
        message = nil
        defer { busy = false }
        do {
            try await session.linkAppleEmail(address, password: password, code: code, scope: scope)
            guard isCurrent, !Task.isCancelled else { return }
            complete()
            _ = try? await session.loadAppleEmailProfile(scope)
        } catch {
            guard isCurrent, !Task.isCancelled else { return }
            if error as? AuthError == .network, let profile = try? await session.loadAppleEmailProfile(scope),
               isCurrent, !Task.isCancelled, profile.email.map(AuthValidation.email) == address {
                complete()
            } else if isCurrent, !Task.isCancelled {
                handleEmailError(error)
            }
        }
    }

    func cancel() {
        active = false
        attempt = nil
        clearSecrets()
    }

    private func clearSecrets() {
        password = ""
        confirmation = ""
        code = ""
    }

    private func complete() {
        completed = true
        clearSecrets()
    }

    private func handleEmailError(_ failure: any Error) {
        switch failure as? AuthError {
        case .server(403, _):
            verified = false
            requestedFor = nil
            clearSecrets()
            error = "请再次完成 Apple 验证。"
        case .server(409, _):
            error = "该邮箱已用于记金账户。请检查绑定状态，或使用另一个可收信邮箱。"
        case .server(422, _):
            error = "验证码错误或已失效，请重新获取。"
        default:
            error = failure.localizedDescription
        }
    }

}
