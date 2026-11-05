/// 数据页：旧版迁移导入（目录/备份文件/粘贴文本）、四类导出、立即备份。
///
/// 导出始终从仓库完整取数，不受界面筛选或过期隐藏影响。
library;
import 'update_page.dart';

import 'dart:io';
import 'sync_page.dart';
import 'management_page.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/exchange.dart';
import '../data/repository.dart';
import '../state/providers.dart';
import 'widgets.dart';

class ExchangePage extends ConsumerStatefulWidget {
  const ExchangePage({super.key});

  @override
  ConsumerState<ExchangePage> createState() => _ExchangePageState();
}

class _ExchangePageState extends ConsumerState<ExchangePage> {
  bool _busy = false;
  String? _legacyDir; // Android 旧版 wc_data 检测结果

  @override
  void initState() {
    super.initState();
    legacyAndroidDataDir().then((d) {
      if (mounted && d != null) setState(() => _legacyDir = d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final lib = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('数据')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          ListTile(leading: const Icon(Icons.system_update), title: const Text('软件更新'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UpdatePage()))),
          ListTile(leading: const Icon(Icons.sync), title: const Text('设备配对与数据同步'),
            subtitle: const Text('配对批准后合并传输记录与凭证'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncPage()))),

          ListTile(leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('AI 助手与管理接口'),
            subtitle: const Text('外部 Agent API · 内置 AI · 批量导入'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagementPage()))),

          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_legacyDir != null) ...[
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '检测到旧版 0.5.0 数据',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text('可直接读取旧版 wc_data 目录完成原地迁移；旧文件不会被删除。'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _importDirectory(_legacyDir!),
                      child: const Text('一键迁移旧版数据'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _section(context, '导入（迁移旧版 / 恢复备份）', [
            const Text('核验要求：赛事归属、奖项名称和作者以证书正文及官方公告为依据，不得根据文件名归类；只知年份或月份时不得补造月日，日期留空并在备注记录原文和精度；来源链接、赛项与阶段需注明；日期离群需复核而非自动改写；报名开始不得晚于同一阶段结束；评审、公示、颁奖可晚于投稿截止；作者角色与一作标记须一致；无凭证须注明原因。禁止直接改写数据库 JSON，请使用导入接口并检查返回报告。'),
            _Tile(
              icon: Icons.folder_open,
              title: '从旧版数据目录导入',
              subtitle:
                  '选择包含 competitions.json / awards.json / certificates/ 的目录',
              onTap: _busy ? null : _pickDirectory,
            ),
            _Tile(
              icon: Icons.archive_outlined,
              title: '从备份文件导入',
              subtitle: '支持：桌面备份 ZIP、安卓备份 JSON、新版备份 ZIP、两类 JSON、Markdown 表格',
              onTap: _busy ? null : _pickFile,
            ),
            _Tile(
              icon: Icons.paste,
              title: '粘贴文本导入',
              subtitle: '粘贴 JSON 或 Markdown 表格，自动识别格式',
              onTap: _busy ? null : _pasteImport,
            ),
          ]),
          const SizedBox(height: 16),
          _section(context, '导出（从完整数据生成，不受筛选影响）', [
            _Tile(
              icon: Icons.verified_user_outlined,
              title: '新版完整备份（ZIP，含清单与校验）',
              subtitle: '推荐日常备份：含 manifest 与逐文件 SHA-256',
              onTap: _busy ? null : () => _export(() => exportV2Backup(repo)),
            ),
            _Tile(
              icon: Icons.history,
              title: '兼容旧版桌面 ZIP',
              subtitle: '可放回 0.5.0 桌面版 data/ 目录恢复',
              onTap: _busy
                  ? null
                  : () => _export(() => exportLegacyDesktopZip(repo)),
            ),
            _Tile(
              icon: Icons.phone_android,
              title: '兼容旧版安卓 JSON（证书 base64）',
              subtitle: '单文件，可被本版重新导入',
              onTap: _busy
                  ? null
                  : () => _export(() => exportAndroidBackup(repo)),
            ),
            _Tile(
              icon: Icons.table_chart_outlined,
              title: 'Markdown 比赛表格',
              subtitle: '列别名与旧版导入一致',
              onTap: _busy ? null : () => _export(() => exportMarkdown(repo)),
            ),
          ]),
          const SizedBox(height: 16),
          _section(context, '备份', [
            _Tile(
              icon: Icons.backup_outlined,
              title: '立即备份',
              subtitle:
                  '当前：比赛 ${repo.compCount} 条 · 获奖 ${lib.awardStats.total} 条；'
                  '每次保存已自动滚动备份（保留 20 份）',
              onTap: _busy
                  ? null
                  : () async {
                      await repo.backupNow();
                      if (context.mounted) showSnack(context, '已备份');
                    },
            ),
          ]),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(child: Column(children: children)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 导入
  // ---------------------------------------------------------------------------

  Future<void> _pickDirectory() async {
    final dir = await getDirectoryPath();
    if (dir == null) return;
    await _importDirectory(dir);
  }

  Future<void> _importDirectory(String dir) async {
    try {
      final bundle = await parseLegacyDirectory(dir);
      await _confirmAndApply(bundle);
    } on ExchangeException catch (e) {
      if (mounted) showSnack(context, '导入失败：${e.message}', error: true);
    }
  }

  Future<void> _pickFile() async {
    const group = XTypeGroup(
      label: '备份与数据',
      extensions: ['zip', 'json', 'md', 'markdown', 'txt'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      final bundle = parseSourceBytes(bytes, file.name);
      await _confirmAndApply(bundle);
    } on ExchangeException catch (e) {
      if (mounted) showSnack(context, '导入失败：${e.message}', error: true);
    } on FileSystemException catch (e) {
      if (mounted) showSnack(context, '读取文件失败：${e.message}', error: true);
    }
  }

  Future<void> _pasteImport() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴文本导入'),
        content: SizedBox(
          width: 520,
          height: 280,
          child: TextField(
            controller: ctrl,
            maxLines: null,
            expands: true,
            decoration: const InputDecoration(
              hintText: '粘贴 JSON 或 Markdown 表格…',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解析'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final bundle = parseTextSource(ctrl.text, '粘贴文本');
      await _confirmAndApply(bundle);
    } on ExchangeException catch (e) {
      if (mounted) showSnack(context, '导入失败：${e.message}', error: true);
    }
  }

  Future<void> _confirmAndApply(ImportBundle bundle) async {
    if (bundle.isEmpty) {
      if (mounted) showSnack(context, '导入源中没有可用数据', error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(bundle.description),
              if (bundle.certificates.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '凭证 ${bundle.certificates.length} 个'
                  '（约 ${(bundle.certificates.values.fold<int>(0, (a, b) => a + b.length) / 1024 / 1024).toStringAsFixed(0)} MB，'
                  '将复制进本应用数据目录）',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                '同名同截止的比赛将按字段合并（人工标记保留）；'
                '获奖按旧 ID 匹配合并。',
              ),
              for (final w in bundle.warnings) ...[
                const SizedBox(height: 4),
                Text(
                  '⚠ $w',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.tertiary),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    // 模态进度：显示真实阶段与计数（不伪造百分比）。
    // 凭证复制阶段不可中断（保证事务完整），弹窗中明确说明。
    final progress = ValueNotifier<String>('准备导入…');
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: ValueListenableBuilder<String>(
              valueListenable: progress,
              builder: (ctx, text, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                    bundle.certificates.length > 20
                        ? '凭证较多（${bundle.certificates.length} 个），可能需要几分钟\n复制阶段不可中断，请勿关闭'
                        : '请勿关闭',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    String stageText(ImportStage stage, int current, int total) {
      switch (stage) {
        case ImportStage.parse:
          return '解析记录… 共 $total 条';
        case ImportStage.certs:
          return '复制凭证 $current / $total';
        case ImportStage.records:
          return '写入记录 $current / $total';
        case ImportStage.verify:
          return '校验凭证引用 $current / $total';
        case ImportStage.done:
          return '完成';
      }
    }

    try {
      final report = await ref
          .read(libraryProvider.notifier)
          .applyBundle(bundle, onProgress: (stage, cur, total) {
        progress.value = stageText(stage, cur, total);
      });
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // 关进度弹窗
        _showReport(report);
      }
    } catch (err) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        showSnack(context, '导入失败：$err', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showReport(ImportRecordReport report) {
    final hasIssues = report.errors.isNotEmpty || report.warnings.isNotEmpty;
    showDialog(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Row(children: [
            const Text('导入完成'),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: hasIssues ? scheme.tertiaryContainer : scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                hasIssues
                    ? '部分成功（${report.errors.length + report.warnings.length} 项提示）'
                    : '完整成功',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: hasIssues
                      ? scheme.onTertiaryContainer
                      : scheme.onSecondaryContainer,
                ),
              ),
            ),
          ]),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  report.summary(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final w in report.warnings) ...[
                          SelectableText(
                            '⚠ $w',
                            style: TextStyle(fontSize: 12.5, color: scheme.tertiary),
                          ),
                          const SizedBox(height: 4),
                        ],
                        for (final e in report.errors)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: SelectableText(
                              '• ${e['name']}：${e['reason']}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        if (report.errors.isEmpty && report.warnings.isEmpty)
                          const Text('没有需要处理的错误。'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('好的'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 导出
  // ---------------------------------------------------------------------------

  Future<void> _export(Future<ExportResult> Function() fn) async {
    setState(() => _busy = true);
    try {
      final result = await fn();
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('导出成功'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(result.path),
                const SizedBox(height: 8),
                Text(result.detail),
                const SizedBox(height: 8),
                Text(
                  '文件在应用数据目录 exports/ 下',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              if (Platform.isWindows)
                TextButton(
                  onPressed: () {
                    Process.run('explorer.exe', ['/select,', result.path]);
                    Navigator.pop(ctx);
                  },
                  child: const Text('打开所在文件夹'),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('好的'),
              ),
            ],
          ),
        );
      }
    } on ExchangeException catch (e) {
      if (mounted) showSnack(context, '导出失败：${e.message}', error: true);
    } on FileSystemException catch (e) {
      if (mounted) showSnack(context, '写入失败：${e.message}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      enabled: onTap != null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      minVerticalPadding: 12,
      leading: Icon(icon, color: scheme.primary),
      title: Text(title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(subtitle, style: const TextStyle(fontSize: 12)),
      ),
      onTap: onTap,
    );
  }
}
