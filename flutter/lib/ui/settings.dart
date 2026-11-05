/// 设置：主题、数据目录、加载自检报告、关于与许可。
library;

import 'dart:io';
import 'sync_page.dart';
import 'management_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'exchange_page.dart';

const appVersion = '1.0.0-alpha.5+31';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final mode = ref.watch(themeModeProvider);
    final notifier = ref.read(themeModeProvider.notifier);
    final skin = ref.watch(skinSeedProvider);
    final skinNotifier = ref.read(skinSeedProvider.notifier);
    final uiMode = ref.watch(uiModeProvider);
    final uiModeNotifier = ref.read(uiModeProvider.notifier);
    final serif = ref.watch(serifFontProvider);
    final serifNotifier = ref.read(serifFontProvider.notifier);
    final reducedMotion = ref.watch(reducedMotionProvider);
    final motionNotifier = ref.read(reducedMotionProvider.notifier);
    final report = repo.loadReport;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          ListTile(leading: const Icon(Icons.sync), title: const Text('设备配对与数据同步'),
            subtitle: const Text('配对批准后合并传输记录与凭证'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncPage()))),

          ListTile(leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('AI 助手与管理接口'),
            subtitle: const Text('外部 Agent API · 内置 AI · 批量导入'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManagementPage()))),

          Text('外观', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: mode,
              onChanged: (v) {
                if (v != null) notifier.set(v);
              },
              child: Column(
                children: [
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.system,
                    title: const Text('跟随系统'),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.light,
                    title: const Text('浅色'),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.dark,
                    title: const Text('深色'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '皮肤',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < skinPresets.length; i++)
                        _SkinChip(
                          index: i,
                          selected: skin == i && uiMode != 'legacy',
                          onSelect: () {
                            uiModeNotifier.set('design');
                            skinNotifier.set(i);
                          },
                        ),
                      // 旧版界面：独立于颜色皮肤的整套界面还原（含缩略预览）
                      FilterChip(
                        selected: uiMode == 'legacy',
                        showCheckmark: false,
                        avatar: _LegacyThumb(),
                        label: const Text('旧版界面'),
                        onSelected: (_) => uiModeNotifier.set(
                            uiMode == 'legacy' ? 'design' : 'legacy'),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: const Text('思源宋体'),
                  subtitle: const Text('wenku8 风格的衬线正文（OFL 开源字体）'),
                  value: serif,
                  onChanged: (v) => serifNotifier.set(v),
                ),
                SwitchListTile(
                  title: const Text('减少动效'),
                  subtitle: const Text('关闭切页揭示与按压弹性，只保留即时状态反馈'),
                  value: reducedMotion,
                  onChanged: (v) => motionNotifier.set(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('数据', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('数据目录'),
              subtitle: SelectableText(
                repo.dataDir,
                style: const TextStyle(fontSize: 12),
              ),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.import_export),
              title: const Text('导入 / 导出 / 备份'),
              subtitle: const Text('旧版数据迁移与完整备份'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExchangePage()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('启动自检（本次加载报告）', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _reportRow(
                    context,
                    '数据完整性',
                    report.mainRecovered || report.awardsRecovered
                        ? '曾有文件损坏，已自动从备份恢复'
                        : '正常',
                  ),
                  _reportRow(
                    context,
                    '跳过的坏记录',
                    '比赛 ${report.skippedComps} 条 · 获奖 ${report.skippedAwards} 条',
                  ),
                  for (final n in report.notes)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '• $n',
                        style: TextStyle(fontSize: 12, color: scheme.tertiary),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('关于', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('工作日历（Flutter 重构版）'),
                  subtitle: const Text('版本 $appVersion · 本地优先，数据完全存本机'),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('开源许可'),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: '工作日历',
                    applicationVersion: appVersion,
                  ),
                ),
                if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
                  ListTile(
                    leading: const Icon(Icons.data_object),
                    title: const Text('在资源管理器中显示数据目录'),
                    onTap: () {
                      if (Platform.isWindows) {
                        Process.run('explorer.exe', [repo.dataDir]);
                      }
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '本版未包含（重构范围说明见交付报告）',
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
          const SizedBox(height: 4),
          Text(
            'AI 助手 · 局域网同步 · 应用内自动更新 · 系统通知 · 月历视图',
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _reportRow(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

/// 皮肤选择胶囊：色点 + 名称。
class _SkinChip extends StatelessWidget {
  const _SkinChip({
    required this.index,
    required this.selected,
    required this.onSelect,
  });
  final int index;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preset = skinPresets[index];
    return FilterChip(
      selected: selected,
      onSelected: (_) => onSelect(),
      showCheckmark: false,
      avatar: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: preset.seed,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outlineVariant, width: 1),
        ),
      ),
      label: Text(preset.name),
    );
  }
}


/// 「旧版界面」缩略预览：蓝白 wenku8 布局示意。
class _LegacyThumb extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 16,
      decoration: BoxDecoration(
        color: const Color(0xFFEDF0F7),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0xFFDFE3EC)),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(children: [
        Container(width: 5, color: const Color(0xFFD3E3FD)),
        const SizedBox(width: 2),
        Expanded(
          child: Column(children: [
            Container(height: 4, color: const Color(0xFF0B57D0)),
            const SizedBox(height: 2),
            Expanded(child: Container(color: Colors.white)),
          ]),
        ),
      ]),
    );
  }
}
