package com.chasetactical.ctrebuild.ui.camera

import android.graphics.RectF
import org.opencv.core.Core
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

internal data class KltResult(val id: Int, val box: RectF)

private data class KltTrack(
    val id: Int,
    val box: RectF,           // mutable: updated every frame
    var pts: MatOfPoint2f,    // current feature point positions
    var missedFrames: Int = 0
)

/**
 * Blender-style KLT (Kanade-Lucas-Tomasi) tracker.
 *
 * Designed to run on the ImageAnalysis background thread.
 * Seeding is requested from any thread via [requestSeed] / [removeTrack] and
 * applied at the start of the next [track] call.
 */
internal class KltTracker {

    private val tracks = mutableListOf<KltTrack>()
    private var prevGray: Mat? = null

    // Thread-safe queues for cross-thread commands
    private val pendingSeeds   = ConcurrentLinkedQueue<Pair<Int, RectF>>()
    private val pendingRemoves = ConcurrentLinkedQueue<Int>()

    companion object {
        private const val MAX_FEATURES  = 25
        private const val MIN_FEATURES  = 4
        private const val MAX_MISSED    = 8
        private const val QUALITY_LEVEL = 0.01
        private const val MIN_DISTANCE  = 5.0
    }

    /** Request that a new track be seeded for [id] at [box] on the next frame. */
    fun requestSeed(id: Int, box: RectF) {
        pendingSeeds.add(id to RectF(box))
    }

    /** Request that the track with [id] be removed. */
    fun removeTrack(id: Int) {
        pendingRemoves.add(id)
    }

    /**
     * Run one KLT step on [gray] (grayscale Mat, already rotated to display orientation).
     * Returns the updated bounding boxes for all active tracks.
     */
    fun track(gray: Mat): List<KltResult> {
        applyPendingRemoves()
        applyPendingSeeds(gray)

        val prev = prevGray
        if (prev == null) {
            prevGray = gray.clone()
            return tracks.map { KltResult(it.id, RectF(it.box)) }
        }

        val toRemove = mutableListOf<KltTrack>()
        val results  = mutableListOf<KltResult>()

        for (track in tracks) {
            if (track.pts.empty() || track.pts.rows() < MIN_FEATURES) {
                track.missedFrames++
                if (track.missedFrames > MAX_MISSED) toRemove += track
                results += KltResult(track.id, RectF(track.box))
                continue
            }

            val nextPts = MatOfPoint2f()
            val status  = MatOfByte()
            val err     = MatOfFloat()

            Video.calcOpticalFlowPyrLK(prev, gray, track.pts, nextPts, status, err)

            val statusArr = status.toArray()
            val prevArr   = track.pts.toArray()
            val nextArr   = nextPts.toArray()

            status.release()
            err.release()
            nextPts.release()

            val good = (statusArr.indices).filter { statusArr[it].toInt() == 1 }

            if (good.size < MIN_FEATURES) {
                track.missedFrames++
                if (track.missedFrames > MAX_MISSED) toRemove += track
                results += KltResult(track.id, RectF(track.box))
                continue
            }

            track.missedFrames = 0

            // Average translation of all well-tracked feature points
            var dx = 0.0; var dy = 0.0
            for (i in good) {
                dx += nextArr[i].x - prevArr[i].x
                dy += nextArr[i].y - prevArr[i].y
            }
            dx /= good.size
            dy /= good.size

            // Scale estimation from radial spread of point cloud around its centroid.
            // This means the box tracks zoom-induced size changes every frame instead of
            // waiting for the next ML Kit detection (~every 15 frames), which was causing
            // the stepped/jumping size appearance during zoom.
            val pcx = good.sumOf { prevArr[it].x } / good.size
            val pcy = good.sumOf { prevArr[it].y } / good.size
            var sumPrevD = 0.0; var sumNextD = 0.0
            for (i in good) {
                sumPrevD += Math.hypot(prevArr[i].x - pcx, prevArr[i].y - pcy)
                sumNextD += Math.hypot(nextArr[i].x - (pcx + dx), nextArr[i].y - (pcy + dy))
            }
            // Only apply when points are well-dispersed (avg >2px from centroid).
            // Clamp to ±5% per frame to suppress noise from tightly-clustered point sets.
            val scale = if (sumPrevD > good.size * 2.0)
                (sumNextD / sumPrevD).toFloat().coerceIn(0.95f, 1.05f)
            else 1.0f

            track.box.offset(dx.toFloat(), dy.toFloat())
            if (scale != 1.0f) {
                val cxBox = track.box.centerX()
                val cyBox = track.box.centerY()
                val hw = track.box.width()  * 0.5f * scale
                val hh = track.box.height() * 0.5f * scale
                track.box.set(cxBox - hw, cyBox - hh, cxBox + hw, cyBox + hh)
            }

            // Keep only the tracked (good) points for next iteration
            track.pts.release()
            track.pts = MatOfPoint2f(*good.map { nextArr[it] }.toTypedArray())

            results += KltResult(track.id, RectF(track.box))
        }

        for (t in toRemove) {
            t.pts.release()
            tracks.remove(t)
        }

        prev.release()
        prevGray = gray.clone()

        return results
    }

    /** Update a track's box without re-detecting features (e.g. from ML Kit lerp). */
    fun updateBox(id: Int, box: RectF) {
        tracks.find { it.id == id }?.box?.set(box)
    }

    /** Release all OpenCV resources. */
    fun reset() {
        for (t in tracks) t.pts.release()
        tracks.clear()
        prevGray?.release()
        prevGray = null
        pendingSeeds.clear()
        pendingRemoves.clear()
    }

    // ---- private helpers ----

    private fun applyPendingSeeds(gray: Mat) {
        while (pendingSeeds.isNotEmpty()) {
            val (id, box) = pendingSeeds.poll() ?: break
            seedTrack(id, box, gray)
        }
    }

    private fun applyPendingRemoves() {
        while (pendingRemoves.isNotEmpty()) {
            val id = pendingRemoves.poll() ?: break
            val removed = tracks.filter { it.id == id }
            removed.forEach { it.pts.release() }
            tracks.removeAll(removed.toSet())
        }
    }

    private fun seedTrack(id: Int, box: RectF, gray: Mat) {
        // Remove any existing track with this id first
        val old = tracks.filter { it.id == id }
        old.forEach { it.pts.release() }
        tracks.removeAll(old.toSet())

        val roi = clampToMat(box, gray)
        if (roi.width <= 0 || roi.height <= 0) return

        val roiMat  = gray.submat(roi)
        val corners = MatOfPoint()
        Imgproc.goodFeaturesToTrack(roiMat, corners, MAX_FEATURES, QUALITY_LEVEL, MIN_DISTANCE)
        roiMat.release()

        if (corners.empty() || corners.rows() < MIN_FEATURES) {
            corners.release()
            return
        }

        // Offset from ROI origin back to full-image origin
        val pts = corners.toArray().map { p ->
            Point(p.x + roi.x, p.y + roi.y)
        }
        corners.release()

        val mat2f = MatOfPoint2f(*pts.toTypedArray())
        tracks += KltTrack(id = id, box = RectF(box), pts = mat2f)
    }

    private fun clampToMat(box: RectF, mat: Mat): Rect {
        val l = box.left.toInt().coerceIn(0, mat.cols() - 1)
        val t = box.top.toInt().coerceIn(0, mat.rows() - 1)
        val r = box.right.toInt().coerceIn(l + 1, mat.cols())
        val b = box.bottom.toInt().coerceIn(t + 1, mat.rows())
        return Rect(l, t, r - l, b - t)
    }
}
