package io.github.amchii.floatingclock

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import android.graphics.drawable.GradientDrawable
import android.util.DisplayMetrics
import android.util.Log

/** Full-screen transparent overlay: the first user tap records physical screen pixels. */
class CoordinatePickerService : Service() {
    private var windowManager: WindowManager? = null
    private var pickerView: FrameLayout? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !android.provider.Settings.canDrawOverlays(this)) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        if (pickerView != null) return START_NOT_STICKY
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        val root = FrameLayout(this)
        root.setBackgroundColor(Color.argb(12, 0, 0, 0))
        val instruction = TextView(this).apply {
            text = "轻触要点击的位置以保存坐标"
            setTextColor(Color.WHITE)
            textSize = 16f
            gravity = Gravity.CENTER
            setPadding(24, 16, 24, 16)
            background = GradientDrawable().apply {
                setColor(Color.argb(220, 30, 30, 30)); cornerRadius = 18f
            }
            typeface = Typeface.DEFAULT_BOLD
        }
        val instructionLp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.CENTER_HORIZONTAL
        ).apply { setMargins(24, 48, 24, 0) }
        root.addView(instruction, instructionLp)
        val cancel = TextView(this).apply {
            text = "取消"
            setTextColor(Color.WHITE)
            textSize = 15f
            gravity = Gravity.CENTER
            setPadding(20, 14, 20, 14)
            background = GradientDrawable().apply {
                setColor(Color.argb(230, 170, 45, 45)); cornerRadius = 18f
            }
            setOnClickListener { stopSelf() }
        }
        val cancelLp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.END
        ).apply { setMargins(0, 48, 24, 0) }
        root.addView(cancel, cancelLp)
        root.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_UP) {
                val metrics = realDisplayMetrics()
                val result = Intent(ACTION_COORDINATE_PICKED).setPackage(packageName)
                    .putExtra("x", event.rawX.toInt())
                    .putExtra("y", event.rawY.toInt())
                    .putExtra("screenWidth", metrics.widthPixels)
                    .putExtra("screenHeight", metrics.heightPixels)
                    .putExtra("densityDpi", metrics.densityDpi)
                    .putExtra("rotation", realDisplayRotation())
                sendBroadcast(result)
                stopSelf()
                true
            } else true
        }
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.TOP or Gravity.START }
        try {
            windowManager?.addView(root, params)
            pickerView = root
        } catch (error: Exception) {
            Log.e(TAG, "Unable to show coordinate picker", error)
            stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    @Suppress("DEPRECATION")
    private fun realDisplayMetrics(): DisplayMetrics {
        val metrics = DisplayMetrics()
        windowManager?.defaultDisplay?.getRealMetrics(metrics)
        return metrics
    }

    @Suppress("DEPRECATION")
    private fun realDisplayRotation(): Int = windowManager?.defaultDisplay?.rotation ?: 0

    override fun onDestroy() {
        try { pickerView?.let { windowManager?.removeView(it) } } catch (_: Exception) { }
        pickerView = null
        windowManager = null
        super.onDestroy()
    }

    companion object {
        const val ACTION_COORDINATE_PICKED = "io.github.amchii.floatingclock.COORDINATE_PICKED"
        private const val TAG = "CoordinatePicker"
    }
}
