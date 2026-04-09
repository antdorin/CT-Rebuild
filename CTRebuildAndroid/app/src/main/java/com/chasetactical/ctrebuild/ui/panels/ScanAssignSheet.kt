package com.chasetactical.ctrebuild.ui.panels

import com.chasetactical.ctrebuild.models.MobileCardEntry
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

private val SheetBg     = Color(0xFF1A1A1A)
private val Muted       = Color(0xFF858585)
private val Accent      = Color(0xFF007ACC)
private val DividerCol  = Color(0xFF2A2A2A)

@Composable
fun ScanAssignSheet(
    scannedValue: String,
    vm: ScanAssignViewModel,
    onDismiss: () -> Unit
) {
    val selectedOption   by vm.selectedOption
    val barcodeColumns   by vm.barcodeColumns
    val entries          by vm.entries
    val isLoadingCols    by vm.isLoadingCols
    val isLoadingEntries by vm.isLoadingEntries
    val assignResult     by vm.assignResult
    val allDefs          by vm.allDefs
    val cardConfig       by vm.cardConfig

    // Auto-dismiss result feedback after 2 s
    LaunchedEffect(assignResult) {
        if (assignResult != null) {
            delay(2_000)
            onDismiss()
        }
    }

    // Full-screen scrim — tap outside the card to dismiss
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xCC000000))
            .clickable(onClick = onDismiss),
        contentAlignment = Alignment.BottomCenter
    ) {
        // Card — consume clicks so they don't bubble through to the scrim
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.52f)
                .clip(RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp))
                .background(SheetBg)
                .clickable(enabled = false, onClick = {})  // consume
        ) {
            Column(modifier = Modifier.fillMaxSize()) {

                // ── Drag handle ──────────────────────────────────────────────
                Box(
                    Modifier
                        .align(Alignment.CenterHorizontally)
                        .padding(top = 8.dp)
                        .width(36.dp)
                        .height(4.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(Color(0xFF444444))
                )

                Spacer(Modifier.height(10.dp))

                // ── Step 1: pick column ──────────────────────────────────────
                if (selectedOption == null) {
                    ColumnPickerContent(
                        scannedValue  = scannedValue,
                        columns       = barcodeColumns,
                        isLoading     = isLoadingCols,
                        onPick        = { vm.selectOption(it) }
                    )
                }
                // ── Step 2: pick entry ───────────────────────────────────────
                else {
                    EntryPickerContent(
                        option        = selectedOption!!,
                        scannedValue  = scannedValue,
                        entries       = entries,
                        defs          = allDefs[selectedOption!!.tableName] ?: emptyList(),
                        cardEntry     = cardConfig[selectedOption!!.tableName],
                        isLoading     = isLoadingEntries,
                        assignResult  = assignResult,
                        onBack        = { vm.selectedOption.value = null; vm.entries.value = emptyList() },
                        onPick        = { entry -> vm.assign(entry, scannedValue) }
                    )
                }
            }
        }
    }
}

// ── Step 1 composable ─────────────────────────────────────────────────────────

@Composable
private fun ColumnPickerContent(
    scannedValue: String,
    columns: List<BarcodeColumnOption>,
    isLoading: Boolean,
    onPick: (BarcodeColumnOption) -> Unit
) {
    // Header
    Column(Modifier.padding(horizontal = 16.dp)) {
        Text("Assign to column", color = Muted, fontSize = 11.sp)
        Spacer(Modifier.height(2.dp))
        Text(
            text       = scannedValue,
            color      = Color.White,
            fontSize   = 15.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Medium,
            maxLines   = 1
        )
        Spacer(Modifier.height(10.dp))
        HorizontalDivider(color = DividerCol)
    }

    when {
        isLoading -> {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Accent, strokeWidth = 2.dp)
            }
        }
        columns.isEmpty() -> {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    "No BarcodeScan columns defined.\nAdd one via column header context menu in CT-Hub.",
                    color = Muted,
                    fontSize = 13.sp,
                    lineHeight = 20.sp
                )
            }
        }
        else -> {
            // Group by tableLabel
            val grouped = columns.groupBy { it.tableLabel }
            LazyColumn(Modifier.fillMaxSize()) {
                grouped.forEach { (tableLabel, options) ->
                    item {
                        Text(
                            text     = tableLabel.uppercase(),
                            color    = Muted,
                            fontSize = 10.sp,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)
                        )
                    }
                    items(options) { opt ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onPick(opt) }
                                .padding(horizontal = 16.dp, vertical = 11.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text     = "▣  ${opt.definition.headerText}",
                                color    = Color.White,
                                fontSize = 14.sp,
                                modifier = Modifier.weight(1f)
                            )
                            Text("›", color = Muted, fontSize = 18.sp)
                        }
                        HorizontalDivider(color = DividerCol, modifier = Modifier.padding(start = 16.dp))
                    }
                }
            }
        }
    }
}

// ── Step 2 composable ─────────────────────────────────────────────────────────

