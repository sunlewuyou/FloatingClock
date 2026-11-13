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

## Phase 6: Android overlay lifecycle hardening

- Reordered foreground service startup so the service promotes itself before
  attaching the overlay window.
- Made repeated service starts reuse the existing overlay and update callback.
- Added clean stop paths for missing/revoked overlay permission and failed
  WindowManager attachment.
- Reduced high-frequency UI queue work by updating overlay TextViews directly
  on the main-thread Handler rather than calling `View.post()` every tick.
- Persisted overlay drag coordinates and clamps them to the current display
  bounds on restore and during movement.
- Added MethodChannel error results for native service start/stop failures and
  guarded callback delivery while Flutter is detaching.
- Added Android M compatibility guards around `Settings.canDrawOverlays`.

See `PHASE6-CHANGELOG.md` for preserved channel contracts and the CI/device
regression checklist.

## 第七阶段：前台服务配置恢复

第七阶段为 `FloatingClockService` 增加最近一次显示配置的持久化。正常 Intent 更新只覆盖明确提供的字段并保存；系统以空 Intent 重建 sticky service 时，从 `floating_clock_service` SharedPreferences 恢复 offset、label、precision 和 fractionColor。未引入新依赖或权限，不更改 Flutter 通道协议、Manifest、CI 工作流或业务时间计算。具体变更和验证边界见 `PHASE7-CHANGELOG.md`。

## 第八阶段：服务状态与显示尺寸变化稳定性

- 使用服务进程内的 `@Volatile` 运行状态标记提供 `isOverlayRunning` 查询，移除对已弃用 `ActivityManager.getRunningServices()` 的依赖。
- 服务启动成功后才标记运行；启动失败、权限撤销、窗口更新失败及服务销毁时清除运行状态。
- 保存当前 `WindowManager.LayoutParams`，在显示配置变化后等待悬浮窗完成布局，再将窗口位置限制在当前显示范围并持久化修正后坐标。
- Flutter 悬浮启动/停止按钮增加操作中状态，防止连续点击造成并发 start/stop 请求。
- 未更改 MethodChannel 名称/方法、服务 Intent extra、广播 Action、时间同步算法、依赖或 CI 工作流。

## 第九阶段：Flutter/原生悬浮服务异步状态收敛

- HomePage 销毁时解除 `floating_clock` MethodChannel handler，避免回调继续持有已销毁页面状态。
- 为悬浮窗启动/停止请求增加 generation 标识；原生服务停止广播到达时使旧请求结果失效，防止异步请求晚返回后把已停止的服务错误显示为运行中。
- `onOverlayStopped` 统一清理运行状态和操作中状态，覆盖服务启动后异步失败、权限撤销及用户主动停止等情况。
- 未改变 MethodChannel 名称、方法名、Intent extras、广播 Action、依赖、Manifest 或 GitHub Actions 构建环境。
