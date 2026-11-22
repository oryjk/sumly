package com.oryjk.sumly.features.holdings

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Circle
import androidx.compose.material.icons.filled.Diamond
import androidx.compose.material.icons.filled.ViewAgenda
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.oryjk.sumly.design.GoldColors
import java.io.File
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
internal fun HoldingReceiptContent(
    receipt: HoldingReceiptSnapshot,
    hidden: Boolean,
    onDone: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val imageLayer = rememberGraphicsLayer()
    val currentHidden by rememberUpdatedState(hidden)
    var preparing by remember { mutableStateOf(false) }
    var shareFailed by remember { mutableStateOf(false) }
    var cardLaidOut by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxWidth().padding(horizontal = 18.dp)) {
        Column(
            Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("入库成功", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            ReceiptCard(
                receipt, hidden,
                Modifier.fillMaxWidth().onSizeChanged { cardLaidOut = it.width > 0 && it.height > 0 }.drawWithContent {
                    imageLayer.record { this@drawWithContent.drawContent() }
                    drawLayer(imageLayer)
                },
            )
        }
        if (!hidden) {
            OutlinedButton(
                onClick = {
                    preparing = true
                    shareFailed = false
                    scope.launch {
                        try {
                            val bitmap = imageLayer.toImageBitmap().asAndroidBitmap()
                            val file = withContext(Dispatchers.IO) { writeReceiptImage(context, bitmap) }
                            if (!currentHidden) context.startActivity(receiptChooser(context, file))
                        } catch (cancelled: CancellationException) {
                            throw cancelled
                        } catch (_: Exception) {
                            shareFailed = true
                        } finally {
                            preparing = false
                        }
                    }
                },
                enabled = cardLaidOut && !preparing,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (preparing) "正在准备纪念卡…" else "分享纪念卡", color = GoldColors.Gold)
            }
            if (shareFailed) {
                Text("纪念卡暂时无法分享，请重试。", color = GoldColors.Up, style = MaterialTheme.typography.bodySmall)
            }
        }
        Button(
            onClick = onDone,
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 14.dp),
        ) { Text("完成") }
    }
}

@Composable
private fun ReceiptCard(receipt: HoldingReceiptSnapshot, hidden: Boolean, modifier: Modifier = Modifier) {
    val date = receipt.timestamp.atZone(ZoneId.systemDefault()).format(ReceiptDateFormat)
    val cardShape = MaterialTheme.shapes.extraLarge
    Column(
        modifier.background(GoldColors.Background).padding(2.dp)
            .background(Brush.linearGradient(listOf(GoldColors.SurfaceElevated, GoldColors.Background)), cardShape)
            .border(1.dp, GoldColors.GoldSoft.copy(alpha = 0.48f), cardShape)
            .padding(horizontal = 16.dp, vertical = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("记金 · 入库纪念卡", Modifier.weight(1f), color = GoldColors.GoldSoft)
            if (!hidden) {
                Text(
                    "第 ${receipt.purchaseSequence} 次攒金",
                    color = GoldColors.OnGold,
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.background(GoldColors.Gold, CircleShape).padding(horizontal = 8.dp, vertical = 5.dp),
                )
            }
        }
        Box(
            Modifier.size(74.dp).background(GoldColors.Background, CircleShape)
                .border(1.dp, GoldColors.Gold.copy(alpha = 0.55f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            val glyph = when (receipt.assetType) {
                HoldingAssetType.Bean -> Icons.Filled.Circle
                HoldingAssetType.Bar -> Icons.Filled.ViewAgenda
                HoldingAssetType.Jewelry -> Icons.Filled.Diamond
                HoldingAssetType.Accumulation, HoldingAssetType.Other -> Icons.Filled.AccountBalance
            }
            Icon(glyph, contentDescription = null, tint = GoldColors.Gold, modifier = Modifier.size(34.dp))
        }
        Text(
            if (hidden) "••••" else "+${holdingWeight(receipt.addedGrams, false)}",
            color = GoldColors.Gold, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold,
        )
        Text(
            if (hidden) "${receipt.assetType.title} · $date" else "${receipt.assetType.title} · $date · ${receipt.bookName}",
            color = GoldColors.Muted, style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.Center,
            maxLines = 2, overflow = TextOverflow.Ellipsis,
        )
        if (!hidden) receipt.newMilestone?.let { milestone ->
            Text("新解锁里程碑 · $milestone", color = GoldColors.GoldSoft, style = MaterialTheme.typography.labelMedium)
        }
        HorizontalDivider(color = GoldColors.Gold.copy(alpha = 0.24f))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ReceiptMetric("累计持有克重", holdingWeight(receipt.totalBookGrams, hidden), Modifier.weight(1f))
            ReceiptMetric("本次入库投入", holdingMoney(receipt.totalCost, hidden), Modifier.weight(1f))
        }
        if (!hidden) {
            Column(
                Modifier.fillMaxWidth().background(GoldColors.Background, MaterialTheme.shapes.medium).padding(10.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    val caption = receipt.nextMilestone?.let {
                        "距「$it」还差 ${holdingWeight(receipt.remainingGrams, false)}"
                    } ?: "已点亮全部 6 档攒金里程碑"
                    Text(caption, Modifier.weight(1f), color = GoldColors.GoldSoft, style = MaterialTheme.typography.labelMedium)
                    Text("${(receipt.progress * 100).roundToInt()}%", color = GoldColors.Gold)
                }
                LinearProgressIndicator(progress = { receipt.progress }, modifier = Modifier.fillMaxWidth())
            }
        }
    }
}

@Composable
private fun ReceiptMetric(title: String, value: String, modifier: Modifier = Modifier) {
    Column(
        modifier.background(GoldColors.Background, MaterialTheme.shapes.medium).padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Text(title, color = GoldColors.Muted, style = MaterialTheme.typography.labelSmall)
        Text(value, fontWeight = FontWeight.SemiBold, color = GoldColors.Text)
    }
}

private val ReceiptDateFormat = DateTimeFormatter.ofPattern("yyyy/MM/dd")

class HoldingReceiptFileProvider : FileProvider()

private fun writeReceiptImage(context: Context, bitmap: Bitmap): File {
    val cache = File(context.cacheDir, "holding-receipts")
    check(cache.isDirectory || cache.mkdirs())
    val expiration = System.currentTimeMillis() - 86_400_000L
    cache.listFiles()?.filter { it.lastModified() < expiration }?.forEach { it.delete() }
    val file = File.createTempFile("sumly-receipt-", ".png", cache)
    try {
        file.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
        return file
    } catch (error: Exception) {
        file.delete()
        throw error
    }
}

private fun receiptChooser(context: Context, file: File): Intent {
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.receipts", file)
    val share = Intent(Intent.ACTION_SEND).apply {
        type = "image/png"
        putExtra(Intent.EXTRA_STREAM, uri)
        clipData = ClipData.newRawUri("记金入库纪念卡", uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    return Intent.createChooser(share, "分享入库纪念卡")
}
