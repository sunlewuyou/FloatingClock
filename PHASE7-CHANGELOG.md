# 第七阶段变更记录

## 目标

增强 Android 悬浮时钟前台服务在进程被系统回收、随后由 `START_STICKY` 重建时的配置恢复能力。

## 变更

仅修改 `android/app/src/main/kotlin/io/github/amchii/floatingclock/FloatingClockService.kt`：

- 将最近一次有效的显示配置保存到独立的 `floating_clock_service` SharedPreferences。
- 服务收到正常启动/更新 Intent 时，只更新 Intent 明确携带的字段，并保存完整配置。
- 服务因系统回收而以 `intent == null` 重建时，恢复时间偏移、显示标签、时间精度和小数颜色。
- 保留 `START_STICKY`、现有 Intent extra 名称、Flutter MethodChannel、广播 Action、通知及悬浮窗位置存储。
- 对显式空标签与未提供标签作区分，避免部分更新 Intent 意外清空标签。

## 兼容性与边界

- 沿用 Android `SharedPreferences`，不新增依赖、权限、数据库或 Manifest 配置。
- 沿用既有默认值；首次安装且没有持久化配置时，行为仍为默认时间偏移、空标签、百分之一秒精度和既有默认小数颜色。
- 用户主动停止服务时不删除保存的配置；下次启动仍由 Flutter 传入当前选中配置覆盖。
- 本阶段不承诺跨设备重启后自动启动服务；Android 对前台服务的重启策略仍由系统决定。

## 验证状态

本交付执行了源码静态检查、Kotlin 语法解析检查（本地无 Android/Flutter 编译 classpath）、Manifest/工作流文件完整性检查和 ZIP 完整性检查。当前环境没有 Flutter SDK、Android SDK，未执行 `flutter analyze`、`flutter test` 或 APK Gradle 构建；这些必须由项目既定 GitHub Actions 工作流验证。
