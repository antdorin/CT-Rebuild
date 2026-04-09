package com.chasetactical.ctrebuild.ui.camera

import android.graphics.SurfaceTexture
import android.view.Surface
import android.view.TextureView
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import kotlin.math.min
import kotlin.math.roundToInt

private val overlayColor = Color(0xFFFF9500)

@Composable
fun CameraPreviewView(
    viewModel: CameraViewModel,
    modifier: Modifier = Modifier
) {
    val overlays  = viewModel.currentOverlays
    val zoomRatio by viewModel.zoomRatio
    val minZoom   by viewModel.minZoom
    val maxZoom   by viewModel.maxZoom

    // Fraction 0..1 of the current zoom between minZoom and maxZoom
    val zoomFraction = ((zoomRatio - minZoom) / (maxZoom - minZoom).coerceAtLeast(0.01f)).coerceIn(0f, 1f)

    Box(
        modifier = modifier.onSizeChanged { size ->
            viewModel.viewWidth  = size.width
            viewModel.viewHeight = size.height
        }
    ) {
        AndroidView(
            factory = { ctx ->
                TextureView(ctx).also { tv ->
                    tv.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                        override fun onSurfaceTextureAvailable(st: SurfaceTexture, w: Int, h: Int) {
                            viewModel.bindCamera(ctx, Surface(st))
                        }
                        override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean {
                            viewModel.onSurfaceDestroyed()
                            return true
                        }
                        override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, w: Int, h: Int) {}
                        override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}
                    }
                }
            },
            modifier = Modifier.fillMaxSize()
        )

        // ── Left-side slider column: visual + gesture + label + sensitivity button ──
        Box(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .fillMaxHeight()
                .width(88.dp)
        ) {
            // Visual slider (narrow, left-inset, centred vertically)
            Box(
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .padding(start = 10.dp)
                    .width(28.dp)
                    .fillMaxHeight(0.70f)
                    .alpha(0.40f)
                    .drawBehind {
                        val trackW = 6.dp.toPx()
                        val trackX = (size.width - trackW) / 2f
                        drawRoundRect(
                            color        = Color(0xFF888888),
                            topLeft      = Offset(trackX, 0f),
                            size         = Size(trackW, size.height),
                            cornerRadius = CornerRadius(trackW / 2)
                        )
                        val fillH = size.height * zoomFraction
                        drawRoundRect(
                            color        = Color(0xFFFF9500),
                            topLeft      = Offset(trackX, size.height - fillH),
                            size         = Size(trackW, fillH),
                            cornerRadius = CornerRadius(trackW / 2)
                        )
                        val thumbY = size.height - size.height * zoomFraction
                        val thumbR = 10.dp.toPx()
                        drawCircle(
                            color  = Color.White,
                            radius = thumbR,
                            center = Offset(size.width / 2f, thumbY)
                        )
                    }
            )
            // Wide invisible gesture zone
            Box(
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .fillMaxWidth()
                    .fillMaxHeight(0.70f)
                    .pointerInput(Unit) {
                        val trackHeightPx = size.height.toFloat()
                        awaitEachGesture {
                            val down = awaitFirstDown(requireUnconsumed = false)
                            down.consume()
                            viewModel.isDraggingZoom.value = true
                            try {
                                while (true) {
                                    val event  = awaitPointerEvent()
                                    val change = event.changes.firstOrNull() ?: break
                                    if (!change.pressed) break
                                    val dy = change.positionChange().y
                                    change.consume()
                                    val currentFraction = ((viewModel.zoomRatio.value - viewModel.minZoom.value) /
                                        (viewModel.maxZoom.value - viewModel.minZoom.value).coerceAtLeast(0.01f)).coerceIn(0f, 1f)
                                    val delta = -dy * viewModel.dragSensitivity.value / trackHeightPx.coerceAtLeast(1f)
                                    val newFraction = (currentFraction + delta).coerceIn(0f, 1f)
                                    viewModel.setZoom(viewModel.minZoom.value + newFraction * (viewModel.maxZoom.value - viewModel.minZoom.value))
                                }
                            } finally {
                                viewModel.isDraggingZoom.value = false
                            }
                        }
                    }
            )
            // Zoom label + sensitivity button, below the slider
            Column(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(start = 12.dp, bottom = 10.dp),
                horizontalAlignment = Alignment.Start
            ) {
                val label = if (zoomRatio >= 10f) "${zoomRatio.roundToInt()}x"
                            else "${"%.1f".format(zoomRatio)}x"
                Text(
                    text     = label,
                    color    = Color(0xFFFF9500),
                    fontSize = 14.sp,
                    modifier = Modifier.alpha(0.90f)
                )
                Spacer(Modifier.height(5.dp))
                ZoomSensitivityButton(viewModel)
            }
        }

        // Barcode tracking overlays (KLT-smoothed, multi-target)
        if (overlays.isNotEmpty()) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val sw = 3.dp.toPx()
                for (ov in overlays) {
                    val rect = ov.bounds
                    val cLen = min(rect.width(), rect.height()) * 0.22f

                    drawLine(overlayColor, Offset(rect.left,  rect.top    + cLen), Offset(rect.left,           rect.top   ), sw)
                    drawLine(overlayColor, Offset(rect.left,  rect.top        ), Offset(rect.left  + cLen, rect.top   ), sw)
                    drawLine(overlayColor, Offset(rect.right - cLen, rect.top ), Offset(rect.right,          rect.top   ), sw)
                    drawLine(overlayColor, Offset(rect.right, rect.top        ), Offset(rect.right,          rect.top   + cLen), sw)
                    drawLine(overlayColor, Offset(rect.left,  rect.bottom - cLen), Offset(rect.left,         rect.bottom), sw)
                    drawLine(overlayColor, Offset(rect.left,  rect.bottom     ), Offset(rect.left  + cLen, rect.bottom), sw)
                    drawLine(overlayColor, Offset(rect.right, rect.bottom - cLen), Offset(rect.right,        rect.bottom), sw)
                    drawLine(overlayColor, Offset(rect.right, rect.bottom     ), Offset(rect.right - cLen, rect.bottom), sw)
                }
            }
        }
    }
}

private val sensitivityLevels = listOf(1.0f, 1.5f, 2.0f, 3.0f, 5.0f)

/** Small bar-graph button that cycles through 5 drag-sensitivity levels on tap.
 *  More filled bars = shorter drag needed to reach max zoom. */
@Composable
private fun ZoomSensitivityButton(viewModel: CameraViewModel) {
    val sensitivity by viewModel.dragSensitivity
    val level = sensitivityLevels.indexOf(sensitivity).coerceAtLeast(0) + 1  // 1..5

    Box(
        modifier = Modifier
            .size(width = 46.dp, height = 28.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(Color(0xFF1A1A1A))
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    down.consume()
                    val up = waitForUpOrCancellation()
                    if (up != null) {
                        up.consume()
                        viewModel.cycleSensitivity()
                    }
                }
            },
        contentAlignment = Alignment.Center
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            verticalAlignment     = Alignment.Bottom,
            modifier = Modifier.padding(horizontal = 5.dp, vertical = 3.dp)
        ) {
            // 5 bars of increasing height — filled in orange up to current level
            listOf(8, 11, 14, 17, 20).forEachIndexed { i, barHeightDp ->
                Box(
                    modifier = Modifier
                        .width(4.dp)
                        .height(barHeightDp.dp)
                        .clip(RoundedCornerShape(1.dp))
                        .background(
                            if (i < level) Color(0xFFFF9500) else Color(0xFF3A3A3A)
                        )
                )
            }
        }
    }
}