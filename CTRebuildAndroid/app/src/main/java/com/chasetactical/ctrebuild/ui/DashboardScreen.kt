package com.chasetactical.ctrebuild.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.*
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.Image
import androidx.compose.ui.res.painterResource
import com.chasetactical.ctrebuild.R
import com.chasetactical.ctrebuild.ui.panels.*
import kotlin.math.abs
import kotlinx.coroutines.withTimeoutOrNull

enum class AppPage {
    NONE,
    PDF_BROWSER, PAGE_2, PAGE_3, PAGE_4, PAGE_5,
    BIN_GRID, WEATHER, SERVER, CAMERA
}

@Composable
fun DashboardScreen(onHubUrlChanged: () -> Unit = {}) {
    var activePage       by remember { mutableStateOf(AppPage.NONE) }
    var showPageOverview by remember { mutableStateOf(false) }

    val density = LocalDensity.current
    val swipeThresholdPx = with(density) { 60.dp.toPx() }

    // Back button: close overview first, then close current page
    BackHandler(enabled = showPageOverview || activePage != AppPage.NONE) {
        if (showPageOverview) showPageOverview = false
        else activePage = AppPage.NONE
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            // Swipe navigation — disabled while overview or a panel is open
            .then(
                if (activePage == AppPage.NONE && !showPageOverview)
                    Modifier.pointerInput(activePage, showPageOverview) {
                        var totalX = 0f
                        var totalY = 0f
                        detectDragGestures(
                            onDragStart  = { totalX = 0f; totalY = 0f },
                            onDragEnd    = { totalX = 0f; totalY = 0f },
                            onDragCancel = { totalX = 0f; totalY = 0f },
                            onDrag = { change, dragAmount ->
                                change.consume()
                                totalX += dragAmount.x
                                totalY += dragAmount.y
                                val absX = abs(totalX)
                                val absY = abs(totalY)
                                if (absX >= swipeThresholdPx && absX >= absY * 1.5f) {
                                    activePage = if (totalX > 0) AppPage.BIN_GRID else AppPage.PDF_BROWSER
                                    totalX = 0f; totalY = 0f
                                } else if (absY >= swipeThresholdPx && absY >= absX * 1.5f) {
                                    activePage = if (totalY > 0) AppPage.WEATHER else AppPage.CAMERA
                                    totalX = 0f; totalY = 0f
                                }
                            }
                        )
                    }
                else Modifier
            )
            // 200ms hold anywhere on the dashboard → show 3×3 page overview
            .then(
                if (activePage == AppPage.NONE && !showPageOverview)
                    Modifier.pointerInput(activePage, showPageOverview) {
                        awaitEachGesture {
                            val down = awaitFirstDown(requireUnconsumed = false)
                            // withTimeoutOrNull returns null when 200ms elapses with no release/movement
                            val completed = withTimeoutOrNull(200L) {
                                while (true) {
                                    val event  = awaitPointerEvent()
                                    val change = event.changes.firstOrNull()
                                        ?: return@withTimeoutOrNull true
                                    if (!change.pressed) return@withTimeoutOrNull true
                                    val dist = (change.position - down.position).getDistance()
                                    if (dist > viewConfiguration.touchSlop)
                                        return@withTimeoutOrNull true
                                }
                                @Suppress("UNREACHABLE_CODE") true
                            }
                            if (completed == null) showPageOverview = true
                        }
                    }
                else Modifier
            )
    ) {

        DashboardWidgetLayout()

        // Scrim
        AnimatedVisibility(
            visible = activePage != AppPage.NONE,
            enter = fadeIn(tween(140)),
            exit  = fadeOut(tween(140))
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color(0x80000000))
                    .clickable { activePage = AppPage.NONE }
            )
        }

        // PDF Browser page
        AnimatedVisibility(
            visible = activePage == AppPage.PDF_BROWSER,
            modifier = Modifier.fillMaxSize().align(Alignment.CenterEnd),
            enter = slideInHorizontally(tween(140)) { it },
            exit  = slideOutHorizontally(tween(140)) { it }
        ) {
            Box(Modifier.fillMaxSize().panelMotionBlur(140)) {
                RightPanel(
                    onClose         = { activePage = AppPage.NONE },
                    onHubUrlChanged = onHubUrlChanged
                )
            }
        }

        // Page 2
        AnimatedVisibility(
            visible = activePage == AppPage.PAGE_2,
            modifier = Modifier.fillMaxSize().align(Alignment.CenterEnd),
            enter = slideInHorizontally(tween(140)) { it },
            exit  = slideOutHorizontally(tween(140)) { it }
        ) {
            Box(Modifier.fillMaxSize().panelMotionBlur(140)) {
                PlaceholderPage(title = "Page 2", onClose = { activePage = AppPage.NONE })
            }
        }

        // Page 3
        AnimatedVisibility(
            visible = activePage == AppPage.PAGE_3,
            modifier = Modifier.fillMaxSize().align(Alignment.CenterEnd),
            enter = slideInHorizontally(tween(140)) { it },
            exit  = slideOutHorizontally(tween(140)) { it }
        ) {
            Box(Modifier.fillMaxSize().panelMotionBlur(140)) {
                PlaceholderPage(title = "Page 3", onClose = { activePage = AppPage.NONE })
            }
        }

        // Bin Grid page
        AnimatedVisibility(
            visible = activePage == AppPage.BIN_GRID,
            modifier = Modifier.fillMaxSize().align(Alignment.CenterStart),
            enter = slideInHorizontally(tween(140)) { -it },
            exit  = slideOutHorizontally(tween(140)) { -it }
        ) {
            Box(Modifier.fillMaxSize().panelMotionBlur(140)) {
                LeftPanel(onClose = { activePage = AppPage.NONE })
            }
        }

        // Weather / Top page
        AnimatedVisibility(
            visible = activePage == AppPage.WEATHER,
            modifier = Modifier.fillMaxSize().align(Alignment.TopCenter),
            enter = slideInVertically(tween(140)) { -it },
            exit  = slideOutVertically(tween(140)) { -it }
        ) {
            Box(Modifier.fillMaxSize().panelMotionBlur(140)) {
                TopPanel(onClose = { activePage = AppPage.NONE })
            }
        }

        // Camera page
        AnimatedVisibility(
            visible = activePage == AppPage.CAMERA,
            modifier = Modifier.fillMaxSize().align(Alignment.BottomCenter),
            enter = slideInVertically(tween(140)) { it },
            exit  = slideOutVertically(tween(140)) { it }
        ) {
            Box(Modifier.fillMaxSize().panelMotionBlur(140)) {
                BottomPanel(onClose = { activePage = AppPage.NONE })
            }
        }

        // Page 4
        AnimatedVisibility(
            visible = activePage == AppPage.PAGE_4,
            modifier = Modifier.fillMaxSize().align(Alignment.CenterEnd),
            enter = slideInHorizontally(tween(140)) { it },
            exit  = slideOutHorizontally(tween(140)) { it }
        ) {
            Box(Modifier.fillMaxSize().panelMotionBlur(140)) {
                PlaceholderPage(title = "Page 4", onClose = { activePage = AppPage.NONE })
            }
        }

        // Page 5
        AnimatedVisibility(
            visible = activePage == AppPage.PAGE_5,
            modifier = Modifier.fillMaxSize().align(Alignment.CenterEnd),
            enter = slideInHorizontally(tween(140)) { it },
            exit  = slideOutHorizontally(tween(140)) { it }
        ) {
            Box(Modifier.fillMaxSize().panelMotionBlur(140)) {
                PlaceholderPage(title = "Page 5", onClose = { activePage = AppPage.NONE })
            }
        }

        // Server page
        AnimatedVisibility(
            visible = activePage == AppPage.SERVER,
            modifier = Modifier.fillMaxSize().align(Alignment.CenterEnd),
            enter = slideInHorizontally(tween(140)) { it },
            exit  = slideOutHorizontally(tween(140)) { it }
        ) {
            Box(Modifier.fillMaxSize().panelMotionBlur(140)) {
                ServerPanel(
                    onClose         = { activePage = AppPage.NONE },
                    onHubUrlChanged = onHubUrlChanged
                )
            }
        }

        // Page overview grid — displayed on 200ms hold, sits above all pages
        if (showPageOverview) {
            PageOverviewGrid(
                onDismiss      = { showPageOverview = false },
                onPageSelected = { idx ->
                    activePage = overviewIndexToPage(idx)
                    showPageOverview = false
                }
            )
        }
    }
}

