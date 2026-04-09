package com.chasetactical.ctrebuild.ui.reader

import android.webkit.WebView
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.chasetactical.ctrebuild.models.BinDataStore
import com.chasetactical.ctrebuild.models.PdfMeta
import com.chasetactical.ctrebuild.models.ShippedStore
import com.chasetactical.ctrebuild.network.HubClient
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private enum class BrowserTab { SALES_ORDER, LIST, SEARCH, SHIPPED }

/**
 * Right panel reader entry point.
 *
 * Bottom tab bar: LIST | SEARCH | SHIPPED
 *  - LIST: PDF file list grouped by date. Tap row to expand pages.
 *          Double-tap a page to toggle shipped stamp.
 *  - SEARCH: Universal search across all PDF display names.
 *  - SHIPPED: Shows only shipped pages, grouped by file.
 *             Double-tap a shipped page to unmark it.
 *
 * Tapping any row (single-tap) opens the reader WebView for that file.
 * `autoOpenLatest` opens the most-recently-modified file immediately.
 */
@Composable
fun PdfBrowserView(
    onClose: () -> Unit,
    onNavigateToSettings: () -> Unit = {},
    onReaderStateChanged: (Boolean) -> Unit = {},
    autoOpenLatest: Boolean = false
) {
    val context = LocalContext.current
    val scope   = rememberCoroutineScope()
    val prefs   = remember { context.getSharedPreferences("ct_rebuild", 0) }

    var pdfs          by remember { mutableStateOf<List<PdfMeta>>(emptyList()) }
    var loading       by remember { mutableStateOf(false) }
    var error         by remember { mutableStateOf<String?>(null) }
    var selectedFile  by remember { mutableStateOf<String?>(prefs.getString("selected_file", null)) }
    var activeTab     by remember { mutableStateOf(BrowserTab.values().getOrElse(prefs.getInt("browser_tab", BrowserTab.LIST.ordinal)) { BrowserTab.LIST }) }
    var searchQuery   by remember { mutableStateOf("") }
    // Set of expanded PDF names in the list
    var expandedFiles         by remember { mutableStateOf<Set<String>>(emptySet()) }
    var showInlineSearch      by remember { mutableStateOf(false) }
    var salesOrderSearchQuery by remember { mutableStateOf("") }
    var listSearchQuery       by remember { mutableStateOf("") }
    var shippedSearchQuery    by remember { mutableStateOf("") }
    var activeWebView         by remember { mutableStateOf<android.webkit.WebView?>(null) }

    val shippedKeys by ShippedStore.shippedKeys.collectAsState()

    // Load PDFs on first show
    LaunchedEffect(Unit) {
        loading = true; error = null
        try { pdfs = HubClient.shared.fetchPdfMeta() }
        catch (e: Exception) { error = e.message ?: "Failed to load" }
        loading = false
    }

    // Persist selected file to prefs whenever it changes
    LaunchedEffect(selectedFile) {
        selectedFile?.let { prefs.edit().putString("selected_file", it).apply() }
    }

    // Activate bin extraction for the selected PDF so the left panel can show quantities
    LaunchedEffect(selectedFile) {
        val file = selectedFile ?: run { BinDataStore.deactivate("selected"); return@LaunchedEffect }
        val text = HubClient.shared.fetchPdfText(file)
        if (text.isNotEmpty()) BinDataStore.activate("selected", text)
        else BinDataStore.deactivate("selected")
    }

    // Auto-select most recent PDF if nothing valid is selected after list loads
    LaunchedEffect(pdfs) {
        if (pdfs.isEmpty()) return@LaunchedEffect
        if (selectedFile == null || pdfs.none { it.name == selectedFile }) {
            val latest = pdfs.maxByOrNull { it.modified } ?: pdfs.first()
            selectedFile = latest.name
        }
    }

    LaunchedEffect(activeTab) {
        onReaderStateChanged(activeTab == BrowserTab.SALES_ORDER)
        prefs.edit().putInt("browser_tab", activeTab.ordinal).apply()
    }

    // Re-fire whenever either the query or the WebView reference changes so the
    // search is re-applied after tab switches that cause a WebView recreation.
    LaunchedEffect(salesOrderSearchQuery, activeWebView) {
        val wv = activeWebView ?: return@LaunchedEffect
        if (salesOrderSearchQuery.isBlank()) {
            // Restore all pages by re-running buildPageList (same as clear button)
            wv.evaluateJavascript(
                "(function(){" +
                "pendingSearch=null;" +
                "var i=document.getElementById('searchInput');" +
                "if(i)i.value='';" +
                "if(typeof buildPageList==='function')buildPageList();" +
                "var r=document.getElementById('searchResults');if(r)r.innerHTML='';" +
                "var c=document.getElementById('clearSearchBtn');if(c)c.style.display='none';" +
                "})();", null
            )
        } else {
            val escaped = salesOrderSearchQuery
                .replace("\\", "\\\\")
                .replace("'", "\\'")
            // Pass query directly to runSearch() — searchInput element no longer exists in reader.html
            // Delay slightly so reader.html has time to load the PDF before
            // runSearch() is called (pdfDoc must be non-null for the filter to work).
            delay(600)
            wv.evaluateJavascript(
                "(function(){if(typeof runSearch==='function')runSearch('$escaped');})();", null
            )
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0F0F0F))
            .imePadding()
    ) {
        // Content area
        Box(modifier = Modifier.weight(1f)) {
            when (activeTab) {
                BrowserTab.SALES_ORDER -> SalesOrderTab(
                    selectedFile   = selectedFile,
                    pdfs           = pdfs,
                    loading        = loading,
                    onAutoSelect   = { file -> selectedFile = file },
                    onClose        = onClose,
                    onWebViewBound = { wv -> activeWebView = wv }
                )
                BrowserTab.LIST    -> ListTab(
                    pdfs          = pdfs,
                    loading       = loading,
                    error         = error,
                    expandedFiles = expandedFiles,
                    shippedKeys   = shippedKeys,
                    selectedFile  = selectedFile,
                    searchQuery   = listSearchQuery,
                    onToggleExpand = { name ->
                        expandedFiles = if (expandedFiles.contains(name))
                            expandedFiles - name else expandedFiles + name
                    },
                    onOpenReader   = { file -> selectedFile = file; activeTab = BrowserTab.SALES_ORDER },
                    onToggleShipped = { file, page ->
                        ShippedStore.toggle(context, file, page)
                    },
                    onRefresh = {
                        scope.launch {
                            loading = true; error = null
                            try { pdfs = HubClient.shared.fetchPdfMeta() }
                            catch (e: Exception) { error = e.message }
                            loading = false
                        }
                    },
                    onNavigateToSettings = onNavigateToSettings
                )
                BrowserTab.SEARCH  -> SearchTab(
                    pdfs        = pdfs,
                    query       = searchQuery,
                    onQueryChange = { searchQuery = it },
                    shippedKeys = shippedKeys,
                    onOpenReader = { file -> selectedFile = file; activeTab = BrowserTab.SALES_ORDER }
                )
                BrowserTab.SHIPPED -> ShippedTab(
                    pdfs        = pdfs,
                    shippedKeys = shippedKeys,
                    searchQuery = shippedSearchQuery,
                    onOpenReader = { file -> selectedFile = file; activeTab = BrowserTab.SALES_ORDER },
                    onUnmark    = { file, page -> ShippedStore.unmarkShipped(context, file, page) }
                )
            }
        }

        // ── Inline search — docks above keyboard via imePadding on Column ────
        InlineSearchOverlay(
            visible            = showInlineSearch,
            activeTab          = activeTab,
            pdfs               = pdfs,
            salesOrderQuery    = salesOrderSearchQuery,
            listQuery          = listSearchQuery,
            shippedQuery       = shippedSearchQuery,
            onSalesOrderChange = { salesOrderSearchQuery = it },
            onListChange       = { listSearchQuery = it },
            onShippedChange    = { shippedSearchQuery = it }
        )

        // ── Bottom tab bar ────────────────────────────────────────────────
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color(0xFF1A1A1A))
                .padding(horizontal = 8.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            BrowserTabButton("SALES ORDER", activeTab == BrowserTab.SALES_ORDER, salesOrderSearchQuery.isNotBlank()) {
                if (activeTab == BrowserTab.SALES_ORDER) {
                    showInlineSearch = !showInlineSearch
                    if (!showInlineSearch) salesOrderSearchQuery = ""
                } else {
                    // Clear the outgoing tab's search so it doesn't stay filtered invisibly
                    when (activeTab) {
                        BrowserTab.LIST    -> listSearchQuery = ""
                        BrowserTab.SHIPPED -> shippedSearchQuery = ""
                        else               -> {}
                    }
                    activeTab = BrowserTab.SALES_ORDER; showInlineSearch = false
                }
            }
            BrowserTabButton("LIST", activeTab == BrowserTab.LIST, listSearchQuery.isNotBlank()) {
                if (activeTab == BrowserTab.LIST) {
                    showInlineSearch = !showInlineSearch
                    if (!showInlineSearch) listSearchQuery = ""
                } else {
                    when (activeTab) {
                        BrowserTab.SHIPPED -> shippedSearchQuery = ""
                        else               -> {}
                    }
                    activeTab = BrowserTab.LIST; showInlineSearch = false
                }
            }
            BrowserTabButton("SHIPPED", activeTab == BrowserTab.SHIPPED, shippedSearchQuery.isNotBlank()) {
                if (activeTab == BrowserTab.SHIPPED) {
                    showInlineSearch = !showInlineSearch
                    if (!showInlineSearch) shippedSearchQuery = ""
                } else {
                    when (activeTab) {
                        BrowserTab.LIST -> listSearchQuery = ""
                        else            -> {}
                    }
                    activeTab = BrowserTab.SHIPPED; showInlineSearch = false
                }
            }
            BrowserTabButton("SEARCH", activeTab == BrowserTab.SEARCH) {
                // Clear any open inline searches when jumping to SEARCH tab
                listSearchQuery = ""; shippedSearchQuery = ""
                activeTab = BrowserTab.SEARCH; showInlineSearch = false
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SALES ORDER TAB
// ─────────────────────────────────────────────────────────────────────────────

@Composable
private fun SalesOrderTab(
    selectedFile: String?,
    pdfs: List<PdfMeta>,
    loading: Boolean,
    onAutoSelect: (String) -> Unit,
    onClose: () -> Unit,
    onWebViewBound: (WebView?) -> Unit = {}
) {
    val context = LocalContext.current
    val webViewRef = remember { mutableStateOf<WebView?>(null) }
    val latestSelectedFile = rememberUpdatedState(selectedFile)
    val latestOnClose      = rememberUpdatedState(onClose)
    val scope              = rememberCoroutineScope()
    var shippedFlashMsg    by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(pdfs, selectedFile) {
        if (selectedFile == null && pdfs.isNotEmpty()) {
            val latest = pdfs.maxByOrNull { it.modified } ?: pdfs.first()
            onAutoSelect(latest.name)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                val swipeThreshold = 80.dp.toPx()
                val doubleTapTimeout = 300L
                var lastTapTime = 0L

                awaitPointerEventScope {
                    while (true) {
                        // Initial pass: parent intercepts before AndroidView
                        val downEvent  = awaitPointerEvent(PointerEventPass.Initial)
                        val downChange = downEvent.changes.firstOrNull() ?: continue
                        if (!downChange.pressed) continue

                        val startX = downChange.position.x
                        val startY = downChange.position.y
                        var totalDx = 0f
                        var swipeDone = false

                        while (true) {
                            val event  = awaitPointerEvent(PointerEventPass.Initial)
                            val change = event.changes.firstOrNull() ?: break

                            if (!change.pressed) {
                                // Finger lifted — check double tap
                                if (!swipeDone) {
                                    val dx = change.position.x - startX
                                    val dy = change.position.y - startY
                                    if (kotlin.math.abs(dx) < 30f && kotlin.math.abs(dy) < 30f) {
                                        val now = System.currentTimeMillis()
                                        if (now - lastTapTime in 1L until doubleTapTimeout) {
                                            event.changes.forEach { it.consume() }
                                            val wv   = webViewRef.value
                                            val file = latestSelectedFile.value
                                            if (wv != null && file != null) {
                                                wv.evaluateJavascript(
                                                    "(typeof currentPage !== 'undefined' ? currentPage : 1).toString()"
                                                ) { result ->
                                                    val page = result.trim('"').toIntOrNull() ?: 1
                                                    val wasShipped = ShippedStore.isShipped(file, page - 1)
                                                    ShippedStore.toggle(context, file, page - 1)
                                                    val msg = if (!wasShipped) "Page $page  ✓  SHIPPED" else "Page $page  ✕  Unmarked"
                                                    scope.launch {
                                                        shippedFlashMsg = msg
                                                        delay(1800)
                                                        shippedFlashMsg = null
                                                    }
                                                }
                                            }
                                            lastTapTime = 0L
                                        } else {
                                            lastTapTime = now
                                        }
                                    }
                                }
                                break
                            }

                            totalDx += (change.position.x - change.previousPosition.x)
                            val absdy = kotlin.math.abs(change.position.y - startY)
                            if (!swipeDone && totalDx > swipeThreshold && totalDx > absdy) {
                                event.changes.forEach { it.consume() }
                                swipeDone = true
                                latestOnClose.value()
                                break
                            }
                        }
                    }
                }
            }
    ) {
        when {
            selectedFile != null -> ReaderWebViewScreen(
                filename         = selectedFile,
                onWebViewCreated = { wv -> webViewRef.value = wv; onWebViewBound(wv) }
            )
            loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Color(0xFFFF9500))
            }
            else -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("No PDF available", color = Color(0xFF555555), fontSize = 13.sp)
            }
        }

        // ── Shipped flash badge ───────────────────────────────────────────────
        AnimatedVisibility(
            visible = shippedFlashMsg != null,
            enter   = fadeIn(tween(180)) + slideInVertically(tween(180)) { it / 2 },
            exit    = fadeOut(tween(350)),
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 36.dp)
        ) {
            shippedFlashMsg?.let { msg ->
                Text(
                    text       = msg,
                    color      = if (msg.contains("SHIPPED")) Color(0xFF4CAF50) else Color(0xFF888888),
                    fontSize   = 13.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                    modifier   = Modifier
                        .background(Color(0xE6101010), RoundedCornerShape(20.dp))
                        .padding(horizontal = 20.dp, vertical = 10.dp)
                )
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// LIST TAB
// ─────────────────────────────────────────────────────────────────────────────

@Composable
private fun ListTab(
    pdfs: List<PdfMeta>,
    loading: Boolean,
    error: String?,
    expandedFiles: Set<String>,
    shippedKeys: Set<String>,
    selectedFile: String?,
    searchQuery: String,
    onToggleExpand: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onToggleShipped: (String, Int) -> Unit,
    onRefresh: () -> Unit,
    onNavigateToSettings: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 14.dp, vertical = 10.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Orders", color = Color(0xFFFF9500), fontSize = 18.sp, fontWeight = FontWeight.Black)
            IconButton(onClick = onRefresh) {
                Icon(Icons.Default.Refresh, contentDescription = "Refresh", tint = Color(0xFFFF9500))
            }
        }
        Spacer(Modifier.height(6.dp))

        when {
            loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Color(0xFFFF9500))
            }
            error != null -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(error, color = Color(0xFFFF6B6B), fontSize = 13.sp)
                TextButton(onClick = onNavigateToSettings) {
                    Text("Open Settings →", color = Color(0xFFFF9500), fontSize = 12.sp)
                }
            }
            pdfs.isEmpty() -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("No PDFs found.", color = Color(0xFFB7B7B7), fontSize = 13.sp)
                TextButton(onClick = onNavigateToSettings) {
                    Text("Check Hub connection →", color = Color(0xFFFF9500), fontSize = 12.sp)
                }
            }
            else -> {
                val filteredPdfs = if (searchQuery.isBlank()) pdfs
                    else pdfs.filter { it.displayName.contains(searchQuery, ignoreCase = true) }
                val grouped = filteredPdfs.groupBy { it.dateLabel }.toSortedMap(reverseOrder())
                LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    grouped.forEach { (date, files) ->
                        item {
                            Text(
                                text = date.ifEmpty { "Unknown Date" },
                                color = Color(0xFFFF9500),
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier.padding(top = 8.dp, bottom = 2.dp)
                            )
                        }
                        items(files, key = { it.name }) { pdf ->
                            val isExpanded = expandedFiles.contains(pdf.name)
                            val shippedForFile = ShippedStore.shippedPagesFor(pdf.name)
                            PdfFileRow(
                                pdf           = pdf,
                                isExpanded    = isExpanded,
                                shippedPages  = shippedForFile,
                                isSelected    = pdf.name == selectedFile,
                                onTap         = {
                                    onToggleExpand(pdf.name)
                                    onOpenReader(pdf.name)
                                },
                                onToggleExpand = { onToggleExpand(pdf.name) },
                                onToggleShipped = { page -> onToggleShipped(pdf.name, page) }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PdfFileRow(
    pdf: PdfMeta,
    isExpanded: Boolean,
    shippedPages: Set<Int>,
    isSelected: Boolean,
    onTap: () -> Unit,
    onToggleExpand: () -> Unit,
    onToggleShipped: (Int) -> Unit
) {
    Column {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onTap),
            color = if (isSelected) Color(0xFF2A1800) else Color(0xFF1C1C1C),
            shape = RoundedCornerShape(8.dp)
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(pdf.displayName, color = if (isSelected) Color(0xFFFF9500) else Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    if (pdf.modified.isNotEmpty()) {
                        Text(
                            pdf.modified.take(19).replace('T', ' '),
                            color = Color(0xFF888888), fontSize = 10.sp
                        )
                    }
                }
                if (shippedPages.isNotEmpty()) {
                    Text(
                        "${shippedPages.size} shipped",
                        color = Color(0xFF4CAF50),
                        fontSize = 10.sp,
                        modifier = Modifier.padding(end = 8.dp)
                    )
                }
                // Expand chevron
                Text(
                    if (isExpanded) "▲" else "▼",
                    color = Color(0xFF555555),
                    fontSize = 10.sp,
                    modifier = Modifier.clickable(onClick = onToggleExpand)
                )
            }
        }

        // Expanded page list — pages are 0-indexed; display as "Page N"
        if (isExpanded) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 12.dp, end = 4.dp, top = 2.dp, bottom = 4.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                val pageCount = pdf.pageCount
                if (pageCount <= 0) {
                    // Page count unknown (e.g. .nl file or not yet loaded)
                    Text(
                        "Page count unavailable",
                        color = Color(0xFF555555),
                        fontSize = 11.sp,
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp)
                    )
                } else {
                    repeat(pageCount) { idx ->
                        val isShipped = shippedPages.contains(idx)
                        PageRow(
                            pageNum   = idx + 1,
                            isShipped = isShipped,
                            onDoubleTap = { onToggleShipped(idx) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PageRow(pageNum: Int, isShipped: Boolean, onDoubleTap: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(4.dp))
            .background(if (isShipped) Color(0xFF1A2E1A) else Color(0xFF151515))
            .pointerInput(Unit) { detectTapGestures(onDoubleTap = { onDoubleTap() }) }
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            "Page $pageNum",
            color = if (isShipped) Color(0xFF4CAF50) else Color(0xFFAAAAAA),
            fontSize = 12.sp,
            modifier = Modifier.weight(1f)
        )
        if (isShipped) {
            Text(
                "✓ SHIPPED",
                color = Color(0xFF4CAF50),
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace
            )
        } else {
            Text(
                "double-tap to ship",
                color = Color(0xFF444444),
                fontSize = 9.sp
            )
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEARCH TAB
// ─────────────────────────────────────────────────────────────────────────────

@Composable
private fun SearchTab(
    pdfs: List<PdfMeta>,
    query: String,
    onQueryChange: (String) -> Unit,
    shippedKeys: Set<String>,
    onOpenReader: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 14.dp, vertical = 10.dp)
    ) {
        // Search bar
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(10.dp))
                .background(Color(0xFF222222))
                .padding(horizontal = 14.dp, vertical = 10.dp)
        ) {
            if (query.isEmpty()) {
                Text("Search PDFs…", color = Color(0xFF555555), fontSize = 14.sp)
            }
            BasicTextField(
                value         = query,
                onValueChange = onQueryChange,
                singleLine    = true,
                textStyle     = TextStyle(color = Color.White, fontSize = 14.sp),
                cursorBrush   = SolidColor(Color(0xFFFF9500)),
                modifier      = Modifier.fillMaxWidth()
            )
        }

        Spacer(Modifier.height(10.dp))

        val results = if (query.isBlank()) emptyList()
        else pdfs.filter { it.displayName.contains(query, ignoreCase = true) }

        if (query.isBlank()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("Type to search", color = Color(0xFF444444), fontSize = 13.sp)
            }
        } else if (results.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("No results for \"$query\"", color = Color(0xFF888888), fontSize = 13.sp)
            }
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                items(results, key = { it.name }) { pdf ->
                    val shippedCount = ShippedStore.shippedPagesFor(pdf.name).size
                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onOpenReader(pdf.name) },
                        color = Color(0xFF1C1C1C),
                        shape = RoundedCornerShape(8.dp)
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(pdf.displayName, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                                if (pdf.modified.isNotEmpty()) {
                                    Text(pdf.modified.take(10), color = Color(0xFF888888), fontSize = 10.sp)
                                }
                            }
                            if (shippedCount > 0) {
                                Text("$shippedCount shipped", color = Color(0xFF4CAF50), fontSize = 10.sp)
                            }
                        }
                    }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// INLINE SEARCH OVERLAY  (standalone composable — avoids ColumnScope receiver)
// ─────────────────────────────────────────────────────────────────────────────

@Composable
private fun InlineSearchOverlay(
    visible: Boolean,
    activeTab: BrowserTab,
    pdfs: List<PdfMeta>,
    salesOrderQuery: String,
    listQuery: String,
    shippedQuery: String,
    onSalesOrderChange: (String) -> Unit,
    onListChange: (String) -> Unit,
    onShippedChange: (String) -> Unit
) {
    val focusRequester = remember { FocusRequester() }
    val keyboard       = LocalSoftwareKeyboardController.current

    LaunchedEffect(visible) {
        if (visible) {
            focusRequester.requestFocus()
            keyboard?.show()
        } else {
            keyboard?.hide()
        }
    }

    AnimatedVisibility(
        visible = visible,
        enter   = slideInVertically(tween(200)) { it } + fadeIn(tween(200)),
        exit    = slideOutVertically(tween(200)) { it } + fadeOut(tween(200))
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            val placeholder = when (activeTab) {
                BrowserTab.SALES_ORDER -> "Find in document\u2026"
                BrowserTab.LIST        -> "Filter orders\u2026"
                BrowserTab.SHIPPED     -> "Filter shipped\u2026"
                else                   -> "Search\u2026"
            }
            val activeQuery = when (activeTab) {
                BrowserTab.SALES_ORDER -> salesOrderQuery
                BrowserTab.LIST        -> listQuery
                BrowserTab.SHIPPED     -> shippedQuery
                else                   -> ""
            }
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF1A1A1A))
                    .padding(horizontal = 14.dp, vertical = 12.dp)
            ) {
                if (activeQuery.isEmpty()) {
                    Text(placeholder, color = Color(0xFF555555), fontSize = 14.sp)
                }
                BasicTextField(
                    value         = activeQuery,
                    onValueChange = { q ->
                        when (activeTab) {
                            BrowserTab.SALES_ORDER -> onSalesOrderChange(q)
                            BrowserTab.LIST        -> onListChange(q)
                            BrowserTab.SHIPPED     -> onShippedChange(q)
                            else                   -> {}
                        }
                    },
                    singleLine    = true,
                    textStyle     = TextStyle(color = Color.White, fontSize = 14.sp),
                    cursorBrush   = SolidColor(Color(0xFFFF9500)),
                    modifier      = Modifier
                        .fillMaxWidth()
                        .focusRequester(focusRequester)
                )
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHIPPED TAB
// ─────────────────────────────────────────────────────────────────────────────

@Composable
private fun ShippedTab(
    pdfs: List<PdfMeta>,
    shippedKeys: Set<String>,
    searchQuery: String,
    onOpenReader: (String) -> Unit,
    onUnmark: (String, Int) -> Unit
) {
    val context = LocalContext.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 14.dp, vertical = 10.dp)
    ) {
        Text("Shipped", color = Color(0xFF4CAF50), fontSize = 18.sp, fontWeight = FontWeight.Black)
        Spacer(Modifier.height(8.dp))

        if (shippedKeys.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    "No items shipped yet.\nDouble-tap a page in List to mark shipped.",
                    color = Color(0xFF555555),
                    fontSize = 13.sp,
                    textAlign = TextAlign.Center
                )
            }
            return
        }

        // Group shipped entries by filename
        val allByFile = shippedKeys
            .mapNotNull { key ->
                val parts = key.split("::")
                if (parts.size == 2) parts[0] to (parts[1].toIntOrNull() ?: return@mapNotNull null)
                else null
            }
            .groupBy({ it.first }, { it.second })
            .toSortedMap()
        val byFile = if (searchQuery.isBlank()) allByFile
            else allByFile.filter { (filename, _) ->
                val meta = pdfs.find { it.name == filename }
                (meta?.displayName ?: filename).contains(searchQuery, ignoreCase = true)
            }

        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            byFile.forEach { (filename, pages) ->
                val meta = pdfs.find { it.name == filename }
                item {
                    Text(
                        meta?.displayName ?: filename,
                        color = Color(0xFFFF9500),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier
                            .padding(top = 8.dp, bottom = 2.dp)
                            .clickable { onOpenReader(filename) }
                    )
                }
                items(pages.sorted(), key = { "$filename::$it" }) { pageIdx ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(4.dp))
                            .background(Color(0xFF1A2E1A))
                            .pointerInput(Unit) {
                                detectTapGestures(onDoubleTap = { onUnmark(filename, pageIdx) })
                            }
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            "Page ${pageIdx + 1}",
                            color = Color(0xFF4CAF50),
                            fontSize = 13.sp,
                            modifier = Modifier.weight(1f)
                        )
                        Text(
                            "✓ SHIPPED",
                            color = Color(0xFF4CAF50),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            fontFamily = FontFamily.Monospace
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(
                            "double-tap to undo",
                            color = Color(0xFF3A5A3A),
                            fontSize = 9.sp
                        )
                    }
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED
// ─────────────────────────────────────────────────────────────────────────────

@Composable
private fun BrowserTabButton(label: String, selected: Boolean, hasActiveFilter: Boolean = false, onClick: () -> Unit) {
    val bg   = if (selected) Color(0xFFFF9500).copy(alpha = 0.15f) else Color.Transparent
    val text = if (selected) Color(0xFFFF9500) else Color(0xFF555555)
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(6.dp))
            .background(bg)
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 6.dp),
        contentAlignment = Alignment.Center
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(label, color = text, fontSize = 11.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
            if (hasActiveFilter) {
                Box(
                    modifier = Modifier
                        .size(5.dp)
                        .clip(androidx.compose.foundation.shape.CircleShape)
                        .background(Color(0xFFFF9500))
                )
            }
        }
    }
}

