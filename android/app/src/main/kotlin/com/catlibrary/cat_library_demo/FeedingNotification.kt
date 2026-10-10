package com.catlibrary.cat_library_demo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/** Only displays a freshly verified server reminder; never schedules a cached cat list. */
object FeedingNotification {
    const val CHANNEL_ID = "feeding_reminders"
    private const val ID = 702
    private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)
    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(CHANNEL_ID, "晚餐提醒", NotificationManager.IMPORTANCE_DEFAULT)
            channel.description = "21:00 汇总本人当天尚未喂食的猫咪"
            channel.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            manager(context).createNotificationChannel(channel)
        }
    }
    fun allowed(context: Context): Boolean {
        createChannel(context)
        return manager(context).areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < 26 || manager(context).getNotificationChannel(CHANNEL_ID)?.importance != NotificationManager.IMPORTANCE_NONE)
    }
    private fun validOwner(owner: String): Boolean = try {
        UUID.fromString(owner).toString() == owner
    } catch (_: IllegalArgumentException) { false }

    @Synchronized
    fun display(context: Context, owner: String, day: String, names: List<String>, update: Boolean): Boolean {
        val now = Calendar.getInstance(TimeZone.getTimeZone("GMT+08:00"))
        val date = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).also { it.timeZone = now.timeZone }.format(now.time)
        if (!validOwner(owner) || day != date || now.get(Calendar.HOUR_OF_DAY) < 21 ||
            names.isEmpty() || names.size > 2 || names.any { it.isBlank() || it.length > 100 } || !allowed(context)) return false
        val tag = "feeding/$owner"
        val active = manager(context).activeNotifications.any { it.tag == tag && it.id == ID }
        val markers = context.getSharedPreferences("feeding_notification_delivery", Context.MODE_PRIVATE)
        val previous = markers.getString(owner, null)
        // A user dismissal is final for this day. Updating must not resurrect it.
        if (update && (!active || previous != "$day/posted")) return false
        if (!update && previous == "$day/posted") return true
        if (!update && previous == "$day/pending") {
            // A crash between the journal and OS post is uncertain. Do not report
            // success or recreate a possibly dismissed notification without evidence.
            return active && markers.edit().putString(owner, "$day/posted").commit()
        }
        val next = (now.clone() as Calendar).also {
            it.add(Calendar.DAY_OF_MONTH, 1)
            it.set(Calendar.HOUR_OF_DAY, 0); it.set(Calendar.MINUTE, 0)
            it.set(Calendar.SECOND, 0); it.set(Calendar.MILLISECOND, 0)
        }
        val open = PendingIntent.getActivity(context, ID, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL_ID) else Notification.Builder(context)
        builder.setSmallIcon(R.drawable.ic_study_timer)
            .setContentTitle("晚餐时间")
            .setContentText(names.joinToString("、") + " · 待喂食")
            .setCategory(Notification.CATEGORY_REMINDER)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setOnlyAlertOnce(true).setAutoCancel(true).setContentIntent(open)
        if (Build.VERSION.SDK_INT >= 26) builder.setTimeoutAfter(next.timeInMillis - now.timeInMillis)
        // Commit the duplicate guard before posting: process death must never alert twice.
        if (!update && !markers.edit().putString(owner, "$day/pending").commit()) return false
        return try {
            manager(context).notify(tag, ID, builder.build())
            update || markers.edit().putString(owner, "$day/posted").commit()
        } catch (_: RuntimeException) {
            // A failed post may be retried; no success is reported to Dart.
            if (!update) markers.edit().remove(owner).commit()
            false
        }
    }
    fun cancel(context: Context, owner: String) {
        if (validOwner(owner)) manager(context).cancel("feeding/$owner", ID)
    }
}
