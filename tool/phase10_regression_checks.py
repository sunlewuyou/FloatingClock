#!/usr/bin/env python3
"""Static guards for Phase 10 regressions; not a Flutter test substitute."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
checks = [
    ("close button stops service", "android/app/src/main/kotlin/io/github/amchii/floatingclock/FloatingClockService.kt", "closeBtn.setOnClickListener {\n            // onDestroy broadcasts only after running=false and the overlay is"),
    ("service clears running before stop notification", "android/app/src/main/kotlin/io/github/amchii/floatingclock/FloatingClockService.kt", "override fun onDestroy() {\n        running = false\n        handler.removeCallbacks(updateRunnable)\n        removeOverlay()\n        notifyOverlayStopped()"),
    ("native PiP query exists", "android/app/src/main/kotlin/io/github/amchii/floatingclock/MainActivity.kt", '"isInPiP" -> {\n                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isInPictureInPictureMode)'),
    ("scheduled page returns to home for PiP", "lib/pages/scheduled_task_page.dart", "if (inPiP && mounted && Navigator.of(context).canPop()) {\n        Navigator.of(context).pop();"),
    ("home reconciles native PiP state", "lib/pages/home_page.dart", "Future<void> _refreshPiPStatus() async {\n    if (!Platform.isAndroid) return;\n    try {\n      final nativeState = await _channel.invokeMethod<bool>('isInPiP');"),
    ("home restores event handler and reconciles state after task route", "lib/pages/home_page.dart", "_channel.setMethodCallHandler(_handlePlatformCall);\n                await _refreshPiPStatus();\n                await _refreshOverlayStatus();"),
    ("crosshair uses local Y coordinate", "android/app/src/main/kotlin/io/github/amchii/floatingclock/CoordinatePickerService.kt", "val localY = (crossY - windowOrigin[1]).coerceIn(0, metrics.heightPixels - 1)\n            horizontalLp.topMargin = localY"),
    ("broadcast preserves absolute screen coordinate", "android/app/src/main/kotlin/io/github/amchii/floatingclock/CoordinatePickerService.kt", "sendCoordinateUpdate(crossX, crossY, metrics)"),
]
failures = []
for label, relative, expected in checks:
    source = (ROOT / relative).read_text(encoding="utf-8")
    if expected not in source:
        failures.append(label)
    else:
        print(f"PASS: {label}")
workflow_dir = ROOT / ".github/workflows"
workflow_names = sorted([p.name for p in workflow_dir.glob("*.yml")] + [p.name for p in workflow_dir.glob("*.yaml")])
if workflow_names != ["release.yml"]:
    failures.append(f"workflow filenames are not exactly release.yml: {workflow_names}")
else:
    print("PASS: workflow filename is release.yml (no duplicate workflow)")
if failures:
    print("FAILED static guards:")
    for failure in failures:
        print(" -", failure)
    raise SystemExit(1)
print("All static regression checks passed. This is not a Flutter or Android build.")
