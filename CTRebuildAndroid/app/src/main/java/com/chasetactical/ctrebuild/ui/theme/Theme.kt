package com.chasetactical.ctrebuild.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val CTColorScheme = darkColorScheme(
    primary          = Color(0xFFFF9500),
    onPrimary        = Color(0xFF111111),
    background       = Color(0xFF000000),
    onBackground     = Color(0xFFFFFFFF),
    surface          = Color(0xFF151515),
    onSurface        = Color(0xFFFFFFFF),
    surfaceVariant   = Color(0xFF1A1A1A),
    onSurfaceVariant = Color(0xFFB7B7B7),
    outline          = Color(0xFF3A3A3A),
)

@Composable
fun CTRebuildTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = CTColorScheme,
        content = content
    )
}
