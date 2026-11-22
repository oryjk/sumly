import Foundation
import Observation

@MainActor @Observable final class AuthSession {
    private(set) var stored: StoredSession?
    var notice: String?
    private(set) var deletionIntent: AccountDeletionIntent?
    func beginAccountDeletion() -> AccountDeletionIntent? {
        guard let user else { return nil }
        let intent = AccountDeletionIntent(userID: user.id, provider: user.provider, maskedIdentifier: user.maskedIdentifier)
        deletionIntent = intent
        return intent
    }
    func cancelAccountDeletion() { deletionIntent = nil }
    var user: NativeUser? { stored?.result.user }
    var needsRecentLogin: Bool { stored.map { Date().timeIntervalSince($0.primaryLoginAt) > 300 } ?? true }
    let service: any AuthServicing
    private let store: any CredentialStoring
    private var didLoadStorage = false
    private var generation = 0
    private var loginAttemptGeneration = 0
    var loginGeneration: Int { loginAttemptGeneration }
    var sessionGeneration: Int { generation }
    func cancelPendingLogin() { loginAttemptGeneration += 1 }
    private var refreshTask: Task<Void, any Error>?

    init(service: any AuthServicing, store: any CredentialStoring) { self.service = service; self.store = store }

    func login(_ request: AuthRequest, appleUserID: String? = nil, expectedGeneration: Int? = nil, reauthentication: AccountDeletionIntent? = nil) async throws {
        if let expectedGeneration, expectedGeneration != loginAttemptGeneration { throw AuthError.stale }
        if let reauthentication, !matchesDeletionIntent(reauthentication) { throw AuthError.stale }
        loginAttemptGeneration += 1
        let attempt = loginAttemptGeneration
        let result = try await service.fetch(LoginResult.self, request)
        guard attempt == loginAttemptGeneration else { throw AuthError.stale }
        guard !result.token.isEmpty, !result.refreshToken.isEmpty, result.expiresIn > 0 else { throw AuthError.malformed }
        if let reauthentication {
            guard matchesDeletionIntent(reauthentication) else {
                _ = try? await service.execute(.logout(result.refreshToken))
                throw AuthError.stale
            }
            guard result.user.id == reauthentication.userID, result.user.provider == reauthentication.provider else {
                // Reject BEFORE saving credentials; this new session must not replace the intended account.
                _ = try? await service.execute(.logout(result.refreshToken))
                throw AuthError.accountMismatch
            }
        }
        let next = StoredSession(result: result, expiresAt: Date().addingTimeInterval(Double(result.expiresIn)), primaryLoginAt: Date(), appleUserID: appleUserID)
        try store.save(next)
        // Only a successfully persisted replacement invalidates the established session.
        generation += 1
        refreshTask?.cancel(); refreshTask = nil
        stored = next
        if reauthentication == nil { deletionIntent = nil }
        didLoadStorage = true
        notice = nil
    }
    func restore() async {
        let stamp = generation
        do {
            if !didLoadStorage {
                stored = try store.load()
                didLoadStorage = true
            }
            guard stored != nil else { return }
            _ = try await currentUser()
        } catch {
            guard stamp == generation else { return }
            if error as? AuthError == .unauthorized { clearLocal() }
            else { notice = error.localizedDescription }
        }
    }
    func currentUser() async throws -> NativeUser {
        try await authorized(NativeUser.self, request: AuthRequest.me)
    }

    func authorized<T: Decodable & Sendable>(_ type: T.Type, request: (String) -> AuthRequest) async throws -> T {
        try await withAuthorization { token in
            try await service.fetch(type, request(token))
        }
    }

    private func withAuthorization<T: Sendable>(expected: AppleEmailLinkScope? = nil, execute: (String) async throws -> T) async throws -> T {
        if let expected { try requireAppleEmailScope(expected) }
        guard let current = stored else { throw AuthError.unauthorized }
        let stamp = generation
        let refreshedForExpiry = current.expiresAt <= Date()
        if refreshedForExpiry { try await refresh() }
        guard stamp == generation, let token = stored?.result.token else { throw AuthError.stale }
        if let expected { try requireAppleEmailScope(expected) }
        do {
            let result = try await execute(token)
            guard stamp == generation else { throw AuthError.stale }
            return result
        } catch AuthError.unauthorized {
            guard stamp == generation else { throw AuthError.stale }
            if refreshedForExpiry { clearLocal(); throw AuthError.unauthorized }
            // Another authorized request may already have rotated this access token.
            if stored?.result.token == token { try await refresh() }
            guard stamp == generation, let retryToken = stored?.result.token else { throw AuthError.stale }
            if let expected { try requireAppleEmailScope(expected) }
            do {
                let result = try await execute(retryToken)
                guard stamp == generation else { throw AuthError.stale }
                return result
            } catch AuthError.unauthorized {
                if stamp == generation { clearLocal() }
                throw AuthError.unauthorized
            }
        }
    }

    var appleEmailLinkScope: AppleEmailLinkScope? {
        guard let user, user.provider == .apple else { return nil }
        return AppleEmailLinkScope(userID: user.id, generation: generation)
    }

    private func requireAppleEmailScope(_ scope: AppleEmailLinkScope) throws {
        try Task.checkCancellation()
        guard scope == appleEmailLinkScope else { throw AuthError.stale }
    }

    func prepareAppleEmailLink(_ scope: AppleEmailLinkScope) async throws -> AppleAttempt {
        let challenge = try await withAuthorization(expected: scope) { token in
            try await service.fetch(AppleChallenge.self, .appleEmailChallenge(token))
        }
        try requireAppleEmailScope(scope)
        return try AppleAttempt(challenge: challenge)
    }

