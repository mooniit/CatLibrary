package com.catlibrary.cat_library_demo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/** User-visible stopwatch display. No reward or persistence decisions live here. */
class StudyTimerService : Service() {
    companion object {
        const val CHANNEL_ID = "study_timer"
        const val NOTIFICATION_ID = 701
        const val MAX_DURATION_MS = 6L * 60 * 60 * 1000
        fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= 26) {
                val channel = NotificationChannel(CHANNEL_ID, "自习锁屏计时", NotificationManager.IMPORTANCE_DEFAULT)
                channel.description = "在自习期间显示同步计时；结束后自动移除"
                channel.setSound(null, null)
                channel.enableVibration(false)
                channel.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
            }
        }
    }
    private val handler = Handler(Looper.getMainLooper())
    private var startedAt = 0L
    private val checkLimit = object : Runnable {
        override fun run() {
            if (System.currentTimeMillis() - startedAt >= MAX_DURATION_MS) stopSelf()
            else handler.postDelayed(this, 1000)
        }
    }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startedAt = intent?.getLongExtra("startedAt", 0L) ?: 0L
        val remaining = MAX_DURATION_MS - (System.currentTimeMillis() - startedAt)
        if (startedAt <= 0 || remaining <= 0 || remaining > MAX_DURATION_MS) {
            stopSelf()
            return START_NOT_STICKY
        }
        createChannel(this)
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        builder.setSmallIcon(R.drawable.ic_study_timer)
            .setContentTitle("自习计时中")
            .setContentText("正在计时 · 点击返回应用")
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setWhen(startedAt)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
        if (Build.VERSION.SDK_INT >= 26) builder.setTimeoutAfter(remaining)
        if (Build.VERSION.SDK_INT >= 31) builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        if (Build.VERSION.SDK_INT >= 34) startForeground(NOTIFICATION_ID, builder.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(NOTIFICATION_ID, builder.build())
        handler.removeCallbacks(checkLimit)
        handler.post(checkLimit)
        // Do not restart a stopwatch after an unexpected process death.
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        handler.removeCallbacks(checkLimit)
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
