package com.chasetactical.ctrebuild.ui.panels

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
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
import androidx.core.content.ContextCompat

// ─────────────────────────────────────────────────────────────────────────────
// Top Panel — Calculator / Notes with swipe-up-to-close
// ─────────────────────────────────────────────────────────────────────────────

@Composable
fun TopPanel(onClose: () -> Unit) {
    val density   = LocalDensity.current
    val threshold = with(density) { 80.dp.toPx() }
    val context   = LocalContext.current
    val prefs     = remember { context.getSharedPreferences("ct_rebuild", Context.MODE_PRIVATE) }

    var selectedTab by remember { mutableIntStateOf(prefs.getInt("top_panel_tab", 0)) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0F0F0F))
            .pointerInput(Unit) {
                var total = 0f
                detectVerticalDragGestures(
                    onDragStart  = { total = 0f },
                    onDragEnd    = { total = 0f },
                    onDragCancel = { total = 0f },
                    onVerticalDrag = { change, amount ->
                        change.consume()
                        total += amount
                        if (total < -threshold) { onClose(); total = 0f }
                    }
                )
            }
    ) {
        // Pull handle
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 10.dp),
            contentAlignment = Alignment.Center
        ) {
            Box(
                modifier = Modifier
                    .width(36.dp)
                    .height(4.dp)
                    .background(Color(0xFF3A3A3A), RoundedCornerShape(2.dp))
            )
        }

        Spacer(Modifier.height(12.dp))

        // Tab bar: CALC | NOTES
        TopTabBar(selected = selectedTab, onSelect = {
            selectedTab = it
            prefs.edit().putInt("top_panel_tab", it).apply()
        })

        Spacer(Modifier.height(8.dp))

        when (selectedTab) {
            0    -> CalculatorContent()
            else -> NotesContent()
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab bar
// ─────────────────────────────────────────────────────────────────────────────

@Composable
private fun TopTabBar(selected: Int, onSelect: (Int) -> Unit) {
    val tabs = listOf("CALC", "NOTES")
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        tabs.forEachIndexed { i, label ->
            val isActive = selected == i
            val bg by animateColorAsState(
                targetValue   = if (isActive) Color(0xFFFF9500) else Color(0xFF1A1A1A),
                animationSpec = tween(160),
                label         = "tabBg"
            )
            val fg by animateColorAsState(
                targetValue   = if (isActive) Color.Black else Color(0xFF7A7A7A),
                animationSpec = tween(160),
                label         = "tabFg"
            )
            Button(
                onClick = { onSelect(i) },
                modifier = Modifier
                    .weight(1f)
                    .height(44.dp),
                colors = ButtonDefaults.buttonColors(containerColor = bg),
                shape  = RoundedCornerShape(22.dp),
                contentPadding = PaddingValues(0.dp)
            ) {
                Text(
                    text       = label,
                    color      = fg,
                    fontSize   = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    fontFamily = FontFamily.Monospace,
                    letterSpacing = 2.sp
                )
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Calculator
// ─────────────────────────────────────────────────────────────────────────────

private sealed class CalcKey {
    data class Digit(val d: Int) : CalcKey()
    object Decimal : CalcKey()
    object Clear   : CalcKey()
    object Sign    : CalcKey()
    object Percent : CalcKey()
    object Equals  : CalcKey()
    data class Op(val op: CalcOp) : CalcKey()
}

private enum class CalcOp(val symbol: String) {
    Add("＋"), Subtract("−"), Multiply("×"), Divide("÷")
}

private val CALC_ROWS = listOf(
    listOf(CalcKey.Clear, CalcKey.Sign, CalcKey.Percent, CalcKey.Op(CalcOp.Divide)),
    listOf(CalcKey.Digit(7), CalcKey.Digit(8), CalcKey.Digit(9), CalcKey.Op(CalcOp.Multiply)),
    listOf(CalcKey.Digit(4), CalcKey.Digit(5), CalcKey.Digit(6), CalcKey.Op(CalcOp.Subtract)),
    listOf(CalcKey.Digit(1), CalcKey.Digit(2), CalcKey.Digit(3), CalcKey.Op(CalcOp.Add)),
    listOf(CalcKey.Digit(0), CalcKey.Decimal, CalcKey.Equals)
)

@Composable
private fun CalculatorContent() {
    var display   by remember { mutableStateOf("0") }
    var operand   by remember { mutableDoubleStateOf(0.0) }
    var pendingOp by remember { mutableStateOf<CalcOp?>(null) }
    var freshEntry by remember { mutableStateOf(true) }

    fun format(v: Double): String {
        if (v.isNaN() || v.isInfinite()) return "Error"
        val s = if (v == kotlin.math.floor(v) && !v.isInfinite())
                    "%.0f".format(v) else v.toString()
        return if (s.length > 10) "%.6g".format(v) else s
    }

    fun commit() {
        val op  = pendingOp ?: return
        val cur = display.toDoubleOrNull() ?: return
        val res = when (op) {
            CalcOp.Add      -> operand + cur
            CalcOp.Subtract -> operand - cur
            CalcOp.Multiply -> operand * cur
            CalcOp.Divide   -> if (cur == 0.0) Double.NaN else operand / cur
        }
        display = format(res)
        operand = res
    }

    fun handle(key: CalcKey) {
        when (key) {
            is CalcKey.Digit   -> {
                if (freshEntry) { display = if (key.d == 0) "0" else "${key.d}"; freshEntry = false }
                else if (display == "0") display = "${key.d}"
                else if (display.length < 10) display += "${key.d}"
            }
            is CalcKey.Decimal -> {
                if (freshEntry) { display = "0."; freshEntry = false }
                else if (!display.contains('.')) display += "."
            }
            is CalcKey.Clear   -> {
                display = "0"
                if (!freshEntry) freshEntry = true else { operand = 0.0; pendingOp = null }
            }
            is CalcKey.Sign    -> display.toDoubleOrNull()?.let { display = format(-it) }
            is CalcKey.Percent -> display.toDoubleOrNull()?.let { display = format(it / 100.0) }
            is CalcKey.Op      -> { commit(); operand = display.toDoubleOrNull() ?: 0.0; pendingOp = key.op; freshEntry = true }
            is CalcKey.Equals  -> { commit(); pendingOp = null; freshEntry = true }
        }
    }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp)
    ) {
        val spacing = 10.dp
        val cols    = 4
        val btnW    = (maxWidth - spacing * (cols - 1)) / cols
        val btnH    = btnW * 0.82f

        Column(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.Bottom
        ) {
            // Display
            val formatted = run {
                val d = display.toDoubleOrNull()
                when {
                    d == null                              -> display
                    display.endsWith(".")                  -> display
                    d == kotlin.math.floor(d) && !display.contains('.') ->
                        "%.0f".format(d).let { if (it.length > 9) d.toString() else it }
                    else -> if (display.length > 10) "%.6g".format(d) else display
                }
            }
            Text(
                text      = formatted,
                color     = Color.White,
                fontSize  = 52.sp,
                fontWeight = FontWeight.Thin,
                fontFamily = FontFamily.Monospace,
                textAlign = TextAlign.End,
                maxLines  = 1,
                modifier  = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 12.dp)
            )

            // Button grid
            CALC_ROWS.forEach { row ->
                Row(
                    horizontalArrangement = Arrangement.spacedBy(spacing),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = spacing)
                ) {
                    row.forEach { key ->
                        val isWide = key == CalcKey.Digit(0)
                        val w      = if (isWide) btnW * 2 + spacing else btnW
                        CalcButton(
                            key    = key,
                            width  = w,
                            height = btnH,
                            active = (key is CalcKey.Op && key.op == pendingOp),
                            onTap  = { handle(key) }
                        )
                    }
                }
            }

            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun CalcButton(
    key:    CalcKey,
    width:  Dp,
    height: Dp,
    active: Boolean,
    onTap:  () -> Unit
) {
    data class Style(val label: String, val fg: Color, val bg: Color)
    val orange = Color(0xFFFF9500)
    val style = when (key) {
        is CalcKey.Clear   -> Style("C",    Color.Black, Color(0xFFBFBFBF))
        is CalcKey.Sign    -> Style("+/−",  Color.Black, Color(0xFFBFBFBF))
        is CalcKey.Percent -> Style("%",    Color.Black, Color(0xFFBFBFBF))
        is CalcKey.Op      -> Style(key.op.symbol, if (active) orange else Color.White, if (active) Color.White else orange)
        is CalcKey.Digit   -> Style("${key.d}", Color.White, Color(0xFF383838))
        is CalcKey.Decimal -> Style(".",    Color.White, Color(0xFF383838))
        is CalcKey.Equals  -> Style("=",   Color.White, orange)
    }
    val radius = height * 0.28f

    Button(
        onClick        = onTap,
        modifier       = Modifier.width(width).height(height),
        colors         = ButtonDefaults.buttonColors(containerColor = style.bg),
        shape          = RoundedCornerShape(radius),
        contentPadding = PaddingValues(0.dp)
    ) {
        Text(
            text     = style.label,
            color    = style.fg,
            fontSize = (height.value * 0.38f).sp,
            textAlign = TextAlign.Center
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notes
// ─────────────────────────────────────────────────────────────────────────────

private const val PREFS_NOTES = "ct_rebuild"
private const val KEY_NOTES   = "top_panel_notes"

@Composable
private fun NotesContent() {
    val context = LocalContext.current
    val prefs   = remember { context.getSharedPreferences(PREFS_NOTES, Context.MODE_PRIVATE) }

    var notes        by remember { mutableStateOf(prefs.getString(KEY_NOTES, "") ?: "") }
    var isRecording  by remember { mutableStateOf(false) }
    var baseText     by remember { mutableStateOf("") }
    var partial      by remember { mutableStateOf("") }
    var showPermDlg  by remember { mutableStateOf(false) }

    val recognizer = remember {
        if (SpeechRecognizer.isRecognitionAvailable(context))
            SpeechRecognizer.createSpeechRecognizer(context)
        else null
    }

    fun stopRecording() {
        recognizer?.stopListening()
        isRecording = false
    }

    fun startRecording() {
        val hasMic    = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                        android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!hasMic) { showPermDlg = true; return }
        baseText = notes
        partial  = ""
        isRecording = true
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        recognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(p: Bundle?)  {}
            override fun onBeginningOfSpeech()         {}
            override fun onRmsChanged(v: Float)        {}
            override fun onBufferReceived(b: ByteArray?) {}
            override fun onEndOfSpeech()               {}
            override fun onError(code: Int)            { isRecording = false }
            override fun onResults(results: Bundle?) {
                val words = results
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull() ?: ""
                val sep = if (baseText.isEmpty()) "" else "\n"
                notes   = if (words.isEmpty()) baseText else baseText + sep + words
                isRecording = false
                partial     = ""
                prefs.edit().putString(KEY_NOTES, notes).apply()
            }
            override fun onPartialResults(partial_: Bundle?) {
                partial = partial_
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull() ?: ""
            }
            override fun onEvent(type: Int, params: Bundle?) {}
        })
        recognizer?.startListening(intent)
    }

    DisposableEffect(Unit) {
        onDispose {
            recognizer?.destroy()
        }
    }

    val liveText = if (isRecording) {
        if (partial.isEmpty()) baseText else baseText + (if (baseText.isEmpty()) "" else "\n") + partial
    } else notes

    Column(modifier = Modifier.fillMaxSize()) {
        TextField(
            value         = liveText,
            onValueChange = { if (!isRecording) { notes = it; prefs.edit().putString(KEY_NOTES, it).apply() } },
            readOnly      = isRecording,
            modifier      = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(horizontal = 12.dp),
            colors = TextFieldDefaults.colors(
                focusedContainerColor   = Color.Transparent,
                unfocusedContainerColor = Color.Transparent,
                focusedIndicatorColor   = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
                focusedTextColor        = if (isRecording) Color.White.copy(alpha = 0.6f) else Color.White,
                unfocusedTextColor      = if (isRecording) Color.White.copy(alpha = 0.6f) else Color.White,
                cursorColor             = Color(0xFFFF9500)
            ),
            textStyle = LocalTextStyle.current.copy(fontSize = 15.sp),
            placeholder = { Text("Notes…", color = Color(0xFF444444), fontSize = 15.sp) }
        )

        // Mic button row
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(end = 16.dp, bottom = 16.dp),
            horizontalArrangement = Arrangement.End
        ) {
            val pulse = rememberInfiniteTransition(label = "pulse")
            val pulseScale by pulse.animateFloat(
                initialValue   = 1f,
                targetValue    = if (isRecording) 1.18f else 1f,
                animationSpec  = infiniteRepeatable(
                    animation  = tween(600, easing = FastOutSlowInEasing),
                    repeatMode = RepeatMode.Reverse
                ),
                label = "micScale"
            )
            IconButton(
                onClick  = { if (isRecording) stopRecording() else startRecording() },
                modifier = Modifier.scale(pulseScale)
            ) {
                Icon(
                    imageVector = if (isRecording) Icons.Default.Stop else Icons.Default.Mic,
                    contentDescription = if (isRecording) "Stop" else "Dictate",
                    tint   = if (isRecording) Color.Red else Color(0xFF7A7A7A),
                    modifier = Modifier.size(30.dp)
                )
            }
        }
    }

    if (showPermDlg) {
        AlertDialog(
            onDismissRequest = { showPermDlg = false },
            title  = { Text("Permission Required") },
            text   = { Text("Microphone access is required for dictation. Grant it in Settings.") },
            confirmButton = {
                TextButton(onClick = {
                    showPermDlg = false
                    context.startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                               Uri.fromParts("package", context.packageName, null))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                }) { Text("Open Settings") }
            },
            dismissButton = {
                TextButton(onClick = { showPermDlg = false }) { Text("Cancel") }
            }
        )
    }
}
