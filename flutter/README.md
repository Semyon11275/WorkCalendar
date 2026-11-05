# WorkCalendar Flutter alpha.6

开发版，源码与旧版 Python/Web 分开维护。Windows 支持独立 GitHub 更新通道；Android 目前仅提供 preview 构建配置，不提供本轮自动安装。

```sh
flutter pub get
flutter analyze
flutter test
flutter build windows --release
python tool/package_update.py build/windows/x64/runner/Release WorkCalendar-Flutter-Windows-x64-v1.0.0-alpha.6.zip 1.0.0-alpha.6
```

在纯 ASCII 路径构建。用户数据使用 EXE 同级 userdata/.portable 便携标记；data 是 Flutter 运行时资源。更新标签必须为 flutter-v1.0.0-alpha.N，不能使用旧版 v0.5.x。Windows 更新入口：数据 → 软件更新。

正式发布前仍需 Android/macOS/iOS 各平台实际验收；本轮发布仅含 Windows 开发预览。完整许可证见 LICENSE。