@Composable
private fun EntryPickerContent(
    option: BarcodeColumnOption,
    scannedValue: String,
    entries: List<org.json.JSONObject>,
    defs: List<com.chasetactical.ctrebuild.models.ColumnDefinition>,
    cardEntry: MobileCardEntry?,
    isLoading: Boolean,
    assignResult: String?,
    onBack: () -> Unit,
    onPick: (org.json.JSONObject) -> Unit
) {
    var search by remember { mutableStateOf("") }

    val filtered = remember(entries, search) {
        if (search.isBlank()) entries
        else entries.filter {
            entryDisplayLabel(it, defs)
                .contains(search, ignoreCase = true)
        }
    }

    // Header row with back button
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 4.dp, end = 16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        IconButton(onClick = onBack) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Color.White)
        }
        Column(Modifier.weight(1f)) {
            Text(
                text     = "${option.tableLabel}  ›  ${option.definition.headerText}",
                color    = Muted,
                fontSize = 11.sp
            )
            Text(
                text       = scannedValue,
                color      = Color.White,
                fontSize   = 14.sp,
                fontFamily = FontFamily.Monospace,
                maxLines   = 1
            )
        }
    }
    HorizontalDivider(color = DividerCol, modifier = Modifier.padding(horizontal = 16.dp))

    // Result feedback
    if (assignResult != null) {
        val isOk = assignResult.startsWith("Saved")
        Box(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 6.dp)
                .clip(RoundedCornerShape(6.dp))
                .background(if (isOk) Color(0xFF1E4620) else Color(0xFF4C1515))
                .padding(10.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(assignResult, color = if (isOk) Color(0xFF4EC9A0) else Color(0xFFFF6B6B), fontSize = 13.sp)
        }
    }

    when {
        isLoading -> {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Accent, strokeWidth = 2.dp)
            }
        }
        else -> {
            // Search field
            OutlinedTextField(
                value         = search,
                onValueChange = { search = it },
                placeholder   = { Text("Search entries…", color = Muted, fontSize = 13.sp) },
                singleLine    = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                colors        = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor   = Accent,
                    unfocusedBorderColor = DividerCol,
                    focusedTextColor     = Color.White,
                    unfocusedTextColor   = Color.White,
                    cursorColor          = Accent
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 6.dp)
            )

            if (filtered.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("No entries found", color = Muted, fontSize = 13.sp)
                }
            } else {
                LazyColumn(Modifier.fillMaxSize()) {
                    items(filtered) { entry ->
                        EntryCard(
                            entry     = entry,
                            cardEntry = cardEntry,
                            defs      = defs,
                            onClick   = { onPick(entry) }
                        )
                        HorizontalDivider(color = DividerCol, modifier = Modifier.padding(start = 16.dp))
                    }
                }
            }
        }
    }
}

// ── Entry card composable ─────────────────────────────────────────────────────

@Composable
internal fun EntryCard(
    entry: org.json.JSONObject,
    cardEntry: MobileCardEntry?,
    defs: List<com.chasetactical.ctrebuild.models.ColumnDefinition>,
    onClick: () -> Unit
) {
    // Resolve a field value from the entry JSON using a BindingPath.
    // BindingPath is PascalCase (e.g. "Sku") — JSON keys are camelCase (e.g. "sku").
    fun fieldValue(bindingPath: String?): String? {
        if (bindingPath.isNullOrBlank()) return null
        val key = bindingPath.replaceFirstChar { it.lowercase() }
        return entry.optString(key).ifBlank { null }
    }

    // Determine row1, row2 fields, and badge from config (with fallback to first/second defs).
    val row1Text: String = fieldValue(cardEntry?.row1)
        ?: defs.firstOrNull { !it.isCollapsibleId && !it.isReadOnly && !it.bindingPath.isNullOrBlank() }
            ?.let { fieldValue(it.bindingPath) }
        ?: entry.optString("id").take(8)

    val row2Parts: List<String> = if (cardEntry != null) {
        cardEntry.row2.mapNotNull { fieldValue(it) }
    } else {
        defs.filter { !it.isCollapsibleId && !it.isReadOnly && !it.bindingPath.isNullOrBlank() }
            .drop(1).take(2).mapNotNull { fieldValue(it.bindingPath) }
    }

    val badgeText: String? = fieldValue(cardEntry?.badge)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            // Row 1 — title
            Text(
                text       = row1Text,
                color      = Color.White,
                fontSize   = 14.sp,
                fontWeight = FontWeight.Medium,
                maxLines   = 1
            )
            // Row 2 — subtitle (only if any parts exist)
            if (row2Parts.isNotEmpty()) {
                Text(
                    text     = row2Parts.joinToString("  ·  "),
                    color    = Muted,
                    fontSize = 12.sp,
                    maxLines = 1
                )
            }
        }
        // Badge pill
        if (badgeText != null) {
            val badgeNum = badgeText.toIntOrNull()
            val badgeColor = when {
                badgeNum == null -> Color(0xFF3A3A3A)
                badgeNum <= 0    -> Color(0xFF4C1515)
                badgeNum <= 5    -> Color(0xFF5A4000)
                else             -> Color(0xFF1E4620)
            }
            val badgeTextColor = when {
                badgeNum == null -> Muted
                badgeNum <= 0    -> Color(0xFFFF6B6B)
                badgeNum <= 5    -> Color(0xFFFFCC00)
                else             -> Color(0xFF4EC9A0)
            }
            Spacer(Modifier.width(8.dp))
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(12.dp))
                    .background(badgeColor)
                    .padding(horizontal = 8.dp, vertical = 3.dp)
            ) {
                Text(badgeText, color = badgeTextColor, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        Spacer(Modifier.width(8.dp))
        Text("›", color = Muted, fontSize = 18.sp)
    }
}
