package com.chasetactical.ctrebuild.ui.panels

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.chasetactical.ctrebuild.R
import com.chasetactical.ctrebuild.ui.camera.CameraPreviewView
import com.chasetactical.ctrebuild.ui.camera.CameraViewModel
import android.media.SoundPool
import android.media.AudioAttributes
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun BottomPanel(onClose: () -> Unit) {
    val density = LocalDensity.current
    val threshold = with(density) { 80.dp.toPx() }
    val context = LocalContext.current

    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
                    == PackageManager.PERMISSION_GRANTED
        )
    }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> hasCameraPermission = granted }

    val cameraVm: CameraViewModel = viewModel()
    val assignVm: ScanAssignViewModel = viewModel()
    var assigningScan by remember { mutableStateOf<com.chasetactical.ctrebuild.ui.camera.ScanResult?>(null) }
    var menuScan     by remember { mutableStateOf<com.chasetactical.ctrebuild.ui.camera.ScanResult?>(null) }
    var editingScan  by remember { mutableStateOf<com.chasetactical.ctrebuild.ui.camera.ScanResult?>(null) }
    var editText     by remember { mutableStateOf("") }

    val cardConfig by cameraVm.cardConfig
    val allDefs    by cameraVm.allDefs

    // Load linked labels once the panel opens
    LaunchedEffect(Unit) { cameraVm.loadLinkedLabels() }

    // Refresh linked labels after every successful assign
    val assignResult by assignVm.assignResult
    LaunchedEffect(assignResult) {
        if (assignResult != null && assignResult!!.startsWith("Saved")) {
            cameraVm.loadLinkedLabels()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0F0F0F))
            .pointerInput(Unit) {
                // Only consume downward drags (close gesture).
                // Upward drags are left unconsumed so the zoom slider can handle them.
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    var total = 0f
                    var closing = false
                    while (true) {
                        val event  = awaitPointerEvent()
                        val change = event.changes.firstOrNull() ?: break
                        if (!change.pressed) break
                        val dy = change.positionChange().y
                        // Block close if the user is actively dragging the zoom slider,
                        // or if the event was already consumed by a child.
                        if (!change.isConsumed && !cameraVm.isDraggingZoom.value && dy > 0f) {
                            total += dy
                            change.consume()
                            if (total > threshold) { closing = true; break }
                        }
                    }
                    if (closing) onClose()
                }
            }
    ) {
        if (hasCameraPermission) {
            val timeFmt = remember { SimpleDateFormat("HH:mm:ss", Locale.getDefault()) }

            // Pre-load beep into SoundPool so it's ready instantly (fixes sometimes-not-playing)
            val soundPool = remember {
                SoundPool.Builder()
                    .setMaxStreams(2)
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    )
                    .build()
            }
            var beepSoundId by remember { mutableStateOf(0) }
            var beepReady   by remember { mutableStateOf(false) }
            DisposableEffect(Unit) {
                soundPool.setOnLoadCompleteListener { _, _, status ->
                    if (status == 0) beepReady = true
                }
                beepSoundId = soundPool.load(context, R.raw.scanner_beep, 1)
                onDispose { soundPool.release() }
            }

            // Play beep on scan — seenTrigger prevents spurious play on panel open/close
            val beepTrigger by cameraVm.scanBeepTrigger
            val seenTrigger = remember { mutableStateOf(beepTrigger) }
            LaunchedEffect(beepTrigger) {
                if (beepTrigger <= seenTrigger.value) return@LaunchedEffect
                seenTrigger.value = beepTrigger
                if (beepReady) soundPool.play(beepSoundId, 0.5f, 0.5f, 1, 0, 1.0f)
            }

            Column(Modifier.fillMaxSize()) {
                // Top 70%: live camera
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(0.7f)
                ) {
                    CameraPreviewView(
                        viewModel = cameraVm,
                        modifier = Modifier.fillMaxSize()
                    )
                    // Scan-arm toggle — grey = off, orange = armed for next scan
                    val scanEnabled by cameraVm.scanEnabled
                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(bottom = 12.dp)
                            .size(64.dp)
                            .alpha(0.4f)
                            .clip(RoundedCornerShape(12.dp))
                            .background(if (scanEnabled) Color(0xFFFF9500) else Color(0xFF2A2A2A))
                            .pointerInput(Unit) {
                                awaitEachGesture {
                                    val down = awaitFirstDown(requireUnconsumed = false)
                                    down.consume()
                                    val up = waitForUpOrCancellation()
                                    if (up != null) {
                                        up.consume()
                                        if (cameraVm.scanEnabled.value) {
                                            cameraVm.scanEnabled.value = false
                                        } else {
                                            cameraVm.armScanner()
                                        }
                                    }
                                }
                            }
                    )
                }
                HorizontalDivider(color = Color(0xFF2A2A2A))
                // Bottom 30%: scan results
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(0.3f)
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                ) {
                    if (cameraVm.scans.isEmpty()) {
                        item {
                            Box(
                                Modifier.fillMaxWidth().padding(top = 20.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text("No scans yet", color = Color(0xFF555555), fontSize = 13.sp)
                            }
                        }
                    } else {
                        items(cameraVm.scans, key = { it.value }) { scan ->
                            val key         = scan.value.lowercase()
                            val linkedLabel = cameraVm.linkedLabels[key]
                            val linkedEntry = cameraVm.linkedEntries[key]
                            val linkedTable = cameraVm.linkedTables[key]
                            val cardEntry   = linkedTable?.let { cardConfig[it] }
                            val defs        = linkedTable?.let { allDefs[it] } ?: emptyList()
                            Box {
                                if (linkedEntry != null) {
                                    Box(
                                        Modifier
                                            .fillMaxWidth()
                                            .combinedClickable(onClick = {}, onLongClick = { menuScan = scan })
                                    ) {
                                        EntryCard(
                                            entry     = linkedEntry,
                                            cardEntry = cardEntry,
                                            defs      = defs,
                                            onClick   = {}
                                        )
                                    }
                                } else {
                                    Row(
                                        Modifier
                                            .fillMaxWidth()
                                            .combinedClickable(
                                                onClick = {},
                                                onLongClick = { menuScan = scan }
                                            )
                                            .padding(vertical = 5.dp),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Column(Modifier.weight(1f)) {
                                            Text(
                                                text = linkedLabel ?: scan.value,
                                                color = if (linkedLabel != null) Color(0xFFFF9500) else Color.White,
                                                fontSize = 14.sp,
                                                fontFamily = if (linkedLabel != null) FontFamily.Default else FontFamily.Monospace,
                                                maxLines = 1
                                            )
                                            if (linkedLabel == null) {
                                                Text(
                                                    text = scan.format,
                                                    color = Color(0xFFFF9500),
                                                    fontSize = 11.sp
                                                )
                                            }
                                        }
                                        Text(
                                            text = timeFmt.format(Date(scan.timeMs)),
                                            color = Color(0xFF555555),
                                            fontSize = 11.sp
                                        )
                                        TextButton(
                                            onClick = {
                                                assignVm.reset()
                                                assigningScan = scan
                                                assignVm.loadBarcodeColumns()
                                            },
                                            contentPadding = PaddingValues(horizontal = 6.dp, vertical = 0.dp)
                                        ) {
                                            Text("→", color = Color.White, fontSize = 14.sp)
                                        }
                                    }
                                }
                                DropdownMenu(
                                    expanded = menuScan == scan,
                                    onDismissRequest = { menuScan = null }
                                ) {
                                    DropdownMenuItem(
                                        text = { Text("Edit") },
                                        onClick = {
                                            editText = scan.value
                                            editingScan = scan
                                            menuScan = null
                                        }
                                    )
                                    DropdownMenuItem(
                                        text = { Text("Delete", color = Color(0xFFFF5555)) },
                                        onClick = {
                                            cameraVm.removeScan(scan.value)
                                            cameraVm.loadLinkedLabels()
                                            menuScan = null
                                        }
                                    )
                                }
                            }
                            HorizontalDivider(color = Color(0xFF1E1E1E))
                        }
                    }
                }
            }
        } else {
            Column(
                Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text("Camera permission required", color = Color(0xFFFF9500))
                Spacer(Modifier.height(16.dp))
                Button(onClick = { permissionLauncher.launch(Manifest.permission.CAMERA) }) {
                    Text("Grant Permission")
                }
            }
        }

        // Scan-to-column assignment sheet
        if (assigningScan != null) {
            ScanAssignSheet(
                scannedValue = assigningScan!!.value,
                vm           = assignVm,
                onDismiss    = { assigningScan = null }
            )
        }

        // Edit scan value dialog
        if (editingScan != null) {
            AlertDialog(
                onDismissRequest = { editingScan = null },
                title = { Text("Edit scan value") },
                text = {
                    OutlinedTextField(
                        value = editText,
                        onValueChange = { editText = it },
                        singleLine = true,
                        label = { Text("Value") }
                    )
                },
                confirmButton = {
                    TextButton(onClick = {
                        cameraVm.editScan(editingScan!!.value, editText.trim())
                        editingScan = null
                    }) { Text("Save") }
                },
                dismissButton = {
                    TextButton(onClick = { editingScan = null }) { Text("Cancel") }
                }
            )
        }
    }
}
