# FloatingClock 0.5.3 升级说明

## 本次范围

本版本完成基础重构与稳定性升级的第一、第二阶段。保留原有 applicationId、SharedPreferences 键名、时间源 JSON 结构、MethodChannel 方法名、时间精度选项和现有界面。

## 主要变化

1. `lib/services/ntp_service.dart`：独立 NTP 客户端，支持 IPv4/IPv6 地址族匹配、DNS 多地址尝试、NTP 服务器响应校验、单调时钟测量及 NTP era 展开。
2. `lib/services/http_time_service.dart`：独立 HTTP 时间客户端，限制协议和响应体大小，确保 HttpClient 在所有退出路径关闭。
3. `lib/pages/home_page.dart`：页面只负责调用服务和更新界面；自动同步采用互斥锁和稳定快照，防止定时同步重叠。
4. `FloatingClockService.kt`：先进入前台服务状态再创建悬浮窗；保存并恢复时间显示参数及拖动位置；增加可诊断日志。
5. `MainActivity.kt`：捕获 Android 启动前台服务时的异常，并通过 MethodChannel 返回明确错误码。
6. CI：执行 `flutter analyze` 和 `flutter test` 后才继续 Release 构建。

## 兼容性

- Android applicationId 保持 `io.github.amchii.floatingclock`。
- 旧版 SharedPreferences 配置无需迁移。
- 原有 Flutter/Android MethodChannel 名称和方法名不变。
- 首次升级后，悬浮窗坐标使用旧版默认位置作为初始值；之后会保存用户最后一次拖动位置。
- 如果用户撤销悬浮窗权限，系统重建服务时会记录原因并停止服务，需要重新授权后手动启动。

## 验证状态

本次源码工作环境未安装 Flutter/Dart SDK，也未连接 Android SDK/设备，因此没有在此环境执行 `flutter analyze`、`flutter test`、Gradle APK 构建或真机悬浮窗验证。新增测试已纳入 GitHub Actions Release 工作流，必须以 CI 实际结果及 Android 真机回归结果作为正式验收依据。

建议验收：

- Android 8、Android 12/13、Android 14/15/16 代表设备启动、更新、关闭悬浮窗。
- IPv4-only、IPv6-only、双栈网络分别测试 NTP。
- 在拖动后强制结束进程/触发服务重建，确认坐标和显示配置恢复。
- 连续运行 10ms 与 100ms 精度至少 30 分钟，检查 CPU、温度、掉帧和服务稳定性。
- 手动同步与每分钟自动同步同时触发，确认不会重叠执行。
