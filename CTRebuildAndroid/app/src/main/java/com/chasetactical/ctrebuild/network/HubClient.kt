package com.chasetactical.ctrebuild.network

import com.chasetactical.ctrebuild.models.MobileCardEntry
import com.chasetactical.ctrebuild.models.ColumnDefinition
import com.chasetactical.ctrebuild.models.PdfMeta
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

class HubClient private constructor() {

    companion object {
        val shared = HubClient()
    }

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    /** Base URL of the active Hub, e.g. "http://192.168.1.42:5050" */
    var activeUrl: String = ""

    // ---------- PDF API ----------

    suspend fun fetchPdfMeta(): List<PdfMeta> = withContext(Dispatchers.IO) {
        if (activeUrl.isBlank()) return@withContext emptyList()
        val url = "$activeUrl/api/pdfs/meta"
        try {
            httpClient.newCall(Request.Builder().url(url).build()).execute().use { response ->
                if (!response.isSuccessful) return@withContext emptyList()
                val body = response.body?.string() ?: return@withContext emptyList()
                val arr = JSONArray(body)
                List(arr.length()) { i ->
                    val obj = arr.getJSONObject(i)
                    // Hub serializes with PascalCase (System.Text.Json default)
                    PdfMeta(
                        name      = obj.optString("Name", obj.optString("name", "")),
                        modified  = obj.optString("Modified", obj.optString("modified", "")),
                        pageCount = obj.optInt("PageCount", obj.optInt("pageCount", 0))
                    )
                }
            }
        } catch (e: Exception) {
            throw e  // let callers see the real error
        }
    }

    /** URL for loading reader.html in a WebView */
    fun getReaderUrl(filename: String): String {
        val encoded = URLEncoder.encode(filename, "UTF-8")
        return "$activeUrl/reader.html?file=$encoded"
    }

    /** Direct download URL for a raw PDF */
    fun getPdfDownloadUrl(filename: String): String {
        val encoded = URLEncoder.encode(filename, "UTF-8")
        return "$activeUrl/api/pdfs/$encoded"
    }

    /**
     * Fetches plain text for all pages of [filename] from the Hub sidecar (via the words endpoint).
     * Returns all page text joined with newlines, ready for BinDataStore.activate.
     * Words are grouped into lines by Y-position proximity (±4pt).
     */
    suspend fun fetchPdfText(filename: String): String = withContext(Dispatchers.IO) {
        if (activeUrl.isBlank()) return@withContext ""
        // URLEncoder uses + for spaces; path segments need %20
        val encoded = URLEncoder.encode(filename, "UTF-8").replace("+", "%20")
        val url = "$activeUrl/api/pdf-words/$encoded"
        try {
            httpClient.newCall(Request.Builder().url(url).build()).execute().use { response ->
                if (!response.isSuccessful) return@withContext ""
                val body = response.body?.string() ?: return@withContext ""
                val root = org.json.JSONObject(body)
                val pages = root.optJSONArray("pages") ?: return@withContext ""
                buildString {
                    for (i in 0 until pages.length()) {
                        val page = pages.getJSONObject(i)
                        val words = page.optJSONArray("words") ?: continue
                        // Collect (y0, x0, text) triples
                        data class W(val y: Float, val x: Float, val text: String)
                        val ws = mutableListOf<W>()
                        for (j in 0 until words.length()) {
                            val w = words.getJSONObject(j)
                            ws += W(w.getDouble("y0").toFloat(), w.getDouble("x0").toFloat(), w.getString("text"))
                        }
                        // Sort top-to-bottom (PDF y-axis: higher y0 = higher on page)
                        ws.sortWith(compareByDescending<W> { it.y }.thenBy { it.x })
                        // Group into lines by Y proximity (within 4pt)
                        val lines = mutableListOf<MutableList<W>>()
                        for (w in ws) {
                            if (lines.isEmpty() || lines.last().first().y - w.y > 4f) lines += mutableListOf(w)
                            else lines.last() += w
                        }
                        // Append each line sorted left-to-right
                        for (line in lines) {
                            if (isNotEmpty()) append('\n')
                            append(line.sortedBy { it.x }.joinToString(" ") { it.text })
                        }
                    }
                }
            }
        } catch (_: Exception) { "" }
    }

    // ---------- Column Definitions ----------

    /**
     * Fetches all column definitions for [tableName] from GET /api/columns/{tableName}.
     * Returns an empty list if the Hub is unreachable.
     */
    suspend fun fetchColumnDefinitions(tableName: String): List<ColumnDefinition> = withContext(Dispatchers.IO) {
        if (activeUrl.isBlank()) return@withContext emptyList()
        val url = "$activeUrl/api/columns/${tableName.lowercase()}"
        try {
            httpClient.newCall(Request.Builder().url(url).build()).execute().use { response ->
                if (!response.isSuccessful) return@withContext emptyList()
                val body = response.body?.string() ?: return@withContext emptyList()
                ColumnDefinition.listFromJsonArray(JSONArray(body))
            }
        } catch (_: Exception) { emptyList() }
    }

