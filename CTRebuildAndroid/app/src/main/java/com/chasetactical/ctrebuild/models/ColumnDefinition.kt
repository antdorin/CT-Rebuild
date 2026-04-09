package com.chasetactical.ctrebuild.models

import org.json.JSONArray
import org.json.JSONObject

enum class DataKind {
    Text, Number, Dropdown, Date, BarcodeScan, Photo, Gps, ManualEntry, Toggle, Computed;

    companion object {
        fun fromString(value: String?): DataKind =
            entries.firstOrNull { it.name.equals(value, ignoreCase = true) } ?: Text
    }
}

data class ColumnDefinition(
    val id: String,
    val tableName: String,
    val headerText: String,
    val dataKind: DataKind,
    val sortOrder: Int,
    val createdAtUtc: String,
    val options: List<String>?,
    val bindingPath: String?,
    val isReadOnly: Boolean,
    val defaultWidth: Double,
    val isCollapsibleId: Boolean
) {
    companion object {
        fun fromJson(obj: JSONObject): ColumnDefinition {
            val optionsArray = obj.optJSONArray("options")
            val options = optionsArray?.let {
                List(it.length()) { i -> it.getString(i) }
            }
            return ColumnDefinition(
                id             = obj.getString("id"),
                tableName      = obj.optString("tableName", ""),
                headerText     = obj.optString("headerText", ""),
                dataKind       = DataKind.fromString(obj.optString("dataKind")),
                sortOrder      = obj.optInt("sortOrder", 0),
                createdAtUtc   = obj.optString("createdAtUtc", ""),
                options        = options,
                bindingPath    = obj.optString("bindingPath").ifBlank { null },
                isReadOnly     = obj.optBoolean("isReadOnly", false),
                defaultWidth   = obj.optDouble("defaultWidth", 0.0),
                isCollapsibleId = obj.optBoolean("isCollapsibleId", false)
            )
        }

        fun listFromJsonArray(array: JSONArray): List<ColumnDefinition> =
            List(array.length()) { i -> fromJson(array.getJSONObject(i)) }
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("tableName", tableName)
        put("headerText", headerText)
        put("dataKind", dataKind.name)
        put("sortOrder", sortOrder)
        put("createdAtUtc", createdAtUtc)
        if (options != null) put("options", JSONArray(options))
        if (bindingPath != null) put("bindingPath", bindingPath)
        put("isReadOnly", isReadOnly)
        put("defaultWidth", defaultWidth)
        put("isCollapsibleId", isCollapsibleId)
    }
}
