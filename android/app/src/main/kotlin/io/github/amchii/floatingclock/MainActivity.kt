package io.github.amchii.floatingclock

import android.app.PictureInPictureParams
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import android.util.Rational
import java.io.ByteArrayOutputStream
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "floating_clock"
    private lateinit var channel: MethodChannel
    private val overlayStoppedAction = "io.github.amchii.floatingclock.OVERLAY_STOPPED"
    private val coordinateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (::channel.isInitialized && intent != null) {
                try { channel.invokeMethod("onCoordinatePicked", mapOf(
                    "x" to intent.getIntExtra("x", 0), "y" to intent.getIntExtra("y", 0),
                    "screenWidth" to intent.getIntExtra("screenWidth", 0),
                    "screenHeight" to intent.getIntExtra("screenHeight", 0),
                    "densityDpi" to intent.getIntExtra("densityDpi", 0),
                    "rotation" to intent.getIntExtra("rotation", 0)
                )) } catch (_: RuntimeException) { }
            }
        }
    }
    private val coordinateMovedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (::channel.isInitialized && intent != null) {
                try { channel.invokeMethod("onCoordinateMoved", mapOf(
                    "x" to intent.getIntExtra("x", 0), "y" to intent.getIntExtra("y", 0),
                    "screenWidth" to intent.getIntExtra("screenWidth", 0),
                    "screenHeight" to intent.getIntExtra("screenHeight", 0),
                    "densityDpi" to intent.getIntExtra("densityDpi", 0),
                    "rotation" to intent.getIntExtra("rotation", 0)
                )) } catch (_: RuntimeException) { }
            }
        }
    }
    private val taskFinishedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (::channel.isInitialized && intent != null) {
                try { channel.invokeMethod("onScheduledTaskFinished", mapOf(
                    "success" to intent.getBooleanExtra("success", false),
                    "status" to intent.getStringExtra("status"),
                    "dispatchEpochMs" to intent.getLongExtra("dispatchEpochMs", 0L),
                    "completedEpochMs" to intent.getLongExtra("completedEpochMs", 0L)
                )) } catch (_: RuntimeException) { }
            }
        }
    }
    private val overlayStoppedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (::channel.isInitialized) {
                try {
                    channel.invokeMethod("onOverlayStopped", null)
                } catch (_: RuntimeException) {
                    // The Flutter engine may already be detaching during Activity teardown.
                }
            }
        }
    }

    private fun hasOverlayPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(overlayStoppedAction)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(overlayStoppedReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            registerReceiver(coordinateReceiver, IntentFilter(CoordinatePickerService.ACTION_COORDINATE_PICKED), Context.RECEIVER_NOT_EXPORTED)
            registerReceiver(coordinateMovedReceiver, IntentFilter(CoordinatePickerService.ACTION_COORDINATE_MOVED), Context.RECEIVER_NOT_EXPORTED)
            registerReceiver(taskFinishedReceiver, IntentFilter(ScheduledClickExecutionService.ACTION_TASK_FINISHED), Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(overlayStoppedReceiver, filter)
            @Suppress("DEPRECATION")
            registerReceiver(coordinateReceiver, IntentFilter(CoordinatePickerService.ACTION_COORDINATE_PICKED))
            @Suppress("DEPRECATION")
            registerReceiver(coordinateMovedReceiver, IntentFilter(CoordinatePickerService.ACTION_COORDINATE_MOVED))
            @Suppress("DEPRECATION")
            registerReceiver(taskFinishedReceiver, IntentFilter(ScheduledClickExecutionService.ACTION_TASK_FINISHED))
        }
    }

    override fun onDestroy() {
        listOf(overlayStoppedReceiver, coordinateReceiver, coordinateMovedReceiver, taskFinishedReceiver).forEach { receiver ->
            try { unregisterReceiver(receiver) } catch (_: IllegalArgumentException) { }
        }
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> {
                    result.success(hasOverlayPermission())
                }
                "requestPermission" -> {
                    // Try to open the app-specific overlay permission page. Some OEM settings
                    // implementations are fragile, so fall back to the app details page when needed.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.fromParts("package", packageName, null)
                            )
                            startActivity(intent)
                            result.success(true)
                        } catch (firstError: Exception) {
                            // Fallback: open application details settings so the user can
                            // navigate to special app access -> Display over other apps.
                            try {
                                val fallbackIntent = Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.fromParts("package", packageName, null)
                                )
                                startActivity(fallbackIntent)
                                result.success(true)
                            } catch (fallbackError: Exception) {
                                result.error(
                                    "PERMISSION_SETTINGS_UNAVAILABLE",
                                    fallbackError.localizedMessage ?: firstError.localizedMessage ?: "Unable to open overlay settings",
                                    null
                                )
                            }
                        }
                    } else {
                        result.success(false)
                    }
                }
                "getCoordinateScreenInfo" -> {
                    val metrics = realDisplayMetrics()
                    result.success(mapOf("screenWidth" to metrics.widthPixels, "screenHeight" to metrics.heightPixels,
                        "densityDpi" to metrics.densityDpi, "rotation" to realDisplayRotation()))
                }
                "isGestureApiSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
                "isAccessibilityEnabled" -> result.success(isClickAccessibilityEnabled())
                "openAccessibilitySettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("ACCESSIBILITY_SETTINGS_UNAVAILABLE", error.localizedMessage, null)
                    }
                }
                "isExactAlarmAllowed" -> result.success(isExactAlarmAllowed())
                "requestExactAlarmPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        try {
                            startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName")))
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("EXACT_ALARM_SETTINGS_UNAVAILABLE", error.localizedMessage, null)
                        }
                    } else result.success(true)
                }
                "pickCoordinate" -> {
                    if (!hasOverlayPermission()) {
                        result.error("NO_OVERLAY_PERMISSION", "需要悬浮窗权限才能显示坐标选取层", null)
                        return@setMethodCallHandler
                    }
                    try {
                        startService(Intent(this, CoordinatePickerService::class.java))
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("COORDINATE_PICKER_FAILED", error.localizedMessage, null)
                    }
                }
                "scheduleClick" -> {
                    if (!isClickAccessibilityEnabled()) {
                        result.error("NO_ACCESSIBILITY_PERMISSION", "请先启用定时点击无障碍服务", null)
                        return@setMethodCallHandler
                    }
                    if (!isExactAlarmAllowed()) {
                        result.error("NO_EXACT_ALARM_PERMISSION", "请先允许精确闹钟", null)
                        return@setMethodCallHandler
                    }
                    val target = call.argument<Number>("targetSystemEpochMs")?.toLong() ?: 0L
                    val x = call.argument<Number>("x")?.toInt() ?: -1
                    val y = call.argument<Number>("y")?.toInt() ?: -1
                    val coordinateName = call.argument<String>("coordinateName") ?: ""
                    val coordinateWidth = call.argument<Number>("screenWidth")?.toInt() ?: 0
                    val coordinateHeight = call.argument<Number>("screenHeight")?.toInt() ?: 0
                    val coordinateDensityDpi = call.argument<Number>("densityDpi")?.toInt() ?: 0
                    val coordinateRotation = call.argument<Number>("rotation")?.toInt() ?: -1
                    val currentMetrics = realDisplayMetrics()
                    val currentRotation = realDisplayRotation()
                    val targetLabel = call.argument<String>("targetLabel") ?: ""
                    val sourceOffsetMillis = call.argument<Number>("sourceOffsetMillis")?.toLong() ?: 0L
                    val sourceLabel = call.argument<String>("sourceLabel") ?: ""
                    if (target <= System.currentTimeMillis() || x < 0 || y < 0 || coordinateWidth <= 0 || coordinateHeight <= 0 || coordinateDensityDpi <= 0 || coordinateRotation < 0) {
                        result.error("INVALID_TASK", "目标时间必须在未来，坐标必须有效", null)
                        return@setMethodCallHandler
                    }
                    if (coordinateWidth != currentMetrics.widthPixels || coordinateHeight != currentMetrics.heightPixels ||
                        coordinateDensityDpi != currentMetrics.densityDpi || coordinateRotation != currentRotation) {
                        result.error("COORDINATE_SCREEN_CHANGED", "屏幕尺寸已变化，请重新点选坐标，避免点击到错误位置", null)
                        return@setMethodCallHandler
                    }
                    if (x >= currentMetrics.widthPixels || y >= currentMetrics.heightPixels) {
                        result.error("INVALID_COORDINATE", "坐标超出当前屏幕范围，请重新点选", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val delayMillis = target - System.currentTimeMillis()
                        val targetElapsed = SystemClock.elapsedRealtime() + delayMillis
                        val prefs = getSharedPreferences(ScheduledClickReceiver.PREFS, Context.MODE_PRIVATE)
                        prefs.edit().putBoolean("active", true).putLong("targetSystemEpochMs", target)
                            .putLong("targetElapsedRealtime", targetElapsed)
                            .putLong("sourceOffsetMillis", sourceOffsetMillis)
                            .putInt("x", x).putInt("y", y)
                            .putInt("screenWidth", coordinateWidth).putInt("screenHeight", coordinateHeight)
                            .putInt("densityDpi", coordinateDensityDpi).putInt("rotation", coordinateRotation)
                            .putString("coordinateName", coordinateName)
                            .putString("targetLabel", targetLabel).putString("sourceLabel", sourceLabel)
                            .putString("status", "等待执行").apply()
                        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        val pending = clickPendingIntent()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            alarmManager.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, targetElapsed, pending)
                        } else {
                            alarmManager.setExact(AlarmManager.ELAPSED_REALTIME_WAKEUP, targetElapsed, pending)
                        }
                        result.success(true)
                    } catch (error: Exception) {
                        getSharedPreferences(ScheduledClickReceiver.PREFS, Context.MODE_PRIVATE)
                            .edit().putBoolean("active", false).putString("status", "创建任务失败").apply()
                        result.error("SCHEDULE_FAILED", error.localizedMessage ?: "无法创建定时任务", null)
                    }
                }
                "cancelScheduledClick" -> {
                    try {
                        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        alarmManager.cancel(clickPendingIntent())
                        stopService(Intent(this, ScheduledClickExecutionService::class.java))
                        getSharedPreferences(ScheduledClickReceiver.PREFS, Context.MODE_PRIVATE)
                            .edit().putBoolean("active", false).putString("status", "已停止").apply()
                        result.success(true)
                    } catch (error: Exception) { result.error("CANCEL_FAILED", error.localizedMessage, null) }
                }
                "getScheduledTaskState" -> {
                    val prefs = getSharedPreferences(ScheduledClickReceiver.PREFS, Context.MODE_PRIVATE)
                    result.success(mapOf(
                        "active" to prefs.getBoolean("active", false),
                        "targetSystemEpochMs" to prefs.getLong("targetSystemEpochMs", 0L),
                        "targetLabel" to prefs.getString("targetLabel", ""),
                        "sourceOffsetMillis" to prefs.getLong("sourceOffsetMillis", 0L),
                        "sourceLabel" to prefs.getString("sourceLabel", ""),
                        "status" to prefs.getString("status", "")
                    ))
                }
                "getAppVersion" -> {
                    try {
                        val pInfo = packageManager.getPackageInfo(packageName, 0)
                        result.success(pInfo.versionName)
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                "getAppIcon" -> {
                    try {
                        val pm = packageManager
                        val appInfo = pm.getApplicationInfo(packageName, 0)
                        val drawable = pm.getApplicationIcon(appInfo)

                        val bitmap: Bitmap = if (drawable is BitmapDrawable) {
                            drawable.bitmap
                        } else {
                            val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 128
                            val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 128
                            val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                            val canvas = Canvas(bmp)
                            drawable.setBounds(0, 0, canvas.width, canvas.height)
                            drawable.draw(canvas)
                            bmp
                        }

                        val stream = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                        val bytes = stream.toByteArray()
                        result.success(bytes)
                    } catch (e: Exception) {
                        result.error("UNAVAILABLE", "Icon not available", null)
                    }
                }
                "startOverlay" -> {
                    if (!hasOverlayPermission()) {
                        result.error("NO_PERMISSION", "Overlay permission not granted", null)
                        return@setMethodCallHandler
                    }
                    // Accept an optional offset (milliseconds) and label from Flutter.
                    val offsetNum = call.argument<Number>("offset")
                    val offset = offsetNum?.toLong() ?: 0L
                    val label = call.argument<String>("label")
                    val precision = call.argument<String>("precision")
                    val fractionColorNum = call.argument<Number>("fractionColor")
                    val fractionColor = fractionColorNum?.toInt()

                    val intent = Intent(this, FloatingClockService::class.java)
                    intent.putExtra("offset", offset)
                    if (label != null) intent.putExtra("label", label)
                    if (precision != null) intent.putExtra("precision", precision)
                    if (fractionColor != null) intent.putExtra("fractionColor", fractionColor)

                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (error: Exception) {
                        result.error(
                            "OVERLAY_START_FAILED",
                            error.localizedMessage ?: "Unable to start floating clock service",
                            null
                        )
                    }
                }
                "stopOverlay" -> {
                    try {
                        val intent = Intent(this, FloatingClockService::class.java)
                        stopService(intent)
                        result.success(true)
                    } catch (error: Exception) {
                        result.error(
                            "OVERLAY_STOP_FAILED",
                            error.localizedMessage ?: "Unable to stop floating clock service",
                            null
                        )
                    }
                }
                "isOverlayRunning" -> {
                    result.success(FloatingClockService.isServiceRunning())
                }
                "isPiPSupported" -> {
                    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    result.success(supported)
                }
                "isInPiP" -> {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isInPictureInPictureMode)
                }
                "enterPiP" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val params = PictureInPictureParams.Builder()
                            .setAspectRatio(Rational(16, 9))
                            .build()
                        val success = try {
                            enterPictureInPictureMode(params)
                        } catch (e: Exception) {
                            result.error("PIP_FAILED", e.message, null)
                            return@setMethodCallHandler
                        }
                        result.success(success)
                    } else {
                        result.error("UNSUPPORTED", "Picture-in-picture not supported", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun realDisplayRotation(): Int =
        (getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager).defaultDisplay.rotation

    @Suppress("DEPRECATION")
    private fun realDisplayMetrics(): android.util.DisplayMetrics {
        val metrics = android.util.DisplayMetrics()
        (getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager).defaultDisplay.getRealMetrics(metrics)
        return metrics
    }

    private fun isClickAccessibilityEnabled(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val expected = "$packageName/${ScheduledClickAccessibilityService::class.java.name}"
        val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
    }

    private fun isExactAlarmAllowed(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return alarmManager.canScheduleExactAlarms()
    }

    private fun clickPendingIntent(): PendingIntent {
        val intent = Intent(this, ScheduledClickReceiver::class.java)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        return PendingIntent.getBroadcast(this, 9301, intent, flags)
    }

    private fun notifyPiPChanged(inPiP: Boolean) {
        if (::channel.isInitialized) {
            channel.invokeMethod("onPiPChanged", mapOf("isInPiP" to inPiP))
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode)
        notifyPiPChanged(isInPictureInPictureMode)
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration?
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        notifyPiPChanged(isInPictureInPictureMode)
    }
}
