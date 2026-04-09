package com.chasetactical.ctrebuild.ui.panels

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chasetactical.ctrebuild.models.BinDataStore

private val LEVELS = listOf("A", "B", "C", "D", "E", "F")

/**
 * Left panel — Bin Grid matching iOS LeftPanelView.
 * Sections A (4 positions) and B (6 positions), 6 levels each.
 * Section A right side (2-column width) is reserved for the display panel.
 * ◀ / ▶ arrows navigate columns; swipe left closes the panel.
 */
@Composable
fun LeftPanel(onClose: () -> Unit) {
    val context      = LocalContext.current
    val prefs        = remember { context.getSharedPreferences("ct_rebuild", Context.MODE_PRIVATE) }
    val totalColumns = remember { prefs.getInt("panel_leftColumns", 3) }
    var columnPage   by remember { mutableStateOf(prefs.getInt("leftPanelColumnPage", 0)) }

    val density        = LocalDensity.current
    val closeThreshold = with(density) { 80.dp.toPx() }

    fun colNum(page: Int): Int {
        val cols = maxOf(1, totalColumns)
        val m    = page % cols
        return if (m < 0) m + cols + 1 else m + 1
    }

    fun navigate(page: Int) {
        columnPage = page
        prefs.edit().putInt("leftPanelColumnPage", page).apply()
    }

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
                        if (total < -closeThreshold) { onClose(); total = 0f }
                    }
                )
            }
    ) {
        val col    = colNum(columnPage)
        val topPad = 16.dp

        Column(modifier = Modifier.fillMaxSize()) {

            // ── Grid — BoxWithConstraints measures the *actual* weight(1f) height
            //    so cellH is computed from real available space, not an estimate ─
            BoxWithConstraints(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
            ) {
                // 12 rows + 5 gaps/section × 2 sections × 4dp + 12dp section gap = 52dp
                val cellH = ((maxHeight - topPad - 52.dp) / 12).coerceAtLeast(16.dp)
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(start = 8.dp, end = 8.dp, top = topPad),
                    verticalArrangement = Arrangement.Center
                ) {
                    // ── Section A: bin grid (4 positions) + display panel (2 columns wide) ──
                    // Height = 6 levels × cellH + 5 gaps × 4dp
                    val sectionAHeight = cellH * 6f + 20.dp
                    Row(
                        modifier = Modifier.fillMaxWidth().height(sectionAHeight),
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        BinSectionGrid(
                            colNum        = col,
                            sectionLetter = "A",
                            positions     = 4,
                            blankCount    = 0,
                            cellH         = cellH,
                            modifier      = Modifier.weight(4f)
                        )
                        SectionADisplayPanel(
                            cellH    = cellH,
                            modifier = Modifier.weight(2f).fillMaxHeight()
                        )
                    }
                    Spacer(modifier = Modifier.height(12.dp))
                    BinSectionGrid(
                        colNum        = col,
                        sectionLetter = "B",
                        positions     = 6,
                        blankCount    = 0,
                        cellH         = cellH
                    )
                }
            }

            // ── Dots + Navigation ─────────────────────────────────────────
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp, bottom = 24.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment     = Alignment.CenterVertically
            ) {
                Text(
                    text     = "◀",
                    color    = Color.White.copy(alpha = 0.45f),
                    fontSize = 14.sp,
                    modifier = Modifier
                        .padding(horizontal = 14.dp)
                        .clickable { navigate(columnPage - 1) }
                )
                val currentCol = colNum(columnPage)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    repeat(totalColumns) { i ->
                        Box(
                            modifier = Modifier
                                .size(6.dp)
                                .clip(CircleShape)
                                .background(
                                    if (currentCol == i + 1) Color.White
                                    else Color.White.copy(alpha = 0.25f)
                                )
                        )
                    }
                }
                Text(
                    text     = "▶",
                    color    = Color.White.copy(alpha = 0.45f),
                    fontSize = 14.sp,
                    modifier = Modifier
                        .padding(horizontal = 14.dp)
                        .clickable { navigate(columnPage + 1) }
                )
            }
        }
    }
}

@Composable
private fun BinSectionGrid(
    colNum: Int,
    sectionLetter: String,
    positions: Int,
    blankCount: Int,
    cellH: Dp,
    modifier: Modifier = Modifier
) {
    val columnCode = "$colNum-$sectionLetter"
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        LEVELS.forEach { level ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                for (pos in 1..positions) {
                    BinCell(
                        code     = "$columnCode-$pos$level",
                        cellH    = cellH,
                        modifier = Modifier.weight(1f)
                    )
                }
                repeat(blankCount) { BlankCell(modifier = Modifier.weight(1f).height(cellH)) }
            }
        }
    }
}

@Composable
private fun BinCell(
    code: String,
    cellH: Dp,
    modifier: Modifier = Modifier
) {
    val textFs = (cellH.value * 0.17f).coerceAtLeast(7f).sp

    Box(
        modifier = modifier
            .height(cellH)
            .background(Color.White.copy(alpha = 0.06f), RoundedCornerShape(6.dp))
            .border(0.5.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(6.dp)),
        contentAlignment = Alignment.TopCenter
    ) {
        Text(
            text       = code,
            color      = Color.White,
            fontSize   = textFs,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Bold,
            textAlign  = TextAlign.Center,
            lineHeight = (cellH.value * 0.20f).coerceAtLeast(8f).sp,
            maxLines   = 2,
            modifier   = Modifier.padding(top = 3.dp, start = 2.dp, end = 2.dp)
        )
    }
}

@Composable
private fun BlankCell(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .background(Color.White.copy(alpha = 0.02f), RoundedCornerShape(6.dp))
            .border(0.5.dp, Color.White.copy(alpha = 0.04f), RoundedCornerShape(6.dp))
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION A DISPLAY PANEL
// Shows bin codes + accumulated committed quantities from the selected PDF.
// Activated automatically when user selects a file in the PDF Browser.
// ─────────────────────────────────────────────────────────────────────────────

@Composable
private fun SectionADisplayPanel(
    cellH: Dp,
    modifier: Modifier = Modifier
) {
    val binQuantities by BinDataStore.binQuantities.collectAsState()
    val entries = remember(binQuantities) {
        binQuantities.entries.sortedBy { it.key }
    }

    Box(
        modifier = modifier
            .background(Color.White.copy(alpha = 0.02f), RoundedCornerShape(6.dp))
            .border(0.5.dp, Color.White.copy(alpha = 0.05f), RoundedCornerShape(6.dp))
            .padding(horizontal = 3.dp, vertical = 2.dp)
    ) {
        if (entries.isEmpty()) {
            // No active PDF — show nothing (blank panel)
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(0.dp)
            ) {
                items(entries, key = { it.key }) { (bin, qty) ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 2.dp, vertical = 1.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text       = bin,
                            color      = Color.White.copy(alpha = 0.75f),
                            fontSize   = (cellH.value * 0.13f + 9f).coerceAtLeast(15f).sp,
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.Medium,
                            maxLines   = 1
                        )
                        Text(
                            text       = qty.toString(),
                            color      = Color(0xFFFF9500),
                            fontSize   = (cellH.value * 0.18f + 9f).coerceAtLeast(16f).sp,
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.Bold,
                            maxLines   = 1
                        )
                    }
                }
            }
        }
    }
}
