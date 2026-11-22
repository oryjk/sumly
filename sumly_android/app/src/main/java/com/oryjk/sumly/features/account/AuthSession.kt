package com.oryjk.sumly.features.account

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

class AuthSession internal constructor(
    private val gateway: AuthGateway,
    private val store: CredentialStore,
    private val scope: CoroutineScope,
    private val clockMillis: () -> Long = System::currentTimeMillis,
    private val isUnauthorized: (Exception) -> Boolean = { it == AuthFailure.Unauthorized },
    private val onAccountDeleted: suspend (Long) -> Unit = {},
) {
    private class RefreshWork(val result: CompletableDeferred<Unit>, val job: Job)

    private class CommittedLogin(
        val identity: AccountIdentity,
        val deletion: DeleteAccountIntent?,
        val formerRefreshToken: String?,
    )

    private val mutex = Mutex()
    private val session = MutableStateFlow(AccountSessionState())
    val state: StateFlow<AccountSessionState> = session.asStateFlow()
    private var stored: StoredSession? = null
    private var loginAttempt = 0L
    private var refreshWork: RefreshWork? = null
    private var deletionIntent: DeleteAccountIntent? = null

    internal suspend fun restore() {
        val identity = mutex.withLock {
            if (!session.value.restoring) return
            try {
                stored = withContext(Dispatchers.IO) { store.load() }
                session.value = AccountSessionState(user = stored?.credentials?.user, restoring = false)
            } catch (error: AuthFailure) {
                session.value = AccountSessionState(restoring = false, notice = error.message)
            }
            session.value.identity
        } ?: return
        try {
            reloadUser(identity)
        } catch (error: AuthFailure) {
            setNotice(identity, error.message)
        }
    }

    internal suspend fun cancelPendingLogin() {
        mutex.withLock { loginAttempt++ }
    }

    internal suspend fun reloadUser(identity: AccountIdentity) {
        val user = authorized(identity, gateway::me)
        mutex.withLock {
            requireCurrentLocked(identity)
            if (!matches(user, identity)) {
                clearLocalLocked()
                throw AuthFailure.Malformed
            }
            session.value = session.value.copy(user = user)
        }
    }

    internal suspend fun login(
        command: Login,
        reauthentication: DeleteAccountIntent? = null,
        fromGuest: AccountSessionState? = null,
    ): DeleteAccountIntent? = performLogin(command, reauthentication, fromGuest = fromGuest).deletion

    internal suspend fun reauthenticate(identity: AccountIdentity, command: Login): AccountIdentity =
        performLogin(command, expectedIdentity = identity).identity

    private suspend fun performLogin(
        command: Login,
        reauthentication: DeleteAccountIntent? = null,
        expectedIdentity: AccountIdentity? = null,
        fromGuest: AccountSessionState? = null,
    ): CommittedLogin {
        val expected = expectedIdentity ?: reauthentication?.identity
        val attempt = mutex.withLock {
            if (reauthentication != null && deletionIntent != reauthentication) throw AuthFailure.Stale
            expected?.let(::requireCurrentLocked)
            if (fromGuest != null) requireGuestLocked(fromGuest)
            ++loginAttempt
        }
        val result = if (command is Login.Google && expected != null) {
            withAccessToken(expected) { gateway.reauthenticateGoogle(command.proof, it) }
        } else {
            gateway.login(command)
        }
        val committed = try {
            currentCoroutineContext().ensureActive()
            result.validate()
            mutex.withLock {
                currentCoroutineContext().ensureActive()
                if (attempt != loginAttempt || (reauthentication != null && deletionIntent != reauthentication)) {
                    throw AuthFailure.Stale
                }
                if (fromGuest != null) requireGuestLocked(fromGuest)
                val former = expected?.let(::requireCurrentLocked)
                if (expected != null && !matches(result.user, expected)) throw AuthFailure.AccountMismatch
                if (command is Login.Google && result.user.provider != AccountProvider.Google) {
                    throw AuthFailure.Malformed
                }
                val now = clockMillis()
                val next = StoredSession(result, now + result.expiresInSeconds * 1_000L, now)
                withContext(NonCancellable) {
                    persist(next)
                    cancelRefreshLocked()
                    session.value = AccountSessionState(
                        user = result.user,
                        generation = session.value.generation + 1,
                        restoring = false,
                    )
                    val identity = requireNotNull(session.value.identity)
                    deletionIntent = reauthentication?.copy(identity = identity)
                    val formerRefreshToken = former?.credentials?.refreshToken?.takeUnless { it == result.refreshToken }
                    CommittedLogin(identity, deletionIntent, formerRefreshToken)
                }
            }
        } catch (error: Exception) {
            // A returned session rejected by the device must not become an orphaned signed-in session.
            scheduleLogout(result.refreshToken)
            throw error
        }
        committed.formerRefreshToken?.let(::scheduleLogout)
        return committed
    }

    // Authenticated sign-in checks the originating identity at commit, with the returned credentials
    // still available for revocation if another session wins the race.
    private suspend fun <T> withAccessToken(identity: AccountIdentity, operation: suspend (String) -> T): T {
        val original = mutex.withLock { requireCurrentLocked(identity) }
        val expired = original.expiresAtMillis <= clockMillis()
        if (expired) refresh(identity, original.credentials.token)
        val token = mutex.withLock { requireCurrentLocked(identity).credentials.token }
        try {
            return operation(token)
        } catch (error: Exception) {
            if (!isUnauthorized(error)) throw error
            if (expired) expireIfCurrent(identity, token)
        }
        refresh(identity, token)
        val retryToken = mutex.withLock { requireCurrentLocked(identity).credentials.token }
        try {
            return operation(retryToken)
        } catch (error: Exception) {
            if (isUnauthorized(error)) expireIfCurrent(identity, retryToken)
            throw error
        }
    }

    suspend fun <T> authorized(identity: AccountIdentity, operation: suspend (String) -> T): T =
        withAccessToken(identity) { token ->
            val response = operation(token)
            mutex.withLock { requireCurrentLocked(identity) }
            response
        }

    private suspend fun refresh(identity: AccountIdentity, oldAccessToken: String) {
        val work = mutex.withLock {
            val previous = requireCurrentLocked(identity)
            if (previous.credentials.token != oldAccessToken) return
            refreshWork ?: createRefreshLocked(identity, previous).also { refreshWork = it }
        }
        work.job.start()
        try {
            work.result.await()
        } catch (error: CancellationException) {
            currentCoroutineContext().ensureActive()
            mutex.withLock { requireCurrentLocked(identity) }
            throw error
        }
    }

    private fun createRefreshLocked(identity: AccountIdentity, previous: StoredSession): RefreshWork {
        val completion = CompletableDeferred<Unit>()
        val job = scope.launch(start = CoroutineStart.LAZY) {
            try {
                val result = gateway.refresh(previous.credentials.refreshToken)
                result.validate()
                mutex.withLock {
                    requireCurrentLocked(identity)
                    if (!matches(result.user, identity)) throw AuthFailure.Malformed
                    val next = previous.copy(
                        credentials = result,
                        expiresAtMillis = clockMillis() + result.expiresInSeconds * 1_000L,
                    )
                    withContext(NonCancellable) {
                        persist(next)
                        session.value = session.value.copy(user = result.user)
                    }
                }
                completion.complete(Unit)
            } catch (error: Exception) {
                val failure = if (isUnauthorized(error)) {
                    try {
                        expireIfCurrent(identity, previous.credentials.token, cancelRefresh = false)
                    } catch (expiry: AuthFailure) {
                        expiry
                    }
                } else {
                    error
                }
                completion.completeExceptionally(failure)
            } finally {
                withContext(NonCancellable) {
                    mutex.withLock {
                        if (refreshWork?.result === completion) refreshWork = null
                    }
                }
            }
        }
        return RefreshWork(completion, job)
    }

    internal suspend fun logout(expectedIdentity: AccountIdentity? = null) {
        val (token, generation) = mutex.withLock {
            expectedIdentity?.let(::requireCurrentLocked)
            val oldToken = stored?.credentials?.refreshToken
            clearLocalLocked()
            oldToken to session.value.generation
        }
        if (token == null) return
        if (!bestEffortLogout(token)) {
            mutex.withLock {
                if (session.value.generation == generation && session.value.notice == null) {
                    session.value = session.value.copy(notice = "已退出本机登录。网络异常，服务端会话可能仍有效。")
                }
            }
        }
    }

    internal suspend fun clearPasswordResetSession(email: String, originalIdentity: AccountIdentity?) {
        mutex.withLock {
            if (originalIdentity != null && session.value.identity == originalIdentity &&
                session.value.user?.email?.let(AuthValidation::email) == email
            ) {
                clearLocalLocked()
            }
        }
    }

    internal suspend fun beginAccountDeletion(): DeleteAccountIntent? = mutex.withLock {
        val identity = session.value.identity ?: return null
        val user = requireCurrentLocked(identity).credentials.user
        DeleteAccountIntent(identity, user.maskedIdentifier).also { deletionIntent = it }
    }

    internal suspend fun cancelAccountDeletion() {
        mutex.withLock {
            deletionIntent = null
            loginAttempt++
        }
    }

    internal suspend fun deleteAccount(confirming: DeleteAccountIntent) {
        val token = mutex.withLock {
            if (deletionIntent != confirming) throw AuthFailure.Stale
            val current = requireCurrentLocked(confirming.identity)
            if (clockMillis() - current.primaryLoginAtMillis !in 0..300_000) {
                throw AuthFailure.Reauthenticate
            }
            current.credentials.token
        }
        gateway.deleteAccount(token)
        withContext(NonCancellable) {
            val deletedUserId = confirming.identity.userId
            val clearedGeneration = mutex.withLock {
                if (session.value.user?.id == deletedUserId) {
                    clearLocalLocked()
                    session.value.generation
                } else {
                    null
                }
            }
            val cacheCleared = try {
                onAccountDeleted(deletedUserId)
                true
            } catch (_: Exception) {
                false
            }
            mutex.withLock {
                if (session.value.generation == clearedGeneration && session.value.notice == null) {
                    val notice = if (cacheCleared) {
                        "账户与云端持仓已注销，独立游客记录已保留。"
                    } else {
                        "账户与云端持仓已注销，本机账户持仓缓存清理失败。"
                    }
                    session.value = session.value.copy(notice = notice)
                }
            }
        }
    }

    private suspend fun expireIfCurrent(
        identity: AccountIdentity,
        token: String,
        cancelRefresh: Boolean = true,
    ): Nothing {
        mutex.withLock {
            val current = requireCurrentLocked(identity)
            if (current.credentials.token == token) {
                clearLocalLocked(cancelRefresh)
                if (session.value.notice == null) {
                    session.value = session.value.copy(notice = AuthFailure.Unauthorized.message)
                }
            }
        }
        throw AuthFailure.Unauthorized
    }

    private suspend fun setNotice(identity: AccountIdentity, notice: String?) {
        mutex.withLock {
            if (session.value.identity == identity) session.value = session.value.copy(notice = notice)
        }
    }

    private suspend fun persist(next: StoredSession) {
        withContext(Dispatchers.IO) { store.save(next) }
        stored = next
    }

    private suspend fun clearLocalLocked(cancelRefresh: Boolean = true) {
        withContext(NonCancellable) {
            loginAttempt++
            if (cancelRefresh) cancelRefreshLocked()
            stored = null
            deletionIntent = null
            session.value = AccountSessionState(
                generation = session.value.generation + 1,
                restoring = false,
            )
            try {
                withContext(Dispatchers.IO) { store.clear() }
            } catch (error: AuthFailure) {
                session.value = session.value.copy(notice = error.message)
            }
        }
    }

    private fun cancelRefreshLocked() {
        refreshWork?.result?.cancel()
        refreshWork?.job?.cancel()
        refreshWork = null
    }

    private fun requireCurrentLocked(identity: AccountIdentity): StoredSession {
        if (session.value.identity != identity) throw AuthFailure.Stale
        return stored ?: throw AuthFailure.Unauthorized
    }

    private fun requireGuestLocked(expected: AccountSessionState) {
        val current = session.value
        if (expected.user != null || current.user != null || current.restoring ||
            current.generation != expected.generation
        ) {
            throw AuthFailure.Stale
        }
    }

    private fun matches(user: AccountUser, identity: AccountIdentity): Boolean =
        user.id == identity.userId && user.provider == identity.provider

    private fun scheduleLogout(token: String) {
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            withContext(NonCancellable) { bestEffortLogout(token) }
        }
    }

    private suspend fun bestEffortLogout(token: String): Boolean {
        return try {
            gateway.logout(token)
            true
        } catch (error: CancellationException) {
            throw error
        } catch (_: AuthFailure) {
            false
        }
    }
}
