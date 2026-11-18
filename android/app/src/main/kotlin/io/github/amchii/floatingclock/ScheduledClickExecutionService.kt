package io.github.amchii.floatingclock

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.os.PowerManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

class ScheduledClickExecutionService : Service() {
    private var executionWakeLock: PowerManager.WakeLock? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var gestureTimeout: Runnable? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try { startForegroundCompat() } catch (error: Exception) {
            Log.e(TAG, "Unable to start click foreground service", error)
            finish("前台服务启动失败", false)
            stopSelf(startId)
            return START_NOT_STICKY
        }
        val wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:scheduled-click")
        executionWakeLock = wakeLock
        try { wakeLock.acquire(8_000L) } catch (error: Exception) {
            Log.w(TAG, "Unable to acquire short execution wake lock", error)
        }
        val target = intent?.getLongExtra("targetSystemEpochMs", 0L) ?: 0L
        val targetElapsed = intent?.getLongExtra("targetElapsedRealtime", 0L) ?: 0L
        val x = intent?.getIntExtra("x", 0) ?: 0
        val y = intent?.getIntExtra("y", 0) ?: 0
        val savedWidth = intent?.getIntExtra("screenWidth", 0) ?: 0
        val savedHeight = intent?.getIntExtra("screenHeight", 0) ?: 0
        val savedDensity = intent?.getIntExtra("densityDpi", 0) ?: 0
        val savedRotation = intent?.getIntExtra("rotation", -1) ?: -1
        if (target <= 0L || targetElapsed <= 0L) {
            finish("目标时间无效", false)
            releaseExecutionWakeLock()
            stopSelf(startId)
            return START_NOT_STICKY
        }
        // Alarm delivery can be delayed by the OS. Never claim success merely because
        // the alarm fired; record the actual dispatch time and gesture callback.
        val remaining = targetElapsed - SystemClock.elapsedRealtime()
        if (remaining > 0L && remaining <= 20L) {
            // Defensive early-delivery path: bounded final wait against the monotonic clock.
            while (SystemClock.elapsedRealtime() < targetElapsed) { /* final short wait */ }
        }
        val currentDisplay = currentDisplaySignature()
        if (currentDisplay.width != savedWidth || currentDisplay.height != savedHeight ||
            currentDisplay.densityDpi != savedDensity || currentDisplay.rotation != savedRotation ||
            x < 0 || y < 0 || x >= currentDisplay.width || y >= currentDisplay.height) {
            finish("执行前屏幕方向或显示参数发生变化，已取消以避免误点", false)
            releaseExecutionWakeLock()
            stopSelf(startId)
            return START_NOT_STICKY
        }
        val service = ScheduledClickAccessibilityService.instance
        if (service == null) {
            finish("无障碍服务未连接，未执行点击", false)
            releaseExecutionWakeLock()
            stopSelf(startId)
            return START_NOT_STICKY
        }
        val dispatchElapsed = SystemClock.elapsedRealtime()
        val dispatchEpoch = System.currentTimeMillis()
        val dispatchError = dispatchElapsed - targetElapsed
        val timeoutRunnable = Runnable {
            finish("无障碍手势派发回调超时，执行结果未知", false, dispatchEpoch, System.currentTimeMillis())
            releaseExecutionWakeLock()
            stopSelf(startId)
        }
        gestureTimeout = timeoutRunnable
        mainHandler.postDelayed(timeoutRunnable, 3_000L)
        try {
            service.dispatchTap(x.toFloat(), y.toFloat()) { success ->
                mainHandler.removeCallbacks(timeoutRunnable)
                gestureTimeout = null
                val completedEpoch = System.currentTimeMillis()
                finish(
                    if (success) "点击已派发，触发偏差 ${dispatchError} ms"
                    else "系统拒绝或取消点击，触发偏差 ${dispatchError} ms",
                    success,
                    dispatchEpoch,
                    completedEpoch
                )
                releaseExecutionWakeLock()
                stopSelf(startId)
            }
        } catch (error: Exception) {
            mainHandler.removeCallbacks(timeoutRunnable)
            gestureTimeout = null
            Log.e(TAG, "Accessibility gesture dispatch failed", error)
            finish("无障碍手势派发异常：${error.javaClass.simpleName}", false, dispatchEpoch, System.currentTimeMillis())
            releaseExecutionWakeLock()
            stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    @Suppress("DEPRECATION")
    private fun currentDisplaySignature(): DisplaySignature {
        val metrics = android.util.DisplayMetrics()
        val display = (getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager).defaultDisplay
        display.getRealMetrics(metrics)
        return DisplaySignature(metrics.widthPixels, metrics.heightPixels, metrics.densityDpi, display.rotation)
    }

    private data class DisplaySignature(val width: Int, val height: Int, val densityDpi: Int, val rotation: Int)

    private fun startForegroundCompat() {
        val channelId = "scheduled_click_channel"
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(channelId, "定时点击任务", NotificationManager.IMPORTANCE_LOW))
        }
        val notification: Notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("定时点击任务")
            .setContentText("正在执行预定点击")
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else startForeground(NOTIFICATION_ID, notification)
    }

    private fun finish(status: String, success: Boolean, dispatchEpoch: Long = 0L, completedEpoch: Long = 0L) {
        getSharedPreferences(ScheduledClickReceiver.PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean("active", false).putString("status", status)
            .putLong("dispatchEpochMs", dispatchEpoch).putLong("completedEpochMs", completedEpoch)
            .apply()
        val update = Intent(ACTION_TASK_FINISHED).setPackage(packageName)
            .putExtra("success", success).putExtra("status", status)
            .putExtra("dispatchEpochMs", dispatchEpoch).putExtra("completedEpochMs", completedEpoch)
        sendBroadcast(update)
        stopForegroundCompat()
    }

    @Suppress("DEPRECATION")
    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            stopForeground(true)
        }
    }

    private fun releaseExecutionWakeLock() {
        try {
            executionWakeLock?.let { if (it.isHeld) it.release() }
        } catch (error: Exception) {
            Log.w(TAG, "Unable to release execution wake lock", error)
        } finally {
            executionWakeLock = null
        }
    }

    override fun onDestroy() {
        gestureTimeout?.let { mainHandler.removeCallbacks(it) }
        gestureTimeout = null
        releaseExecutionWakeLock()
        stopForegroundCompat()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "ScheduledClickExec"
        private const val NOTIFICATION_ID = 42
        const val ACTION_TASK_FINISHED = "io.github.amchii.floatingclock.SCHEDULED_CLICK_FINISHED"
    }
}
