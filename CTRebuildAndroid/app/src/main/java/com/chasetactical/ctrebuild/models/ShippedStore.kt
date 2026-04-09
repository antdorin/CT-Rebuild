package com.chasetactical.ctrebuild.models

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Tracks which PDF pages have been marked as "shipped".
 * Keys are "filename::pageIndex" (0-based).
 * Persisted to SharedPreferences so it survives process death.
 */
object ShippedStore {

    private const val PREFS_NAME = "ct_rebuild"
    private const val KEY        = "shipped_pages"

    private val _shippedKeys = MutableStateFlow<Set<String>>(emptySet())
    val shippedKeys: StateFlow<Set<String>> = _shippedKeys.asStateFlow()

    fun init(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getStringSet(KEY, emptySet()) ?: emptySet()
        _shippedKeys.value = raw.toSet()
    }

    private fun save(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(KEY, _shippedKeys.value)
            .apply()
    }

    fun key(filename: String, pageIndex: Int) = "$filename::$pageIndex"

    fun isShipped(filename: String, pageIndex: Int) =
        _shippedKeys.value.contains(key(filename, pageIndex))

    fun markShipped(context: Context, filename: String, pageIndex: Int) {
        _shippedKeys.value = _shippedKeys.value + key(filename, pageIndex)
        save(context)
    }

    fun unmarkShipped(context: Context, filename: String, pageIndex: Int) {
        _shippedKeys.value = _shippedKeys.value - key(filename, pageIndex)
        save(context)
    }

    fun toggle(context: Context, filename: String, pageIndex: Int) {
        if (isShipped(filename, pageIndex)) unmarkShipped(context, filename, pageIndex)
        else markShipped(context, filename, pageIndex)
    }

    /** All (filename, pageIndex) pairs that are shipped. */
    fun allShipped(): List<Pair<String, Int>> =
        _shippedKeys.value.mapNotNull { k ->
            val parts = k.split("::")
            if (parts.size == 2) parts[0] to (parts[1].toIntOrNull() ?: return@mapNotNull null)
            else null
        }

    /** Shipped page indices for a specific file. */
    fun shippedPagesFor(filename: String): Set<Int> =
        _shippedKeys.value
            .filter { it.startsWith("$filename::") }
            .mapNotNull { it.removePrefix("$filename::").toIntOrNull() }
            .toSet()
}
