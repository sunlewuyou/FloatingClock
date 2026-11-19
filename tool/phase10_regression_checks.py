#!/usr/bin/env python3
"""Static guards for Phase 10 regressions; not a Flutter/Android test substitute."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
checks = [
    ("overlay close button stops service", "android/app/src/main/kotlin/io/github/amchii/floatingclock/FloatingClockService.kt", "closeBtn.setOnClickListener {\n            // onDestroy broadcasts only after running=false and the overlay is"),
    ("service clears running before notifying host", "android/app/src/main/kotlin/io/github/amchii/floatingclock/FloatingClockService.kt", "override fun onDestroy() {\n        running = false\n        handler.removeCallbacks(updateRunnable)\n        removeOverlay()\n        notifyOverlayStopped()"),
    ("PiP surface switches before native transition", "lib/pages/home_page.dart", "setState(() => _isInPiP = true);"),
    ("PiP clock timer stays active while paused", "lib/pages/home_page.dart", "if (!_isInPiP) {\n        _uiTimer?.cancel();\n        _uiTimer = null;"),
    ("PiP mode callback restarts clock timer", "lib/pages/home_page.dart", "setState(() => _isInPiP = inPiP);\n        // PiP still renders the Flutter clock while the Activity is paused.\n        // Re-start its tick source when PiP enters, and keep it available after\n        // exiting PiP until lifecycle reconciliation finishes.\n        _restartUiTimer();"),
    ("task route returns home if PiP entered while it is active", "lib/pages/scheduled_task_page.dart", "if (inPiP && mounted && Navigator.of(context).canPop()) {\n        Navigator.of(context).pop();"),
    ("crosshair draws both axes in clipped Canvas", "android/app/src/main/kotlin/io/github/amchii/floatingclock/CoordinatePickerService.kt", "canvas.drawLine(0f, localY, width.toFloat(), localY, paint)\n        canvas.drawLine(localX, 0f, localX, height.toFloat(), paint)"),
    ("crosshair uses shared screen-to-window transform", "android/app/src/main/kotlin/io/github/amchii/floatingclock/CoordinatePickerService.kt", "val local = screenToWindowLocal(screenX.toInt(), screenY.toInt(), originX.toInt(), originY.toInt())"),
    ("picker refreshes screen metrics and clamps both axes", "android/app/src/main/kotlin/io/github/amchii/floatingclock/CoordinatePickerService.kt", "val currentMetrics = realDisplayMetrics()\n            crossX = screenX.coerceIn(0, currentMetrics.widthPixels - 1)\n            crossY = screenY.coerceIn(0, currentMetrics.heightPixels - 1)"),
    ("broadcast uses screen-space point and current metrics", "android/app/src/main/kotlin/io/github/amchii/floatingclock/CoordinatePickerService.kt", "sendCoordinateUpdate(crossX, crossY, currentMetrics)"),
    ("coordinate transform smoke test is included", "tool/coordinate_mapping_smoke_test.kt", "screenToWindowLocal(x, y, origin.x, origin.y)"),
]
failures = []
for label, relative, expected in checks:
    if expected not in (ROOT / relative).read_text(encoding="utf-8"):
        failures.append(label)
    else:
        print(f"PASS: {label}")
picker = (ROOT / "android/app/src/main/kotlin/io/github/amchii/floatingclock/CoordinatePickerService.kt").read_text(encoding="utf-8")
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
