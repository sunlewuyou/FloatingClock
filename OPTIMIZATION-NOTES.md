# FloatingClock optimization notes

## High-frequency clock rendering isolation

The main page previously called `setState()` every 10 ms (centisecond mode) or
100 ms (decisecond mode). Since the timer belonged to `HomePage`, this rebuilt
the complete page subtree, including source controls and the source list, even
though only the clock digits changed.

The clock display is now isolated in `lib/widgets/clock_time_text.dart` and
subscribes to a `ValueListenable<int>`. The page timer increments a
`ValueNotifier` instead of calling `setState`, so only the clock text subtree
rebuilds on each tick. Precision changes and source selection still rebuild the
page normally and pass the updated display configuration to the clock widget.

When the app enters the paused lifecycle state, the high-frequency Dart timer
is stopped. It is restarted when the app resumes. The Android overlay service
continues to own its own display updates and is not coupled to this page timer.

The 10 ms centisecond and 100 ms decisecond update intervals, displayed time
format, source offset calculation, fractional-digit coloring, and PiP display
are preserved.

## Regression tests

`test/widgets/clock_time_text_test.dart` checks centisecond/decisecond output
format and that a notifier tick refreshes the isolated clock widget.

Run in the project root:

```bash
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter build apk --release --split-per-abi
```


## Phase 4: persistence boundary and migration safety

- Extracted SharedPreferences access for time sources and display settings into
  `TimeSourceRepository`; `HomePage` no longer owns JSON persistence details.
- Preserved the existing storage keys (`time_sources_json`,
  `ntp_servers_json`, `hidden_presets_json`, `time_precision`, and
  `fraction_color`).
- Continue writing both the unified NTP/HTTP source list and the legacy NTP-only
  list so older app versions can still read NTP entries.
- Added defensive decoding: malformed rows are skipped, malformed unified
  payloads fall back to the legacy NTP key, and a valid empty unified list is
  respected as an intentional empty custom-source list.
- Added repository tests for unified NTP/HTTP settings, legacy fallback,
  malformed rows, unsupported color values, hidden preset filtering, and
  backward-compatible writes.
- Added the explicit Flutter foundation import for `ValueListenable` in
  `ClockTimeText`, fixing the analyzer error reported by the release workflow.

Validation commands (must run in the pinned Flutter 3.35.7 CI environment):

```bash
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter build apk --release --split-per-abi
```
