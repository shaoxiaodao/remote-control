package com.remotecontrol.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val SCREEN_CHANNEL = "com.remotecontrol/screen_capture"
        private const val CONTROL_CHANNEL = "com.remotecontrol/touch_control"
        private const val WAKE_CHANNEL = "com.remotecontrol/wake_lock"
        private const val DEVICE_CHANNEL = "com.remotecontrol/device_info"
        private const val FRAME_EVENT_CHANNEL = "com.remotecontrol/screen_frames"
        private const val STATUS_EVENT_CHANNEL = "com.remotecontrol/service_status"

        private const val REQUEST_MEDIA_PROJECTION = 1001
    }

    private var screenCaptureService: ScreenCaptureService? = null
    private var wakeLockManager: WakeLockManager? = null
    private var frameEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        screenCaptureService = ScreenCaptureService(this)
        wakeLockManager = WakeLockManager(this)

        // ─── 屏幕捕获通道 ───
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCapture" -> {
                        val fps = call.argument<Int>("fps") ?: 15
                        val quality = call.argument<Int>("quality") ?: 50
                        val maxWidth = call.argument<Int>("maxWidth") ?: 720
                        requestScreenCapture(fps, quality, maxWidth, result)
                    }
                    "stopCapture" -> {
                        screenCaptureService?.stopCapture()
                        result.success(null)
                    }
                    "isCapturing" -> {
                        result.success(screenCaptureService?.isCapturing() ?: false)
                    }
                    else -> result.notImplemented()
                }
            }

        // ─── 触控模拟通道 ───
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTROL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAccessibilityEnabled" -> {
                        result.success(isAccessibilityServiceEnabled())
                    }
                    "openAccessibilitySettings" -> {
                        openAccessibilitySettings()
                        result.success(null)
                    }
                    "canWriteSettings" -> {
                        result.success(Settings.System.canWrite(this@MainActivity))
                    }
                    "requestWriteSettings" -> {
                        val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
                        intent.data = android.net.Uri.parse("package:$packageName")
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(null)
                    }
                    "touchDown" -> {
                        val x = call.argument<Double>("x")?.toFloat() ?: 0f
                        val y = call.argument<Double>("y")?.toFloat() ?: 0f
                        TouchControlService.touchDown(x, y)
                        result.success(null)
                    }
                    "touchMove" -> {
                        val x = call.argument<Double>("x")?.toFloat() ?: 0f
                        val y = call.argument<Double>("y")?.toFloat() ?: 0f
                        TouchControlService.touchMove(x, y)
                        result.success(null)
                    }
                    "touchUp" -> {
                        val x = call.argument<Double>("x")?.toFloat() ?: 0f
                        val y = call.argument<Double>("y")?.toFloat() ?: 0f
                        TouchControlService.touchUp(x, y)
                        result.success(null)
                    }
                    "scroll" -> {
                        val x = call.argument<Double>("x")?.toFloat() ?: 0f
                        val y = call.argument<Double>("y")?.toFloat() ?: 0f
                        val delta = call.argument<Double>("delta")?.toFloat() ?: 0f
                        TouchControlService.scroll(x, y, delta)
                        result.success(null)
                    }
                    "keyAction" -> {
                        val action = call.argument<String>("action") ?: "back"
                        TouchControlService.performKeyAction(action)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ─── 唤醒/锁屏通道 ───
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAKE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "wakeUp" -> {
                        wakeLockManager?.wakeUpScreen()
                        result.success(null)
                    }
                    "lockScreen" -> {
                        wakeLockManager?.lockScreen()
                        result.success(null)
                    }
                    "keepScreenOn" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        wakeLockManager?.keepScreenOn(on)
                        result.success(null)
                    }
                    "startForegroundService" -> {
                        startRemoteControlService()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ─── 设备信息通道 ───
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceId" -> {
                        result.success(Settings.Secure.getString(
                            contentResolver, Settings.Secure.ANDROID_ID))
                    }
                    "getDeviceName" -> {
                        result.success(Build.MODEL ?: "Android Device")
                    }
                    "getScreenSize" -> {
                        val display = windowManager.defaultDisplay
                        val size = android.graphics.Point()
                        @Suppress("DEPRECATION")
                        display.getRealSize(size)
                        result.success(mapOf(
                            "width" to size.x,
                            "height" to size.y,
                        ))
                    }
                    else -> result.notImplemented()
                }
            }

        // ─── 帧数据事件通道 ───
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, FRAME_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    frameEventSink = events
                    screenCaptureService?.setFrameCallback { frameData ->
                        runOnUiThread {
                            frameEventSink?.success(frameData)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    frameEventSink = null
                    screenCaptureService?.setFrameCallback(null)
                }
            })

        // ─── 服务状态事件通道 ───
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STATUS_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    RemoteControlAccessibilityService.statusCallback = { status ->
                        runOnUiThread {
                            events?.success(status)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    RemoteControlAccessibilityService.statusCallback = null
                }
            })
    }

    private fun requestScreenCapture(fps: Int, quality: Int, maxWidth: Int,
                                    result: MethodChannel.Result) {
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                as MediaProjectionManager
        startActivityForResult(mpm.createScreenCaptureIntent(), REQUEST_MEDIA_PROJECTION)

        // 存储回调参数，在 onActivityResult 中使用
        pendingCaptureParams = CaptureParams(fps, quality, maxWidth, result)
    }

    private data class CaptureParams(
        val fps: Int,
        val quality: Int,
        val maxWidth: Int,
        val result: MethodChannel.Result,
    )

    private var pendingCaptureParams: CaptureParams? = null

    @Deprecated("Use Activity Result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == REQUEST_MEDIA_PROJECTION) {
            val params = pendingCaptureParams
            if (resultCode == Activity.RESULT_OK && data != null && params != null) {
                screenCaptureService?.startCapture(
                    resultCode, data,
                    params.fps, params.quality, params.maxWidth,
                )
                params.result.success(true)
            } else {
                params?.result?.success(false)
            }
            pendingCaptureParams = null
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val service = "${packageName}/${RemoteControlAccessibilityService::class.java.canonicalName}"
        val enabledServices = Settings.Secure.getString(
            contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
        return enabledServices?.contains(service) == true
    }

    private fun openAccessibilitySettings() {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun startRemoteControlService() {
        val intent = Intent(this, RemoteControlForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        screenCaptureService?.stopCapture()
        wakeLockManager?.release()
    }
}
