# 第九阶段变更记录

## 目标

修复 Flutter 页面与 Android 悬浮服务之间的异步状态竞态，并完善页面销毁时的回调清理。此阶段不增加新功能，不改变服务协议或构建环境。

## 修改文件

- `lib/pages/home_page.dart`
- `OPTIMIZATION-NOTES.md`

## 具体变更

1. `HomePage.dispose()` 中解除 `floating_clock` MethodChannel handler，避免已销毁的 State 继续接收原生回调。
2. 增加 `_overlayOperationGeneration`，用于标识当前启动/停止请求。
3. 收到 `onOverlayStopped` 时递增 generation，并清除 `_overlayRunning` 与 `_overlayOperationInProgress`。
4. 启动/停止请求完成后，仅当 generation 未变化时才允许旧请求结果更新页面状态；防止服务异步启动失败、权限撤销或主动停止广播先于 MethodChannel Future 完成时出现状态回滚。

## 兼容性约束

- 保留 `floating_clock` MethodChannel 及全部既有方法名。
- 保留 Intent extras：`offset`、`label`、`precision`、`fractionColor`。
- 保留广播 Action：`io.github.amchii.floatingclock.OVERLAY_STOPPED`。
- 不修改 Android 原生 Kotlin、Manifest、依赖版本、pubspec 版本、Flutter/Gradle/JDK 配置或 GitHub Actions 工作流。
- 不修改时间源、时间偏移、NTP/HTTP 校时和画中画逻辑。

## 验证边界

本次进行源码差异审查、静态不变量检查、Manifest XML、工作流 YAML 和 ZIP 完整性检查。当前执行环境没有 Flutter/Dart/Android SDK，不能在本地执行 `flutter analyze`、`flutter test --reporter expanded` 或 Release APK 构建；必须由既有 GitHub Actions 工作流完成最终验证。
