# Phase 6: Android overlay service lifecycle hardening

## Scope

This phase is intentionally limited to the Android native overlay service and
its existing Flutter MethodChannel entry points. Existing channel names,
method names, argument keys, notification channel ID, service class name, and
broadcast action are preserved.

## Changes

- Promote the service to foreground before creating or attaching the overlay
  window, keeping the `startForegroundService()` startup path prompt.
- Make repeated start requests idempotent: reuse the existing overlay and
  replace the existing clock update callback instead of creating duplicates.
- Stop the foreground service cleanly when overlay permission is unavailable
  or when WindowManager cannot attach the overlay.
- Re-check overlay permission at a low frequency while the clock is running;
  stop the service if permission has been revoked.
- Update the overlay TextViews directly from the main-thread Handler instead
  of adding another `View.post()` callback on every 10 ms tick.
- Persist drag position and restore it on the next start. Clamp restored and
  dragged coordinates to the current display bounds so the overlay remains
  reachable after display-size changes.
- Catch service start/stop failures at the MethodChannel boundary and return
  structured errors to Flutter instead of allowing an uncaught platform
  exception to escape the handler.
- Guard MethodChannel event delivery during Flutter engine teardown.
- Treat devices below Android M as having no runtime overlay special-access
  gate, avoiding an API 23 method call on older supported Android versions.

## Compatibility preserved

- MethodChannel: `floating_clock`
- Methods: `hasPermission`, `requestPermission`, `startOverlay`, `stopOverlay`,
  `isOverlayRunning`, `isPiPSupported`, `enterPiP`
- Service: `FloatingClockService`
- Broadcast: `io.github.amchii.floatingclock.OVERLAY_STOPPED`
- Intent extras: `offset`, `label`, `precision`, `fractionColor`
- Display precision, time offset calculation, fractional color, and close button
  behavior remain unchanged.

## Validation required in CI / on device

Run with the repository's pinned Flutter 3.35.7 workflow:

```bash
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter build apk --release --split-per-abi
```

Then verify on Android devices/API levels supported by the project:

1. Start overlay with permission granted; confirm notification and overlay appear.
2. Invoke start repeatedly with different time offsets/labels; confirm one overlay
   remains and it displays the latest settings.
3. Drag the overlay to each screen edge, close and reopen the app; confirm its
   position is restored and remains reachable.
4. Revoke overlay permission while running; confirm the service stops and the
   Flutter UI receives `onOverlayStopped`.
5. Deny overlay permission before starting; confirm Flutter receives
   `NO_PERMISSION` and no foreground service remains.
6. Stop via the close button and via `stopOverlay`; confirm both paths clean up
   the notification, overlay window, and update callback.
7. Exercise PiP and notification-tap flows to confirm they are unaffected.

The source package static checks do not replace Kotlin/Android compilation or
real-device validation. The CI workflow is the authoritative build check.
