# 工作日历 WorkCalendar 0.4.2

面向设计类比赛的本地日程与获奖管理工具。作者：Varsha32。

支持 Windows 桌面与 Android：比赛增删改查、临期线和时间线、获奖凭证、JSON/表格导入、导出备份，以及可选的 AI 助手。基础数据管理可离线使用；AI、网页检索和模型服务需要网络，服务商可能收费。

## 下载

从 [GitHub Releases](https://github.com/Semyon11275/WorkCalendar/releases/latest) 下载 Windows 压缩包或 Android APK；源码压缩包供开发者使用。下载后可按 SHA256SUMS.txt 校验。

## 使用

- Windows：解压公开 Windows 包，运行 `WorkCalendar.exe`。需要 Windows 10/11 x64 和 Microsoft Edge WebView2 Runtime。程序首次运行在自身目录创建 `data/` 和 `webview_data/`，因此请放在可写目录。
- Android：安装正式签名 APK。程序数据存于应用私有目录，卸载会删除。0.4.1 若为 debug 签名，与正式签名不兼容；先从旧版导出并验证备份，再卸载旧版安装，不能直接覆盖安装。
- 升级 Windows：关闭旧程序，保存旧目录的完整副本，将 `data/` 和 `webview_data/` 复制到新版程序目录；不要将这些目录上传 GitHub。
- 配对：两端连接同一可信局域网，在电脑设置中显示配对码，手机扫码，电脑核对请求 IP 和配对码后允许。手机只获得比赛/获奖数据同步权限，不能配置或调用电脑的 AI。电脑重启后需要重新配对。
- 同步传输使用 HTTP，仅用于可信局域网；不要开放到公网。同步内容不包括证书文件、AI Key 和聊天历史。导入覆盖操作前先备份。
- API Token 自动生成，缺失/错误凭据不可访问数据。证书通过已授权电脑会话读取。Token 保存失败会停止启动。

## AI 与隐私

AI 是可选功能，需自行填写服务商 API Key。Key 在本地明文保存，请保护设备和备份。对话、选择的图片/表格、AI 工具查询返回的数据会发送给所选服务商；网页检索会访问外部网站。不要发送不希望提供给服务商的信息。

AI 可以修改日历数据。外部网页内容和模型判断可能不准确；关键日期、资格、费用须人工核实。AI 提示词要求删除前确认，但这不是程序强制执行的授权机制；操作前请导出备份。不得把完整数据目录或日志作为公开问题附件。

网页抓取仅允许公网 HTTP/HTTPS 的 80/443 端口，校验解析结果、固定连接地址并逐跳检查重定向，限制响应为 1MB。手机使用 SafeWeb 原生模块；安全模块缺失时不会降级成不受保护的抓取。

## 开发与验证

唯一维护前端位于 `web/`，Android 的 `www/` 和 native assets 由脚本同步生成。

```sh
python -m venv .venv
# 激活 .venv 后
pip install pywebview==6.2.1 pyinstaller==6.21.0
python -m unittest discover -s tests -t .
node tests/test_mobile.cjs
python -m app.main
```

Windows 打包（在项目根运行）：

```sh
python -m PyInstaller --noconfirm build.spec
```

环境变量 `PYTHONPATH` 应为空；输出为 `dist/WorkCalendar/`。不要直接打包正在使用的程序目录。

Android 构建需要 JDK 21、Android SDK 34、Node.js 22+：

```sh
python scripts/sync_web.py
cd android-app
npm ci
npm run sync
cd android
# 在 local.properties 中配置自己的 sdk.dir
gradlew.bat assembleRelease
```

输出默认未签名。使用自己的长期发布密钥，经 `zipalign` 和 `apksigner` 签名后才能作为正式安装包发布。密钥、密码和 `local.properties` 不入库。

保留 Capacitor 6.2.2；通过 `overrides` 将构建依赖 tar 固定为 7.5.22。`postinstall` 执行有版本和内容校验的兼容补丁，调整旧 CLI 的默认导入；修改 CLI 版本前必须重新检查该补丁。`npm audit` 通过不等于 APK 无所有漏洞。

SheetJS 浏览器库固定为 0.20.3，校验和及取得方式见 `vendor/SheetJS-PROVENANCE.json`。它已随源码存放，无需运行时下载。不要重新安装 npm 的旧 `xlsx@0.18.5`。

## GitHub 发布

只上传本源码目录。不要上传使用中的 `data/`、`webview_data/`、签名密钥、旧安装包、测试数据、日志或原项目 `.git` 历史。公开安装包单独上传 GitHub Releases，并附 SHA256。

先通过 CI、检查公开文件清单和签名，再发布。当前交付的测试范围和限制以随包验收报告为准，不把尚未进行的实机测试写成已通过。

## 许可

Copyright (c) 2026 Varsha32。

本项目自有代码以 **Apache License 2.0 + Commons Clause License Condition 1.0** 提供，见 `LICENSE`。这是 **source-available（源码可用）**，不是 OSI 定义的开源许可。销售限制以 Commons Clause 对 “Sell” 的定义为准，并非禁止所有商业使用。

第三方组件按各自原许可证提供，不因本项目的 Commons Clause 而重新授权。见 `THIRD_PARTY_NOTICES.md` 与 `LICENSES/`。

