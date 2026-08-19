package com.remotecontrol.app

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.util.Log
import android.view.WindowManager

/**
 * 唤醒锁管理器
 *
 * 负责：
 * - 唤醒屏幕（从锁屏状态点亮）
 * - 解除 Keyguard（让屏幕可交互）
 * - 保持屏幕常亮
 * - 锁屏操作
 *
 * 关键设计：
 * wakeUpScreen() 使用 SHOW_WHEN_LOCKED + TURN_SCREEN_ON flags
 * 配合 FULL_WAKE_LOCK 确保即使深度锁屏也能唤醒
 */
class WakeLockManager(private val context: Context) {

    companion object {
        private const val TAG = "RC_WakeLockManager"
    }

    private val powerManager =
        context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val keyguardManager =
        context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager

    private var wakeLock: PowerManager.WakeLock? = null

    /**
     * 唤醒设备屏幕（即使处于锁屏状态）
     *
     * 策略：
     * 1. 使用 FULL_WAKE_LOCK + ACQUIRE_CAUSES_WAKEUP 强制点亮屏幕
     * 2. 使用 KeyguardManager.requestDismissKeyguard (API 26+) 尝试解除锁定
     * 3. 设置 Activity flags 让窗口显示在锁屏之上
     */
    @Suppress("DEPRECATION")
    fun wakeUpScreen() {
        Log.i(TAG, "wakeUpScreen called, isInteractive=${powerManager.isInteractive}")

        // 步骤 1: 强制唤醒屏幕
        val fullWakeLock = powerManager.newWakeLock(
            PowerManager.FULL_WAKE_LOCK or
            PowerManager.ACQUIRE_CAUSES_WAKEUP or
            PowerManager.ON_AFTER_RELEASE,
            "RemoteControl:WakeUp",
        )
        fullWakeLock.acquire(10000) // 10 秒超时释放（延长以确保唤醒完成）

        // 步骤 2: 设置 Activity flags（让窗口显示在锁屏之上并点亮屏幕）
        try {
            if (context is android.app.Activity) {
                context.runOnUiThread {
                    val window = context.window
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                        window.setFlags(
                            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
                            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        window.setFlags(
                            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                            WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
                            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                            WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
                        )
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set window flags: ${e.message}")
        }

        // 步骤 3: 请求解除 Keyguard (API 26+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                if (context is android.app.Activity && keyguardManager.isKeyguardLocked) {
                    context.runOnUiThread {
                        keyguardManager.requestDismissKeyguard(context,
                            object : KeyguardManager.KeyguardDismissCallback() {
                                override fun onDismissSucceeded() {
                                    Log.i(TAG, "Keyguard dismissed successfully")
                                }
                                override fun onDismissCancelled() {
                                    Log.w(TAG, "Keyguard dismiss cancelled")
                                }
                                override fun onDismissError() {
                                    Log.e(TAG, "Keyguard dismiss error")
                                }
                            })
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to dismiss keyguard: ${e.message}")
            }
        }
    }

    /**
     * 锁定屏幕
     * 使用 AccessibilityService 的 GLOBAL_ACTION_LOCK_SCREEN
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
            Log.i(TAG, "Keep screen ON, wakeLock acquired")
        } else {
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
            wakeLock = null
            Log.i(TAG, "Keep screen OFF, wakeLock released")
        }
    }

    fun release() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }
}
