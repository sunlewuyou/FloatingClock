# Phase 10 fix13

## Fixed
- Prevent the Home and Scheduled Task routes from replacing/clearing the same Flutter MethodChannel callback handler. Added a shared dispatcher that keeps one native callback handler installed and routes events to mounted route listeners.
- Home and Scheduled Task listeners unregister only their own callbacks on dispose.
- Removed the redundant Home callback-handler reinstallation after the scheduled-task route returns.
- Scheduled-task time-source refresh now queries actual native service state before updating a running overlay; stale Flutter state cannot start an overlay on page entry.
- Updated phase10 static regression guards to test shared callback dispatch ownership, page-entry side-effect prevention, and native close ordering (the previous guard strings were stale and failed against fix12).

## Verification
- Python static regression guards passed.
- Kotlin coordinate transform smoke test passed (27 edge/center points).
- AndroidManifest XML parse passed.
- release.yml YAML parse passed.
- Flutter analyze, Flutter tests, and Android APK build were not run: Flutter/Android SDK unavailable in this environment.
