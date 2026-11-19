# Phase 10 fix11 maintenance corrections

Based on `FloatingClock-optimize-phase10-fix10.zip`.

## Fixes

- PiP: switch Flutter to the compact clock surface before requesting native PiP entry, so the first PiP frame is less likely to capture the full Home UI. Restore the full Home surface when native PiP entry fails.
- PiP: keep the Flutter clock tick notifier running while the Activity is paused in PiP; restart the notifier on PiP mode callbacks.
- Floating overlay: remove the delayed stop-state polling that could resurrect the Home toggle from stale native state after the service's stop notification.
- Coordinate picker: draw both crosshair axes using a clipped Canvas view; transform screen coordinates to overlay-local coordinates only for drawing; preserve screen-space coordinates for HUD, selection, and click execution.
- Coordinate picker: read display metrics on each touch update and clamp X/Y against the current real-display bounds.
- Regression guard: update `tool/phase10_regression_checks.py` and add `tool/coordinate_mapping_smoke_test.kt` to cover static guards and the actual pure-Kotlin screen/window transform.

## Validation performed

- Python static regression guard script passed.
- Standalone Kotlin coordinate-transform smoke test passed on 27 edge/center points across three screen layouts/origins.
- Android Manifest XML parsed successfully.
- `release.yml` parsed successfully and includes `workflow_dispatch`.
- ZIP integrity and SHA-256 checked after packaging.

## Validation not performed

Flutter analyze, Flutter widget tests, Gradle/Android APK compilation, and device-level PiP/overlay/coordinate tests were not run because this environment has no Flutter/Dart SDK or Android SDK. Static checks and the pure Kotlin transform smoke test are not substitutes for those tests.
