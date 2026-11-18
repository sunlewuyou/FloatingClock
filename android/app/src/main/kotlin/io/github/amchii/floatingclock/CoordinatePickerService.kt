package io.github.amchii.floatingclock

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import android.util.DisplayMetrics
import android.util.Log

/** Full-screen transparent overlay with a draggable target; releasing confirms its center. */
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
        val metrics = realDisplayMetrics()
        val root = FrameLayout(this).apply { setBackgroundColor(Color.argb(10, 0, 0, 0)) }

        val instruction = TextView(this).apply {
            text = "拖动准星到目标位置，松开即确认"
            setTextColor(Color.WHITE)
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(18, 12, 18, 12)
            background = rounded(Color.argb(215, 25, 28, 32), 18f)
            typeface = Typeface.DEFAULT_BOLD
        }
        val instructionLp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.CENTER_HORIZONTAL
        ).apply { topMargin = (24 * resources.displayMetrics.density).toInt() }
        root.addView(instruction, instructionLp)

        val cancel = TextView(this).apply {
            text = "取消"
            setTextColor(Color.WHITE)
            textSize = 13f
            gravity = Gravity.CENTER
            setPadding(14, 10, 14, 10)
            background = rounded(Color.argb(220, 150, 45, 45), 16f)
            setOnClickListener { stopSelf() }
        }
        val cancelLp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.END
        ).apply {
            topMargin = (22 * resources.displayMetrics.density).toInt()
            marginEnd = (14 * resources.displayMetrics.density).toInt()
        }
        root.addView(cancel, cancelLp)

        val markerSize = (58 * resources.displayMetrics.density).toInt()
        val marker = TextView(this).apply {
            text = "⊕"
            setTextColor(Color.WHITE)
            textSize = 48f
            gravity = Gravity.CENTER
            includeFontPadding = false
            typeface = Typeface.DEFAULT_BOLD
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.argb(205, 25, 115, 210))
                setStroke((2 * resources.displayMetrics.density).toInt(), Color.WHITE)
            }
            elevation = 10f
            contentDescription = "可拖动坐标准星"
        }
        val markerLp = FrameLayout.LayoutParams(markerSize, markerSize, Gravity.TOP or Gravity.START).apply {
            leftMargin = ((metrics.widthPixels - markerSize) / 2).coerceAtLeast(0)
            topMargin = ((metrics.heightPixels - markerSize) / 2).coerceAtLeast(0)
        }
        marker.setOnTouchListener(object : View.OnTouchListener {
            private var startLeft = 0
            private var startTop = 0
            private var downRawX = 0f
            private var downRawY = 0f
            override fun onTouch(view: View, event: MotionEvent): Boolean {
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        startLeft = markerLp.leftMargin
                        startTop = markerLp.topMargin
                        downRawX = event.rawX
                        downRawY = event.rawY
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        markerLp.leftMargin = (startLeft + event.rawX - downRawX).toInt()
                            .coerceIn(0, (metrics.widthPixels - markerSize).coerceAtLeast(0))
                        markerLp.topMargin = (startTop + event.rawY - downRawY).toInt()
                            .coerceIn(0, (metrics.heightPixels - markerSize).coerceAtLeast(0))
                        try {
                            marker.layoutParams = markerLp
                            marker.requestLayout()
                        } catch (error: Exception) {
                            Log.e(TAG, "Unable to move coordinate marker", error)
                            stopSelf()
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        val x = (markerLp.leftMargin + marker.width / 2).coerceIn(0, metrics.widthPixels - 1)
                        val y = (markerLp.topMargin + marker.height / 2).coerceIn(0, metrics.heightPixels - 1)
                        val result = Intent(ACTION_COORDINATE_PICKED).setPackage(packageName)
                            .putExtra("x", x).putExtra("y", y)
                            .putExtra("screenWidth", metrics.widthPixels)
                            .putExtra("screenHeight", metrics.heightPixels)
                            .putExtra("densityDpi", metrics.densityDpi)
                            .putExtra("rotation", realDisplayRotation())
                        sendBroadcast(result)
                        stopSelf()
                        return true
                    }
                    MotionEvent.ACTION_CANCEL -> return true
                }
                return true
            }
        })
        root.addView(marker, markerLp)
        root.setOnTouchListener { _, _ -> true }

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

    private fun rounded(color: Int, radius: Float) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = radius * resources.displayMetrics.density
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
