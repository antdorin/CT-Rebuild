package com.chasetactical.ctrebuild.models

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Singleton that maps bin location codes (e.g. "1A-4D") to committed quantities
 * extracted from active picking-ticket PDFs. Mirrors iOS BinDataStore.swift.
 */
object BinDataStore {

    private val _binQuantities = MutableStateFlow<Map<String, Int>>(emptyMap())
    val binQuantities: StateFlow<Map<String, Int>> = _binQuantities.asStateFlow()

    private val groupData = mutableMapOf<String, Map<String, Int>>() // groupId -> per-group map

    // Matches bin codes like "1-A-4D", "2-B-1E", case-insensitive
    private val binRegex = Regex("""(?i)\b(\d+-[A-F]-\d+[A-F])\b""")

    // Matches the Committed column pattern: <qty> <units-abbrev> <committed>
    private val committedRegex = Regex("""\b\d+\s+[A-Z]{1,8}\s+(\d+)\b""")

    /** Keeps PDF format "1-A-4D" as-is (grid now matches PDF format) */
    private fun toGridCode(raw: String): String = raw.uppercase()

    private fun extractBinCommitted(text: String): List<Pair<String, Int>> {
        val results = mutableListOf<Pair<String, Int>>()
        for (line in text.lines()) {
            val binMatches = binRegex.findAll(line).toList()
            if (binMatches.isEmpty()) continue
            val committed = committedRegex.findAll(line).lastOrNull()
                ?.groupValues?.getOrNull(1)?.toIntOrNull()
            if (committed != null && committed > 0) {
                for (bm in binMatches) {
                    results += toGridCode(bm.groupValues[1]) to committed
                }
            } else {
                val qty = line.split(Regex("""\s+"""))
                    .mapNotNull { it.toIntOrNull() }.filter { it > 0 }.lastOrNull() ?: continue
                for (bm in binMatches) {
                    results += toGridCode(bm.groupValues[1]) to qty
                }
            }
        }
        return results
    }

    /** Activate a group using its concatenated PDF page text. */
    fun activate(groupId: String, text: String) {
        val perGroup = mutableMapOf<String, Int>()
        for ((bin, qty) in extractBinCommitted(text)) {
            perGroup[bin] = (perGroup[bin] ?: 0) + qty
        }
        groupData[groupId] = perGroup
        recalculate()
    }

    fun deactivate(groupId: String) {
        groupData.remove(groupId)
        recalculate()
    }

    fun isActive(groupId: String) = groupData.containsKey(groupId)

    private fun recalculate() {
        val merged = mutableMapOf<String, Int>()
        for (perGroup in groupData.values) {
            for ((bin, qty) in perGroup) {
                merged[bin] = (merged[bin] ?: 0) + qty
            }
        }
        _binQuantities.value = merged
    }
}
