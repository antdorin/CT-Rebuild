package com.chasetactical.ctrebuild.ui.camera

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.graphics.Rect
import android.hardware.camera2.*
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.media.Image
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Range
import android.util.Size
import android.view.Surface
import androidx.core.content.ContextCompat
import kotlin.math.abs

/**
 * Manages a Camera2 capture session for the back camera.
 *
 * - Preview is delivered to [previewSurface] (hardware-composited to TextureView).
 * - Analysis frames arrive via [onFrame] at [CAPTURE_FPS] fps on a background thread.
 *   The Image is open when [onFrame] is called; close it when done with the data.
 *   In practice, callers should copy all needed data and call image.close() immediately.
 *
 * Call [open] when the preview Surface is ready.
 * Call [close] in ViewModel.onCleared / surface destroyed.
 */
internal class Camera2Session(
    private val context: Context,
    private val onFrame: (image: Image, sensorOrientation: Int) -> Unit
) {
    companion object {
        const val CAPTURE_FPS   = 24
        // Target landscape sensor size; Camera2 picks the closest available.
        private const val TARGET_W = 1920
        private const val TARGET_H = 1080
        private const val BUFFERS  = 3
    }

    private val bgThread  = HandlerThread("Cam2-BG").also { it.start() }
    val bgHandler         = Handler(bgThread.looper)

    private var device:   CameraDevice?         = null
    private var session:  CameraCaptureSession? = null
    private var reader:   ImageReader?          = null
    private var prevSurf: Surface?              = null

    // Populated on open; read by ViewModel.
    @Volatile var sensorOrientation: Int  = 90
    @Volatile var minZoom:           Float = 1f
    @Volatile var maxZoom:           Float = 10f
    private var  sensorRect:         Rect? = null
    @Volatile private var zoom = 1f

    // ── Open ─────────────────────────────────────────────────────────────

    fun open(surface: Surface) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
                != PackageManager.PERMISSION_GRANTED) return

        prevSurf = surface
        val mgr      = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val id       = findBack(mgr) ?: return
        val chars    = mgr.getCameraCharacteristics(id)

        sensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
        sensorRect        = chars.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)

        if (Build.VERSION.SDK_INT >= 30) {
            chars.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)?.let {
                minZoom = it.lower
                maxZoom = it.upper.coerceAtMost(30f)
            }
        }

        val map    = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)!!
        val size   = pickSize(map.getOutputSizes(ImageFormat.YUV_420_888), TARGET_W, TARGET_H)

        reader = ImageReader.newInstance(size.width, size.height, ImageFormat.YUV_420_888, BUFFERS)
            .also { r ->
                r.setOnImageAvailableListener({ src ->
                    val img = src.acquireLatestImage() ?: return@setOnImageAvailableListener
                    onFrame(img, sensorOrientation)
                }, bgHandler)
            }

        @Suppress("MissingPermission")
        mgr.openCamera(id, object : CameraDevice.StateCallback() {
            override fun onOpened(cam: CameraDevice) {
                device = cam
                startSession(cam, surface, reader!!.surface)
            }
            override fun onDisconnected(cam: CameraDevice) { cam.close(); device = null }
            override fun onError(cam: CameraDevice, e: Int) { cam.close(); device = null }
        }, bgHandler)
    }

    // ── Session ───────────────────────────────────────────────────────────

    private fun startSession(cam: CameraDevice, preview: Surface, analysis: Surface) {
        val cb = object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(s: CameraCaptureSession) {
                session = s
                issueRepeating(s, preview, analysis)
            }
            override fun onConfigureFailed(s: CameraCaptureSession) {}
        }
        val surfaces = listOf(preview, analysis)
        if (Build.VERSION.SDK_INT >= 28) {
            cam.createCaptureSession(SessionConfiguration(
                SessionConfiguration.SESSION_REGULAR,
                surfaces.map { OutputConfiguration(it) },
                { bgHandler.post(it) }, cb
            ))
        } else {
            @Suppress("DEPRECATION")
            cam.createCaptureSession(surfaces, cb, bgHandler)
        }
    }

    private fun buildRequest(preview: Surface, analysis: Surface): CaptureRequest {
        val b = device!!.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
        b.addTarget(preview)
        b.addTarget(analysis)
        b.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, Range(CAPTURE_FPS, CAPTURE_FPS))
        b.set(CaptureRequest.CONTROL_AE_MODE,  CaptureRequest.CONTROL_AE_MODE_ON)
        b.set(CaptureRequest.CONTROL_AWB_MODE, CaptureRequest.CONTROL_AWB_MODE_AUTO)
        b.set(CaptureRequest.CONTROL_AF_MODE,  CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
        applyZoom(b)
        return b.build()
    }

    private fun issueRepeating(s: CameraCaptureSession, preview: Surface, analysis: Surface) =
        s.setRepeatingRequest(buildRequest(preview, analysis), null, bgHandler)

    // ── Zoom ──────────────────────────────────────────────────────────────

    fun setZoom(ratio: Float) {
        zoom = ratio.coerceIn(minZoom, maxZoom)
        val s   = session  ?: return
        val cam = device   ?: return
        val p   = prevSurf ?: return
        val a   = reader?.surface ?: return
        s.setRepeatingRequest(buildRequest(p, a), null, bgHandler)
    }

    private fun applyZoom(b: CaptureRequest.Builder) {
        if (Build.VERSION.SDK_INT >= 30) {
            b.set(CaptureRequest.CONTROL_ZOOM_RATIO, zoom)
        } else {
            val arr = sensorRect ?: return
            val scale = 1f / zoom
            val cw = (arr.width()  * scale).toInt()
            val ch = (arr.height() * scale).toInt()
            val cx = (arr.width()  - cw) / 2
            val cy = (arr.height() - ch) / 2
            b.set(CaptureRequest.SCALER_CROP_REGION, Rect(cx, cy, cx + cw, cy + ch))
        }
    }

    // ── Close ─────────────────────────────────────────────────────────────

    fun close() {
        session?.close();  session = null
        device?.close();   device  = null
        reader?.close();   reader  = null
        prevSurf = null
        bgThread.quitSafely()
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private fun findBack(mgr: CameraManager) = mgr.cameraIdList.firstOrNull { id ->
        mgr.getCameraCharacteristics(id)
            .get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
    }

    private fun pickSize(sizes: Array<Size>, tw: Int, th: Int): Size =
        sizes.minByOrNull { abs(it.width.toLong() * it.height - tw.toLong() * th) } ?: sizes.first()
}
