package com.chasetactical.ctrebuild.ui.camera

import android.content.Context
import android.graphics.Bitmap
import org.opencv.android.Utils
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.imgproc.Imgproc
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.gpu.GpuDelegate
import org.tensorflow.lite.nnapi.NnApiDelegate
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel

/**
 * TFLite super-resolution step applied to an ROI crop before ML Kit decode.
 *
 * Model   : src/main/assets/sr_model_int8.tflite  (FSRCNN ×2, INT8/UINT8 quantized)
 * I/O     : Input  [1, H, W, 1] UINT8 grayscale
 *           Output [1, H×2, W×2, 1] UINT8 grayscale
 * Backend : NNAPI (NPU) → GPU → CPU, selected automatically at init.
 *
 * Falls back to passthrough (no upscaling) if the model file is absent or if
 * all accelerator delegates fail to initialise.
 *
 * [process] accepts a 3-channel RGB Mat (as produced by CameraViewModel) and
 * returns an ARGB_8888 Bitmap at ×2 resolution for ML Kit InputImage.
 */
internal class SuperResolutionProcessor(context: Context) {

    private var interpreter: Interpreter? = null
    private var nnApiDelegate: NnApiDelegate? = null
    private var gpuDelegate: GpuDelegate? = null

    init {
        try {
            val buf  = loadModelFile(context, "sr_model_int8.tflite")
            interpreter = buildInterpreter(buf)
        } catch (_: Exception) {
            // Model absent or all delegates failed — passthrough mode
            releaseDelegate()
        }
    }

    /**
     * Process [crop] (3-channel RGB Mat from CameraViewModel).
     * Returns an ARGB_8888 Bitmap for [com.google.mlkit.vision.common.InputImage.fromBitmap].
     * With SR active  : converts to grayscale, runs ×2 NPU upscale, returns RGB bitmap at ×2 size.
     * Passthrough mode: returns an ARGB bitmap at the original input resolution.
     */
    fun process(crop: Mat): Bitmap {
        interpreter?.let { interp ->
            try { return runSuperResolution(interp, crop) } catch (_: Exception) { }
        }
        return matToArgbBitmap(crop)
    }

    fun close() {
        interpreter?.close()
        interpreter = null
        releaseDelegate()
    }

    // ── Inference ──────────────────────────────────────────────────────────

    private fun runSuperResolution(interp: Interpreter, rgb: Mat): Bitmap {
        // The model operates on single-channel grayscale; convert from RGB input.
        val gray = Mat()
        Imgproc.cvtColor(rgb, gray, Imgproc.COLOR_RGB2GRAY)

        val h = gray.rows()
        val w = gray.cols()

        // Dynamic input shape: resize if this crop differs from the last allocation.
        interp.resizeInput(0, intArrayOf(1, h, w, 1))
        interp.allocateTensors()

        val inputBuf = ByteBuffer.allocateDirect(h * w).order(ByteOrder.nativeOrder())
        val grayBytes = ByteArray(h * w)
        gray.get(0, 0, grayBytes)
        gray.release()
        inputBuf.put(grayBytes)
        inputBuf.rewind()

        val outH = h * 2
        val outW = w * 2
        val outputBuf = ByteBuffer.allocateDirect(outH * outW).order(ByteOrder.nativeOrder())

        interp.run(inputBuf, outputBuf)
        outputBuf.rewind()

        val outBytes = ByteArray(outH * outW)
        outputBuf.get(outBytes)

        val outGray = Mat(outH, outW, CvType.CV_8UC1)
        outGray.put(0, 0, outBytes)

        val outRgb = Mat()
        Imgproc.cvtColor(outGray, outRgb, Imgproc.COLOR_GRAY2RGB)
        outGray.release()

        val bmp = Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(outRgb, bmp)
        outRgb.release()
        return bmp
    }

    // ── Delegate selection ─────────────────────────────────────────────────

    /**
     * Tries NNAPI (NPU) → GPU → CPU, returning the first working Interpreter.
     * Failing delegates are closed before the next attempt.
     */
    private fun buildInterpreter(buf: MappedByteBuffer): Interpreter {
        // 1. NNAPI — routes to NPU / DSP on supported SoCs (Snapdragon, Exynos, etc.)
        try {
            val nd = NnApiDelegate()
            val interp = Interpreter(buf, Interpreter.Options()
                .addDelegate(nd)
                .setNumThreads(1))
            nnApiDelegate = nd
            return interp
        } catch (_: Exception) { nnApiDelegate?.close(); nnApiDelegate = null }

        // 2. GPU delegate — uses OpenCL/Vulkan compute shaders
        try {
            val gd = GpuDelegate()
            val interp = Interpreter(buf, Interpreter.Options()
                .addDelegate(gd)
                .setNumThreads(1))
            gpuDelegate = gd
            return interp
        } catch (_: Exception) { gpuDelegate?.close(); gpuDelegate = null }

        // 3. CPU fallback — use all available big cores
        return Interpreter(buf, Interpreter.Options().setNumThreads(4))
    }

    private fun releaseDelegate() {
        nnApiDelegate?.close(); nnApiDelegate = null
        gpuDelegate?.close();   gpuDelegate   = null
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private fun matToArgbBitmap(mat: Mat): Bitmap {
        val bmp = Bitmap.createBitmap(mat.cols(), mat.rows(), Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(mat, bmp)
        return bmp
    }

    private fun loadModelFile(ctx: Context, name: String): MappedByteBuffer {
        val fd = ctx.assets.openFd(name)
        return FileInputStream(fd.fileDescriptor).channel.map(
            FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.declaredLength
        )
    }
}
