# 工作日历 0.4.2 交付说明

作者与许可证署名：Varsha32。交付日期：2026-09-09。

本次基于原项目的独立副本完成审查、修复和构建；未覆盖原程序、个人数据或原 Git 历史。尚未上传 GitHub。

## 交付文件

| 文件 | 用途 |
| --- | --- |
| WorkCalendar-Windows-x64-v0.4.2.zip | Windows 10/11 x64 可运行程序，解压后启动 WorkCalendar.exe；需 WebView2 Runtime |
| WorkCalendar-Android-v0.4.2.apk | 正式发布密钥签名的 Android 包，版本号 0.4.2、versionCode 18 |
| WorkCalendar-Source-v0.4.2.zip | 清理后的完整源码、构建配置、测试、GitHub CI、许可和第三方声明 |
| SHA256SUMS.txt / RELEASE_MANIFEST.json | 三个公开交付包的 SHA256 与大小 |
| PRIVATE_DO_NOT_UPLOAD/ | 私有 Android 发布密钥与密码，仅交给作者保存，绝不能上传 GitHub |

## 复查与修复

- 默认强制鉴权，Token 持久化失败即停止启动；手机同步凭据不再获得电脑 AI 配置等管理权限。
- 桌面 bootstrap 加入本机、Host、Origin 和自定义请求头校验，取消通配 CORS；证书读取受授权会话保护，并限制活动内容执行。
- 手机配对必须经过电脑批准，增加等待、拒绝、过期和频率限制；电脑重启后需重新配对。
- 修复 AI 状态响应和前端成功结果被覆盖的问题，轮询超时不再重复提交整段对话。
- 修复附件脚本部署路径，并限制单个附件大小。
- 手机损坏数据先保留原件，再尝试有效备份；没有有效备份时停止初始化并提示，不再悄悄覆盖为空。写入使用临时文件与串行保存。
- Python 网页抓取固定已验证的公网连接地址，逐跳检查重定向，限制端口、时长与响应大小；Android 增加 SafeWeb 原生模块，禁用不安全降级。
- SheetJS 更新至 0.20.3，记录来源及与官方公布校验值一致的证据；构建依赖 tar 更新并加入 Capacitor CLI 兼容补丁。
- 补充 README、SECURITY、CHANGELOG、Apache 2.0 + Commons Clause、第三方许可和 CI；前端改为单一维护来源，脚本同步到 Android。

## 验收证据与范围

| 检查 | 结果 |
| --- | --- |
| Python 回归与安全测试 | 110 项通过，包含鉴权、配对、证书访问、SSRF 与 Token 保存失败 |
| JavaScript 数据恢复与表格测试 | 4 项通过 |
| Android release 单元测试 | 3 项通过，其中 SafeWeb 地址策略测试 2 项 |
| npm audit | 本次锁定依赖报告 0 个已知漏洞 |
| 浏览器端到端 | 日历新增/显示及模拟 OpenAI 服务对话通过，无页面脚本或资源加载错误 |
| Windows 实际 EXE | 启动、版本、空数据、无凭据拒绝及 CLI 向运行程序转交导入通过 |
| Android 构建及签名 | release 构建通过，APK v1/v2/v3 签名验证通过 |
| APK 前端资源 | 与交付源码的页面、核心脚本、AI 脚本、SheetJS 逐字节比对一致；初始比赛与获奖数据为空 |
| 公开包检查 | ZIP 完整性与 SHA256 检查通过；排除个人数据目录、Token 文件、签名私钥和原 Git 历史 |

本次没有连接 Android 实机，因此安装、摄像头权限、真实扫码及两台设备完整同步仍需实机验收。AI 端到端测试使用模拟服务，没有验证真实服务商的响应质量、联网搜索耗时或账号配置。Windows 检查包含实际 EXE 进程与 API，页面交互在 Chromium 中验证，未自动验收全部原生 WebView 操作。

上述检查不等于保证不存在其他漏洞。Windows EXE 未做 Authenticode 代码签名，可能出现系统信誉提示。局域网同步仍使用 HTTP，应限于可信网络；AI Key 本地明文保存。AI 删除确认是提示词约束，并非后端强制授权机制，重要操作前请备份。

## 升级与发布

1. 先保存旧版完整副本，并在程序中导出数据备份。Windows 关闭旧程序后，把旧版 data/ 与 webview_data/ 复制到新版可写目录。
2. Android 正式密钥与旧 debug 签名不兼容时，不能覆盖安装：先导出并验证备份，再卸载旧版、安装新版并恢复。卸载会删除应用私有数据。
3. 妥善离线备份 PRIVATE_DO_NOT_UPLOAD 内的密钥及密码，未来 APK 更新必须继续使用同一密钥。本次证书 SHA256：39e37f9a201a53dd06b645116d3a2004061306407bed32cd9d62b52a1dcf0b37。
4. GitHub 仓库上传源码 ZIP 解压后的内容；Release 附件上传公开 Windows ZIP、APK、源码 ZIP 和 SHA256SUMS.txt。不要整目录上传交付区。
5. 项目自有代码采用 Apache License 2.0 + Commons Clause 1.0，属于源码可用许可，并非 OSI 定义的开源许可；第三方组件保留各自许可。

源码包含 README 中的本地测试和构建步骤，以及 BUILD_ENVIRONMENT.txt 中的本次 Python 环境记录。Android 发布签名不进入构建源码，后续构建需由作者使用私钥签名。
