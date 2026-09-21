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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cat_library/lock_screen_timer")
            .setMethodCallHandler { call, reply ->
                when (call.method) {
                    "requestPermission" -> {
                        StudyTimerService.createChannel(this)
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            if (permissionReply != null) reply.error("busy", "Permission request is pending", null)
                            else {
                                permissionReply = reply
                                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 701)
                            }
                        } else reply.success(notificationsAllowed())
                    }
                    "show" -> {
                        val start = call.argument<Number>("startedAt")?.toLong()
                        if (start == null || start <= 0 || start > System.currentTimeMillis() || !notificationsAllowed()) {
                            reply.success(false)
                        } else {
                            try {
                                val intent = Intent(this, StudyTimerService::class.java).putExtra("startedAt", start)
                                if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                                reply.success(true)
                            } catch (_: RuntimeException) {
                                reply.success(false)
                            }
                        }
                    }
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
            permissionReply?.success(notificationsAllowed())
            permissionReply = null
        }
    }
}
