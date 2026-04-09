package com.chasetactical.ctrebuild.ui.camera

import android.graphics.RectF
import org.opencv.core.Mat
import org.opencv.core.MatOfByte
import org.opencv.core.MatOfFloat
import org.opencv.core.MatOfPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Point
import org.opencv.core.Rect
import org.opencv.imgproc.Imgproc
import org.opencv.video.Video
import java.util.concurrent.ConcurrentLinkedQueue

internal data class CsrtResult(val id: Int, val box: RectF, val ok: Boolean)

private data class CsrtTrack(
    val id: Int,
    var box: RectF,
    var pts: MatOfPoint2f,
    var missedFrames: Int = 0
)

/**
 * Multi-target sparse optical-flow tracker with the same external interface previously
 * provided by TrackerCSRT.  Implemented with Lucas-Kanade pyramid LK flow
 * (available in the base `org.opencv:opencv` Maven artifact) because TrackerCSRT
 * lives in opencv_contrib which is not shipped in that artifact.
 *
 * Coordinate space: all [RectF] values and the [Mat] passed to [track] are in the
 * same coordinate system (half-resolution image space).  The ViewModel converts to/from
 * full-resolution on the way in and out.
 *
 * [updateBox] intentionally does NOT re-seed features when tracking is healthy —
 * this preserves point coherence across fast ML Kit corrections.  It only re-seeds
 * when [missedFrames] > 0 (tracker has lost the target).
 */
internal class CsrtTracker {

    private val tracks         = mutableListOf<CsrtTrack>()
    private var prevGray: Mat? = null

    private val pendingSeeds   = ConcurrentLinkedQueue<Pair<Int, RectF>>()
    private val pendingRemoves = ConcurrentLinkedQueue<Int>()

    companion object {
        private const val MAX_FEATURES  = 25
        private const val MIN_FEATURES  = 4
        private const val MAX_MISSED    = 6
        private const val QUALITY_LEVEL = 0.01
        private const val MIN_DISTANCE  = 5.0
    }

    fun requestSeed(id: Int, box: RectF) = pendingSeeds.add(id to RectF(box))

    fun removeTrack(id: Int) = pendingRemoves.add(id)

    /**
     * Update a track's box from an external ML Kit correction.
     * Only re-seeds features when the tracker has previously missed frames;
     * otherwise leaves the point set intact so appearance history is preserved.
     */
    fun updateBox(id: Int, box: RectF) {
        val track = tracks.find { it.id == id }
        if (track != null) {
            track.box.set(box)
            if (track.missedFrames > 0) requestSeed(id, box)
        }
    }

