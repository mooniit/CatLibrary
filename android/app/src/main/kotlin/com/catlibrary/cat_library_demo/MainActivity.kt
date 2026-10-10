package com.catlibrary.cat_library_demo

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var permissionReply: MethodChannel.Result? = null
    private var permissionChannel = StudyTimerService.CHANNEL_ID

    private fun requestNotificationPermission(channel: String, reply: MethodChannel.Result) {
        if (channel == FeedingNotification.CHANNEL_ID) FeedingNotification.createChannel(this)
        else StudyTimerService.createChannel(this)
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            if (permissionReply != null) reply.error("busy", "Permission request is pending", null)
            else {
                permissionChannel = channel
                permissionReply = reply
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 701)
            }
        } else reply.success(if (channel == FeedingNotification.CHANNEL_ID) FeedingNotification.allowed(this) else notificationsAllowed())
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cat_library/feeding_reminders")
            .setMethodCallHandler { call, reply ->
                when (call.method) {
                    "requestPermission" -> requestNotificationPermission(FeedingNotification.CHANNEL_ID, reply)
                    "isAllowed" -> reply.success(FeedingNotification.allowed(this))
                    "show", "update" -> {
                        val owner = call.argument<String>("ownerId")
                        val day = call.argument<String>("businessDay")
                        val names = call.argument<List<String>>("names")
                        reply.success(if (owner == null || day == null || names == null) false
                            else FeedingNotification.display(this, owner, day, names, call.method == "update"))
                    }
                    "cancel" -> {
                        call.argument<String>("ownerId")?.let { FeedingNotification.cancel(this, it) }
                        reply.success(true)
                    }
                    else -> reply.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cat_library/lock_screen_timer")
            .setMethodCallHandler { call, reply ->
                when (call.method) {
                    "requestPermission" -> {
                        requestNotificationPermission(StudyTimerService.CHANNEL_ID, reply)
                    }
                    "show" -> {
                        val start = call.argument<Number>("startedAt")?.toLong()
                        if (start == null || start <= 0 || start > System.currentTimeMillis() || (call.argument<String>("sessionId") == null && !notificationsAllowed())) {
                            reply.success(false)
                        } else {
                            try {
                                val intent = Intent(this, StudyTimerService::class.java).putExtra("startedAt", start)
                                    .putExtra("sessionId", call.argument<String>("sessionId"))
                                    .putExtra("ownerId", call.argument<String>("ownerId"))
                                    .putExtra("displayElapsedMs", call.argument<Number>("displayElapsedMs")?.toLong() ?: 0L)
                                    .putExtra("countdownRemainingMs", call.argument<Number>("countdownRemainingMs")?.toLong() ?: -1L)
                                    .putExtra("maximumRemainingMs", call.argument<Number>("maximumRemainingMs")?.toLong() ?: StudyTimerService.MAX_DURATION_MS)
                                    .putExtra("title", call.argument<String>("title"))
                                if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                                reply.success(true)
                            } catch (_: RuntimeException) {
                                reply.success(false)
                            }
                        }
                    }
                    "readCheckpoint" -> reply.success(StudyCheckpointJournal.read(this))
                    "isActive" -> reply.success(
                        getSystemService(NotificationManager::class.java).activeNotifications.any { it.id == StudyTimerService.NOTIFICATION_ID }
                    )
                    "stop" -> {
                        stopService(Intent(this, StudyTimerService::class.java))
                        getSystemService(NotificationManager::class.java).cancel(StudyTimerService.NOTIFICATION_ID)
                        reply.success(true)
                    }
                    else -> reply.notImplemented()
                }
            }
    }

    private fun notificationsAllowed(): Boolean {
        val manager = getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < 26 || manager.getNotificationChannel(StudyTimerService.CHANNEL_ID)?.importance != NotificationManager.IMPORTANCE_NONE
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 701) {
            permissionReply?.success(if (permissionChannel == FeedingNotification.CHANNEL_ID) FeedingNotification.allowed(this) else notificationsAllowed())
            permissionReply = null
        }
    }
}
