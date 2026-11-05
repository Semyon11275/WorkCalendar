/// 比赛详情：全字段展示、里程碑倒计时、快捷状态标记、编辑/删除。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../domain/rules.dart';
import '../state/providers.dart';
import 'competition_edit.dart';
import 'motion.dart';
import 'theme.dart';
import 'widgets.dart';

class CompetitionDetailPage extends ConsumerWidget {
  const CompetitionDetailPage({super.key, required this.compId});
  final String compId;

  static Route<void> route(String compId) =>
      MaterialPageRoute(builder: (_) => CompetitionDetailPage(compId: compId));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final comp = lib.comps.where((c) => c.id == compId).firstOrNull;
    final scheme = Theme.of(context).colorScheme;

    if (comp == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyView(icon: Icons.error_outline, title: '记录不存在或已被删除'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('比赛详情'),
        actions: [
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              CompetitionEditPage.route(existing: comp),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'delete') {
                final ok = await confirmDialog(
                  context,
                  '删除比赛',
                  '确定删除「${comp.name}」？此操作不可撤销。',
                  okText: '删除',
                  danger: true,
                );
                if (ok == true) {
                  await ref
                      .read(libraryProvider.notifier)
                      .deleteCompById(comp.id);
                  appToast('已删除「${comp.name}」');
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          StaggerIn(
            delay: Duration.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  comp.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(comp: comp),
                    CountdownBadge(comp: comp),
                    CountdownBadge(comp: comp, official: true),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          StaggerIn(
            delay: const Duration(milliseconds: 60),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    _row('官方截止', dateIso(comp.deadline) ?? '—', emphasis: true),
                    _row(
                      '临期线',
                      dateIso(comp.effectiveSuggested()) ?? '—',
                      note: comp.suggestedDeadline == null
                          ? '按默认缓冲 ${comp.deadlineBufferDays ?? defaultBufferDays} 天自动计算'
                          : null,
                    ),
                    if (comp.signupStart != null || comp.signupEnd != null)
                      _row(
                        '报名区间',
                        '${dateIso(comp.signupStart) ?? '…'} ~ ${dateIso(comp.signupEnd) ?? '…'}',
                      ),
                    if (comp.deadlineNote.isNotEmpty)
                      _row('截止说明', comp.deadlineNote),
                    if (comp.category.isNotEmpty) _row('类别', comp.category),
                    if (comp.organizer.isNotEmpty) _row('主办方', comp.organizer),
                    if (comp.website.isNotEmpty)
                      _row(
                        '官网',
                        comp.website,
                        trailing: IconButton(
                          tooltip: '在浏览器打开',
                          icon: const Icon(Icons.open_in_new, size: 18),
                          onPressed: () => OpenFilex.open(comp.website),
                        ),
                      ),
                    if (comp.tags.isNotEmpty)
                      _row('标签', comp.tags.map((t) => '#$t').join(' ')),
                    if (comp.requirements.isNotEmpty)
                      _row('要求', comp.requirements, multiline: true),
                    if (comp.notes.isNotEmpty)
                      _row('备注', comp.notes, multiline: true),
                    if (comp.statusOverride != null)
                      _row('人工标记', statusLabels[comp.statusOverride] ?? ''),
                    if (comp.extra.isNotEmpty)
                      _row('旧版保留字段', comp.extra.keys.join('、')),
                  ],
                ),
              ),
            ),
          ),
          if (comp.milestones.isNotEmpty) ...[
            const SizedBox(height: 16),
            StaggerIn(
              delay: const Duration(milliseconds: 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('里程碑', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: [
                        for (final m in comp.milestones)
                          ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 0,
                            ),
                            leading: Icon(
                              m.date.isBefore(DateTime.now())
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: m.date.isBefore(DateTime.now())
                                  ? scheme.primary
                                  : scheme.outline,
                              size: 20,
                            ),
                            title: Text(m.name.isEmpty ? '(未命名)' : m.name),
                            trailing: Text(
                              _milestoneLabel(m.date),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.countdownColor(
                                  daysBetween(m.date, today()),
                                  scheme,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          StaggerIn(
            delay: const Duration(milliseconds: 180),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('快捷标记', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in validOverrides)
                      FilterChip(
                        label: Text(statusLabels[s] ?? s),
                        selected: comp.statusOverride == s,
                        onSelected: (v) => ref
                            .read(libraryProvider.notifier)
                            .markStatus(comp.id, v ? s : null),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (comp.statusOverride != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton(
                onPressed: () => ref
                    .read(libraryProvider.notifier)
                    .markStatus(comp.id, null),
                child: const Text('清除人工标记，恢复自动状态'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(
    String label,
    String value, {
    bool multiline = false,
    bool emphasis = false,
    String? note,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: multiline
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 正文一律可选可复制（0.5.0 曾因宿主禁用选中导致无法复制，不得复发）
                SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: emphasis ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                if (note != null)
                  SelectableText(
                    note,
                    style: const TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  String _milestoneLabel(DateTime d) {
    final days = daysBetween(d, today());
    return days == 0
        ? '今天'
        : days > 0
        ? '还剩 $days 天'
        : '已过 ${-days} 天';
  }
}
