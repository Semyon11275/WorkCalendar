工作日历 v0.5.0，支持 Windows x64 与 Android。

下载与使用
Windows：下载 WorkCalendar-Windows-x64-v0.5.0.zip，解压后运行 WorkCalendar.exe，需要 WebView2 Runtime。可覆盖旧版目录（建议先备份）。
Android：下载 WorkCalendar-Android-v0.5.0.apk（versionCode 26），与 v0.4.x 同一正式签名，可直接覆盖安装。
开发者：查看仓库源码或下载 Source ZIP。SHA256SUMS.txt 提供安装包校验值。
本版更新（相对 0.4.2）
界面：Material 3 + 思源宋体、视图切换动效、获奖分组折叠、过期项默认隐藏。
复制：右键/快捷键复制图片与文字。
手机同步凭证：新增配对手机专用附件接口（仅可读获奖引用文件、单件 16MB 上限），预览图（~200KB）独立落盘，原件不覆盖。
修复：AI 助手成功后误报错误、启动加载提速、表单页底部操作栏、特殊比赛名分组崩溃、中文/空格附件票据、大文件上传分块编码。
安全：npm 依赖审计 0 高危；凭证路由鉴权保持本机/票据双通道。
本地验收：115 项 Python、5 项 JavaScript 测试通过，Windows EXE 实机验证（新接口鉴权、中文票据、静态资源），APK 签名校验通过。详细范围见 ACCEPTANCE.md 与仓库 CHANGELOG。

已知限制
局域网同步使用 HTTP，只用于可信网络。Windows 程序未作 Authenticode 签名。AI 可修改数据，重要操作前请备份。安装包含思源宋体字体（OFL 许可），Windows 包体积因此增大约 23MB。

许可 Apache-2.0 + Commons Clause 1.0（源码可用，并非 OSI 定义的开源许可）。第三方组件保留各自许可。

### Android 修订版（versionCode 26）
补齐手机标签页斜向切换、点击弹性反馈、详情文字展开动效；获奖分组标题改为整行按钮，最小高度 60px，支持长标题换行。沿用原签名，可直接覆盖安装，无需卸载。Windows 安装包不变。
