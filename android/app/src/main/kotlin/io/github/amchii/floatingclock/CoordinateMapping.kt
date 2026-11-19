package io.github.amchii.floatingclock

/** Screen-space point translated into the local coordinate space of an overlay view. */
internal data class WindowLocalPoint(val x: Int, val y: Int)

internal fun screenToWindowLocal(
    screenX: Int,
    screenY: Int,
    windowOriginX: Int,
    windowOriginY: Int
): WindowLocalPoint = WindowLocalPoint(
    x = screenX - windowOriginX,
    y = screenY - windowOriginY
)
