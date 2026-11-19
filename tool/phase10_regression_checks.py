#!/usr/bin/env python3
"""Static guards for Phase 10 regressions; not a Flutter/Android test substitute."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
checks = [
    ("native close button marks service stopped before broadcast", "android/app/src/main/kotlin/io/github/amchii/floatingclock/FloatingClockService.kt", "running = false\n            handler.removeCallbacks(updateRunnable)\n            removeOverlay()\n            notifyOverlayStopped()"),
    ("native stop broadcast is package-scoped and emitted once", "android/app/src/main/kotlin/io/github/amchii/floatingclock/FloatingClockService.kt", "if (stopNotificationSent) return\n        stopNotificationSent = true\n        sendBroadcast(Intent(\"io.github.amchii.floatingclock.OVERLAY_STOPPED\").setPackage(packageName))"),
    ("single shared MethodChannel dispatcher exists", "lib/services/platform_method_dispatcher.dart", "static const MethodChannel channel = MethodChannel('floating_clock');"),
    ("dispatcher installs only one native callback handler", "lib/services/platform_method_dispatcher.dart", "channel.setMethodCallHandler(_dispatch);"),
    ("dispatcher snapshots listeners and protects individual callbacks", "lib/services/platform_method_dispatcher.dart", "List<PlatformCallHandler>.of(_listeners.values)"),
    ("home registers native callback through dispatcher", "lib/pages/home_page.dart", "PlatformMethodDispatcher.register(this, _handlePlatformCall)"),
    ("home unregisters its listener without clearing shared handler", "lib/pages/home_page.dart", "_removePlatformListener?.call();"),
    ("scheduled route registers native callback through dispatcher", "lib/pages/scheduled_task_page.dart", "PlatformMethodDispatcher.register(this, _handleNativeCall)"),
    ("scheduled route unregisters only its own listener", "lib/pages/scheduled_task_page.dart", "_removePlatformListener?.call();"),
    ("scheduled task time-source refresh queries actual native service state", "lib/pages/home_page.dart", "nativeRunning = await _channel.invokeMethod<bool>('isOverlayRunning') ?? false;"),
    ("scheduled task refresh only updates an already-running native overlay", "lib/pages/home_page.dart", "if (nativeRunning) {\n          unawaited(_updateOverlayForSelected());\n        }"),
    ("PiP surface switches before native transition", "lib/pages/home_page.dart", "setState(() => _isInPiP = true);"),
    ("PiP clock timer stays active while paused", "lib/pages/home_page.dart", "if (!_isInPiP) {\n        _uiTimer?.cancel();\n        _uiTimer = null;"),
    ("crosshair draws both axes on one clipped Canvas", "android/app/src/main/kotlin/io/github/amchii/floatingclock/CoordinatePickerService.kt", "canvas.drawLine(0f, localY, width.toFloat(), localY, paint)\n        canvas.drawLine(localX, 0f, localX, height.toFloat(), paint)"),
    ("crosshair transform uses screen and window origin", "android/app/src/main/kotlin/io/github/amchii/floatingclock/CoordinatePickerService.kt", "screenToWindowLocal(screenX.toInt(), screenY.toInt(), originX.toInt(), originY.toInt())"),
]
failures = []
for label, relative, expected in checks:
    if expected not in (ROOT / relative).read_text(encoding="utf8"):
        failures.append(label)
    else:
        print(f"PASS: {label}")

for relative in ("lib/pages/home_page.dart", "lib/pages/scheduled_task_page.dart"):
    source = (ROOT / relative).read_text(encoding="utf8")
    if "setMethodCallHandler(" in source:
        failures.append(f"page still directly owns MethodChannel handler: {relative}")
    else:
        print(f"PASS: no page overwrites shared MethodChannel handler ({relative})")

picker = (ROOT / "android/app/src/main/kotlin/io/github/amchii/floatingclock/CoordinatePickerService.kt").read_text(encoding="utf8")
if "horizontalLp.topMargin" in picker or "verticalLp.leftMargin" in picker:
    failures.append("crosshair still uses margin positioning")
else:
    print("PASS: crosshair is not positioned with margins")
workflow_dir = ROOT / ".github/workflows"
workflow_names = sorted([p.name for p in workflow_dir.glob("*.yml")] + [p.name for p in workflow_dir.glob("*.yaml")])
if workflow_names != ["release.yml"]:
    failures.append(f"workflow files are not exactly release.yml: {workflow_names}")
else:
    print("PASS: release.yml is the only workflow")
if failures:
    print("FAILED static guards:")
    for failure in failures:
        print(" -", failure)
    raise SystemExit(1)
print("All source guards passed (static only; no Flutter/Android build).")
