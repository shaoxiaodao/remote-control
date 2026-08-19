package com.remotecontrol.app

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.view.WindowManager

/**
 * 唤醒锁管理器
 *
 * 负责：
 * - 唤醒屏幕（从锁屏状态点亮）
 * - 保持屏幕常亮
 * - 锁屏操作
 */
class WakeLockManager(private val context: Context) {

    private val powerManager =
        context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val keyguardManager =
        context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager

    private var wakeLock: PowerManager.WakeLock? = null

    /**
     * 唤醒设备屏幕
     *
     * 使用 FULL_WAKE_LOCK + ACQUIRE_CAUSES_WAKEUP 组合
     * 即使设备处于锁屏状态也能点亮屏幕
     *
     * 注意：解锁 Keyguard 需要 Activity 上下文，
     * 这里只负责点亮屏幕，解锁由用户在手机端操作
     */
    @Suppress("DEPRECATION")
    fun wakeUpScreen() {
        // 检查屏幕是否已亮
        if (!powerManager.isInteractive) {
            // 唤醒屏幕
            val fullWakeLock = powerManager.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
                "RemoteControl:WakeUp",
            )
            fullWakeLock.acquire(5000) // 5 秒超时释放
        }
    }

    /**
     * 锁定屏幕
     * 注意：这需要 Device Admin 权限，普通应用无法直接锁屏
     * 这里使用 AccessibilityService 的 GLOBAL_ACTION_LOCK_SCREEN
     */
    fun lockScreen() {
        val service = RemoteControlAccessibilityService.instance
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            service?.performGlobalAction("lock_screen")
        }
    }

    /**
     * 保持屏幕常亮
     */
    @Suppress("DEPRECATION")
    fun keepScreenOn(on: Boolean) {
        if (on) {
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
            wakeLock = powerManager.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "RemoteControl:KeepScreenOn",
            ).apply {
                acquire(24 * 60 * 60 * 1000L) // 最长 24 小时
            }
        } else {
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
            wakeLock = null
        }
    }

    fun release() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }
}
