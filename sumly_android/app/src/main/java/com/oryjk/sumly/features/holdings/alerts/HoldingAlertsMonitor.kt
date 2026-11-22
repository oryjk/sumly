package com.oryjk.sumly.features.holdings.alerts

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.oryjk.sumly.features.holdings.HoldingDisposition
import com.oryjk.sumly.features.holdings.HoldingRecord
import com.oryjk.sumly.features.holdings.HoldingsSnapshot
import com.oryjk.sumly.features.market.MarketBasis
import com.oryjk.sumly.features.market.MarketQuote
import java.security.MessageDigest
import java.time.Instant
import java.util.Base64
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import org.json.JSONObject

/** Foreground-only runtime baselines, independent of the cloud document. */
internal class HoldingAlertsMonitor(context: Context, private val workspace: String) {
    private val app = context.applicationContext
    private val preferences = app.getSharedPreferences(preferenceName(workspace), Context.MODE_PRIVATE)
    private val notifications = requireNotNull(app.getSystemService(NotificationManager::class.java))

    suspend fun check(
        snapshot: HoldingsSnapshot,
        quote: suspend (MarketBasis) -> MarketQuote?,
        isCurrent: () -> Boolean,
    ) {
        if (!isCurrent()) return
        val configured = snapshot.records.asSequence()
            .filter { it.disposition == HoldingDisposition.Holding }
            .flatMap { record -> record.alerts.asSequence().map { alert -> Candidate(record, alert) } }
            .associateBy { it.key }
        removeInactive(configured)

        val byBasis = configured.values.filter { it.alert.canCheck }.groupBy { it.alert.basis }
        if (byBasis.isEmpty() || !allowed(app)) return
        for ((basis, candidates) in byBasis) {
            currentCoroutineContext().ensureActive()
            if (!isCurrent()) return
            val latest = try {
                quote(basis)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                null
            } ?: continue
            val price = latest.cnyPerGram ?: continue
            val now = Instant.now()
            for (candidate in candidates) {
                currentCoroutineContext().ensureActive()
                if (!isCurrent()) return
                val previous = previousState(candidate)
                val evaluated = evaluateHoldingAlert(candidate.alert, candidate.record.input, previous, price, latest.asOf, now)
                if (evaluated.state == previous) continue
                if (evaluated.triggered && !send(candidate.key)) continue
                if (!isCurrent()) {
                    if (evaluated.triggered) notifications.cancel(tag(workspace, candidate.key), 0)
                    return
                }
                writeState(candidate, evaluated.state)
            }
        }
    }

    fun clearNotifications() {
        preferences.all.keys.forEach { notifications.cancel(tag(workspace, it), 0) }
    }

    private fun removeInactive(configured: Map<String, Candidate>) {
        val saved = preferences.all
        val removed = saved.keys - configured.keys
        val disabled = configured.values.filter { !it.alert.canCheck && it.key in saved }
        if (removed.isNotEmpty() || disabled.isNotEmpty()) {
            val editor = preferences.edit()
            removed.forEach { key ->
                notifications.cancel(tag(workspace, key), 0)
                editor.remove(key)
            }
            disabled.forEach { candidate ->
                val previous = previousState(candidate)
                // Disabled alerts retain their device cooldown only.
                if (previous.lastTriggeredAt != null) {
                    val value = stateJson(candidate, HoldingAlertState(lastTriggeredAt = previous.lastTriggeredAt))
                    if (value == saved[candidate.key]) return@forEach
                    editor.putString(candidate.key, value)
                } else {
                    editor.remove(candidate.key)
                }
                notifications.cancel(tag(workspace, candidate.key), 0)
            }
            editor.apply()
        }
    }

    private fun previousState(candidate: Candidate): HoldingAlertState = runCatching {
        val saved = preferences.getString(candidate.key, null) ?: return HoldingAlertState()
        val json = JSONObject(saved)
        val fired = json.optString("lastTriggeredAt").takeUnless(String::isEmpty)?.let(Instant::parse)
        if (json.getString("configuration") != candidate.configuration) HoldingAlertState(lastTriggeredAt = fired)
        else HoldingAlertState(
            previousPrice = json.optDouble("previousPrice").takeIf { it.isFinite() && it > 0 },
            previousAsOf = json.optString("previousAsOf").takeUnless(String::isEmpty)?.let(Instant::parse),
            armed = json.optBoolean("armed"),
            lastTriggeredAt = fired,
        )
    }.getOrDefault(HoldingAlertState())

    private fun writeState(candidate: Candidate, state: HoldingAlertState) =
        preferences.edit().putString(candidate.key, stateJson(candidate, state)).apply()

    private fun stateJson(candidate: Candidate, state: HoldingAlertState) = JSONObject()
        .put("configuration", candidate.configuration)
        .put("previousPrice", state.previousPrice)
        .put("previousAsOf", state.previousAsOf?.toString())
        .put("armed", state.armed)
        .put("lastTriggeredAt", state.lastTriggeredAt?.toString())
        .toString()

    @SuppressLint("MissingPermission")
    private fun send(key: String): Boolean {
        if (!allowed(app)) return false
        return try {
            notifications.createNotificationChannel(NotificationChannel(Channel, "持仓提醒", NotificationManager.IMPORTANCE_DEFAULT))
            val notification = Notification.Builder(app, Channel)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("记金 · 持仓提醒")
                .setContentText("持仓已达到你设置的提醒目标。")
                .setVisibility(Notification.VISIBILITY_SECRET)
                .setAutoCancel(true)
            app.packageManager.getLaunchIntentForPackage(app.packageName)?.let { launch ->
                notification.setContentIntent(PendingIntent.getActivity(app, 0, launch, PendingIntent.FLAG_IMMUTABLE))
            }
            notifications.notify(tag(workspace, key), 0, notification.build())
            true
        } catch (_: SecurityException) {
            false
        }
    }

    private data class Candidate(val record: HoldingRecord, val alert: HoldingAlert) {
        val key: String get() = "${record.id}-${alert.id}"
        val configuration: String
            get() {
                val input = "${alert.kind.key}|${alert.basis.name}|${alert.threshold}|${alert.enabled}|${record.input}"
                val digest = MessageDigest.getInstance("SHA-256").digest(input.toByteArray())
                return Base64.getEncoder().encodeToString(digest)
            }
    }

    companion object {
        private const val Channel = "holding-alerts"
        private fun preferenceName(workspace: String) = "holding_alerts_$workspace"
        private fun tag(workspace: String, key: String) = "holding-alert-$workspace-$key"

        fun allowed(context: Context): Boolean {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return false
            return canPost(context) && manager.areNotificationsEnabled() &&
                manager.getNotificationChannel(Channel)?.importance != NotificationManager.IMPORTANCE_NONE
        }

        fun canPost(context: Context): Boolean = Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

        fun erase(context: Context, workspace: String) {
            HoldingAlertsMonitor(context, workspace).clearNotifications()
            context.deleteSharedPreferences(preferenceName(workspace))
        }
    }
}
