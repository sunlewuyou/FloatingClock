package io.github.amchii.floatingclock

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import android.widget.LinearLayout
import android.text.TextUtils
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.graphics.drawable.GradientDrawable
import android.graphics.Typeface
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat
import java.util.*

class FloatingClockService : Service() {
    companion object {
        private const val TAG = "FloatingClockService"
    }

    private lateinit var windowManager: WindowManager
    private var overlayView: View? = null
    private var containerView: View? = null
    private var textView: TextView? = null
    // offset in milliseconds to apply to system time (ntpTime - systemTime)
    private var offsetMillis: Long = 0L
    private var label: String? = null
    private var displayPrecision = DisplayPrecision.CENTISECOND
    private var updateIntervalMs = 10L
    private var fractionColor: Int = Color.parseColor("#C62828")
    private val handler = Handler(Looper.getMainLooper())
    private var lastPermissionCheckElapsedRealtime = 0L
    private val updateRunnable = object : Runnable {
        override fun run() {
            updateTime()
            handler.postDelayed(this, updateIntervalMs)
        }
    }

    private fun hasOverlayPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Apply the latest settings before scheduling updates. Repeated start requests
        // update the existing service instead of creating another overlay or timer.
        intent?.let {
            offsetMillis = it.getLongExtra("offset", offsetMillis)
            label = it.getStringExtra("label")
            applyPrecision(it.getStringExtra("precision"))
            fractionColor = it.getIntExtra("fractionColor", fractionColor)
        }

        // A foreground service must promote itself promptly. Do this before touching
        // WindowManager so a slow/failing overlay operation cannot delay promotion.
        try {
            startForegroundWithNotification()
        } catch (error: Exception) {
            Log.e(TAG, "Unable to promote overlay service to foreground", error)
            handler.removeCallbacks(updateRunnable)
            removeOverlay()
            stopSelfResult(startId)
            return START_NOT_STICKY
        }

        // Overlay permission can be revoked while the process is alive. Never keep an
        // invisible foreground service running when the required special permission is gone.
        if (!hasOverlayPermission()) {
            Log.w(TAG, "Overlay permission is not granted; stopping service")
            stopForegroundCompat()
            stopSelfResult(startId)
            return START_NOT_STICKY
        }

        if (overlayView == null && !createOverlay()) {
            Log.e(TAG, "Unable to attach overlay window; stopping service")
            stopForegroundCompat()
            stopSelfResult(startId)
            return START_NOT_STICKY
        }

