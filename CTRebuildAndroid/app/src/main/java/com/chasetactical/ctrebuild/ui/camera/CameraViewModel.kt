package com.chasetactical.ctrebuild.ui.camera

import android.graphics.RectF
import android.media.Image
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.chasetactical.ctrebuild.models.ColumnDefinition
import com.chasetactical.ctrebuild.models.MobileCardEntry
import com.chasetactical.ctrebuild.network.HubClient
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import kotlinx.coroutines.launch
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.imgproc.Imgproc
import java.util.concurrent.Executor
import kotlin.math.max

data class ScanResult(
    val value: String,
    val format: String,
    var timeMs: Long = System.currentTimeMillis()
)

data class BarcodeOverlay(
    val id: Int,
    val bounds: RectF
)

private data class BarcodeDetection(
    val rawValue: String,
    val format: Int,
    val bounds: RectF?
)

private data class KalmanTrackData(
    val id: Int,
    var bounds: RectF,
    val kalman: KalmanBoxFilter,
    var lastSeenMs: Long
)

class CameraViewModel : ViewModel() {

    val linkedLabels  = mutableStateMapOf<String, String>()
    val linkedEntries = mutableStateMapOf<String, org.json.JSONObject>()
    val linkedTables  = mutableStateMapOf<String, String>()
    val cardConfig    = mutableStateOf<Map<String, MobileCardEntry>>(emptyMap())
    val allDefs       = mutableStateOf<Map<String, List<ColumnDefinition>>>(emptyMap())

    val scans           = mutableStateListOf<ScanResult>()
    val currentOverlays = mutableStateListOf<BarcodeOverlay>()
    val zoomRatio        = mutableStateOf(1f)
    val minZoom          = mutableStateOf(1f)
    val maxZoom          = mutableStateOf(30f)
    val isDraggingZoom   = mutableStateOf(false)
    val dragSensitivity  = mutableStateOf(1.0f)

    val scanEnabled     = mutableStateOf(false)
    val scanBeepTrigger = mutableStateOf(0)

    private val sensitivityLevels = listOf(1.0f, 1.5f, 2.0f, 3.0f, 5.0f)

    fun cycleSensitivity() {
        val idx = sensitivityLevels.indexOf(dragSensitivity.value)
        dragSensitivity.value = sensitivityLevels[(idx + 1) % sensitivityLevels.size]
    }

    @Volatile var viewWidth  = 0
    @Volatile var viewHeight = 0

    private val mainHandler  = Handler(Looper.getMainLooper())
    private val mainExecutor = Executor { mainHandler.post(it) }

    private var camera2Session: Camera2Session? = null
    private val csrtTracker    = CsrtTracker()
    private lateinit var superResolution: SuperResolutionProcessor
    private val barcodeScanner = BarcodeScanning.getClient(
        BarcodeScannerOptions.Builder()
            .setBarcodeFormats(
                Barcode.FORMAT_QR_CODE,
                Barcode.FORMAT_CODE_128,
                Barcode.FORMAT_CODE_39,
                Barcode.FORMAT_DATA_MATRIX,
                Barcode.FORMAT_EAN_13,
                Barcode.FORMAT_PDF417
            )
            .build()
    )

    @Volatile private var mlKitBusy  = false
    @Volatile private var mlKitArmed = false

    private val kalmanTracks = linkedMapOf<Int, KalmanTrackData>()
    private var nextTrackId  = 1
    private val iouThreshold = 0.25f
    private val staleTrackMs = 800L
    private val smoothing    = 0.35f

    private val lastSeenValues = linkedMapOf<String, Long>()

    @Volatile private var lastImgW   = 0
    @Volatile private var lastImgH   = 0
    @Volatile private var lastRotDeg = 0

    private var lastDisplayMs = System.currentTimeMillis()
    private val displayRunnable = object : Runnable {
        override fun run() {
            tickKalmanPrediction()
            mainHandler.postDelayed(this, 16L)
        }
    }

    init {
        mainHandler.post { mainHandler.postDelayed(displayRunnable, 16L) }
    }

    fun armScanner() {
        lastSeenValues.clear()
        mlKitArmed = true
        scanEnabled.value = true
    }

    // ────────────────────────────────────────────────────────────────────────
    // Camera binding (Camera2)
    // ────────────────────────────────────────────────────────────────────────

