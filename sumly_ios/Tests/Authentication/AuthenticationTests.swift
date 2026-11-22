import Foundation
import Testing
@testable import Sumly

private let loginJSON = Data(#"{"token":"access","refresh_token":"refresh","expires_in":900,"user":{"id":42,"nickname":"记金用户","avatar_url":"","email":null,"phone_number":"+8613800138000","status":"active","provider":"phone"}}"#.utf8)

@Test func appleEmailLinkRequiresNewCapabilityAndSendsOnlyExpectedProof() throws {
    let old = try AuthCoding.decode(AuthCapabilities.self, from: Data(#"{"apple":true,"phone":false,"email":true}"#.utf8))
    let enabled = try AuthCoding.decode(AuthCapabilities.self, from: Data(#"{"apple":true,"phone":false,"email":true,"apple_email_link":true}"#.utf8))
    #expect(!old.canLinkAppleEmail)
    #expect(enabled.canLinkAppleEmail)
    let url = URL(string: "https://example.test/sumly/api/v1")!
    let challenge = try NativeAuthService.makeRequest(.appleEmailChallenge("apple-access"), baseURL: url)
    #expect(challenge.url?.path == "/sumly/api/v1/app/auth/apple/reauthenticate/challenge")
    #expect(challenge.value(forHTTPHeaderField: "Authorization") == "Bearer apple-access")
    let proof = AuthRequest.verifyAppleForEmail(challengeID: "c", token: "id-token", code: "grant", bearer: "apple-access")
    #expect(proof.fields == ["challenge_id": "c", "identity_token": "id-token", "authorization_code": "grant"])
    #expect(proof.path == "apple/reauthenticate")
    let link = AuthRequest.linkAppleEmail("test@example.test", password: "fixture-only-password", code: "123456", bearer: "fresh-access")
    #expect(link.path == "email/link")
    #expect(link.bearer == "fresh-access")
    #expect(link.fields["email"] == "test@example.test")
}

private actor AppleEmailLinkFake: AuthServicing {
    private var requests: [AuthRequest] = []
    private var verifiedID: Int64 = 42
    private var suspendReauth = false
    private var reauthWaiter: CheckedContinuation<Void, Never>?
    private var linkedEmail: String?
    private var loseLinkReply = false

    func configure(verifiedID: Int64 = 42, suspendReauth: Bool = false, loseLinkReply: Bool = false) {
        self.verifiedID = verifiedID
        self.suspendReauth = suspendReauth
        self.loseLinkReply = loseLinkReply
    }

    func call(_ path: String) -> AuthRequest? { requests.last { $0.path == path } }
    func isReauthWaiting() -> Bool { reauthWaiter != nil }
    func finishReauth() { reauthWaiter?.resume(); reauthWaiter = nil }

    func execute(_ request: AuthRequest) async throws -> Data {
        requests.append(request)
        switch request.path {
        case "apple/login":
            return try JSONEncoder().encode(result(id: 42, token: "initial"))
        case "apple/reauthenticate/challenge":
            return Data(#"{"challenge_id":"c","nonce":"nonce","expires_in":300}"#.utf8)
        case "apple/reauthenticate":
            if suspendReauth { await withCheckedContinuation { reauthWaiter = $0 } }
            return try JSONEncoder().encode(result(id: verifiedID, token: "fresh"))
        case "email/link/code":
            return Data(#"{"retry_after":60,"expires_in":300}"#.utf8)
        case "email/link":
            linkedEmail = request.fields["email"]
            if loseLinkReply { throw AuthError.network }
            return Data("{}".utf8)
        case "me":
            return try JSONEncoder().encode(result(id: 42, token: "fresh").user)
        case "email/login":
            return try JSONEncoder().encode(LoginResult(token: "other", refreshToken: "other-refresh", expiresIn: 900, user: .init(
                id: 100, nickname: "", avatarURL: "", email: "other@example.test", phoneNumber: nil, status: "active", provider: .email
            )))
        default:
            return Data("{}".utf8)
        }
    }

    private func result(id: Int64, token: String) -> LoginResult {
        LoginResult(token: token, refreshToken: token + "-refresh", expiresIn: 900, user: .init(
            id: id, nickname: "记金用户", avatarURL: "", email: linkedEmail, phoneNumber: nil, status: "active", provider: .apple
        ))
    }
}

@MainActor @Test func appleEmailBindingSurvivesLostReplyWithinSameAccount() async throws {
    let fake = AppleEmailLinkFake()
    await fake.configure(loseLinkReply: true)
    let store = MemoryCredentials()
    let session = AuthSession(service: fake, store: store)
    try await session.login(.appleLogin(challengeID: "login", token: "old", code: "code", nickname: nil), appleUserID: "apple-sub")
    let scope = try #require(session.appleEmailLinkScope)
    let form = AppleEmailLinkModel(session: session, scope: scope)
    await form.prepareApple()
    let attempt = try #require(form.beginApple())
    await form.completeApple(state: attempt.state, token: "proof", authorizationCode: "grant", appleUserID: "apple-sub")
    #expect(form.verified)
    #expect(session.sessionGeneration == scope.generation + 1)
    #expect(await fake.call("apple/reauthenticate")?.bearer == "initial")
    form.email = " Fixture@EXAMPLE.test "
    await form.sendCode()
    #expect(await fake.call("email/link/code")?.bearer == "fresh")
    form.password = "fixture-only-password"
    form.confirmation = form.password
    form.code = "123456"
    await form.submit()
    #expect(form.completed)
    #expect(form.password.isEmpty && form.code.isEmpty)
    #expect(session.user?.id == 42 && session.user?.provider == .apple)
    #expect(session.user?.email == "fixture@example.test")
    #expect(store.value?.result.user.email == "fixture@example.test")
    #expect(await fake.call("email/link")?.fields["email"] == "fixture@example.test")
}

@MainActor @Test func appleEmailReauthRejectsAnotherLocalOrServerIdentity() async throws {
    let fake = AppleEmailLinkFake()
    let session = AuthSession(service: fake, store: MemoryCredentials())
    try await session.login(.appleLogin(challengeID: "login", token: "old", code: "code", nickname: nil), appleUserID: "apple-sub")
    let scope = try #require(session.appleEmailLinkScope)
    let attempt = try await session.prepareAppleEmailLink(scope)
    await #expect(throws: AuthError.appleEmailAccountMismatch) {
        try await session.verifyAppleEmailLink(scope, attempt: attempt, state: attempt.state, identityToken: "proof", code: "grant", appleUserID: "wrong")
    }
    #expect(await fake.call("apple/reauthenticate") == nil)

    await fake.configure(verifiedID: 999)
    await #expect(throws: AuthError.appleEmailAccountMismatch) {
        try await session.verifyAppleEmailLink(scope, attempt: attempt, state: attempt.state, identityToken: "proof", code: "grant", appleUserID: "apple-sub")
    }
    #expect(session.appleEmailLinkScope == scope)
    #expect(session.stored?.result.token == "initial")
}

@MainActor @Test func oldAppleBindingCannotContinueAcrossAccountSwitch() async throws {
    let fake = AppleEmailLinkFake()
    await fake.configure(suspendReauth: true)
    let session = AuthSession(service: fake, store: MemoryCredentials())
    try await session.login(.appleLogin(challengeID: "login", token: "old", code: "code", nickname: nil), appleUserID: "apple-sub")
    let scope = try #require(session.appleEmailLinkScope)
    let attempt = try await session.prepareAppleEmailLink(scope)
    let reauth = Task {
        try await session.verifyAppleEmailLink(scope, attempt: attempt, state: attempt.state, identityToken: "proof", code: "grant", appleUserID: "apple-sub")
    }
    while !(await fake.isReauthWaiting()) { await Task.yield() }
    try await session.login(.emailLogin(email: "other@example.test", password: "fixture-only-password"))
    await fake.finishReauth()
    await #expect(throws: AuthError.stale) { try await reauth.value }
    await #expect(throws: AuthError.stale) { try await session.sendAppleEmailCode("fixture@example.test", scope: scope) }
    #expect(await fake.call("email/link/code") == nil)
    #expect(session.user?.id == 100 && session.user?.provider == .email)
}

@Test func nativeUserContractAndPasswordBoundaries() throws {
    let result = try AuthCoding.decode(LoginResult.self, from: loginJSON)
    #expect(result.user.provider == .phone)
    #expect(result.user.email == nil)
    #expect(result.user.avatarURL == "")
    #expect(AuthValidation.validPassword(String(repeating: "金", count: 12)))
    #expect(!AuthValidation.validPassword(String(repeating: "a", count: 11)))
    #expect(!AuthValidation.validPassword(String(repeating: "a", count: 129)))
    #expect(AuthValidation.validPassword(String(repeating: "😀", count: 128)))
    #expect(!AuthValidation.validPassword(String(repeating: "😀", count: 129)))
    #expect(AuthValidation.validPassword("            "))
    #expect(AuthValidation.phone("13800138000") == "+8613800138000")
    #expect(AuthValidation.phone("+8613800138000") == "+8613800138000")
    #expect(AuthValidation.phone("+14155552671") == nil)
    #expect(AuthValidation.email(" User+tag@EXAMPLE.com ") == "user+tag@example.com")
}

@Test func authWireRequestAndEnvelope() throws {
    let request = AuthRequest.appleLogin(challengeID: "challenge", token: "jwt", code: "authcode", nickname: nil)
    let urlRequest = try NativeAuthService.makeRequest(request, baseURL: URL(string: "https://example.com/sumly/api/v1")!)
    #expect(urlRequest.url?.path == "/sumly/api/v1/app/auth/apple/login")
    let data = try #require(urlRequest.httpBody)
    let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
    #expect(body == ["challenge_id": "challenge", "identity_token": "jwt", "authorization_code": "authcode"])
    #expect(throws: AuthError.self) {
        try NativeAuthService.unwrap(Data(#"{"code":401,"message":"expired","data":null}"#.utf8), status: 401)
    }
    let bytes = try NativeAuthService.unwrap(Data(#"{"code":0,"message":"ok","data":{"apple":false,"phone":true,"email":false}}"#.utf8), status: 200)
    #expect(try AuthCoding.decode(AuthCapabilities.self, from: bytes).phone)
}

@MainActor private final class MemoryCredentials: CredentialStoring {
    var value: StoredSession?
    var failClear = false
    func load() throws -> StoredSession? { value }
    func save(_ session: StoredSession) throws { value = session }
    func clear() throws { if failClear { throw AuthError.keychain(-1) }; value = nil }
}

private actor AuthFake: AuthServicing {
    var suspended = false
    var pending: [CheckedContinuation<Data, any Error>] = []
    var calls: [String] = []
    var failure: AuthError?
    func configure(suspended: Bool = false, failure: AuthError? = nil) { self.suspended = suspended; self.failure = failure }
    func execute(_ request: AuthRequest) async throws -> Data {
        calls.append(request.path)
        if let failure { throw failure }
        if suspended { return try await withCheckedThrowingContinuation { pending.append($0) } }
        if request.path == "capabilities" { return Data(#"{"apple":true,"phone":true,"email":true}"#.utf8) }
        if request.path == "apple/challenge" { return Data(#"{"challenge_id":"c","nonce":"nonce","expires_in":300}"#.utf8) }
        if request.path.hasSuffix("/code") { return Data(#"{"retry_after":60,"expires_in":300}"#.utf8) }
        if request.path == "me" {
            let object = try JSONSerialization.jsonObject(with: loginJSON) as! [String: Any]
            return try JSONSerialization.data(withJSONObject: object["user"]!)
        }
        if request.path == "logout" || request.path == "account" { return Data("{}".utf8) }
        return loginJSON
    }
    func release() { let saved = pending; pending = []; for item in saved { item.resume(returning: loginJSON) } }
    func count(_ path: String) -> Int { calls.filter { $0 == path }.count }
    func waiting() -> Int { pending.count }
}

@MainActor @Test func logoutCannotBeUndoneByPendingLogin() async throws {
    let fake = AuthFake(); let store = MemoryCredentials()
    let session = AuthSession(service: fake, store: store)
    await fake.configure(suspended: true)
    let login = Task { try await session.login(.phoneLogin(phone: "+8613800138000", code: "123456")) }
    while await fake.waiting() == 0 { await Task.yield() }
    await session.logout()
    await fake.release()
    _ = await login.result
    #expect(session.user == nil)
    #expect(store.value == nil)
}

@MainActor @Test func refreshIsSingleFlightAndLogoutWins() async throws {
    let fake = AuthFake(); let store = MemoryCredentials()
    let session = AuthSession(service: fake, store: store)
    try await session.login(.phoneLogin(phone: "+8613800138000", code: "123456"))
    await fake.configure(suspended: true)
    let one = Task { try await session.refresh() }
    let two = Task { try await session.refresh() }
    while await fake.waiting() == 0 { await Task.yield() }
    for _ in 0..<20 { await Task.yield() }
    #expect(await fake.count("refresh") == 1)
    let logout = Task { await session.logout() }
    while session.user != nil { await Task.yield() }
    await fake.release()
    _ = await one.result; _ = await two.result; await logout.value
    #expect(session.user == nil)
    #expect(store.value == nil)
}

@MainActor @Test func restorePreservesCredentialsOnNetworkFailureButClearsRevocation() async throws {
    let fake = AuthFake(); let store = MemoryCredentials()
    let first = AuthSession(service: fake, store: store)
    try await first.login(.emailLogin(email: "a@example.com", password: "abcdefghijkl"))
    await fake.configure(failure: .network)
    let restored = AuthSession(service: fake, store: store)
    await restored.restore()
    #expect(restored.user?.id == 42)
    #expect(store.value != nil)
    await fake.configure(failure: .unauthorized)
    await restored.restore()
    #expect(restored.user == nil)
    #expect(store.value == nil)
}

@Test func appleAttemptUsesExactNonceAndRejectsWrongStateOrExpiration() throws {
    let challenge = try AuthCoding.decode(AppleChallenge.self, from: Data(#"{"challenge_id":"c","nonce":"server-exact-nonce","expires_in":300}"#.utf8))
    let date = Date(timeIntervalSince1970: 100)
    let attempt = try AppleAttempt(challenge: challenge, now: date)
    #expect(attempt.nonce == "server-exact-nonce")
    #expect(attempt.state.count >= 32)
    #expect(attempt.accepts(state: attempt.state, now: date.addingTimeInterval(299)))
    #expect(!attempt.accepts(state: "attacker", now: date))
    #expect(!attempt.accepts(state: attempt.state, now: date.addingTimeInterval(300)))
    #expect(try AppleAttempt(challenge: challenge, now: date).state != attempt.state)
}

@MainActor @Test func formRequiresConfirmationAndResetDoesNotLogin() async throws {
    let fake = AuthFake(); let session = AuthSession(service: fake, store: MemoryCredentials())
    let form = AuthFormModel(session: session)
    await form.load()
    form.mode = .register
    form.email = " Test@Example.com "
    form.password = "abcdefghijkl"
    form.confirmation = "wrong"
    form.code = "123456"
    #expect(!form.canSubmit)
    form.confirmation = form.password
    #expect(form.canSubmit)
    form.mode = .reset
    await form.submit()
    #expect(form.mode == .email)
    #expect(session.user == nil)
    #expect(form.password.isEmpty)
    #expect(form.message != nil)
}

@MainActor @Test func oldAppleAttemptCannotLoginAfterLogout() async throws {
    let fake = AuthFake(); let store = MemoryCredentials()
    let session = AuthSession(service: fake, store: store)
    let generation = session.loginGeneration
    await session.logout()
    await #expect(throws: AuthError.stale) {
        try await session.login(.phoneLogin(phone: "+8613800138000", code: "123456"), expectedGeneration: generation)
    }
    #expect(session.user == nil)
}

private struct CredentialFake: AppleCredentialChecking {
    let state: AppleCredentialState
    let fails: Bool
    func state(for userID: String) async throws -> AppleCredentialState {
        if fails { throw AuthError.network }
        return state
    }
}
@MainActor @Test func appleCredentialNetworkFailurePreservesSessionAndRevocationClearsIt() async throws {
    let session = AuthSession(service: AuthFake(), store: MemoryCredentials())
    try await session.login(.phoneLogin(phone: "+8613800138000", code: "123456"), appleUserID: "apple-subject")
    await session.checkAppleCredential(using: CredentialFake(state: .revoked, fails: true))
    #expect(session.user != nil)
    await session.checkAppleCredential(using: CredentialFake(state: .revoked, fails: false))
    #expect(session.user == nil)
}

@Test func authRoutesHaveExactMethodsAndPayloads() throws {
    let cases: [(AuthRequest, String, String, [String: String])] = [
        (.phoneCode("+8613800138000"), "phone/code", "POST", ["phone_number": "+8613800138000"]),
        (.phoneLogin(phone: "+8613800138000", code: "123456"), "phone/login", "POST", ["phone_number": "+8613800138000", "code": "123456"]),
        (.emailCode("a@b.com", purpose: "register"), "email/code", "POST", ["email": "a@b.com", "purpose": "register"]),
        (.emailRegister(email: "a@b.com", password: " 1234567890 ", code: "123456"), "email/register", "POST", ["email": "a@b.com", "password": " 1234567890 ", "code": "123456"]),
        (.emailLogin(email: "a@b.com", password: " 1234567890 "), "email/login", "POST", ["email": "a@b.com", "password": " 1234567890 "]),
        (.reset(email: "a@b.com", password: "new password", code: "123456"), "email/reset-password", "POST", ["email": "a@b.com", "new_password": "new password", "code": "123456"]),
        (.refresh("refresh"), "refresh", "POST", ["refresh_token": "refresh"]),
        (.logout("refresh"), "logout", "POST", ["refresh_token": "refresh"]),
        (.delete("access"), "account", "DELETE", ["confirmation": "DELETE"])
    ]
    for (request, path, method, fields) in cases {
        let wire = try NativeAuthService.makeRequest(request, baseURL: URL(string: "https://example.com/api/v1/")!)
        #expect(wire.url?.path == "/api/v1/app/auth/" + path)
        #expect(wire.httpMethod == method)
        let data = try #require(wire.httpBody)
        #expect(try JSONSerialization.jsonObject(with: data) as? [String: String] == fields)
    }
    let me = try NativeAuthService.makeRequest(.me("access"), baseURL: URL(string: "https://example.com/api/v1")!)
    #expect(me.httpMethod == "GET")
    #expect(me.value(forHTTPHeaderField: "Authorization") == "Bearer access")
    #expect(me.httpBody == nil)
    #expect(throws: AuthError.insecureURL) {
        try NativeAuthService.makeRequest(.capabilities, baseURL: URL(string: "http://example.com/api/v1")!)
    }
    #expect(throws: AuthError.unavailable) { try NativeAuthService.unwrap(Data(), status: 404) }
    #expect(throws: AuthError.malformed) { try NativeAuthService.unwrap(Data(repeating: 0, count: 1_048_577), status: 200) }
}

private actor RejectedMeService: AuthServicing {
    private(set) var refreshes = 0
    func execute(_ request: AuthRequest) async throws -> Data {
        if request.path == "me" { throw AuthError.unauthorized }
        if request.path == "refresh" { refreshes += 1 }
        return loginJSON
    }
}
@MainActor @Test func expiredRestoreRefreshesOnlyOnceWhenMeStillRejects() async throws {
    let fake = RejectedMeService(); let store = MemoryCredentials()
    store.value = StoredSession(result: try AuthCoding.decode(LoginResult.self, from: loginJSON), expiresAt: .distantPast, primaryLoginAt: .now, appleUserID: nil)
    let session = AuthSession(service: fake, store: store)
    await session.restore()
    #expect(await fake.refreshes == 1)
    #expect(session.user == nil)
    #expect(store.value == nil)
}
@MainActor @Test func cooldownSurvivesModeSwitchAndUsesWallClock() async {
    let form = AuthFormModel(session: AuthSession(service: AuthFake(), store: MemoryCredentials()))
    await form.load()
    form.phone = "13800138000"
    #expect(form.canSend)
    await form.sendCode()
    #expect(!form.canSend)
    #expect(form.remaining(at: Date()) > 0)
    #expect(form.remaining(at: Date().addingTimeInterval(61)) == 0)
    form.changeMode(.email)
    form.changeMode(.phone)
    #expect(!form.canSend)
}
@MainActor @Test func refreshDoesNotMakeDeletionRecentAndDeletionFailureKeepsSession() async throws {
    let fake = AuthFake(); let store = MemoryCredentials()
    store.value = StoredSession(result: try AuthCoding.decode(LoginResult.self, from: loginJSON), expiresAt: .distantPast, primaryLoginAt: Date().addingTimeInterval(-301), appleUserID: nil)
    let session = AuthSession(service: fake, store: store)
    await session.restore()
    let expiredIntent = try #require(session.beginAccountDeletion())
    await #expect(throws: AuthError.reauthenticate) { try await session.deleteAccount(confirming: expiredIntent) }
    #expect(session.user != nil)
    try await session.login(.phoneLogin(phone: "+8613800138000", code: "123456"))
    await fake.configure(failure: .network)
    let intent = try #require(session.beginAccountDeletion())
    await #expect(throws: AuthError.network) { try await session.deleteAccount(confirming: intent) }
    #expect(session.user != nil)
    await fake.configure()
    try await session.deleteAccount(confirming: intent)
    #expect(session.user == nil)
    #expect(store.value == nil)
}


@MainActor @Test func failedKeychainClearCannotRestoreLoggedOutSessionOnForeground() async throws {
    let store = MemoryCredentials()
    let session = AuthSession(service: AuthFake(), store: store)
    try await session.login(.phoneLogin(phone: "+8613800138000", code: "123456"))
    store.failClear = true
    await session.logout()
    #expect(session.user == nil)
    #expect(session.notice != nil)
    await session.restore()
    #expect(session.user == nil)
}

@MainActor @Test func disabledCapabilitiesCannotSubmitAValidForm() async {
    let session = AuthSession(service: AuthFake(), store: MemoryCredentials())
    let form = AuthFormModel(session: session)
    form.phone = "13800138000"
    form.code = "123456"
    await form.submit()
    #expect(session.user == nil)
}

@MainActor @Test func resettingCurrentEmailClearsItsRevokedLocalSession() async throws {
    let user = NativeUser(id: 42, nickname: "test", avatarURL: "", email: "test@example.com", phoneNumber: nil, status: "active", provider: .email)
    let result = LoginResult(token: "access", refreshToken: "refresh", expiresIn: 900, user: user)
    let store = MemoryCredentials()
    store.value = StoredSession(result: result, expiresAt: Date().addingTimeInterval(900), primaryLoginAt: .now, appleUserID: nil)
    let session = AuthSession(service: AuthFake(), store: store)
    await session.restore()
    let form = AuthFormModel(session: session)
    await form.load()
    form.mode = .reset
    form.email = " TEST@Example.com "
    form.password = "abcdefghijkl"
    form.confirmation = form.password
    form.code = "123456"
    await form.submit()
    #expect(form.mode == .email)
    #expect(session.user == nil)
    #expect(store.value == nil)
}