        handler.removeCallbacks(updateRunnable)
        handler.post(updateRunnable)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(updateRunnable)
        removeOverlay()
        val intent = Intent("io.github.amchii.floatingclock.OVERLAY_STOPPED")
        intent.setPackage(packageName)
        sendBroadcast(intent)
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            stopForeground(true)
        }
    }

    private fun startForegroundWithNotification() {
        val channelId = "floating_clock_channel"
        
        // 创建通知渠道
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId, 
                "悬浮时间", 
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "悬浮时钟持续显示时间"
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }

        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE 
        else 
            PendingIntent.FLAG_UPDATE_CURRENT
        
        val pendingIntent = PendingIntent.getActivity(this, 0, notificationIntent, pendingFlags)
        
        // 根据 Android 版本设置不同的通知内容
        val notificationText = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            "悬浮时钟持续运行，用于显示时间信息"
        } else {
            "悬浮时间正在运行"
        }
        
        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("悬浮时间")
            .setContentText(notificationText)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
        
        // 根据 Android 版本使用不同的 startForeground 方法
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+ 使用 specialUse 类型
            val serviceType = ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            startForeground(1, notification, serviceType)
        } else {
            // Android 13 及以下
            startForeground(1, notification)
        }
    }

    private fun createOverlay(): Boolean {
        if (!hasOverlayPermission()) return false

        val layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )

        layoutParams.gravity = Gravity.START or Gravity.TOP
        val positionPrefs = getSharedPreferences("floating_clock_overlay", Context.MODE_PRIVATE)
        layoutParams.x = positionPrefs.getInt("x", 0).coerceAtLeast(0)
        layoutParams.y = positionPrefs.getInt("y", 200).coerceAtLeast(0)

        // Horizontal layout: alias (small, left), time (center, monospace), close button (right)
        val container = LinearLayout(this)
        container.orientation = LinearLayout.HORIZONTAL

        val density = resources.displayMetrics.density
        val bg = GradientDrawable()
        bg.cornerRadius = 8 * density
        // slightly more transparent background so underlying content is readable
        bg.setColor(0x88000000.toInt())
        container.background = bg
        val pad = (8 * density).toInt()
        container.setPadding(pad, (6 * density).toInt(), pad, (6 * density).toInt())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) container.elevation = 6f

        // Alias TextView: small, single line, marquee for long aliases.
        val aliasTv = TextView(this)
        aliasTv.setTextColor(0xFFFFFFFF.toInt())
        aliasTv.textSize = 12f
        aliasTv.isSingleLine = true
        aliasTv.ellipsize = TextUtils.TruncateAt.MARQUEE
        aliasTv.isSelected = true
        aliasTv.setHorizontallyScrolling(true)

        // Restrict alias width so it doesn't push the time display; allow marquee inside.
        val aliasMaxWidth = (120 * density).toInt()
        aliasTv.maxWidth = aliasMaxWidth
        val aliasLp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        aliasLp.marginEnd = (8 * density).toInt()
        container.addView(aliasTv, aliasLp)

        val tv = TextView(this)
        tv.typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        tv.setTextColor(0xFFFFFFFF.toInt())
        tv.setShadowLayer(3f, 0f, 1f, 0x80000000.toInt())
        tv.textSize = 20f
        tv.isSingleLine = true
        tv.ellipsize = TextUtils.TruncateAt.END
        tv.text = currentTimeText()

        val tvLp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        tvLp.weight = 1f
        tvLp.marginEnd = (6 * density).toInt()
        container.addView(tv, tvLp)

        val closeBtn = TextView(this)
        closeBtn.text = "✕"
        closeBtn.setTextColor(0xFFFFFFFF.toInt())
        closeBtn.textSize = 12f
        val closeSize = (28 * density).toInt()
        closeBtn.setPadding((6 * density).toInt(), (2 * density).toInt(), (6 * density).toInt(), (2 * density).toInt())
        closeBtn.minWidth = closeSize
        closeBtn.minHeight = closeSize
        val closeBg = GradientDrawable()
        closeBg.shape = GradientDrawable.OVAL
        closeBg.setColor(0x99FF4444.toInt())
        closeBtn.background = closeBg
        // Center the '✕' inside the circular background and remove extra font padding
        closeBtn.setGravity(Gravity.CENTER)
        closeBtn.setIncludeFontPadding(false)
        val closeLp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        closeLp.gravity = Gravity.CENTER_VERTICAL
        container.addView(closeBtn, closeLp)

        closeBtn.setOnClickListener {
            stopSelf()
        }

        // Dragging handler on the whole container
        container.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f

            override fun onTouch(v: View?, event: MotionEvent?): Boolean {
                when (event?.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = layoutParams.x
                        initialY = layoutParams.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (event.rawX - initialTouchX).toInt()
                        val dy = (event.rawY - initialTouchY).toInt()
                        val metrics = resources.displayMetrics
                        val maxX = (metrics.widthPixels - container.width).coerceAtLeast(0)
                        val maxY = (metrics.heightPixels - container.height).coerceAtLeast(0)
                        layoutParams.x = (initialX + dx).coerceIn(0, maxX)
                        layoutParams.y = (initialY + dy).coerceIn(0, maxY)
                        try {
                            windowManager.updateViewLayout(container, layoutParams)
                        } catch (error: Exception) {
                            // A revoked overlay permission or invalid window token makes
                            // the overlay unusable; stop cleanly and notify the host.
                            Log.e(TAG, "WindowManager.updateViewLayout failed during drag", error)
                            stopSelf()
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        positionPrefs.edit()
                            .putInt("x", layoutParams.x)
                            .putInt("y", layoutParams.y)
                            .apply()
                        return true
                    }
                }
                return false
            }
        })

        // Keep the alias view attached to the container. Publish references only after
        // addView succeeds, otherwise later updates could target a detached view.
        container.tag = aliasTv
        try {
            windowManager.addView(container, layoutParams)
        } catch (error: Exception) {
            Log.e(TAG, "WindowManager.addView failed", error)
            return false
        }
        textView = tv
        containerView = container
        overlayView = container
        lastPermissionCheckElapsedRealtime = SystemClock.elapsedRealtime()
        // Clamp restored coordinates after the view has been measured so a screen-size
        // change cannot leave the clock completely outside the visible display area.
        container.post {
            if (overlayView === container) {
                val metrics = resources.displayMetrics
                val maxX = (metrics.widthPixels - container.width).coerceAtLeast(0)
                val maxY = (metrics.heightPixels - container.height).coerceAtLeast(0)
                val clampedX = layoutParams.x.coerceIn(0, maxX)
                val clampedY = layoutParams.y.coerceIn(0, maxY)
                if (clampedX != layoutParams.x || clampedY != layoutParams.y) {
                    layoutParams.x = clampedX
                    layoutParams.y = clampedY
                    try {
                        windowManager.updateViewLayout(container, layoutParams)
                        positionPrefs.edit().putInt("x", clampedX).putInt("y", clampedY).apply()
                    } catch (_: Exception) {
                        stopSelf()
                    }
                }
            }
        }
        return true
    }

    private fun removeOverlay() {
        try {
            overlayView?.let { windowManager.removeView(it) }
        } catch (error: Exception) {
            Log.w(TAG, "Unable to remove overlay window cleanly", error)
        }
        overlayView = null
        textView = null
        containerView = null
    }

    private fun updateTime() {
        // updateRunnable and WindowManager callbacks run on the main thread. Updating
        // views directly avoids enqueueing an additional View.post every 10 ms.
        val nowElapsed = SystemClock.elapsedRealtime()
        if (nowElapsed - lastPermissionCheckElapsedRealtime >= 1_000L) {
            lastPermissionCheckElapsedRealtime = nowElapsed
            if (!hasOverlayPermission()) {
                Log.w(TAG, "Overlay permission was revoked while service was running")
                stopSelf()
                return
            }
        }

        val timeView = textView ?: return
        timeView.text = currentTimeText()
        val aliasTv = containerView?.tag as? TextView
        aliasTv?.text = label ?: ""
        aliasTv?.isSelected = true
    }

    private fun currentTimeText(): CharSequence {
        val nowMs = System.currentTimeMillis() + offsetMillis
        val cal = Calendar.getInstance()
        cal.timeInMillis = nowMs
        val h = cal.get(Calendar.HOUR_OF_DAY)
        val m = cal.get(Calendar.MINUTE)
        val s = cal.get(Calendar.SECOND)
        val base = String.format(Locale.getDefault(), "%02d:%02d:%02d", h, m, s)
        val fraction = if (displayPrecision == DisplayPrecision.CENTISECOND) {
            String.format(Locale.getDefault(), "%02d", cal.get(Calendar.MILLISECOND) / 10)
        } else {
            (cal.get(Calendar.MILLISECOND) / 100).toString()
        }
        val display = "$base.$fraction"
        val spannable = SpannableString(display)
        val dotIndex = display.lastIndexOf('.')
        if (dotIndex in 0 until display.length - 1) {
            spannable.setSpan(
                ForegroundColorSpan(fractionColor),
                dotIndex + 1,
                display.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
        // Overlay should show only the time (no alias), keep it compact.
        return spannable
    }

    private fun applyPrecision(raw: String?) {
        val newPrecision = when (raw) {
            "decisecond" -> DisplayPrecision.DECISECOND
            else -> DisplayPrecision.CENTISECOND
        }
        displayPrecision = newPrecision
        updateIntervalMs = if (newPrecision == DisplayPrecision.CENTISECOND) 10L else 100L
    }
}

private enum class DisplayPrecision {
    CENTISECOND,
    DECISECOND
}
