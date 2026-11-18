package io.github.amchii.floatingclock

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log

/** Rebuilds a pending one-shot task after reboot when exact-alarm access remains granted. */
class ScheduledClickBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        val prefs = context.getSharedPreferences(ScheduledClickReceiver.PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("active", false)) return
        val targetSystemEpoch = prefs.getLong("targetSystemEpochMs", 0L)
        val delay = targetSystemEpoch - System.currentTimeMillis()
        if (targetSystemEpoch <= 0L || delay <= 0L) {
            prefs.edit().putBoolean("active", false).putString("status", "设备重启后目标时间已过，任务未恢复").apply()
            return
        }
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            prefs.edit().putBoolean("active", false).putString("status", "设备重启后精确闹钟权限不可用，任务未恢复").apply()
            return
        }
        val targetElapsed = SystemClock.elapsedRealtime() + delay
        prefs.edit().putLong("targetElapsedRealtime", targetElapsed).apply()
        val alarmIntent = Intent(context, ScheduledClickReceiver::class.java)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        val pending = PendingIntent.getBroadcast(context, 9301, alarmIntent, flags)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, targetElapsed, pending)
            } else {
                alarmManager.setExact(AlarmManager.ELAPSED_REALTIME_WAKEUP, targetElapsed, pending)
            }
            Log.i(TAG, "Restored pending scheduled click after reboot")
        } catch (error: Exception) {
            Log.e(TAG, "Unable to restore scheduled click after reboot", error)
            prefs.edit().putBoolean("active", false).putString("status", "设备重启后恢复任务失败").apply()
        }
    }

    companion object { private const val TAG = "ScheduledClickBoot" }
}
