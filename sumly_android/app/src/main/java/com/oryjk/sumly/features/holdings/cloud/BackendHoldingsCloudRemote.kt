package com.oryjk.sumly.features.holdings.cloud

import com.oryjk.sumly.core.network.ApiClient
import com.oryjk.sumly.core.network.ApiException
import com.oryjk.sumly.features.account.AccountIdentity
import com.oryjk.sumly.features.account.AuthSession
import java.io.IOException
import org.json.JSONObject

internal class BackendHoldingsCloudRemote(
    private val api: ApiClient,
    private val session: AuthSession,
    private val identity: AccountIdentity,
) : HoldingsCloudRemote {
    override suspend fun fetch(): HoldingsCloudSnapshot = session.authorized(identity) { token ->
        HoldingCloudWire.decodeSnapshot(api.get(Path, accessToken = token, maxResponseBytes = MaxResponseBytes))
    }

    override suspend fun put(expectedRevision: Long, document: HoldingsCloudDocument): HoldingsCloudSnapshot {
        require(expectedRevision >= 0 && expectedRevision < Long.MAX_VALUE)
        val body = JSONObject()
            .put("expectedRevision", expectedRevision)
            .put("document", HoldingCloudWire.encodeDocument(document.validate()))
        if (body.toString().toByteArray(Charsets.UTF_8).size > HoldingsCloudMaxBytes) {
            throw IOException("账户账本记录过大。")
        }
        return try {
            session.authorized(identity) { token ->
                HoldingCloudWire.decodeSnapshot(api.put(Path, body, token, maxResponseBytes = MaxResponseBytes))
            }
        } catch (error: ApiException) {
            if (error.httpStatus == 409) throw HoldingsRevisionConflict()
            throw error
        }
    }

    private companion object {
        const val Path = "app/holdings"
        const val MaxResponseBytes = 4L * 1024 * 1024
    }
}
