package com.oryjk.sumly.bootstrap

import android.content.Context
import androidx.compose.runtime.Stable
import com.oryjk.sumly.core.network.ApiClient
import com.oryjk.sumly.features.account.AccountIdentity
import com.oryjk.sumly.features.account.AuthSession
import com.oryjk.sumly.features.holdings.SQLiteGuestHoldingsStore
import com.oryjk.sumly.features.holdings.alerts.HoldingAlertsMonitor
import com.oryjk.sumly.features.holdings.cloud.AccountHoldingsStore
import com.oryjk.sumly.features.holdings.cloud.BackendHoldingsCloudRemote
import com.oryjk.sumly.features.holdings.cloud.HoldingsCloudSync
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

internal class HoldingsWorkspaces(context: Context, private val api: ApiClient) {
    private val appContext = context.applicationContext
    val guestStore = SQLiteGuestHoldingsStore(appContext)

    fun open(session: AuthSession, identity: AccountIdentity): AccountWorkspace {
        val isCurrent = { session.state.value.identity == identity }
        val store = AccountHoldingsStore(appContext, identity.userId, isCurrent = isCurrent)
        val remote = BackendHoldingsCloudRemote(api, session, identity)
        return AccountWorkspace(store, HoldingsCloudSync(store, remote, isCurrent))
    }

    suspend fun erase(userId: Long) = withContext(Dispatchers.IO) {
        try {
            AccountHoldingsStore.erase(appContext, userId)
        } finally {
            HoldingAlertsMonitor.erase(appContext, "user-$userId")
        }
    }
}

@Stable
internal class AccountWorkspace(val store: AccountHoldingsStore, val sync: HoldingsCloudSync)
