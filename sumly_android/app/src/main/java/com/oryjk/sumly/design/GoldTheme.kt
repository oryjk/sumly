package com.oryjk.sumly.design

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

// Keep the visual and financial semantics aligned with the iOS GoldTheme.
object GoldColors {
    val Background = Color(0xFF1B1B1D)
    val Surface = Color(0xFF282523)
    val SurfaceElevated = Color(0xFF34312F)
    val Text = Color(0xFFF2F2F5)
    val Muted = Color(0xFFA3A3A3)
    val Faint = Color(0xFF6C6C76)
    val Gold = Color(0xFFF2C512)
    val GoldSoft = Color(0xFFFFE08A)
    val OnGold = Color(0xFF1A1A1A)
    val Border = Color.White.copy(alpha = 0.07f)
    val Up = Color(0xFFFF5D5D)
    val Down = Color(0xFF3DD68C)
    val TempFreezing = Color(0xFF56B4E9)
    val TempWarm = Color(0xFFF59E0B)
}

private val scheme = darkColorScheme(
    primary = GoldColors.Gold,
    onPrimary = GoldColors.OnGold,
    primaryContainer = GoldColors.SurfaceElevated,
    onPrimaryContainer = GoldColors.GoldSoft,
    secondary = GoldColors.GoldSoft,
    onSecondary = GoldColors.OnGold,
    background = GoldColors.Background,
    onBackground = GoldColors.Text,
    surface = GoldColors.Surface,
    onSurface = GoldColors.Text,
    surfaceVariant = GoldColors.SurfaceElevated,
    onSurfaceVariant = GoldColors.Muted,
    outline = GoldColors.Faint,
    outlineVariant = GoldColors.Border,
    error = GoldColors.Up,
)

private val shapes = Shapes(
    small = RoundedCornerShape(8.dp),
    medium = RoundedCornerShape(12.dp),
    large = RoundedCornerShape(16.dp),
    extraLarge = RoundedCornerShape(20.dp),
)

@Composable
fun GoldTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = scheme, shapes = shapes, content = content)
}
