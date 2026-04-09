package com.chasetactical.ctrebuild.ui

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.shape.RoundedCornerShape
import kotlinx.coroutines.launch

private data class OverviewPage(val label: String, val sub: String)

private val PAGES = listOf(
    OverviewPage("PDF Reader",  ""),
    OverviewPage("Page 2",      ""),
    OverviewPage("Page 3",      ""),
    OverviewPage("Bin Grid",    ""),
    OverviewPage("Dashboard",   ""),
    OverviewPage("Weather",     ""),
    OverviewPage("Page 4",      ""),
    OverviewPage("Page 5",      ""),
    OverviewPage("Server",      ""),
)

/** Maps a grid overview index to the corresponding [AppPage]. */
fun overviewIndexToPage(idx: Int): AppPage = when (idx) {
    0    -> AppPage.PDF_BROWSER
    1    -> AppPage.PAGE_2
    2    -> AppPage.PAGE_3
    3    -> AppPage.BIN_GRID
    4    -> AppPage.NONE        // Dashboard = go home
    5    -> AppPage.WEATHER
    6    -> AppPage.PAGE_4
    7    -> AppPage.PAGE_5
    8    -> AppPage.SERVER
    else -> AppPage.NONE
}

/**
 * Full-screen 3×3 page-picker overlay.
 *
 * Entry: 9 cards stagger-scale in.
 * Selection: tapped card zooms from its grid position to fill the screen,
 *   other cards fade, then [onPageSelected] is called.
 * Dismiss: tap the dark background or press back.
 */
@Composable
fun PageOverviewGrid(
    onDismiss:     () -> Unit,
    onPageSelected: (idx: Int) -> Unit,
) {
    val density = LocalDensity.current
    val scope   = rememberCoroutineScope()

    // Overall overlay fade-in
    val bgAlpha = remember { Animatable(0f) }
    LaunchedEffect(Unit) { bgAlpha.animateTo(1f, tween(200)) }

    // Per-card entrance animation state
    val cardScales = remember { List(9) { Animatable(0.72f) } }
    val cardAlphas = remember { List(9) { Animatable(0f) } }
    LaunchedEffect(Unit) {
        cardScales.forEachIndexed { i, a ->
            launch {
                kotlinx.coroutines.delay(i * 28L)
                a.animateTo(1f, spring(Spring.DampingRatioLowBouncy, Spring.StiffnessMediumLow))
            }
        }
        cardAlphas.forEachIndexed { i, a ->
            launch {
                kotlinx.coroutines.delay(i * 28L)
                a.animateTo(1f, tween(130))
            }
        }
    }

    // Zoom-in state for the selected card
    var zoomingIdx   by remember { mutableStateOf<Int?>(null) }
    val zoomProgress = remember { Animatable(0f) }

    // Read bg alpha in composition scope so graphicsLayer gets the current value
    val bgA = bgAlpha.value

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .graphicsLayer { alpha = bgA }
            .background(Color(0xEA000000))
            .clickable(
                indication        = null,
                interactionSource = remember { MutableInteractionSource() }
            ) { if (zoomingIdx == null) onDismiss() }
    ) {
        val swPx = with(density) { maxWidth.toPx() }
        val shPx = with(density) { maxHeight.toPx() }

        val hPad = 20.dp
        val vPad = 36.dp
        val gap  = 10.dp

        val cardW = (maxWidth  - hPad * 2 - gap * 2) / 3
        val cardH = (maxHeight - vPad * 2 - gap * 2) / 3

        val cardWpx = with(density) { cardW.toPx() }
        val cardHpx = with(density) { cardH.toPx() }
        val hPadPx  = with(density) { hPad.toPx() }
        val vPadPx  = with(density) { vPad.toPx() }
        val gapPx   = with(density) { gap.toPx() }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = hPad, vertical = vPad),
            verticalArrangement = Arrangement.spacedBy(gap)
        ) {
            repeat(3) { row ->
                Row(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(gap)
                ) {
                    repeat(3) { col ->
                        val idx  = row * 3 + col
                        val page = PAGES[idx]

                        val isZooming = zoomingIdx == idx
                        // Read animatable state values during composition so recomposition
                        // is triggered on every animation frame.
                        val prog     = if (isZooming) zoomProgress.value else 0f
                        val cScale   = cardScales[idx].value
                        val cAlpha   = cardAlphas[idx].value

                        // Card center in screen px — used to translate toward screen center
                        val cx       = hPadPx + col * (cardWpx + gapPx) + cardWpx / 2f
                        val cy       = vPadPx + row * (cardHpx + gapPx) + cardHpx / 2f
                        val txTarget = swPx / 2f - cx
                        val tyTarget = shPx / 2f - cy

                        // Text fades out in the first 33% of the zoom
                        val textAlpha = if (isZooming) (1f - prog * 3f).coerceIn(0f, 1f) else 1f

                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxHeight()
                                .graphicsLayer {
                                    scaleX       = if (isZooming) gridLerp(1f, swPx / cardWpx, prog) else cScale
                                    scaleY       = if (isZooming) gridLerp(1f, shPx / cardHpx, prog) else cScale
                                    alpha        = cAlpha
                                    translationX = if (isZooming) gridLerp(0f, txTarget, prog) else 0f
                                    translationY = if (isZooming) gridLerp(0f, tyTarget, prog) else 0f
                                    // Animate corner radius from 12dp → 0dp so edges align with screen
                                    shape        = RoundedCornerShape((12f * (1f - prog)).dp)
                                    clip         = true
                                }
                                // Dark background matching the panel color so the zoom looks seamless
                                .background(Color(0xFF0F0F0F))
                                .clickable(
                                    indication        = null,
                                    interactionSource = remember { MutableInteractionSource() }
                                ) {
                                    if (zoomingIdx != null) return@clickable
                                    zoomingIdx = idx
                                    scope.launch {
                                        // Fade out all non-selected cards in parallel
                                        cardAlphas.forEachIndexed { i, a ->
                                            if (i != idx) launch { a.animateTo(0f, tween(120)) }
                                        }
                                        // Zoom selected card from grid position to full screen
                                        zoomProgress.animateTo(
                                            targetValue   = 1f,
                                            animationSpec = tween(300, easing = FastOutSlowInEasing)
                                        )
                                        onPageSelected(idx)
                                    }
                                },
                            contentAlignment = Alignment.Center
                        ) {
                            Column(
                                horizontalAlignment = Alignment.CenterHorizontally,
                                modifier = Modifier.graphicsLayer { alpha = textAlpha }
                            ) {
                                Text(
                                    text       = page.label,
                                    color      = Color(0xFFFF9500),
                                    fontSize   = 13.sp,
                                    fontWeight = FontWeight.Bold,
                                    textAlign  = TextAlign.Center
                                )
                                if (page.sub.isNotEmpty()) {
                                    Spacer(Modifier.height(2.dp))
                                    Text(
                                        text      = page.sub,
                                        color     = Color(0xFF555555),
                                        fontSize  = 10.sp,
                                        textAlign = TextAlign.Center
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun gridLerp(a: Float, b: Float, t: Float) = a + (b - a) * t
