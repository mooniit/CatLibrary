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
import android.os.PowerManager
import android.os.SystemClock
import android.widget.RemoteViews

/** User-visible stopwatch with durable native checkpoints; never awards currency. */
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
    private var durationLimit = MAX_DURATION_MS
    private var journal: StudyCheckpointJournal? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var lastSaved = 0L
    private val checkLimit = object : Runnable {
        override fun run() {
            val elapsed = journal?.elapsed() ?: (System.currentTimeMillis() - startedAt)
            if (journal != null && (elapsed - lastSaved >= 5000 || elapsed >= durationLimit)) {
                if (journal?.save() != true) { stopSelf(); return }
                lastSaved = elapsed
            }
            if (elapsed >= durationLimit) stopSelf()
            else handler.postDelayed(this, 1000)
        }
    }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startedAt = intent?.getLongExtra("startedAt", 0L) ?: 0L
        val countdownRemaining = intent?.getLongExtra("countdownRemainingMs", -1L) ?: -1L
        val countdown = countdownRemaining >= 0L
        val maximumRemaining = intent?.getLongExtra("maximumRemainingMs", MAX_DURATION_MS) ?: MAX_DURATION_MS
        durationLimit = minOf(MAX_DURATION_MS, maximumRemaining,
            if (countdown) countdownRemaining else MAX_DURATION_MS)
        val remaining = durationLimit - (System.currentTimeMillis() - startedAt)
        if (startedAt <= 0 || remaining <= 0 || remaining > MAX_DURATION_MS) {
            stopSelf()
            return START_NOT_STICKY
        }
        createChannel(this)
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        val offset = intent?.getLongExtra("displayElapsedMs", 0L) ?: 0L
        val displayWhen = if (countdown) System.currentTimeMillis() + remaining
            else startedAt - offset
        builder.setSmallIcon(R.drawable.ic_study_timer)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setWhen(displayWhen)
            .setShowWhen(false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
        val content = RemoteViews(packageName, R.layout.timer_notification)
        content.setChronometer(R.id.timer_time,
            SystemClock.elapsedRealtime() + displayWhen - System.currentTimeMillis(), null, true)
        if (Build.VERSION.SDK_INT >= 24) content.setChronometerCountDown(R.id.timer_time, countdown)
        content.setOnClickPendingIntent(R.id.timer_notification, open)
        builder.setCustomContentView(content).setCustomBigContentView(content)
        // Builder reuses its Notification: the public version must be independent.
        builder.setPublicVersion(builder.build().clone())
        if (Build.VERSION.SDK_INT >= 26) builder.setTimeoutAfter(remaining)
        if (countdown && Build.VERSION.SDK_INT >= 24) builder.setChronometerCountDown(true)
        if (Build.VERSION.SDK_INT >= 31) builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        if (Build.VERSION.SDK_INT >= 34) startForeground(NOTIFICATION_ID, builder.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(NOTIFICATION_ID, builder.build())
        val recordId = intent?.getStringExtra("sessionId")
        val ownerId = intent?.getStringExtra("ownerId")
        if (recordId != null && ownerId != null) {
            journal = StudyCheckpointJournal(this, recordId, ownerId, startedAt, durationLimit)
            if (journal?.save() != true) { stopSelf(); return START_NOT_STICKY }
            lastSaved = journal!!.elapsed()
            wakeLock?.let { if (it.isHeld) it.release() }
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "CatLibrary:StudyCheckpoint")
                .also { it.acquire(remaining) }
        }
        handler.removeCallbacks(checkLimit)
        handler.post(checkLimit)
        // Do not restart a stopwatch after an unexpected process death.
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        handler.removeCallbacks(checkLimit)
        wakeLock?.let { if (it.isHeld) it.release() }
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