    /**
     * Fetches the per-table mobile card config from GET /api/mobile-card-config.
     * Returns an empty map if the Hub is unreachable or the endpoint doesn't exist yet.
     */
    suspend fun fetchMobileCardConfig(): Map<String, MobileCardEntry> = withContext(Dispatchers.IO) {
        if (activeUrl.isBlank()) return@withContext emptyMap()
        try {
            httpClient.newCall(Request.Builder().url("$activeUrl/api/mobile-card-config").build())
                .execute().use { r ->
                    if (!r.isSuccessful) return@withContext emptyMap()
                    val body = r.body?.string() ?: return@withContext emptyMap()
                    MobileCardEntry.mapFromJson(org.json.JSONObject(body))
                }
        } catch (_: Exception) { emptyMap() }
    }

    /**
     * Upserts a single entry by POSTing its JSON to POST /api/{tableName}.
     * [entryJson] must be a JSONObject that already contains all entry fields
     * including the updated extraFields map.
     * Returns true on success.
     */
    suspend fun upsertEntry(tableName: String, entryJson: JSONObject): Boolean = withContext(Dispatchers.IO) {
        if (activeUrl.isBlank()) return@withContext false
        val url = "$activeUrl/api/${tableName.lowercase()}"
        val body = entryJson.toString()
            .toRequestBody("application/json; charset=utf-8".toMediaType())
        val request = Request.Builder().url(url).post(body).build()
        try {
            httpClient.newCall(request).execute().use { it.isSuccessful }
        } catch (_: Exception) { false }
    }

    /**
     * Fetches all barcode link entries from GET /api/barcodelinks.
     */
    suspend fun fetchBarcodeLinks(): List<JSONObject> = withContext(Dispatchers.IO) {
        if (activeUrl.isBlank()) return@withContext emptyList()
        try {
            httpClient.newCall(Request.Builder().url("$activeUrl/api/barcodelinks").build())
                .execute().use { r ->
                    if (!r.isSuccessful) return@withContext emptyList()
                    val body = r.body?.string() ?: return@withContext emptyList()
                    val arr = JSONArray(body)
                    List(arr.length()) { i -> arr.getJSONObject(i) }
                }
        } catch (_: Exception) { emptyList() }
    }

    /**
     * Creates a barcode link entry via POST /api/barcodelinks.
     * Returns true on success.
     */
    suspend fun createBarcodeLink(link: JSONObject): Boolean = withContext(Dispatchers.IO) {
        if (activeUrl.isBlank()) return@withContext false
        val body = link.toString()
            .toRequestBody("application/json; charset=utf-8".toMediaType())
        try {
            httpClient.newCall(
                Request.Builder().url("$activeUrl/api/barcodelinks").post(body).build()
            ).execute().use { it.isSuccessful }
        } catch (_: Exception) { false }
    }

    /**
     * Creates a QR/barcode class mapping entry via POST /api/qr_class_mappings.
     * Returns true on success.
     */
    suspend fun createQrMapping(mapping: JSONObject): Boolean = withContext(Dispatchers.IO) {
        if (activeUrl.isBlank()) return@withContext false
        val body = mapping.toString()
            .toRequestBody("application/json; charset=utf-8".toMediaType())
        try {
            httpClient.newCall(
                Request.Builder().url("$activeUrl/api/qr_class_mappings").post(body).build()
            ).execute().use { it.isSuccessful }
        } catch (_: Exception) { false }
    }

    /**
     * Fetches all entries for [tableName] from GET /api/{tableName}.
     * Returns raw JSONObjects so callers can read any field including extraFields.
     */
    suspend fun fetchEntries(tableName: String): List<JSONObject> = withContext(Dispatchers.IO) {
        if (activeUrl.isBlank()) return@withContext emptyList()
        val url = "$activeUrl/api/${tableName.lowercase()}"
        try {
            httpClient.newCall(Request.Builder().url(url).build()).execute().use { r ->
                if (!r.isSuccessful) return@withContext emptyList()
                val body = r.body?.string() ?: return@withContext emptyList()
                val arr = org.json.JSONArray(body)
                List(arr.length()) { i -> arr.getJSONObject(i) }
            }
        } catch (_: Exception) { emptyList() }
    }

    // ---------- Connection ----------

    /** Quick reachability check — returns true if the Hub responds to /api/pdfs/meta */
    suspend fun testConnection(): Boolean = withContext(Dispatchers.IO) {
        if (activeUrl.isBlank() || !activeUrl.startsWith("http")) return@withContext false
        try {
            httpClient.newCall(
                Request.Builder().url("$activeUrl/api/pdfs/meta").build()
            ).execute().use { it.isSuccessful }
        } catch (_: IOException) {
            false
        }
    }

    /** Open a WebSocket to /ws for live push events from the Hub */
    fun connectWebSocket(listener: WebSocketListener): WebSocket {
        val wsUrl = activeUrl
            .replace("http://", "ws://")
            .replace("https://", "wss://") + "/ws"
        val request = Request.Builder().url(wsUrl).build()
        return httpClient.newWebSocket(request, listener)
    }
}
