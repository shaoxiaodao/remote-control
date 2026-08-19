package com.remotecontrol.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Build
import android.view.accessibility.AccessibilityEvent

/**
 * 无障碍服务 —— 用于模拟触控操作
 *
 * 通过 AccessibilityService 的 dispatchGesture() API 实现：
 * - 单点触控（tap、swipe）
 * - 滚动
 * - 全局按键（返回、Home、最近任务）
 *
 * 需要在 Android 系统设置中手动开启此服务。
 */
class RemoteControlAccessibilityService : AccessibilityService() {

    companion object {
        var instance: RemoteControlAccessibilityService? = null
            private set

        var statusCallback: ((Map<String, Any>) -> Unit)? = null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        statusCallback?.invoke(mapOf(
            "type" to "accessibility",
            "enabled" to true,
        ))
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // 不需要处理事件
    }

    override fun onInterrupt() {
        // 服务被中断
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        statusCallback?.invoke(mapOf(
            "type" to "accessibility",
            "enabled" to false,
        ))
    }

    /**
     * 执行触控手势（tap/click）
     */
    fun performTap(x: Float, y: Float, duration: Long = 100): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false

        val path = Path().apply {
            moveTo(x, y)
        }

        val stroke = GestureDescription.StrokeDescription(
            path, 0, duration,
        )

        val gesture = GestureDescription.Builder()
            .addStroke(stroke)
            .build()

        return dispatchGesture(gesture, null, null)
    }

    /**
     * 执行滑动手势
     */
    fun performSwipe(
        startX: Float, startY: Float,
        endX: Float, endY: Float,
        duration: Long = 300,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false

        val path = Path().apply {
            moveTo(startX, startY)
            lineTo(endX, endY)
        }

        val stroke = GestureDescription.StrokeDescription(path, 0, duration)
        val gesture = GestureDescription.Builder()
            .addStroke(stroke)
            .build()

        return dispatchGesture(gesture, null, null)
    }

    /**
     * 执行滚动（垂直方向的 swipe）
     */
    fun performScroll(x: Float, y: Float, delta: Float): Boolean {
        val scrollDistance = delta * 500 // 调整滚动灵敏度
        return performSwipe(x, y - scrollDistance / 2, x, y + scrollDistance / 2, 200)
    }

    /**
     * 执行全局按键操作
     */
    fun performGlobalAction(action: String): Boolean {
        val actionId = when (action) {
            "back" -> GLOBAL_ACTION_BACK
            "home" -> GLOBAL_ACTION_HOME
            "recent" -> GLOBAL_ACTION_RECENTS
            "notifications" -> GLOBAL_ACTION_NOTIFICATIONS
            "quick_settings" -> GLOBAL_ACTION_QUICK_SETTINGS
            "power_dialog" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    GLOBAL_ACTION_POWER_DIALOG
                } else return false
            }
            "lock_screen" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    GLOBAL_ACTION_LOCK_SCREEN
                } else return false
            }
            "screenshot" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    GLOBAL_ACTION_TAKE_SCREENSHOT
                } else return false
            }
            else -> return false
        }
        return performGlobalAction(actionId)
    }
}

/**
 * 触控控制 —— 供 Flutter MethodChannel 调用的静态接口
 *
 * 封装了对 AccessibilityService 的调用，处理触摸的连续状态。
 */
object TouchControlService {
    // 追踪触摸状态用于连续的 touchDown -> move -> up 序列
    private var touchStartX = 0f
    private var touchStartY = 0f
    private var isTouching = false

    fun touchDown(x: Float, y: Float) {
        touchStartX = x
        touchStartY = y
        isTouching = true
        // 不立即执行，等 touchUp 或 touchMove 形成完整手势
    }

    fun touchMove(x: Float, y: Float) {
        if (!isTouching) return
        // 移动不立即发送，在 touchUp 时以 swipe 形式发送
        // 对于实时控制，可以在这里发送中间点
    }

    fun touchUp(x: Float, y: Float) {
        if (!isTouching) return
        val service = RemoteControlAccessibilityService.instance ?: return

        val dx = Math.abs(x - touchStartX)
        val dy = Math.abs(y - touchStartY)

        if (dx < 10 && dy < 10) {
            // 位移很小，视为 tap
            service.performTap(x, y)
        } else {
            // 位移较大，视为 swipe
            service.performSwipe(touchStartX, touchStartY, x, y)
        }

        isTouching = false
    }

    fun scroll(x: Float, y: Float, delta: Float) {
        val service = RemoteControlAccessibilityService.instance ?: return
        service.performScroll(x, y, delta)
    }

    fun performKeyAction(action: String) {
        val service = RemoteControlAccessibilityService.instance ?: return
        service.performGlobalAction(action)
    }
}
