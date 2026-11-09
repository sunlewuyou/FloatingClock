<div align="center">
    <h1>悬浮时间</h1>

  <img src="./assets/home.jpg" alt="App 界面预览" width="45%" />
  <img src="./assets/PiP.jpg" alt="App 界面预览" width="45%" />
<br/>
</div>
<br/>

一个使用 Flutter 编写的轻量级应用，在 Android 上可将一个可拖动的时钟以悬浮窗形式显示在屏幕任意位置，支持多源时间同步与偏差显示。

**主要特性**

- 可在 0.1 秒与 0.01 秒显示精度间切换，并提供多种暗色高亮（默认暗红）用于渲染快速变化的小数位，兼容悬浮窗与画中画显示（例如 `12:34:56.7` / `12:34:56.78`）。
- 可在 Android 上以悬浮窗（Overlay）形式显示，可拖动、固定与关闭。
- 支持多时间源（System、NTP、HTTP 等），并展示与系统时间的偏差（ms）。
- 定期自动同步 NTP/HTTP 时间并保存最近同步记录。
- 支持本地持久化用户添加的时间源（`shared_preferences`）。
- 支持画中画模式（PiP）。

**代码结构**

- `lib/main.dart`：应用入口，仅负责启动 `MyApp` 并引用具体页面。
- `lib/pages/`：`HomePage`、`AboutPage` 等页面及交互；首页通过服务层调用网络时间同步。
- `lib/services/`：独立的 NTP/HTTP 时间查询服务。
- `lib/models/`：定义 `TimePrecision`/`TimeSource` 数据模型及序列化。
- `android/.../FloatingClockService.kt`：原生悬浮窗、前台服务、显示配置和位置恢复。
- `test/`：页面、时间源序列化、NTP 时间戳和 HTTP 同步服务测试。

**运行与测试**

- `flutter pub get`
- `flutter run`
- `flutter test test/widget_test.dart`

## 当前维护版本

当前源码版本：**0.5.3**。本次维护重点是时间同步可靠性与 Android 悬浮窗服务生命周期，不改变应用包名和原有用户配置格式。

- NTP/HTTP 网络逻辑位于 `lib/services/`。
- 网络服务与时间源持久化测试位于 `test/`。
- Android 悬浮窗配置（时间偏移、标签、精度、颜色、位置）由原生服务保存并在系统重建时恢复。
- 变更详情见 `CHANGELOG.md` 和 `UPGRADE-NOTES.md`。

本地验证命令：

```bash
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter build apk --release
```
