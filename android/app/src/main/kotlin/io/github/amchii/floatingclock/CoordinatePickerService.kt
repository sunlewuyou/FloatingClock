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
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import android.util.DisplayMetrics
import android.util.Log

/** Transparent full-screen coordinate picker. Crosshair follows the finger; release confirms. */
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
        val root = FrameLayout(this).apply { setBackgroundColor(Color.TRANSPARENT) }
        val density = resources.displayMetrics.density
        val horizontal = View(this).apply { setBackgroundColor(Color.argb(230, 30, 144, 255)) }
        val vertical = View(this).apply { setBackgroundColor(Color.argb(230, 30, 144, 255)) }
        val horizontalLp = FrameLayout.LayoutParams(metrics.widthPixels, maxOf(1, (1.5f * density).toInt()), Gravity.TOP or Gravity.START)
        val verticalLp = FrameLayout.LayoutParams(maxOf(1, (1.5f * density).toInt()), metrics.heightPixels, Gravity.TOP or Gravity.START)

        val coordinateHud = TextView(this).apply {
            text = "X 0  ·  Y 0"
            setTextColor(Color.WHITE)
            textSize = 14f
            typeface = Typeface.MONOSPACE
            gravity = Gravity.CENTER
            setPadding((10 * density).toInt(), (7 * density).toInt(), (10 * density).toInt(), (7 * density).toInt())
            background = rounded(Color.argb(210, 20, 24, 30), 8f)
        }
        val hudLp = FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply {
            topMargin = (12 * density).toInt()
        }
        val cancel = TextView(this).apply {
            text = "取消"
            setTextColor(Color.WHITE)
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding((14 * density).toInt(), (9 * density).toInt(), (14 * density).toInt(), (9 * density).toInt())
            background = rounded(Color.argb(220, 155, 45, 45), 16f)
            setOnClickListener { stopSelf() }
        }
        val cancelLp = FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.TOP or Gravity.END).apply {
            topMargin = (12 * density).toInt()
            marginEnd = (12 * density).toInt()
        }
        root.addView(horizontal, horizontalLp)
        root.addView(vertical, verticalLp)
        root.addView(coordinateHud, hudLp)
        root.addView(cancel, cancelLp)


        var crossX = metrics.widthPixels / 2
        var crossY = metrics.heightPixels / 2
        fun moveCrosshair(x: Int, y: Int) {
            crossX = x.coerceIn(0, metrics.widthPixels - 1)
            crossY = y.coerceIn(0, metrics.heightPixels - 1)
            horizontalLp.topMargin = crossY
            verticalLp.leftMargin = crossX
            horizontal.layoutParams = horizontalLp
            vertical.layoutParams = verticalLp
            coordinateHud.text = "X $crossX  ·  Y $crossY"
            sendCoordinateUpdate(crossX, crossY, metrics)
        }
        root.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                    moveCrosshair(event.rawX.toInt(), event.rawY.toInt())
                    true
                }
                MotionEvent.ACTION_UP -> {
                    moveCrosshair(event.rawX.toInt(), event.rawY.toInt())
                    sendCoordinatePicked(crossX, crossY, metrics)
                    stopSelf()
                    true
                }
                MotionEvent.ACTION_CANCEL -> true
                else -> true
            }
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
        moveCrosshair(crossX, crossY)
        return START_NOT_STICKY
    }


    private fun sendCoordinateUpdate(x: Int, y: Int, metrics: DisplayMetrics) {
        sendBroadcast(Intent(ACTION_COORDINATE_MOVED).setPackage(packageName)
            .putExtra("x", x).putExtra("y", y)
            .putExtra("screenWidth", metrics.widthPixels).putExtra("screenHeight", metrics.heightPixels)
            .putExtra("densityDpi", metrics.densityDpi).putExtra("rotation", realDisplayRotation()))
    }

    private fun sendCoordinatePicked(x: Int, y: Int, metrics: DisplayMetrics) {
        sendBroadcast(Intent(ACTION_COORDINATE_PICKED).setPackage(packageName)
            .putExtra("x", x).putExtra("y", y)
            .putExtra("screenWidth", metrics.widthPixels).putExtra("screenHeight", metrics.heightPixels)
            .putExtra("densityDpi", metrics.densityDpi).putExtra("rotation", realDisplayRotation()))
    }

    private fun rounded(color: Int, radius: Float) = android.graphics.drawable.GradientDrawable().apply {
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
        const val ACTION_COORDINATE_MOVED = "io.github.amchii.floatingclock.COORDINATE_MOVED"
        const val ACTION_COORDINATE_PICKED = "io.github.amchii.floatingclock.COORDINATE_PICKED"
        private const val TAG = "CoordinatePicker"
    }
}
