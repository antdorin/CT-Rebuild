package com.chasetactical.ctrebuild.ui.panels

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import com.chasetactical.ctrebuild.ui.settings.HubSettingsView

/** Full-screen Server / Hub-settings panel. Swipe right to close. */
@Composable
fun ServerPanel(onClose: () -> Unit, onHubUrlChanged: () -> Unit = {}) {
    val density   = LocalDensity.current
    val threshold = with(density) { 80.dp.toPx() }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0F0F0F))
            .pointerInput(Unit) {
                var total = 0f
                detectHorizontalDragGestures(
                    onDragStart      = { total = 0f },
                    onDragEnd        = { total = 0f },
                    onDragCancel     = { total = 0f },
                    onHorizontalDrag = { change, amount ->
                        change.consume()
                        total += amount
                        if (total > threshold) { onClose(); total = 0f }
                    }
                )
            }
    ) {
        HubSettingsView(
            onBack     = onClose,
            onUrlSaved = onHubUrlChanged
        )
    }
}