    func verifyAppleEmailLink(
        _ scope: AppleEmailLinkScope, attempt: AppleAttempt, state: String?,
        identityToken: String, code: String, appleUserID: String
    ) async throws -> AppleEmailLinkScope {
        try requireAppleEmailScope(scope)
        guard attempt.accepts(state: state), !identityToken.isEmpty, !code.isEmpty, !appleUserID.isEmpty else { throw AuthError.stale }
        if let storedID = stored?.appleUserID, storedID != appleUserID { throw AuthError.appleEmailAccountMismatch }
        let attemptGeneration = loginAttemptGeneration
        var provisional: LoginResult?
        do {
            let result = try await withAuthorization(expected: scope) { bearer in
                let result = try await service.fetch(LoginResult.self, .verifyAppleForEmail(
                    challengeID: attempt.challengeID, token: identityToken, code: code, bearer: bearer
                ))
                provisional = result
                return result
            }
            try requireAppleEmailScope(scope)
            guard attemptGeneration == loginAttemptGeneration else { throw AuthError.stale }
            guard result.user.id == scope.userID, result.user.provider == .apple else { throw AuthError.appleEmailAccountMismatch }
            guard !result.token.isEmpty, !result.refreshToken.isEmpty, result.expiresIn > 0 else { throw AuthError.malformed }
            let now = Date()
            let next = StoredSession(
                result: result, expiresAt: now.addingTimeInterval(Double(result.expiresIn)), primaryLoginAt: now, appleUserID: appleUserID
            )
            try store.save(next)
            let previousToken = stored?.result.refreshToken
            loginAttemptGeneration += 1
            generation += 1
            refreshTask?.cancel()
            refreshTask = nil
            stored = next
            if let previousToken, previousToken != result.refreshToken { retireEmailLinkSession(previousToken) }
            return AppleEmailLinkScope(userID: scope.userID, generation: generation)
        } catch {
            if let token = provisional?.refreshToken, !token.isEmpty, token != stored?.result.refreshToken {
                retireEmailLinkSession(token)
            }
            throw error
        }
    }

    private func retireEmailLinkSession(_ token: String) {
        let service = service
        Task { _ = try? await service.execute(.logout(token)) }
    }

    func sendAppleEmailCode(_ email: String, scope: AppleEmailLinkScope) async throws -> CodeDelivery {
        let delivery = try await withAuthorization(expected: scope) { bearer in
            try await service.fetch(CodeDelivery.self, .appleEmailCode(email, bearer: bearer))
        }
        try requireAppleEmailScope(scope)
        return delivery
    }

    func linkAppleEmail(_ email: String, password: String, code: String, scope: AppleEmailLinkScope) async throws {
        _ = try await withAuthorization(expected: scope) { bearer in
            try await service.execute(.linkAppleEmail(email, password: password, code: code, bearer: bearer))
        }
        try requireAppleEmailScope(scope)
    }

    func loadAppleEmailProfile(_ scope: AppleEmailLinkScope) async throws -> NativeUser {
        let profile = try await withAuthorization(expected: scope) { bearer in
            try await service.fetch(NativeUser.self, .me(bearer))
        }
        try requireAppleEmailScope(scope)
        guard var next = stored, profile.id == scope.userID, profile.provider == .apple else { throw AuthError.stale }
        if next.result.user != profile {
            let result = next.result
            next.result = LoginResult(token: result.token, refreshToken: result.refreshToken, expiresIn: result.expiresIn, user: profile)
            // Profile metadata also comes from the service on the next load if Keychain is unavailable.
            try? store.save(next)
            stored = next
        }
        return profile
    }
    func refresh() async throws {
        if let refreshTask { return try await refreshTask.value }
        guard let previous = stored else { throw AuthError.unauthorized }
        let stamp = generation
        let task = Task { @MainActor in
            defer { if stamp == self.generation { self.refreshTask = nil } }
            do {
                let result = try await self.service.fetch(LoginResult.self, .refresh(previous.result.refreshToken))
                guard stamp == self.generation else { throw AuthError.stale }
                guard !result.token.isEmpty, !result.refreshToken.isEmpty, result.expiresIn > 0 else { throw AuthError.malformed }
                var next = previous
                next.result = result
                next.expiresAt = Date().addingTimeInterval(Double(result.expiresIn))
                try self.store.save(next)
                self.stored = next
            } catch AuthError.unauthorized {
                if stamp == self.generation { self.clearLocal() }
                throw AuthError.unauthorized
            }
        }
        refreshTask = task
        try await task.value
    }
    func logout() async {
        let token = stored?.result.refreshToken
        clearLocal()
        let stamp = generation
        guard let token else { return }
        do { _ = try await service.execute(.logout(token)) }
        catch { if stamp == generation { notice = "已退出本机登录；网络异常，服务端会话可能仍有效。" } }
    }
    func clearLocal() {
        loginAttemptGeneration += 1
        generation += 1
        refreshTask?.cancel(); refreshTask = nil
        stored = nil
        deletionIntent = nil
        didLoadStorage = true
        do { try store.clear() } catch { notice = error.localizedDescription }
    }
    private func matchesDeletionIntent(_ intent: AccountDeletionIntent) -> Bool {
        deletionIntent == intent && user?.id == intent.userID && user?.provider == intent.provider
    }
    func deleteAccount(confirming intent: AccountDeletionIntent) async throws {
        guard matchesDeletionIntent(intent) else { throw AuthError.stale }
        guard !needsRecentLogin, let current = stored else { throw AuthError.reauthenticate }
        let stamp = generation
        _ = try await service.execute(.delete(current.result.token))
        guard stamp == generation else { throw AuthError.stale }
        clearLocal()
        notice = "账户与云端持仓已注销。此设备的独立游客记录保留。"
    }
}
