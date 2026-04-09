package com.chasetactical.ctrebuild.ui.camera

import android.graphics.RectF

/**
 * Constant-velocity Kalman filter for a 2D bounding box.
 *
 * State  : [cx, cy, w, h, vcx, vcy, vw, vh]   (8-element)
 * Measure: [cx, cy, w, h]                       (4-element)
 *
 * Used to interpolate tracking boxes at 60 Hz display rate given ~24 Hz
 * measurements from CSRT or ML Kit.  The diagonal-P approximation is
 * sufficient for smooth visual interpolation — full matrix propagation is
 * not required here.
 *
 * Typical usage:
 *   - Call [correct] when a new CSRT or ML Kit measurement arrives (~24 Hz).
 *   - Call [predict] every display frame (~60 Hz) to get a smoothed box.
 */
internal class KalmanBoxFilter {

    private val s = FloatArray(8)  // state: [cx, cy, w, h, vcx, vcy, vw, vh]
    private val P = FloatArray(8)  // diagonal covariance

    // Process noise — how much we trust the constant-velocity model.
    private val Q_pos = 4f    // position states
    private val Q_vel = 1f    // velocity states

    // Measurement noise — how much we trust each CSRT/ML-Kit box.
    private val R = 9f

    var initialized = false
        private set

    // ── Init ──────────────────────────────────────────────────────────────

    fun init(box: RectF) {
        s[0] = box.centerX(); s[1] = box.centerY()
        s[2] = box.width();   s[3] = box.height()
        s[4] = 0f; s[5] = 0f; s[6] = 0f; s[7] = 0f
        for (i in 0..3) P[i] = 100f
        for (i in 4..7) P[i] = 10f
        initialized = true
    }

    // ── Predict — call at display refresh rate (60 Hz) ───────────────────

    fun predict(dtSec: Float): RectF {
        if (!initialized) return RectF()
        val dt = dtSec.coerceIn(0.001f, 0.1f)
        // State transition: position += velocity * dt
        for (i in 0..3) {
            s[i] += s[i + 4] * dt
            // Covariance growth (diagonal approximation, no cross terms)
            P[i]     += P[i + 4] * dt * dt + Q_pos
            P[i + 4] += Q_vel
        }
        return toBox()
    }

    // ── Correct — call when a new measurement arrives (~24 Hz) ───────────

    fun correct(box: RectF) {
        if (!initialized) { init(box); return }
        val meas = floatArrayOf(box.centerX(), box.centerY(), box.width(), box.height())
        for (i in 0..3) {
            val innov = meas[i] - s[i]
            // Kalman gain for position
            val Kp = P[i] / (P[i] + R)
            // Smaller gain for velocity — measurement is position-only
            val Kv = P[i + 4] / (P[i + 4] + R * 4f)
            s[i]     += Kp * innov
            s[i + 4] += Kv * innov
            P[i]     *= (1f - Kp).coerceAtLeast(0.01f)
            P[i + 4] *= (1f - Kv).coerceAtLeast(0.01f)
        }
    }

    /** Returns the current box without advancing the state. */
    fun currentBox() = toBox()

    fun reset() {
        initialized = false
        s.fill(0f)
        P.fill(100f)
    }

    private fun toBox(): RectF {
        val cx = s[0]; val cy = s[1]
        val w  = s[2].coerceAtLeast(4f)
        val h  = s[3].coerceAtLeast(4f)
        return RectF(cx - w / 2f, cy - h / 2f, cx + w / 2f, cy + h / 2f)
    }
}