    fun bindCamera(context: android.content.Context, surface: android.view.Surface) {
        val appCtx = context.applicationContext
        superResolution = SuperResolutionProcessor(appCtx)
        val session = Camera2Session(appCtx) { image, sensorOrientation ->
            onFrame(image, sensorOrientation)
        }
        camera2Session = session
        session.open(surface)
        minZoom.value = session.minZoom
        maxZoom.value = session.maxZoom
    }

    fun onSurfaceDestroyed() {
        camera2Session?.close()
        camera2Session = null
    }

    // ────────────────────────────────────────────────────────────────────────
    // Frame processing (Camera2 background thread)
    // ────────────────────────────────────────────────────────────────────────

    private fun onFrame(image: android.media.Image, sensorOrientation: Int) {
        val imgW = if (sensorOrientation == 90 || sensorOrientation == 270) image.height else image.width
        val imgH = if (sensorOrientation == 90 || sensorOrientation == 270) image.width else image.height
        lastImgW   = imgW
        lastImgH   = imgH
        // extractRotatedGray already rotates the Mat into display orientation, so all
        // coordinates in this pipeline (CSRT boxes, ML Kit detections) are in display
        // space (imgW × imgH).  imageToViewRect must NOT apply a further axis swap.
        lastRotDeg = 0

        // Extract gray Mat synchronously; close Image immediately after
        val grayFull: Mat
        try {
            grayFull = extractRotatedGray(image, sensorOrientation)
        } catch (_: Exception) {
            image.close()
            return
        }
        image.close()

        // CSRT tracking on half-res gray
        val grayHalf = Mat()
        Imgproc.resize(grayFull, grayHalf, org.opencv.core.Size(0.0, 0.0), 0.5, 0.5)
        grayFull.release()

        val csrtResults = csrtTracker.track(grayHalf)
        mainHandler.post { applyCsrtResults(csrtResults, imgW, imgH, sensorOrientation) }

        // ML Kit fires when armed or when no active tracks exist
        if ((!mlKitArmed && kalmanTracks.isNotEmpty()) || mlKitBusy) {
            grayHalf.release()
            return
        }
        mlKitBusy = true

        val hasExistingTracks = kalmanTracks.isNotEmpty()
        val bitmap: android.graphics.Bitmap
        var roiOffset: android.graphics.Point? = null

        if (hasExistingTracks) {
            val allBounds = kalmanTracks.values.map { it.bounds }
            val union = allBounds.reduce { acc, r ->
                RectF(minOf(acc.left, r.left), minOf(acc.top, r.top),
                    maxOf(acc.right, r.right), maxOf(acc.bottom, r.bottom))
            }
            val roi = expandedRoiRect(union, imgW, imgH)
            if (roi != null) {
                roiOffset = android.graphics.Point(roi.x, roi.y)
                val fullForRoi = Mat()
                Imgproc.resize(grayHalf, fullForRoi, org.opencv.core.Size(0.0, 0.0), 2.0, 2.0)
                val subMat = fullForRoi.submat(roi)
                val rgbMat = Mat()
                Imgproc.cvtColor(subMat, rgbMat, Imgproc.COLOR_GRAY2RGB)
                subMat.release(); fullForRoi.release()
                bitmap = superResolution.process(rgbMat)
                rgbMat.release()
            } else {
                bitmap = buildFullFrameBitmap(grayHalf)
            }
        } else {
            bitmap = buildFullFrameBitmap(grayHalf)
        }
        grayHalf.release()

        val roiOffsetFinal = roiOffset
        val input = InputImage.fromBitmap(bitmap, 0)
        barcodeScanner.process(input)
            .addOnSuccessListener(mainExecutor) { barcodes ->
                val detections = barcodes.mapNotNull { b ->
                    val raw = b.rawValue ?: return@mapNotNull null
                    val box = b.boundingBox?.let { rect ->
                        val r = RectF(rect)
                        if (roiOffsetFinal != null) r.offset(roiOffsetFinal.x.toFloat(), roiOffsetFinal.y.toFloat())
                        r
                    }
                    BarcodeDetection(raw, b.format, box)
                }
                handleMlKitDetections(detections, imgW, imgH, sensorOrientation)
                mlKitBusy = false
            }
            .addOnFailureListener { mlKitBusy = false }
    }