@Composable
private fun DashboardWidgetLayout() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Image(
            painter = painterResource(id = R.drawable.cthelmet),
            contentDescription = null,
            modifier = Modifier.size(220.dp)
        )
    }
}

/** Standalone placeholder page — swipe right (or back) to close. */
@Composable
private fun PlaceholderPage(title: String, onClose: () -> Unit) {
    val density   = LocalDensity.current
    val threshold = with(density) { 80.dp.toPx() }
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0F0F0F))
            .pointerInput(Unit) {
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
            },
        contentAlignment = Alignment.Center
    ) {
        Text(title, color = Color(0xFFFF9500), fontSize = 24.sp)
    }
}

/** Animates a direction-aware blur from [startBlur]dp to 0 over [durationMs]ms on entry.
 *  Blur is applied along the axis of the slide (horizontal panels → blur X, vertical → blur Y).
 *  Gracefully no-ops on devices below API 31 since [BlurEffect] is silently ignored there. */
@Composable
private fun Modifier.panelMotionBlur(durationMs: Int = 140, startBlur: Float = 18f): Modifier {
    val radius = remember { Animatable(startBlur) }
    LaunchedEffect(Unit) {
        radius.animateTo(0f, animationSpec = tween(durationMs, easing = FastOutSlowInEasing))
    }
    return graphicsLayer {
        val r = radius.value
        if (r > 0.5f) {
            renderEffect = BlurEffect(r, r, TileMode.Decal)
            alpha = 0.85f + 0.15f * (1f - r / startBlur) // subtle fade-in alongside blur clear
        }
    }
}
