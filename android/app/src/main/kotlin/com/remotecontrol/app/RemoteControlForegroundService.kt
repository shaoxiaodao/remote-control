package com.remotecontrol.app

import android.app.*
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log

/**
 * 前台服务 —— 用于保活
 *
 * 核心机制：
 * 1. 前台通知（防止系统杀死进程）
 * 2. PARTIAL_WAKE_LOCK（保持 CPU 运行，即使屏幕关闭）
 * 3. WifiLock（保持 WiFi 连接，防止网络断开）
 * 4. START_STICKY（服务被杀后自动重启）
 *
 * 这确保了手机长时间锁屏后，WebSocket 连接仍然存活，
 * 能够接收远程唤醒命令。
 */
class RemoteControlForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "remote_control_service"
        private const val NOTIFICATION_ID = 1001
        private const val TAG = "RC_ForegroundService"
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireLocks()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY // 被杀后自动重启
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "远程控制服务",
                NotificationManager.IMPORTANCE_LOW, // 低优先级，不弹横幅
            ).apply {
                description = "保持远程控制服务运行（后台保活）"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("远程控制正在运行")
            .setContentText("服务保持连接中，锁屏后仍可远程控制")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    /**
     * 获取 CPU 和 WiFi 锁
     *
     * PARTIAL_WAKE_LOCK: 保持 CPU 运行（不亮屏），
     * 这样即使屏幕关闭，WebSocket 心跳和重连逻辑也能执行。
     *
     * WIFI_MODE_FULL_HIGH_PERF: 保持 WiFi 连接活跃，
     * 防止系统为省电而断开 WiFi（Doze 模式下常见）。
     */
    @Suppress("DEPRECATION")
    private fun acquireLocks() {
        try {
            // CPU WakeLock —— 保持 CPU 运行
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "RemoteControl:ServiceKeepAlive",
            ).apply {
                setReferenceCounted(false)
                acquire(24 * 60 * 60 * 1000L) // 最长 24 小时
            }
            Log.i(TAG, "CPU WakeLock acquired")

            // WiFi Lock —— 保持 WiFi 连接
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            wifiLock = wifiManager.createWifiLock(
                WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                "RemoteControl:WifiKeepAlive",
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
            Log.i(TAG, "WiFi Lock acquired")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire locks: ${e.message}")
        }
    }

    /**
     * 释放所有锁
     */
    private fun releaseLocks() {
        try {
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
            wakeLock = null

            wifiLock?.let {
                if (it.isHeld) it.release()
            }
            wifiLock = null

            Log.i(TAG, "All locks released")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to release locks: ${e.message}")
        }
    }

    override fun onDestroy() {
        releaseLocks()
        stopForeground(true)
        super.onDestroy()
    }
}
