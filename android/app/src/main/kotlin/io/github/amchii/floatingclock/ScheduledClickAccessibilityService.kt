package io.github.amchii.floatingclock

import android.accessibilityservice.AccessibilityService
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/** User-enabled accessibility bridge used only to dispatch the user's configured tap. */
class ScheduledClickAccessibilityService : AccessibilityService() {
    companion object {
        private const val TAG = "ScheduledClickA11y"
        @Volatile var instance: ScheduledClickAccessibilityService? = null
            private set
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(TAG, "Accessibility click service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit
    override fun onInterrupt() = Unit

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    fun dispatchTap(x: Float, y: Float, callback: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            callback(false)
            return
        }
        Api24GestureDispatcher.dispatch(this, x, y, callback)
    }
}
