# FloatingClock 第五阶段优化记录

## 本阶段目标

将网络时间同步从 `HomePage` 拆分为独立服务，降低页面层职责，便于单元测试和后续维护。没有改变时间源配置格式、SharedPreferences 键、MethodChannel 协议或 Android 悬浮服务行为。

## 修改内容

- 新增 `lib/services/time_sync_service.dart`，集中处理 NTP 与 HTTP 时间查询。
- `HomePage` 保留原有调用入口，内部委托给 `TimeSyncService`，尽量减少 UI 层改动。
- NTP 查询增加参数校验、DNS/Socket 超时、IPv4/IPv6 匹配绑定、应答模式/闰秒/stratum/Originate Timestamp 校验和 NTP Era 处理。
- NTP Socket、事件订阅和超时 Timer 在所有退出路径清理。
- HTTP 时间源校验 URL scheme、状态码和 JSON `data` 时间戳；限制响应体大小为 64 KiB，并确保 HttpClient 关闭。
- 新增 `test/services/time_sync_service_test.dart`，覆盖无效参数、NTP 超时、非法 URL、HTTP 数值/字符串时间戳、自定义请求头、非成功状态和异常 JSON。
- 保留上一阶段 `ValueListenable` 的显式导入修复。

## 兼容性

- 保留 NTP 默认端口 123、默认超时 2 秒、默认最多 5 次尝试。
- 保留 HTTP JSON `data` 字段为 Unix 毫秒时间戳的现有约定。
- 保留 `TimeSource` 模型和持久化结构。
- 不修改 Android Kotlin 服务及原生通信协议。
- 不修改应用版本号。

## 验证状态

本次执行环境没有 Flutter/Dart SDK，无法在此运行 `flutter analyze`、`flutter test` 或 APK 构建。交付前进行了源码结构、调用点、测试覆盖和压缩包静态检查；必须由仓库现有 GitHub Actions（Flutter 3.35.7）执行 Analyze、Test 和 Release APK 构建作为最终验证。不得将静态检查表述为实际编译通过。
