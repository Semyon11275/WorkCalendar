# 工作日历 0.5.0 交付说明

作者与许可证署名：Varsha32。交付日期：2026-10-17。

本轮在 0.4.2 基础上完成界面、复制、同步与一批缺陷修复；构建与验收在本机完成，尚未上传 GitHub。

## 交付文件

| 文件 | 用途 |
| --- | --- |
| WorkCalendar-Windows-x64-v0.5.0.zip | Windows 10/11 x64 可运行程序，解压后启动 WorkCalendar.exe；需 WebView2 Runtime |
| WorkCalendar-Android-v0.5.0.apk | 正式发布密钥签名的 Android 包，版本号 0.5.0、versionCode 25（含四种 ABI） |
| WorkCalendar-Source-v0.5.0.zip | 清理后的完整源码、构建配置、测试、GitHub CI、许可和第三方声明（不含 release-assets） |
| SHA256SUMS.txt / RELEASE_MANIFEST.json | 三个公开交付包的 SHA256 与大小 |
| PRIVATE_DO_NOT_UPLOAD/ | 私有 Android 发布密钥与密码，仅交给作者保存，绝不能上传 GitHub |

## 本轮修复与新增（相对 0.4.2）

- 界面：仿 wenku8 主题（Material 3 色调分层 + 思源宋体，OFL 许可随包）、视图切换/点击/文字刷出动效、获奖按比赛分组折叠、过期 5 天未完成默认隐藏。
- 复制：pywebview 宿主禁用了右键菜单与文字选中，前端补齐自定义右键菜单与 Ctrl+C/A 兜底，图片可复制位图/拖出。
- 手机同步凭证：旧版只同步 JSON；新增 /api/sync_certificate（仅配对手机、只读获奖引用附件、16MB 上限）；压缩预览图（~200KB）独立落盘，原件不覆盖；内容按魔数嗅探 MIME。
- 桌面：AI 成功后误报「未知错误」修复；启动首屏提速（2.4MB 脚本移出 head）；附件外部浏览器打开经一次性票据授权。
- 审计问题修复：中文/空格附件票据（unquote + 普通 equality）、大文件上传分块编码（3MB 实测）、预览生成全局并发上限 2、分组 Map 防原型链冲突、npm audit 0 漏洞、OkHttp 去重、版本统一 0.5.0。

## 验收证据与范围

| 检查 | 结果 |
| --- | --- |
| Python 回归与安全测试 | 115 项通过（新增凭证同步 4 项 + 一次性票据含中文/空格 1 项） |
| JavaScript 测试 | 数据恢复/表格 4 项 + 凭证同步契约 1 项通过 |
| 大文件编码 | 3MB 分块 base64 实测通过（原实现 RangeError） |
| 预览并发 | 双批次同时入队实测最大并发 2（全局队列） |
| npm audit | 0 个已知漏洞 |
| Windows 实际 EXE | 启动、/api/health=0.5.0、新接口 401 鉴权、静态资源、中文票据打开通过 |
| Android 构建及签名 | release 构建通过，同一正式密钥（SHA256 39e37f9a…1dcf0b37），versionCode 25 |

本次仍未连接 Android 实机：安装、扫码配对、双端完整同步、凭证预览查看需实机验收。AI 端到端使用模拟服务。局域网同步仍为 HTTP，限于可信网络；AI Key 本地明文保存；Windows EXE 未做 Authenticode 签名。上述检查不等于保证不存在其他漏洞。

## 升级与发布

1. Windows：关闭旧程序后备份整个目录（含 data/），新包解压覆盖；旧版可整体换回（本机安装目录另留有 `导入前备份/` 与 `_internal.old`）。
2. Android：与 0.4.x 同一正式签名，可直接覆盖安装（versionCode 25）。
3. GitHub：推送后 CI 将以 release-assets 内 0.5.0 包发布（check.yml 已指向 v0.5.0）；源码 ZIP 为 git archive 排除 release-assets 的产物。
4. 私钥与密码仍保存在 PRIVATE_DO_NOT_UPLOAD，不入库。

源码包含 README 构建步骤与 BUILD_ENVIRONMENT.txt 环境记录；Android 发布签名经 gradle 属性注入，不进入构建源码。
