工作日历首个公开版本，作者 Varsha32。支持 Windows x64 与 Android。

## 下载与使用

- Windows：下载 WorkCalendar-Windows-x64-v0.4.2.zip，解压后运行 WorkCalendar.exe，需要 WebView2 Runtime。
- Android：下载 WorkCalendar-Android-v0.4.2.apk。旧 debug 签名版本无法覆盖安装，请先导出并验证备份，再卸载旧版安装。
- 开发者：查看仓库源码或下载 Source ZIP。SHA256SUMS.txt 提供安装包校验值。

## 本版修复

强制 API 鉴权、电脑批准手机配对、手机同步权限限制、AI 轮询和附件路径修复、损坏数据备份恢复、Python/Android 网页抓取安全加固，以及 SheetJS 和构建依赖更新。

本地验收：110 项 Python、4 项 JavaScript、3 项 Android 单元测试通过，Windows EXE 和浏览器模拟 AI 对话验证通过，APK 签名验证通过。详细范围见 ACCEPTANCE.md。

## 已知限制

Android 实机扫码与同步尚待验收；真实 AI 服务商未在本轮端到端测试。局域网同步使用 HTTP，只用于可信网络。Windows 程序未作 Authenticode 签名。AI 可修改数据，重要操作前请备份。

许可为 Apache-2.0 + Commons Clause 1.0（源码可用，并非 OSI 定义的开源许可）。第三方组件保留各自许可。
