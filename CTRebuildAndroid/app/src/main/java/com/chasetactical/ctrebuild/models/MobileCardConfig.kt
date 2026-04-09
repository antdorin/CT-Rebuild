package com.chasetactical.ctrebuild.models

import org.json.JSONObject

data class MobileCardEntry(
    /** BindingPath of the primary (bold) title field. Null = first non-ID column. */
    val row1: String?,
    /** BindingPath values for the subtitle line (joined with  ·  separator). */
    val row2: List<String>,
    /** BindingPath of the badge pill field (e.g. "Qty"). Null = no badge. */
    val badge: String?
) {
    companion object {
        fun fromJson(obj: JSONObject): MobileCardEntry {
            val row2Array = obj.optJSONArray("row2")
            val row2 = if (row2Array != null) {
                List(row2Array.length()) { i -> row2Array.getString(i) }
            } else emptyList()
            return MobileCardEntry(
                row1  = obj.optString("row1").ifBlank { null },
                row2  = row2,
                badge = obj.optString("badge").ifBlank { null }
            )
        }

        /** Parses the full map response from GET /api/mobile-card-config. */
        fun mapFromJson(obj: JSONObject): Map<String, MobileCardEntry> {
            val result = mutableMapOf<String, MobileCardEntry>()
            for (key in obj.keys()) {
                result[key] = fromJson(obj.getJSONObject(key))
            }
            return result
        }
    }
}
