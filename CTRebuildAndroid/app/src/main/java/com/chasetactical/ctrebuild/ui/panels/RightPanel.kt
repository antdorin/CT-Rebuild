package com.chasetactical.ctrebuild.ui.panels

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import com.chasetactical.ctrebuild.ui.reader.PdfBrowserView

/** PDF Browser page — swipe right to close. */
@Composable
fun RightPanel(onClose: () -> Unit, onHubUrlChanged: () -> Unit = {}) {
    var readerOpen by remember { mutableStateOf(false) }
    val density   = LocalDensity.current
    val threshold = with(density) { 80.dp.toPx() }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0F0F0F))
            .then(if (!readerOpen) Modifier.pointerInput(Unit) {
                var total = 0f
                detectHorizontalDragGestures(
                    onDragStart  = { total = 0f },
                    onDragEnd    = { total = 0f },
                    onDragCancel = { total = 0f },
                    onHorizontalDrag = { change, amount ->
                        change.consume()
                        total += amount
                        if (total > threshold) { onClose(); total = 0f }
                    }
                )
            } else Modifier)
    ) {
        PdfBrowserView(
            onClose              = onClose,
            onNavigateToSettings = {},
            onReaderStateChanged = { readerOpen = it },
            autoOpenLatest       = true
        )
    }
}
