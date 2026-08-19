package com.remotecontrol.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.WindowManager
import java.io.ByteArrayOutputStream

/**
 * 屏幕捕获服务
 *
 * 使用 MediaProjection API 捕获屏幕内容，
 * 通过 ImageReader 获取帧数据，压缩为 JPEG 后通过回调传出。
 */
class ScreenCaptureService(private val context: Context) {

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var isCapturing = false
    private var isCleaning = false
    private var frameCallback: ((ByteArray) -> Unit)? = null
    private val handler = Handler(Looper.getMainLooper())

    private var captureWidth = 720
    private var captureHeight = 1280
    private var fps = 15
    private var quality = 50
    private var captureInterval: Long = 66 // ~15fps
    private var lastCaptureTime = 0L
    private val jpegStream = ByteArrayOutputStream()

    fun isCapturing(): Boolean = isCapturing

    fun setFrameCallback(callback: ((ByteArray) -> Unit)?) {
        frameCallback = callback
    }

    fun startCapture(
        resultCode: Int,
        data: Intent,
        fps: Int,
        quality: Int,
        maxWidth: Int,
    ) {
        if (isCapturing) return

        // 清理上一次会话（防止资源泄漏）
        cleanup()

        this.fps = fps
        this.quality = quality
        this.captureInterval = 1000L / fps

        // 获取屏幕尺寸
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(metrics)

        // 计算缩放后的捕获尺寸
        val screenW = metrics.widthPixels
        val screenH = metrics.heightPixels
        val scale = (maxWidth.toFloat() / screenW).coerceAtMost(1f)
        captureWidth = (screenW * scale).toInt()
        captureHeight = (screenH * scale).toInt()

        // 获取 MediaProjection
        val mpm = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                as MediaProjectionManager
        mediaProjection = mpm.getMediaProjection(resultCode, data)
        mediaProjection?.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                cleanup()
            }
        }, handler)

        // 创建 ImageReader
        imageReader = ImageReader.newInstance(
            captureWidth, captureHeight,
            PixelFormat.RGBA_8888,
            2, // maxImages
        )

        imageReader?.setOnImageAvailableListener({ reader ->
            val now = System.currentTimeMillis()
            if (now - lastCaptureTime < captureInterval) {
                // 跳过帧以控制帧率
                val image = reader.acquireLatestImage()
                image?.close()
                return@setOnImageAvailableListener
            }
            lastCaptureTime = now

            val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                val planes = image.planes
                val buffer = planes[0].buffer
                val pixelStride = planes[0].pixelStride
                val rowStride = planes[0].rowStride
                val rowPadding = rowStride - pixelStride * captureWidth

                val bitmap = Bitmap.createBitmap(
                    captureWidth + rowPadding / pixelStride,
                    captureHeight,
                    Bitmap.Config.ARGB_8888,
                )
                bitmap.copyPixelsFromBuffer(buffer)

                // 裁剪到实际尺寸
                val cropped = Bitmap.createBitmap(bitmap, 0, 0, captureWidth, captureHeight)
                if (cropped != bitmap) {
                    bitmap.recycle()
                }

                // 压缩为 JPEG
                jpegStream.reset()
                cropped.compress(Bitmap.CompressFormat.JPEG, quality, jpegStream)
                cropped.recycle()

                // 回调帧数据
                val frameData = jpegStream.toByteArray()
                frameCallback?.invoke(frameData)

            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                image.close()
            }
        }, handler)

        // 创建 VirtualDisplay
        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "RemoteControl",
            captureWidth, captureHeight,
            metrics.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader?.surface,
            null, handler,
        )

        isCapturing = true
    }

    fun stopCapture() {
        cleanup()
    }

    private fun cleanup() {
        if (isCleaning) return
        isCleaning = true
        isCapturing = false
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null
        // 先置空再 stop，防止 onStop 回调再次触发 cleanup
        val mp = mediaProjection
        mediaProjection = null
        mp?.stop()
        isCleaning = false
    }
}
