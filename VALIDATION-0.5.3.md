# 0.5.3 源码包验证记录

验证日期：2026-11-09

## 已完成的静态检查

- [x] `AndroidManifest.xml` XML 解析通过。
- [x] `pubspec.yaml` YAML 解析通过。
- [x] `.github/workflows/release.yml` YAML 解析通过。
- [x] `pubspec.yaml` 版本号为 `0.5.3`。
- [x] Release 工作流包含 Flutter 3.35.7、`flutter analyze` 和 `flutter test` 质量门禁。
- [x] 首页不再直接创建 NTP UDP Socket 或 HTTP Client，网络实现已移至 `lib/services/`。
- [x] Android 服务先进入前台状态，再创建悬浮窗。
- [x] Android 服务保存并恢复显示配置和悬浮窗坐标。
- [x] Kotlin 编译器未报告语法解析错误。

## 当前环境限制

当前工作环境没有 Flutter/Dart SDK、Android SDK 和可用 Android 设备。Kotlin 单文件检查因缺少 Android/AndroidX 类库而无法完成类型编译。因此以下项目未在本环境执行，不能标记为通过：

- `flutter pub get`
- `flutter analyze`
- `flutter test --reporter expanded`
- `flutter build apk --release`
- Android 真机悬浮窗生命周期、权限、位置恢复和高频刷新测试

Release GitHub Actions 已加入 `flutter analyze` 和 `flutter test` 步骤。正式发布前仍需 CI 构建成功，并按 `UPGRADE-NOTES.md` 完成真机回归。
