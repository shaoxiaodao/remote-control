package com.remotecontrol.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * 开机广播接收器
 *
 * 设备开机后自动启动前台服务，确保：
 * - WebSocket 连接自动建立
 * - 设备可以被远程唤醒和控制
 * - 无需用户手动打开 app
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "RC_BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON") {

            Log.i(TAG, "Boot completed, starting foreground service...")

            val serviceIntent = Intent(context, RemoteControlForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }

            // 同时启动 MainActivity 初始化 Flutter 引擎和 WebSocket 连接
            // 使用 FLAG_ACTIVITY_NEW_TASK 因为 BroadcastReceiver 没有 Activity 上下文
            val activityIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra("auto_start", true)
            }
            try {
                context.startActivity(activityIntent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start MainActivity on boot: ${e.message}")
            }
        }
    }
}