    /** Run one LK step on [gray].  Must be called on the analyzer thread only. */
    fun track(gray: Mat): List<CsrtResult> {
        applyPendingRemoves()
        applyPendingSeeds(gray)

        val prev = prevGray
        if (prev == null) {
            prevGray = gray.clone()
            return tracks.map { CsrtResult(it.id, RectF(it.box), true) }
        }

        val toRemove = mutableListOf<CsrtTrack>()
        val results  = mutableListOf<CsrtResult>()

        for (track in tracks) {
            if (track.pts.empty() || track.pts.rows() < MIN_FEATURES) {
                track.missedFrames++
                if (track.missedFrames > MAX_MISSED) toRemove += track
                results += CsrtResult(track.id, RectF(track.box), false)
                continue
            }

            val nextPts = MatOfPoint2f()
            val status  = MatOfByte()
            val err     = MatOfFloat()
            Video.calcOpticalFlowPyrLK(prev, gray, track.pts, nextPts, status, err)

            val statusArr = status.toArray()
            val prevArr   = track.pts.toArray()
            val nextArr   = nextPts.toArray()
            status.release(); err.release(); nextPts.release()

            val good = statusArr.indices.filter { statusArr[it].toInt() == 1 }

            if (good.size < MIN_FEATURES) {
                track.missedFrames++
                if (track.missedFrames > MAX_MISSED) toRemove += track
                results += CsrtResult(track.id, RectF(track.box), false)
                continue
            }

            track.missedFrames = 0

            // Estimate translation from average feature displacement
            var dx = 0.0; var dy = 0.0
            for (i in good) { dx += nextArr[i].x - prevArr[i].x; dy += nextArr[i].y - prevArr[i].y }
            dx /= good.size; dy /= good.size

            // Estimate scale from radial spread around centroid
            val pcx = good.sumOf { prevArr[it].x } / good.size
            val pcy = good.sumOf { prevArr[it].y } / good.size
            var sumPrevD = 0.0; var sumNextD = 0.0
            for (i in good) {
                sumPrevD += Math.hypot(prevArr[i].x - pcx, prevArr[i].y - pcy)
                sumNextD += Math.hypot(nextArr[i].x - (pcx + dx), nextArr[i].y - (pcy + dy))
            }
            val scale = if (sumPrevD > good.size * 2.0)
                (sumNextD / sumPrevD).toFloat().coerceIn(0.95f, 1.05f)
            else 1.0f

            track.box.offset(dx.toFloat(), dy.toFloat())
            if (scale != 1.0f) {
                val cx = track.box.centerX(); val cy = track.box.centerY()
                val hw = track.box.width() * 0.5f * scale
                val hh = track.box.height() * 0.5f * scale
                track.box.set(cx - hw, cy - hh, cx + hw, cy + hh)
            }

            track.pts.release()
            track.pts = MatOfPoint2f(*good.map { nextArr[it] }.toTypedArray())

            results += CsrtResult(track.id, RectF(track.box), true)
        }

        toRemove.forEach { it.pts.release(); tracks.remove(it) }
        prev.release()
        prevGray = gray.clone()
        return results
    }

    fun reset() {
        tracks.forEach { it.pts.release() }
        tracks.clear()
        prevGray?.release()
        prevGray = null
        pendingSeeds.clear()
        pendingRemoves.clear()
    }

    // ── Private helpers ───────────────────────────────────────────────────

    private fun applyPendingRemoves() {
        while (pendingRemoves.isNotEmpty()) {
            val id = pendingRemoves.poll() ?: break
            val removed = tracks.filter { it.id == id }
            removed.forEach { it.pts.release() }
            tracks.removeAll(removed.toSet())
        }
    }

    private fun applyPendingSeeds(gray: Mat) {
        while (pendingSeeds.isNotEmpty()) {
            val (id, box) = pendingSeeds.poll() ?: break
            seedTrack(id, box, gray)
        }
    }

    private fun seedTrack(id: Int, box: RectF, gray: Mat) {
        val removed = tracks.filter { it.id == id }
        removed.forEach { it.pts.release() }
        tracks.removeAll(removed.toSet())

        val roi = clampToMat(box, gray)
        if (roi.width <= 0 || roi.height <= 0) return

        val roiMat  = gray.submat(roi)
        val corners = MatOfPoint()
        Imgproc.goodFeaturesToTrack(roiMat, corners, MAX_FEATURES, QUALITY_LEVEL, MIN_DISTANCE)
        roiMat.release()

        if (corners.empty() || corners.rows() < MIN_FEATURES) { corners.release(); return }

        val pts = corners.toArray().map { p -> Point(p.x + roi.x, p.y + roi.y) }
        corners.release()

        tracks += CsrtTrack(id = id, box = RectF(box), pts = MatOfPoint2f(*pts.toTypedArray()))
    }

    private fun clampToMat(box: RectF, mat: Mat): Rect {
        val l = box.left.toInt().coerceIn(0, mat.cols() - 1)
        val t = box.top.toInt().coerceIn(0, mat.rows() - 1)
        val r = box.right.toInt().coerceIn(l + 1, mat.cols())
        val b = box.bottom.toInt().coerceIn(t + 1, mat.rows())
        return Rect(l, t, r - l, b - t)
    }
}
