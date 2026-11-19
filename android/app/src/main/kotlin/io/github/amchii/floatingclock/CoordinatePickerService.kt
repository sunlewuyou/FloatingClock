package io.github.amchii.floatingclock

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.Canvas
import android.graphics.Paint
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

/** Draws a crosshair in window-local canvas coordinates while preserving screen coordinates. */
private class CrosshairLayer(
    context: android.content.Context,
    color: Int,
    strokeWidthPx: Float
) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        strokeWidth = strokeWidthPx
        style = Paint.Style.STROKE
    }
    private var screenX = -1f
    private var screenY = -1f
    private var originX = 0f
    private var originY = 0f

    fun updateScreenPoint(x: Int, y: Int, windowX: Int, windowY: Int) {
        screenX = x.toFloat()
        screenY = y.toFloat()
        originX = windowX.toFloat()
        originY = windowY.toFloat()
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (screenX < 0f || screenY < 0f || width <= 0 || height <= 0) return
        // Canvas clips at the View bounds. At display edges, the stroke may be
        // clipped symmetrically, but its center (the coordinate) remains exact.
        val local = screenToWindowLocal(screenX.toInt(), screenY.toInt(), originX.toInt(), originY.toInt())
        val localX = local.x.toFloat()
        val localY = local.y.toFloat()
        canvas.drawLine(0f, localY, width.toFloat(), localY, paint)
        canvas.drawLine(localX, 0f, localX, height.toFloat(), paint)
    }
}


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
        val crosshair = CrosshairLayer(this, Color.argb(230, 30, 144, 255), maxOf(1f, 1.5f * density))

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
        // Draw both axes in one clipped Canvas. Unlike margin-positioned child views,
        // this keeps the line center tied to the actual touch point and prevents
        // either line from extending beyond the overlay's drawable bounds.
        root.addView(crosshair, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        root.addView(coordinateHud, hudLp)
        root.addView(cancel, cancelLp)


        // rawX/rawY are physical display coordinates. Each move recomputes the
        // attached overlay's screen origin and converts only for Canvas drawing.
        val windowOrigin = IntArray(2)
        var crossX = metrics.widthPixels / 2
        var crossY = metrics.heightPixels / 2
        fun moveCrosshair(screenX: Int, screenY: Int) {
            // Clamp the physical touch coordinates to the real display pixel bounds.
            // Drawing is a separate transform and never changes the saved target.
            val currentMetrics = realDisplayMetrics()
            crossX = screenX.coerceIn(0, currentMetrics.widthPixels - 1)
            crossY = screenY.coerceIn(0, currentMetrics.heightPixels - 1)
            root.getLocationOnScreen(windowOrigin)
            crosshair.updateScreenPoint(crossX, crossY, windowOrigin[0], windowOrigin[1])
            coordinateHud.text = "X $crossX  ·  Y $crossY"
            // Broadcast physical screen coordinates and current display metadata.
            // Local Canvas coordinates are never used as the saved click target.
            sendCoordinateUpdate(crossX, crossY, currentMetrics)
        }
        root.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                    moveCrosshair(event.rawX.toInt(), event.rawY.toInt())
                    true
                }
                MotionEvent.ACTION_UP -> {
                    moveCrosshair(event.rawX.toInt(), event.rawY.toInt())
                    sendCoordinatePicked(crossX, crossY, realDisplayMetrics())
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
            root.getLocationOnScreen(windowOrigin)
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
