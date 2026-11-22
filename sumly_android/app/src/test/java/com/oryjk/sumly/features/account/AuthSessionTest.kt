package com.oryjk.sumly.features.account

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class AuthSessionTest {
    @Test
    fun concurrentRequestsShareOneRefreshEvenWhenLoginSheetIsCancelled() = runBlocking {
        val gateway = FakeAuthGateway()
        val store = MemoryCredentialStore()
        var now = 100L
        val session = AuthSession(gateway, store, this, clockMillis = { now })
        session.login(Login.Email("a@example.com", "abcdefghijkl"))
        val identity = requireNotNull(session.state.value.identity)
        now += 1_000L

        val first = async(start = CoroutineStart.UNDISPATCHED) {
            session.authorized(identity) { it }
        }
        gateway.refreshStarted.await()
        val second = async(start = CoroutineStart.UNDISPATCHED) {
            session.authorized(identity) { it }
        }
        session.cancelPendingLogin()
        gateway.finishRefresh.complete(credentials("rotated", "new-refresh"))

        assertEquals("rotated", first.await())
        assertEquals("rotated", second.await())
        assertEquals(1, gateway.refreshCount)
        assertEquals("new-refresh", store.value?.credentials?.refreshToken)
        assertEquals(identity, session.state.value.identity)
    }

    @Test
    fun logoutDuringAuthorizedWorkReturnsStaleAndClearsCredentials() = runBlocking {
        val gateway = FakeAuthGateway()
        val store = MemoryCredentialStore()
        val session = AuthSession(gateway, store, this, clockMillis = { 100L })
        session.login(Login.Email("a@example.com", "abcdefghijkl"))
        val identity = requireNotNull(session.state.value.identity)
        val release = CompletableDeferred<Unit>()
        val inFlight = async(start = CoroutineStart.UNDISPATCHED) {
            runCatching {
                session.authorized(identity) {
                    release.await()
                    "data from old account"
                }
            }
        }
        session.logout()
        release.complete(Unit)

        assertSame(AuthFailure.Stale, inFlight.await().exceptionOrNull())
        assertNull(session.state.value.identity)
        assertNull(store.value)
        assertEquals(listOf("first-refresh"), gateway.revokedTokens)
    }

    @Test
    fun deletionReauthenticationRejectsAnotherUserBeforePersistingNewCredentials() = runBlocking {
        val gateway = FakeAuthGateway()
        val store = MemoryCredentialStore()
        val session = AuthSession(gateway, store, this, clockMillis = { 100L })
        session.login(Login.Email("a@example.com", "abcdefghijkl"))
        val intent = requireNotNull(session.beginAccountDeletion())
        gateway.nextLogin = credentials("unrelated", "unrelated-refresh", userId = 43)

        val error = runCatching {
            session.login(Login.Email("b@example.com", "mnopqrstuvwx"), intent)
        }.exceptionOrNull()
        yield()

        assertSame(AuthFailure.AccountMismatch, error)
        assertEquals(intent.identity, session.state.value.identity)
        assertEquals("first-refresh", store.value?.credentials?.refreshToken)
        assertEquals(listOf("unrelated-refresh"), gateway.revokedTokens)
    }

    @Test
    fun deletionPurgesOnlyTheDeletedAccountAfterAnotherAccountSignsIn() = runBlocking {
        val gateway = FakeAuthGateway()
        val store = MemoryCredentialStore()
        val purged = mutableListOf<Long>()
        val session = AuthSession(gateway, store, this, clockMillis = { 100L }, onAccountDeleted = { purged.add(it) })
        session.login(Login.Email("a@example.com", "abcdefghijkl"))
        val intent = requireNotNull(session.beginAccountDeletion())
        val deletion = async(start = CoroutineStart.UNDISPATCHED) { session.deleteAccount(intent) }
        gateway.deletionStarted.await()
        gateway.nextLogin = credentials("other", "other-refresh", userId = 44)
        session.login(Login.Email("other@example.com", "abcdefghijkl"))
        gateway.finishDeletion.complete(Unit)
        deletion.await()

        assertEquals(listOf(42L), purged)
        assertEquals(44L, session.state.value.user?.id)
        assertEquals("other-refresh", store.value?.credentials?.refreshToken)
    }

    @Test
    fun linkingReauthenticationNeverSwitchesToAnUnrelatedAccount() = runBlocking {
        val gateway = FakeAuthGateway()
        val store = MemoryCredentialStore()
        val session = AuthSession(gateway, store, this, clockMillis = { 100L })
        session.login(Login.Email("a@example.com", "abcdefghijkl"))
        val identity = requireNotNull(session.state.value.identity)
        gateway.nextLogin = credentials("unrelated", "unrelated-refresh", userId = 43)

        val error = runCatching {
            session.reauthenticate(identity, Login.Email("b@example.com", "mnopqrstuvwx"))
        }.exceptionOrNull()
        yield()

        assertSame(AuthFailure.AccountMismatch, error)
        assertEquals(identity, session.state.value.identity)
        assertEquals("first-refresh", store.value?.credentials?.refreshToken)
        assertEquals(listOf("unrelated-refresh"), gateway.revokedTokens)
    }

    @Test
    fun aLateGooglePickerCannotReplaceASessionStartedAfterThePickerOpened() = runBlocking {
        val gateway = FakeAuthGateway()
        val store = MemoryCredentialStore()
        val session = AuthSession(gateway, store, this, clockMillis = { 100L })
        session.restore()
        val originalGuest = session.state.value
        session.login(Login.Email("a@example.com", "abcdefghijkl"), fromGuest = originalGuest)
        val activeIdentity = session.state.value.identity

        val failure = runCatching {
            session.login(Login.Google(GoogleProof("late-challenge", "identity")), fromGuest = originalGuest)
        }.exceptionOrNull()

        assertSame(AuthFailure.Stale, failure)
        assertEquals(1, gateway.loginCount)
        assertEquals(activeIdentity, session.state.value.identity)
        assertEquals("first-refresh", store.value?.credentials?.refreshToken)
    }

    @Test
    fun googleReauthenticationUsesTheCurrentBearerAndRevokesTheFormerFamilyAfterCommit() = runBlocking {
        val gateway = FakeAuthGateway()
        val store = MemoryCredentialStore()
        val session = AuthSession(gateway, store, this, clockMillis = { 100L })
        gateway.nextLogin = credentials("google-first", "google-first-refresh", provider = AccountProvider.Google)
        session.login(Login.Google(GoogleProof("login-challenge", "identity")))
        val origin = requireNotNull(session.state.value.identity)
        val deletion = requireNotNull(session.beginAccountDeletion())
        gateway.nextLogin = credentials("new-google", "new-google-refresh", provider = AccountProvider.Google)
        gateway.beforeLogout = {
            assertEquals("new-google-refresh", store.value?.credentials?.refreshToken)
            assertEquals(origin.generation + 1, session.state.value.identity?.generation)
        }

        val updatedDeletion = session.login(Login.Google(GoogleProof("account-bound-challenge", "identity")), deletion)
        yield()

        assertEquals(session.state.value.identity, updatedDeletion?.identity)
        assertEquals(1, gateway.loginCount)
        assertEquals(listOf("google-first"), gateway.googleReauthenticationBearers)
        assertEquals(listOf("google-first-refresh"), gateway.revokedTokens)
    }

    @Test
    fun reauthenticationStorageFailureKeepsTheOldFamilyAndRevokesOnlyTheReturnedCredentials() = runBlocking {
        val gateway = FakeAuthGateway()
        val store = MemoryCredentialStore()
        val session = AuthSession(gateway, store, this, clockMillis = { 100L })
        session.login(Login.Email("a@example.com", "abcdefghijkl"))
        val origin = requireNotNull(session.state.value.identity)
        gateway.nextLogin = credentials("new-email", "new-email-refresh")
        store.saveFailure = AuthFailure.SafeStorage

        val failure = runCatching { session.reauthenticate(origin, Login.Email("a@example.com", "abcdefghijkl")) }
            .exceptionOrNull()
        yield()

        assertSame(AuthFailure.SafeStorage, failure)
        assertEquals(origin, session.state.value.identity)
        assertEquals("first-refresh", store.value?.credentials?.refreshToken)
        assertEquals(listOf("new-email-refresh"), gateway.revokedTokens)
    }

    @Test
    fun googleReauthenticationReturningAfterAccountSwitchRevokesTheProvisionalFamily() = runBlocking {
        val gateway = FakeAuthGateway()
        val store = MemoryCredentialStore()
        val session = AuthSession(gateway, store, this, clockMillis = { 100L })
        gateway.nextLogin = credentials("google-first", "google-first-refresh", provider = AccountProvider.Google)
        session.login(Login.Google(GoogleProof("first-login", "identity")))
        val origin = requireNotNull(session.state.value.identity)
        gateway.nextLogin = credentials("provisional", "provisional-refresh", provider = AccountProvider.Google)
        val finishReply = CompletableDeferred<Unit>()
        gateway.beforeGoogleReauthenticationReply = { finishReply.await() }
        val inFlight = async(start = CoroutineStart.UNDISPATCHED) {
            runCatching { session.reauthenticate(origin, Login.Google(GoogleProof("bound-challenge", "identity"))) }
        }
        gateway.nextLogin = credentials("other", "other-refresh", userId = 43)
        session.login(Login.Email("other@example.com", "abcdefghijkl"))
        finishReply.complete(Unit)

        assertSame(AuthFailure.Stale, inFlight.await().exceptionOrNull())
        assertEquals(43L, session.state.value.user?.id)
        assertEquals("other-refresh", store.value?.credentials?.refreshToken)
        assertEquals(listOf("provisional-refresh"), gateway.revokedTokens)
    }

    private class MemoryCredentialStore : CredentialStore {
        var value: StoredSession? = null
        var saveFailure: AuthFailure? = null
        override fun load() = value
        override fun save(value: StoredSession) {
            saveFailure?.let { throw it }
            this.value = value
        }
        override fun clear() { value = null }
    }

    private class FakeAuthGateway : AuthGateway {
        var nextLogin = credentials("first", "first-refresh")
        var loginCount = 0
        var refreshCount = 0
        val refreshStarted = CompletableDeferred<Unit>()
        val finishRefresh = CompletableDeferred<LoginResult>()
        val deletionStarted = CompletableDeferred<Unit>()
        val finishDeletion = CompletableDeferred<Unit>()
        val revokedTokens = mutableListOf<String>()
        val googleReauthenticationBearers = mutableListOf<String>()
        var beforeLogout: () -> Unit = {}
        var beforeGoogleReauthenticationReply: suspend () -> Unit = {}

        override suspend fun capabilities() = AuthCapabilities.Disabled
        override suspend fun sendCode(destination: String, purpose: CodePurpose) = error("unused")
        override suspend fun login(login: Login): LoginResult {
            loginCount++
            return nextLogin
        }
        override suspend fun reauthenticateGoogle(proof: GoogleProof, accessToken: String): LoginResult {
            googleReauthenticationBearers.add(accessToken)
            val result = nextLogin
            beforeGoogleReauthenticationReply()
            return result
        }
        override suspend fun resetPassword(email: String, password: String, code: String) = error("unused")
        override suspend fun me(token: String) = credentials("first", "first-refresh").user
        override suspend fun refresh(refreshToken: String): LoginResult {
            refreshCount++
            refreshStarted.complete(Unit)
            return finishRefresh.await()
        }
        override suspend fun logout(refreshToken: String) {
            beforeLogout()
            revokedTokens.add(refreshToken)
        }
        override suspend fun deleteAccount(token: String) {
            deletionStarted.complete(Unit)
            finishDeletion.await()
        }
    }

    companion object {
        private fun credentials(
            token: String,
            refreshToken: String,
            userId: Long = 42,
            provider: AccountProvider = AccountProvider.Email,
        ) = LoginResult(
            token = token,
            refreshToken = refreshToken,
            expiresInSeconds = 1,
            user = AccountUser(userId, "测试用户", "", "active", provider, "a@example.com", null),
        )
    }
}
