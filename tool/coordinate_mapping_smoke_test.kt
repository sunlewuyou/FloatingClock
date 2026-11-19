package io.github.amchii.floatingclock

/** Standalone smoke test for the actual pure-Kotlin coordinate transform. */
fun main() {
    val layouts = listOf(
        Triple(1080, 2400, WindowLocalPoint(0, 0)),
        Triple(2400, 1080, WindowLocalPoint(0, 0)),
        Triple(1080, 2400, WindowLocalPoint(0, 24)),
    )
    layouts.forEach { (width, height, origin) ->
        val points = listOf(
            0 to 0,
            width - 1 to 0,
            0 to height - 1,
            width - 1 to height - 1,
            width / 2 to height / 2,
            width / 2 to 0,
            width / 2 to height - 1,
            0 to height / 2,
            width - 1 to height / 2,
        )
        points.forEach { (x, y) ->
            val local = screenToWindowLocal(x, y, origin.x, origin.y)
            check(local.x + origin.x == x) { "X transform drift at screen point ($x,$y)" }
            check(local.y + origin.y == y) { "Y transform drift at screen point ($x,$y)" }
        }
    }
    println("PASS: coordinate mapping round-trip on 27 edge/center points")
}
