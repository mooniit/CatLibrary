package com.catlibrary.cat_library_demo

import android.content.Context
import android.os.SystemClock

/** The native foreground timer stores its own atomic recovery evidence. */
class StudyCheckpointJournal(context: Context, private val id: String,
    private val owner: String, private val start: Long,
    private val maxElapsed: Long = StudyTimerService.MAX_DURATION_MS) {
    private val preferences = context.getSharedPreferences("study_checkpoint", Context.MODE_PRIVATE)
    private val origin = SystemClock.elapsedRealtime() - (System.currentTimeMillis() - start).coerceAtLeast(0L)
    fun elapsed(): Long = (SystemClock.elapsedRealtime() - origin).coerceIn(0L, maxElapsed)
    fun save(): Boolean = preferences.edit()
        .putString("id", id).putString("ownerId", owner)
        .putLong("startedAt", start).putLong("recordedUntil", start + elapsed()).commit()
    companion object {
        fun read(context: Context): Map<String, Any>? {
            val preferences = context.getSharedPreferences("study_checkpoint", Context.MODE_PRIVATE)
            val id = preferences.getString("id", null) ?: return null
            val owner = preferences.getString("ownerId", null) ?: return null
            return mapOf("id" to id, "ownerId" to owner,
                "startedAt" to preferences.getLong("startedAt", 0L),
                "recordedUntil" to preferences.getLong("recordedUntil", 0L))
        }
    }
}