    private fun buildFullFrameBitmap(grayHalf: Mat): android.graphics.Bitmap {
        val fullMat = Mat()
        Imgproc.resize(grayHalf, fullMat, org.opencv.core.Size(0.0, 0.0), 2.0, 2.0)
        val rgbMat = Mat()
        Imgproc.cvtColor(fullMat, rgbMat, Imgproc.COLOR_GRAY2RGB)
        fullMat.release()
        val bmp = superResolution.process(rgbMat)
        rgbMat.release()
        return bmp
    }

    // ────────────────────────────────────────────────────────────────────────
    // CSRT overlay update (main thread)
    // ────────────────────────────────────────────────────────────────────────

    private fun applyCsrtResults(results: List<CsrtResult>, imgW: Int, imgH: Int, rotation: Int) {
        val now = System.currentTimeMillis()
        for (r in results) {
            val track = kalmanTracks[r.id] ?: continue
            if (r.ok) {
                val fullBox = fromCsrtBox(r.box)
                track.bounds.set(fullBox)
                track.kalman.correct(fullBox)
                track.lastSeenMs = now
            }
            // missed frames: Kalman prediction fills the gap; stale check handles eviction
        }
        val stale = kalmanTracks.values.filter { now - it.lastSeenMs > staleTrackMs }.map { it.id }
        stale.forEach { id ->
            kalmanTracks.remove(id)
            csrtTracker.removeTrack(id)
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // 60 Hz Kalman prediction loop (main thread)
    // ────────────────────────────────────────────────────────────────────────

    private fun tickKalmanPrediction() {
        val now   = System.currentTimeMillis()
        val dtSec = ((now - lastDisplayMs) / 1000f).coerceIn(0.001f, 0.1f)
        lastDisplayMs = now

        val vW = viewWidth; val vH = viewHeight
        if (vW <= 0 || vH <= 0) { currentOverlays.clear(); return }

        val imgW = lastImgW; val imgH = lastImgH; val rotation = lastRotDeg
        if (imgW <= 0 || imgH <= 0) { currentOverlays.clear(); return }

        val overlays = kalmanTracks.values.sortedBy { it.id }.map { track ->
            BarcodeOverlay(
                id     = track.id,
                bounds = imageToViewRect(track.kalman.predict(dtSec), imgW, imgH, rotation, vW, vH)
            )
        }
        currentOverlays.clear()
        currentOverlays.addAll(overlays)
    }

    // ────────────────────────────────────────────────────────────────────────
    // ML Kit detection handling (main thread)
    // ────────────────────────────────────────────────────────────────────────

    private fun handleMlKitDetections(
        detections: List<BarcodeDetection>,
        imgW: Int, imgH: Int, rotation: Int
    ) {
        val now         = System.currentTimeMillis()
        val boundedDets = detections.filter { it.bounds != null }
        val detBoxes    = boundedDets.map { it.bounds!! }

        // ── IoU-Hungarian matching ─────────────────────────────────────────
        val trackIds          = kalmanTracks.keys.toList()
        val matchedDetIndexes = mutableSetOf<Int>()

        if (trackIds.isNotEmpty() && detBoxes.isNotEmpty()) {
            val matches = matchHungarian(trackIds, detBoxes)
            for ((trackId, detIdx) in matches) {
                val track = kalmanTracks[trackId] ?: continue
                val det   = detBoxes[detIdx]
                val newBox = RectF(
                    lerp(track.bounds.left,   det.left,   smoothing),
                    lerp(track.bounds.top,    det.top,    smoothing),
                    lerp(track.bounds.right,  det.right,  smoothing),
                    lerp(track.bounds.bottom, det.bottom, smoothing)
                )
                track.bounds.set(newBox)
                track.kalman.correct(newBox)
                track.lastSeenMs = now
                matchedDetIndexes += detIdx
                csrtTracker.updateBox(trackId, toCsrtBox(newBox))
            }
        }

        // ── New detections ─────────────────────────────────────────────────
        boundedDets.forEachIndexed { idx, det ->
            if (idx in matchedDetIndexes) return@forEachIndexed
            val box = det.bounds ?: return@forEachIndexed
            val id  = nextTrackId++
            kalmanTracks[id] = KalmanTrackData(
                id         = id,
                bounds     = RectF(box),
                kalman     = KalmanBoxFilter().also { it.correct(box) },
                lastSeenMs = now
            )
            csrtTracker.requestSeed(id, toCsrtBox(box))
        }

        // ── Purge stale tracks ─────────────────────────────────────────────
        val stale = kalmanTracks.values.filter { now - it.lastSeenMs > staleTrackMs }.map { it.id }
        stale.forEach { id ->
            kalmanTracks.remove(id)
            csrtTracker.removeTrack(id)
        }

        // ── Scan log ───────────────────────────────────────────────────────
        for (detection in detections) {
            val raw  = detection.rawValue
            val last = lastSeenValues[raw]
            if (last != null && now - last < 2000L) continue
            lastSeenValues[raw] = now
            val existing = scans.indexOfFirst { it.value == raw }
            if (existing >= 0) {
                scans[existing].timeMs = now
                scans.add(0, scans.removeAt(existing))
            } else {
                scans.add(0, ScanResult(raw, formatName(detection.format), now))
                if (scans.size > 50) scans.removeAt(scans.lastIndex)
            }
            if (scanEnabled.value) {
                scanBeepTrigger.value++
                scanEnabled.value = false
                mlKitArmed = false
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // Coordinate transform: upright-image space → view screen space
    // ────────────────────────────────────────────────────────────────────────

    private fun imageToViewRect(
        box: RectF,
        imgW: Int, imgH: Int, rotation: Int,
        vW: Int, vH: Int
    ): RectF {
        val (rW, rH) = if (rotation == 90 || rotation == 270) {
            imgH.toFloat() to imgW.toFloat()
        } else {
            imgW.toFloat() to imgH.toFloat()
        }
        val scale = maxOf(vW / rW, vH / rH)
        val dx    = (vW - rW * scale) / 2f
        val dy    = (vH - rH * scale) / 2f
        return RectF(
            box.left   * scale + dx,
            box.top    * scale + dy,
            box.right  * scale + dx,
            box.bottom * scale + dy
        )
    }

    // ────────────────────────────────────────────────────────────────────────
    // Zoom
    // ────────────────────────────────────────────────────────────────────────

    fun setZoom(ratio: Float) {
        val clamped = ratio.coerceIn(minZoom.value, maxZoom.value)
        zoomRatio.value = clamped
        camera2Session?.setZoom(clamped)
    }

    fun resetZoom() {
        val min = minZoom.value
        zoomRatio.value = min
        camera2Session?.setZoom(min)
    }

    // ────────────────────────────────────────────────────────────────────────
    // Linked labels / scan management
    // ────────────────────────────────────────────────────────────────────────

    /** Fetches barcode links from the Hub and populates [linkedLabels], [linkedEntries], [linkedTables], [cardConfig], and [allDefs]. */
    fun loadLinkedLabels() {
        viewModelScope.launch {
            val links = HubClient.shared.fetchBarcodeLinks()
            val labelMap  = mutableMapOf<String, String>()
            val tableMap  = mutableMapOf<String, String>()  // barcodeValue → tableName
            val entryIdMap = mutableMapOf<String, String>() // barcodeValue → entryId
            for (link in links) {
                val bv = link.optString("sourceBarcodeValue").ifBlank { continue }
                val label = link.optString("targetEntryLabelSnapshot").ifBlank {
                    link.optString("targetEntryId").take(8).ifBlank { continue }
                }
                labelMap[bv.lowercase()] = label
                val table = link.optString("targetTableName").ifBlank { null } ?: continue
                val entryId = link.optString("targetEntryId").ifBlank { null } ?: continue
                tableMap[bv.lowercase()]   = table
                entryIdMap[bv.lowercase()] = entryId
            }
            linkedLabels.clear()
            linkedLabels.putAll(labelMap)
            linkedTables.clear()
            linkedTables.putAll(tableMap)

            if (tableMap.isNotEmpty()) {
                val tableNames = tableMap.values.toSet()
                val fetchedEntries = mutableMapOf<String, List<org.json.JSONObject>>()
                val fetchedDefs    = mutableMapOf<String, List<ColumnDefinition>>()
                for (table in tableNames) {
                    fetchedEntries[table] = HubClient.shared.fetchEntries(table)
                    fetchedDefs[table]    = HubClient.shared.fetchColumnDefinitions(table)
                }
                allDefs.value = fetchedDefs

                val entryMap = mutableMapOf<String, org.json.JSONObject>()
                for ((bv, table) in tableMap) {
                    val targetId = entryIdMap[bv] ?: continue
                    val entry = fetchedEntries[table]?.firstOrNull { it.optString("id") == targetId }
                        ?: continue
                    entryMap[bv] = entry
                }
                linkedEntries.clear()
                linkedEntries.putAll(entryMap)

                cardConfig.value = HubClient.shared.fetchMobileCardConfig()
            }
        }
    }

    /** Called after a successful assign to immediately reflect the new label. */
    fun setLinkedLabel(barcodeValue: String, label: String) {
        linkedLabels[barcodeValue.lowercase()] = label
    }

    fun removeScan(value: String) {
        scans.removeAll { it.value == value }
        lastSeenValues.remove(value)
        val key = value.lowercase()
        linkedLabels.remove(key)
        linkedEntries.remove(key)
        linkedTables.remove(key)
    }

    fun editScan(oldValue: String, newValue: String) {
        if (newValue.isBlank()) return
        val idx = scans.indexOfFirst { it.value == oldValue }
        if (idx >= 0) scans[idx] = scans[idx].copy(value = newValue)
        lastSeenValues.remove(oldValue)
        val oldKey = oldValue.lowercase()
        val newKey = newValue.lowercase()
        val label = linkedLabels.remove(oldKey)
        if (label != null) linkedLabels[newKey] = label
        val entry = linkedEntries.remove(oldKey)
        if (entry != null) linkedEntries[newKey] = entry
        val table = linkedTables.remove(oldKey)
        if (table != null) linkedTables[newKey] = table
    }

    // ────────────────────────────────────────────────────────────────────────
    // Lifecycle
    // ────────────────────────────────────────────────────────────────────────

    override fun onCleared() {
        super.onCleared()
        mainHandler.removeCallbacks(displayRunnable)
        camera2Session?.close()
        csrtTracker.reset()
        if (::superResolution.isInitialized) superResolution.close()
        barcodeScanner.close()
    }

    // ────────────────────────────────────────────────────────────────────────
    // Image extraction helper (Camera2 background thread)
    // ────────────────────────────────────────────────────────────────────────

    private fun extractRotatedGray(image: android.media.Image, rotationDegrees: Int): Mat {
        val plane       = image.planes[0]
        val buffer      = plane.buffer
        val rowStride   = plane.rowStride
        val pixelStride = plane.pixelStride
        val width       = image.width
        val height      = image.height

        val raw  = Mat(height, width, CvType.CV_8UC1)
        val data = ByteArray(buffer.remaining())
        buffer.get(data)

        if (rowStride == width && pixelStride == 1) {
            raw.put(0, 0, data)
        } else if (pixelStride == 1) {
            for (r in 0 until height) {
                raw.put(r, 0, data, r * rowStride, width)
            }
        } else {
            val row = ByteArray(width)
            for (r in 0 until height) {
                for (c in 0 until width) {
                    row[c] = data[r * rowStride + c * pixelStride]
                }
                raw.put(r, 0, row)
            }
        }

        val rotated = Mat()
        when (rotationDegrees) {
            90  -> Core.rotate(raw, rotated, Core.ROTATE_90_CLOCKWISE)
            180 -> Core.rotate(raw, rotated, Core.ROTATE_180)
            270 -> Core.rotate(raw, rotated, Core.ROTATE_90_COUNTERCLOCKWISE)
            else -> raw.copyTo(rotated)
        }
        raw.release()
        return rotated
    }

    // ────────────────────────────────────────────────────────────────────────
    // Coordinate helpers (CSRT ↔ full-res image space)
    // ────────────────────────────────────────────────────────────────────────

    private fun toCsrtBox(r: RectF)   = RectF(r.left * 0.5f, r.top * 0.5f, r.right * 0.5f, r.bottom * 0.5f)
    private fun fromCsrtBox(r: RectF) = RectF(r.left * 2f,   r.top * 2f,   r.right * 2f,   r.bottom * 2f)

    private fun expandedRoiRect(box: RectF, cols: Int, rows: Int): org.opencv.core.Rect? {
        val dw     = box.width()  * 0.2f
        val dh     = box.height() * 0.2f
        val left   = (box.left   - dw).toInt().coerceAtLeast(0)
        val top    = (box.top    - dh).toInt().coerceAtLeast(0)
        val right  = (box.right  + dw).toInt().coerceAtMost(cols)
        val bottom = (box.bottom + dh).toInt().coerceAtMost(rows)
        val w = right - left; val h = bottom - top
        return if (w < 4 || h < 4) null else org.opencv.core.Rect(left, top, w, h)
    }

    // ────────────────────────────────────────────────────────────────────────
    // IoU + Hungarian assignment (main thread)
    // ────────────────────────────────────────────────────────────────────────

    private fun matchHungarian(trackIds: List<Int>, detections: List<RectF>): List<Pair<Int, Int>> {
        val tCount = trackIds.size
        val dCount = detections.size
        val size   = max(tCount, dCount)
        val cost   = Array(size) { FloatArray(size) { 1f } }

        for (i in 0 until tCount) {
            val track = kalmanTracks[trackIds[i]] ?: continue
            for (j in 0 until dCount) {
                cost[i][j] = 1f - iou(track.bounds, detections[j])
            }
        }

        val assignment = hungarian(cost)
        return (0 until tCount).mapNotNull { i ->
            val j = assignment[i]
            if (j < 0 || j >= dCount) return@mapNotNull null
            val overlap = iou(kalmanTracks[trackIds[i]]?.bounds ?: return@mapNotNull null, detections[j])
            if (overlap >= iouThreshold) trackIds[i] to j else null
        }
    }

    private fun hungarian(cost: Array<FloatArray>): IntArray {
        val n   = cost.size
        val u   = FloatArray(n + 1)
        val v   = FloatArray(n + 1)
        val p   = IntArray(n + 1)
        val way = IntArray(n + 1)

        for (i in 1..n) {
            p[0] = i; var j0 = 0
            val minV = FloatArray(n + 1) { Float.POSITIVE_INFINITY }
            val used = BooleanArray(n + 1)
            do {
                used[j0] = true
                val i0 = p[j0]; var delta = Float.POSITIVE_INFINITY; var j1 = 0
                for (j in 1..n) {
                    if (used[j]) continue
                    val cur = cost[i0 - 1][j - 1] - u[i0] - v[j]
                    if (cur < minV[j]) { minV[j] = cur; way[j] = j0 }
                    if (minV[j] < delta) { delta = minV[j]; j1 = j }
                }
                for (j in 0..n) {
                    if (used[j]) { u[p[j]] += delta; v[j] -= delta } else { minV[j] -= delta }
                }
                j0 = j1
            } while (p[j0] != 0)
            do { val j1 = way[j0]; p[j0] = p[j1]; j0 = j1 } while (j0 != 0)
        }

        val result = IntArray(n) { -1 }
        for (j in 1..n) { if (p[j] != 0) result[p[j] - 1] = j - 1 }
        return result
    }

    private fun iou(a: RectF, b: RectF): Float {
        val iW = (minOf(a.right, b.right)  - maxOf(a.left, b.left)).coerceAtLeast(0f)
        val iH = (minOf(a.bottom, b.bottom) - maxOf(a.top,  b.top)).coerceAtLeast(0f)
        val inter = iW * iH
        if (inter <= 0f) return 0f
        val union = a.width() * a.height() + b.width() * b.height() - inter
        return if (union <= 0f) 0f else inter / union
    }

    private fun lerp(a: Float, b: Float, t: Float) = a + (b - a) * t

    // ────────────────────────────────────────────────────────────────────────
    // Format helpers
    // ────────────────────────────────────────────────────────────────────────

    private fun formatName(format: Int): String = when (format) {
        Barcode.FORMAT_QR_CODE     -> "QR"
        Barcode.FORMAT_EAN_13      -> "EAN-13"
        Barcode.FORMAT_EAN_8       -> "EAN-8"
        Barcode.FORMAT_CODE_128    -> "Code 128"
        Barcode.FORMAT_CODE_39     -> "Code 39"
        Barcode.FORMAT_CODE_93     -> "Code 93"
        Barcode.FORMAT_DATA_MATRIX -> "Data Matrix"
        Barcode.FORMAT_PDF417      -> "PDF417"
        Barcode.FORMAT_AZTEC       -> "Aztec"
        Barcode.FORMAT_ITF         -> "ITF"
        Barcode.FORMAT_UPC_A       -> "UPC-A"
        Barcode.FORMAT_UPC_E       -> "UPC-E"
        else                       -> "Barcode"
    }
}