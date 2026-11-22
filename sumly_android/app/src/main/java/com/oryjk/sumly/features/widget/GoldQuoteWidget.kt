package com.oryjk.sumly.features.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import androidx.compose.ui.graphics.toArgb
import com.oryjk.sumly.R
import com.oryjk.sumly.bootstrap.MainActivity
import com.oryjk.sumly.core.network.ApiClient
import com.oryjk.sumly.design.GoldColors
import com.oryjk.sumly.features.market.BackendGoldMarketService
import com.oryjk.sumly.features.market.MarketBasis
import com.oryjk.sumly.features.market.MarketChartLogic
import com.oryjk.sumly.features.market.MarketQuote
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull

class GoldQuoteWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, widgetIds: IntArray) {
        if (widgetIds.isEmpty()) return
        val pending = goAsync()
        val app = context.applicationContext
        scope.launch {
            try {
                // Bound the whole receiver update, including time waiting on another update.
                withTimeoutOrNull(8_000L) {
                    updateLock.withLock {
                        refresh(app, manager, widgetIds)
                    }
                }
            } finally {
                pending.finish()
            }
        }
    }

    private suspend fun refresh(context: Context, manager: AppWidgetManager, widgetIds: IntArray) {
        val basis = currentBasis(context)
        val market = BackendGoldMarketService(ApiClient(), File(context.cacheDir, "sumly-widget-quotes"))
        val fresh = withTimeoutOrNull(5_000L) {
            try {
                market.fetchQuote(basis).takeIf { it.cnyPerGram != null }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                null
            }
        }
        val quote = fresh ?: market.cachedQuote(basis)?.takeIf { it.cnyPerGram != null }
        if (basis == currentBasis(context)) {
            manager.updateAppWidget(widgetIds, render(context, basis, quote, isCached = fresh == null))
        }
    }

    private fun render(context: Context, basis: MarketBasis, quote: MarketQuote?, isCached: Boolean): RemoteViews {
        val openApp = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return RemoteViews(context.packageName, R.layout.gold_quote_widget).apply {
            setOnClickPendingIntent(R.id.gold_quote_widget, openApp)
            setTextViewText(R.id.gold_quote_basis, basis.nameInChinese)
            val price = quote?.cnyPerGram
            setTextColor(R.id.gold_quote_change, GoldColors.Muted.toArgb())
            if (quote == null || price == null) {
                setTextViewText(R.id.gold_quote_price, context.getText(R.string.widget_gold_quote_unavailable_price))
                setTextViewText(R.id.gold_quote_change, context.getText(R.string.widget_gold_quote_unavailable))
                setTextViewText(R.id.gold_quote_time, context.getText(R.string.widget_gold_quote_open))
                return@apply
            }

            setTextViewText(R.id.gold_quote_price, String.format(Locale.CHINA, "%,.2f", price))
            val change = quote.changePerGram
            val percent = quote.changePercent
            if (change != null && percent != null) {
                val color = when {
                    change > 0 -> GoldColors.Up
                    change < 0 -> GoldColors.Down
                    else -> GoldColors.Muted
                }
                setTextViewText(R.id.gold_quote_change, String.format(Locale.CHINA, "%+.2f (%+.2f%%)", change, percent))
                setTextColor(R.id.gold_quote_change, color.toArgb())
            } else {
                setTextViewText(R.id.gold_quote_change, context.getText(R.string.widget_gold_quote_change_unavailable))
            }

            val now = Instant.now()
            val zone = ZoneId.systemDefault()
            val timestamp = quote.asOf.atZone(zone)
            val formatter = if (timestamp.toLocalDate() == now.atZone(zone).toLocalDate()) updateTime else updateDate
            val status = when {
                isCached -> R.string.widget_gold_quote_cached
                MarketChartLogic.isQuoteStale(quote.asOf, now) -> R.string.widget_gold_quote_delayed
                else -> R.string.widget_gold_quote_updated
            }
            setTextViewText(R.id.gold_quote_time, context.getString(status, formatter.format(timestamp)))
        }
    }

    companion object {
        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        private val updateLock = Mutex()
        private val updateTime = DateTimeFormatter.ofPattern("HH:mm", Locale.CHINA)
        private val updateDate = DateTimeFormatter.ofPattern("MM-dd HH:mm", Locale.CHINA)

        internal fun requestRefresh(context: Context) {
            val component = ComponentName(context, GoldQuoteWidget::class.java)
            val ids = AppWidgetManager.getInstance(context).getAppWidgetIds(component)
            if (ids.isNotEmpty()) {
                context.sendBroadcast(
                    Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).setComponent(component)
                        .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids),
                )
            }
        }

        private fun currentBasis(context: Context): MarketBasis {
            val stored = context.getSharedPreferences("sumly_market", Context.MODE_PRIVATE).getString("basis", null)
            return MarketBasis.entries.firstOrNull { it.name == stored } ?: MarketBasis.Domestic
        }
    }
}
