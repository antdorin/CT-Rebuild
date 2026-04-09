package com.chasetactical.ctrebuild.ui.panels

import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.chasetactical.ctrebuild.models.ColumnDefinition
import com.chasetactical.ctrebuild.models.DataKind
import com.chasetactical.ctrebuild.models.MobileCardEntry
import com.chasetactical.ctrebuild.network.HubClient
import kotlinx.coroutines.launch
import org.json.JSONObject

data class BarcodeColumnOption(
    val tableName: String,
    val tableLabel: String,
    val definition: ColumnDefinition
)

class ScanAssignViewModel : ViewModel() {

    val barcodeColumns   = mutableStateOf<List<BarcodeColumnOption>>(emptyList())
    val entries          = mutableStateOf<List<JSONObject>>(emptyList())
    val selectedOption   = mutableStateOf<BarcodeColumnOption?>(null)
    val isLoadingCols    = mutableStateOf(false)
    val isLoadingEntries = mutableStateOf(false)
    val assignResult     = mutableStateOf<String?>(null)

    private val tables = listOf(
        "chasetactical"   to "Chase Tactical",
        "toughhooks"      to "Tough Hook",
        "shippingsupplys" to "Shipping Supplies"
    )

    // All column definitions keyed by tableName, used for building entry labels.
    val allDefs    = mutableStateOf<Map<String, List<ColumnDefinition>>>(emptyMap())
    private val _allDefs = mutableMapOf<String, List<ColumnDefinition>>()

    // Mobile card config fetched from CT-Hub settings.
    val cardConfig = mutableStateOf<Map<String, MobileCardEntry>>(emptyMap())

    fun loadBarcodeColumns() {
        viewModelScope.launch {
            isLoadingCols.value = true
            val options = mutableListOf<BarcodeColumnOption>()
            for ((tableName, tableLabel) in tables) {
                val defs = HubClient.shared.fetchColumnDefinitions(tableName)
                _allDefs[tableName] = defs
                defs.filter { it.dataKind == DataKind.BarcodeScan }
                    .forEach { def -> options += BarcodeColumnOption(tableName, tableLabel, def) }
            }
            allDefs.value        = _allDefs.toMap()
            cardConfig.value     = HubClient.shared.fetchMobileCardConfig()
            barcodeColumns.value = options
            isLoadingCols.value  = false
        }
    }

    fun selectOption(option: BarcodeColumnOption) {
        selectedOption.value = option
        entries.value        = emptyList()
        viewModelScope.launch {
            isLoadingEntries.value = true
            entries.value          = HubClient.shared.fetchEntries(option.tableName)
            isLoadingEntries.value = false
        }
    }

    fun assign(entry: JSONObject, scannedValue: String) {
        val option = selectedOption.value ?: return
        viewModelScope.launch {
            val extraFields = entry.optJSONObject("extraFields")?.let {
                JSONObject(it.toString())
            } ?: JSONObject()
            extraFields.put(option.definition.id, scannedValue)
            val updated = JSONObject(entry.toString())
            updated.put("extraFields", extraFields)
            val ok = HubClient.shared.upsertEntry(option.tableName, updated)
            if (ok) {
                // Record the link so the scan list can display the item name
                val label = entryDisplayLabel(entry, _allDefs[option.tableName] ?: emptyList())
                val link = JSONObject().apply {
                    put("sourceBarcodeValue", scannedValue)
                    put("sourceColumnId",     option.definition.id)
                    put("sourceTableName",    option.tableName)
                    put("targetTableName",    option.tableName)
                    put("targetEntryId",      entry.optString("id"))
                    put("targetEntryLabelSnapshot", label)
                }
                HubClient.shared.createBarcodeLink(link)
                // Auto-create a Code Mapping row so the desktop label generator is ready
                val mapping = JSONObject().apply {
                    put("qrValue", scannedValue)
                    put("classification", label)
                    put("description", option.definition.id)
                }
                HubClient.shared.createQrMapping(mapping)
                assignResult.value = "Saved \u2192 ${option.definition.headerText}"
            } else {
                assignResult.value = "Save failed"
            }
        }
    }

    fun reset() {
        selectedOption.value = null
        entries.value        = emptyList()
        assignResult.value   = null
    }
}

fun entryDisplayLabel(entry: JSONObject, defs: List<ColumnDefinition>): String {
    // Use the first two non-ID, non-readonly display columns (sorted by sortOrder).
    val displayDefs = defs
        .filter { !it.isCollapsibleId && !it.isReadOnly && !it.bindingPath.isNullOrBlank() }
        .sortedBy { it.sortOrder }
        .take(2)
    if (displayDefs.isEmpty()) return entry.optString("id").take(8)
    return buildString {
        for (def in displayDefs) {
            val key   = def.bindingPath!!.replaceFirstChar { it.lowercase() }
            val value = entry.optString(key).ifBlank { null } ?: continue
            if (isNotEmpty()) append(" \u2013 ")
            append(value)
        }
        if (isEmpty()) append(entry.optString("id").take(8))
    }
}
