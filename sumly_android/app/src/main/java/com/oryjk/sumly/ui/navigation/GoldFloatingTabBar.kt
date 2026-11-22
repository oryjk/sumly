package com.oryjk.sumly.ui.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ShowChart
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.oryjk.sumly.R
import com.oryjk.sumly.design.GoldColors

private val holdingBag = ImageVector.Builder("Gold money bag", 20.dp, 20.dp, 100f, 100f).apply {
    path(fill = SolidColor(Color.Black)) {
        moveTo(29f, 4f)
        quadTo(34f, -1f, 50f, 5.5f)
        quadTo(66f, -1.5f, 73f, 4f)
        quadTo(82f, 16f, 67f, 24f)
        quadTo(50f, 29f, 32f, 24f)
        quadTo(20f, 14f, 29f, 4f)
        close()
        moveTo(32f, 33f)
        quadTo(50f, 37f, 68f, 33f)
        curveTo(80f, 46f, 96f, 68f, 88f, 85f)
        quadTo(86f, 98f, 70f, 98f)
        lineTo(30f, 98f)
        quadTo(14f, 98f, 12f, 85f)
        curveTo(4f, 68f, 20f, 46f, 32f, 33f)
        close()
    }
}.build()

internal enum class SumlyTab(val label: Int, val icon: ImageVector) {
    Market(R.string.tab_market, Icons.AutoMirrored.Outlined.ShowChart),
    Holdings(R.string.tab_holdings, holdingBag),
    Calendar(R.string.tab_calendar, Icons.Filled.CalendarMonth),
    Account(R.string.tab_account, Icons.Filled.Person),
}

private val capsule = RoundedCornerShape(32.dp)

@Composable
internal fun GoldFloatingTabBar(
    selection: SumlyTab,
    onSelect: (SumlyTab) -> Unit,
    onAdd: () -> Unit,
) {
    val haptic = LocalHapticFeedback.current
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(Brush.verticalGradient(listOf(GoldColors.Background.copy(alpha = 0f), GoldColors.Background)))
            .navigationBarsPadding()
            .padding(start = 16.dp, end = 16.dp, bottom = 9.dp, top = 5.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            modifier = Modifier.widthIn(max = 560.dp).fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                modifier = Modifier.weight(1f)
                    .shadow(8.dp, capsule)
                    .border(1.dp, GoldColors.Border, capsule)
                    .background(GoldColors.Surface, capsule)
                    .padding(4.dp)
                    .selectableGroup(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SumlyTab.entries.forEach { tab ->
                    val active = tab == selection
                    val color = if (active) GoldColors.Gold else GoldColors.Muted
                    Column(
                        modifier = Modifier.weight(1f)
                            .heightIn(min = 48.dp)
                            .clip(capsule)
                            .background(if (active) GoldColors.Gold.copy(alpha = 0.14f) else GoldColors.Surface)
                            .selectable(selected = active, role = Role.Tab) {
                                if (!active) {
                                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                    onSelect(tab)
                                }
                            }
                            .padding(vertical = 4.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Icon(tab.icon, contentDescription = null, tint = color, modifier = Modifier.size(20.dp))
                        Text(
                            stringResource(tab.label),
                            color = color,
                            fontWeight = if (active) FontWeight.SemiBold else FontWeight.Medium,
                            style = MaterialTheme.typography.labelSmall,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
            FloatingActionButton(
                onClick = onAdd,
                modifier = Modifier.size(56.dp),
                shape = CircleShape,
                containerColor = GoldColors.Gold,
                contentColor = GoldColors.OnGold,
            ) {
                Icon(Icons.Outlined.Add, stringResource(R.string.add_holding), modifier = Modifier.size(28.dp))
            }
        }
    }
}
