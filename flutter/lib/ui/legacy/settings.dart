/// 旧版界面 · 设置页：逐卡还原原版 renderSettings ——
/// 💾数据管理 / 📥导入比赛（JSON/Markdown）/ 🔄数据同步 / 🖼️外观 / 🎨偏好 / ℹ️关于。
/// 原版有而新版能力缺失的按钮（同步/日志/预览图）如实禁用并说明，不造假。
library;

import 'dart:io';
import '../sync_page.dart';
import '../management_page.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/exchange.dart';
import '../../data/repository.dart' show WcRepository;
import '../../state/providers.dart';
import '../widgets.dart' show appToast;
import 'widgets.dart';

class LegacySettingsPage extends ConsumerStatefulWidget {
  const LegacySettingsPage({super.key, required this.p});

  final LegacyPalette p;

  @override
  ConsumerState<LegacySettingsPage> createState() => _LegacySettingsPageState();
}

class _LegacySettingsPageState extends ConsumerState<LegacySettingsPage> {
  final _impText = TextEditingController();
  String _backupInfo = '';
  bool _busy = false;

  @override
  void dispose() {
    _impText.dispose();
    super.dispose();
  }

  LegacyPalette get p => widget.p;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final dark = ref.watch(legacyDarkProvider);
    final darkNotifier = ref.read(legacyDarkProvider.notifier);
    final uiMode = ref.watch(uiModeProvider);
    final uiModeNotifier = ref.read(uiModeProvider.notifier);
    final report = repo.loadReport;
    final pet = ref.watch(legacyPetProvider);

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ListTile(leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('AI 助手与管理接口'),
            subtitle: const Text('外部 Agent API · 内置 AI · 批量导入'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagementPage()))),

        Row(children: [
          Container(
              width: 5,
              height: 18,
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFFA855F7)]),
                  borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
          Text('设置',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 14, runSpacing: 14, children: [
          // ---------- 💾 数据管理 + 📥 导入 ----------
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: LCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cardTitle(context, Icons.save_outlined, '💾 数据管理'),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      LButton(
                          label: '立即备份',
                          kind: LBtnKind.primary,
                          onPressed: _busy
                              ? null
                              : () async {
                                  await repo.backupNow();
                                  setState(() =>
                                      _backupInfo = '最近备份：${repo.backupDir}');
                                  appToast('已备份');
                                }),
                      LButton(
                          label: '📦 一键导出全部数据（比赛+获奖+证书）',
                          kind: LBtnKind.primary,
                          onPressed:
                              _busy ? null : () => _export(exportV2Backup)),
                      LButton(
                          label: '📂 打开导出文件夹',
                          onPressed: () => _openFolder(repo.exportsDir)),
                      LButton(
                          label: '📂 打开数据文件夹',
                          onPressed: () => _openFolder(repo.dataDir)),
                      // 原版有日志目录；新版无日志文件，如实禁用（还原清单登记）
                      LButton(label: '🧾 打开日志文件夹', onPressed: null),
                      LButton(
                          label: '📱 生成手机同步预览图',
                          onPressed: null), // 无同步能力，如实禁用
                    ]),
                    const SizedBox(height: 8),
                    Text('导出为 zip 备份包，保存在数据目录 exports\\ 下',
                        style: TextStyle(fontSize: 11.5, color: p.muted)),
                    if (_backupInfo.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SelectableText(_backupInfo,
                            style:
                                TextStyle(fontSize: 11.5, color: p.muted)),
                      ),
                    if (report.mainRecovered || report.awardsRecovered)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('⚠ 本次启动曾自动从备份恢复，详见交付报告',
                            style:
                                TextStyle(fontSize: 11.5, color: p.muted)),
                      ),
                    const SizedBox(height: 14),
                    Divider(height: 1, color: p.hairline),
                    const SizedBox(height: 12),
                    Text('📥 导入比赛（JSON / Markdown）',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: p.text)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _impText,
                      maxLines: 4,
                      style: TextStyle(fontSize: 11.5, color: p.text),
                      decoration: lInputDeco(
                          p,
                          '{"competitions": [{"name": "2026 XX大赛", "deadline": "2026-09-15", "category": "视觉传达"}]}'),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      LButton(
                          label: '📥 导入',
                          kind: LBtnKind.primary,
                          dense: true,
                          onPressed:
                              _busy ? null : () => _importText(repo)),
                      LButton(
                          label: '📂 选择文件',
                          dense: true,
                          onPressed: _busy ? null : _importFile),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                        'Agent 或自己粘贴比赛清单，点「导入」自动去重；'
                        '支持桌面备份 ZIP、安卓备份 JSON、Markdown 表格',
                        style: TextStyle(fontSize: 11, color: p.muted)),
                  ]),
            ),
          ),
          ListTile(leading: const Icon(Icons.sync), title: const Text('设备配对与数据同步'),
            subtitle: const Text('手动批准设备 · 合并推送/拉取 · 原件校验'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncPage()))),
          // ---------- 🖼️ 外观 ----------
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: LCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cardTitle(context, Icons.wallpaper, '🖼️ 外观'),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, children: [
                      LButton(
                          label: '🖼️ 设置首页壁纸',
                          onPressed: _busy ? null : _pickWallpaper),
                      LButton(
                          label: '恢复默认背景',
                          onPressed: _busy ? null : _clearWallpaper),
                    ]),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () => ref
                          .read(legacyPetProvider.notifier)
                          .set(!pet),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            pet
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 17,
                            color: pet ? p.primary : p.muted,
                          ),
                          const SizedBox(width: 6),
                          Text('🐱 桌面宠物（右下角小猫，点它会说话）',
                              style:
                                  TextStyle(fontSize: 13, color: p.text)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('壁纸会自动淡化处理，保证内容可读。',
                        style: TextStyle(fontSize: 11, color: p.muted)),
                  ]),
            ),
          ),
          // ---------- 🎨 偏好 ----------
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: LCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cardTitle(context, Icons.palette_outlined, '🎨 偏好'),
                    const SizedBox(height: 10),
                    Row(children: [
                      Text('深色模式',
                          style: TextStyle(fontSize: 13, color: p.text)),
                      const Spacer(),
                      LButton(
                          label: dark ? '🌙 切到浅色' : '☀️ 切到深色',
                          onPressed: () => darkNotifier.set(!dark)),
                    ]),
                    const SizedBox(height: 10),
                    Divider(height: 1, color: p.hairline),
                    const SizedBox(height: 10),
                    Text('当前界面：旧版界面（0.4.2 wenku8 风格）',
                        style: TextStyle(fontSize: 12, color: p.muted)),
                    const SizedBox(height: 8),
                    LButton(
                        label: '切回新版界面（炭黑荧光黄）',
                        onPressed: uiMode == 'legacy'
                            ? () => uiModeNotifier.set('design')
                            : null),
                  ]),
            ),
          ),
          // ---------- ℹ️ 关于（整行） ----------
          LCard(
            padding: const EdgeInsets.all(20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _cardTitle(context, Icons.info_outline, 'ℹ️ 关于'),
                  const SizedBox(height: 8),
                  Text(
                      '版本 1.0.0-alpha.5+31（Flutter 重构版 · 旧版界面为 0.4.2 wenku8 风格，功能补齐测试版）',
                      style: TextStyle(fontSize: 12, color: p.muted)),
                  const SizedBox(height: 4),
                  Text('本地单机工具，数据不出本机 · 源码可用',
                      style: TextStyle(fontSize: 12, color: p.muted)),
                  const SizedBox(height: 4),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('数据目录：',
                        style: TextStyle(fontSize: 12, color: p.muted)),
                    Expanded(
                      child: SelectableText(repo.dataDir,
                          style: lMono(11,
                              color: p.text, weight: FontWeight.w400)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                      '数据文件：data/competitions.json、awards.json（记事本可直接查看/备份）',
                      style: TextStyle(fontSize: 12, color: p.muted)),
                  const SizedBox(height: 4),
                  Text('Agent 端口：在「AI 助手与管理接口」开启并查看',
                      style: TextStyle(fontSize: 12, color: p.muted)),
                  const SizedBox(height: 4),
                  Text(
                      '自动备份：每次写数据后备份，保留最近 20 份（backups/）· 损坏自动回滚',
                      style: TextStyle(fontSize: 12, color: p.muted)),
                ]),
          ),
        ]),
      ]),
    );
  }

  Widget _cardTitle(BuildContext context, IconData icon, String title) {
    return Row(children: [
      Icon(icon, size: 16, color: p.text),
      const SizedBox(width: 6),
      Text(title,
          style: TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
    ]);
  }

  // -------------------------------------------------------------------

  Future<void> _export(Future<ExportResult> Function(WcRepository) fn) async {
    final repo = ref.read(repositoryProvider);
    setState(() => _busy = true);
    try {
      final result = await fn(repo);
      setState(
          () => _backupInfo = '最近导出：${result.path}（${result.detail}）');
      appToast('已导出：${result.path}');
    } on Exception catch (e) {
      appToast('导出失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openFolder(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    if (Platform.isWindows) {
      Process.run('explorer.exe', [path]);
    }
  }

  Future<void> _importText(WcRepository repo) async {
    final text = _impText.text.trim();
    if (text.isEmpty) {
      appToast('先粘贴 JSON 或 Markdown 内容', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final bundle = parseSourceBytes(text.codeUnits, '粘贴文本');
      final report = await ref
          .read(libraryProvider.notifier)
          .applyBundle(bundle, updateExisting: true);
      appToast('导入完成：${report.summary()}');
    } on Exception catch (e) {
      appToast('导入失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFile() async {
    const group = XTypeGroup(
        label: '备份与数据',
        extensions: ['zip', 'json', 'md', 'markdown', 'txt']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      final bundle = parseSourceBytes(bytes, file.name);
      final report = await ref
          .read(libraryProvider.notifier)
          .applyBundle(bundle, updateExisting: true);
      appToast('导入完成：${report.summary()}');
    } on Exception catch (e) {
      appToast('导入失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickWallpaper() async {
    const group = XTypeGroup(
        label: '图片', extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    final repo = ref.read(repositoryProvider);
    final dst = File('${repo.dataDir}${Platform.pathSeparator}wallpaper.img');
    await dst.writeAsBytes(await file.readAsBytes(), flush: true);
    await writeAppSetting(repo, 'wallpaper', '1');
    ref.read(legacyWallpaperProvider.notifier).bump();
    appToast('壁纸已设置（自动淡化处理）');
  }

  Future<void> _clearWallpaper() async {
    final repo = ref.read(repositoryProvider);
    final f = File('${repo.dataDir}${Platform.pathSeparator}wallpaper.img');
    if (f.existsSync()) f.deleteSync();
    await writeAppSetting(repo, 'wallpaper', '0');
    ref.read(legacyWallpaperProvider.notifier).bump();
    appToast('已恢复默认背景');
  }
}
