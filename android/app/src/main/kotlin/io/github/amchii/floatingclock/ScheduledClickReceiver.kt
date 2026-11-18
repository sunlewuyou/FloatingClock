package io.github.amchii.floatingclock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class ScheduledClickReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("active", false)) return
        val serviceIntent = Intent(context, ScheduledClickExecutionService::class.java)
            .putExtra("targetSystemEpochMs", prefs.getLong("targetSystemEpochMs", 0L))
            .putExtra("targetElapsedRealtime", prefs.getLong("targetElapsedRealtime", 0L))
            .putExtra("x", prefs.getInt("x", 0))
            .putExtra("y", prefs.getInt("y", 0))
            .putExtra("screenWidth", prefs.getInt("screenWidth", 0))
            .putExtra("screenHeight", prefs.getInt("screenHeight", 0))
            .putExtra("densityDpi", prefs.getInt("densityDpi", 0))
            .putExtra("rotation", prefs.getInt("rotation", -1))
            .putExtra("coordinateName", prefs.getString("coordinateName", "") ?: "")
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(serviceIntent)
            else context.startService(serviceIntent)
        } catch (error: Exception) {
            Log.e("ScheduledClickReceiver", "Unable to start click executor", error)
            val status = "启动执行服务失败：${error.javaClass.simpleName}"
            prefs.edit().putBoolean("active", false).putString("status", status).apply()
            context.sendBroadcast(Intent(ScheduledClickExecutionService.ACTION_TASK_FINISHED)
                .setPackage(context.packageName).putExtra("success", false).putExtra("status", status))
        }
    }

    companion object { const val PREFS = "scheduled_click_task" }
}
