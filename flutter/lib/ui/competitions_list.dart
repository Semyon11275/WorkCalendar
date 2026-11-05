/// 比赛：手机为卡片列表，桌面（≥1000）为「行式表格 + 右侧检查面板」工作区，
/// 选中行高亮、边看边切；↑↓ 选择、Enter 打开（对齐设计稿 02/05/06）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../domain/classification.dart';
import '../domain/rules.dart';
import '../state/providers.dart';
import 'competition_edit.dart';
import 'competitions_detail.dart';
import 'theme.dart';
import 'widgets.dart';

class CompetitionsListPage extends ConsumerStatefulWidget {
  const CompetitionsListPage({super.key});

  @override
  ConsumerState<CompetitionsListPage> createState() =>
      _CompetitionsListPageState();
}

class _CompetitionsListPageState extends ConsumerState<CompetitionsListPage> {
  String? _selectedId;
  final _tableFocus = FocusNode();

  @override
  void dispose() {
    _tableFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = ref.watch(visibleCompsProvider);
    final filter = ref.watch(compsFilterProvider);
    final filterNotifier = ref.read(compsFilterProvider.notifier);
    final staleCount = ref.watch(staleHiddenCountProvider);
    final wide = MediaQuery.sizeOf(context).width >= 1280;
    final scheme = Theme.of(context).colorScheme;

    // 桌面工作区：保持选中行在过滤结果内
    if (wide && visible.isNotEmpty) {
      if (_selectedId == null || !visible.any((c) => c.id == _selectedId)) {
        _selectedId = visible.first.id;
      }
    }

    return Scaffold(
      appBar: _appBar(context, visible),
      floatingActionButton: wide
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  Navigator.push(context, CompetitionEditPage.route()),
              icon: const Icon(Icons.add),
              label: const Text('添加比赛'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索名称、主办方或标签',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                suffixIcon: filter.keyword.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () =>
                            filterNotifier.update(filter.copyWith(keyword: '')),
                      ),
              ),
              onChanged: (v) =>
                  filterNotifier.update(filter.copyWith(keyword: v)),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _QuickChip(
                    label: filter.statuses.isEmpty
                        ? '状态'
                        : '状态 · ${filter.statuses.map((s) => statusLabels[s] ?? s).join('/')}',
                    selected: filter.statuses.isNotEmpty,
                    onTap: () => _pickStatuses(context, filter).then((p) {
                      if (p != null) {
                        filterNotifier.update(filter.copyWith(statuses: p));
                      }
                    }),
                  ),
                  _QuickChip(
                    label: filter.categories.isEmpty
                        ? '类别'
                        : '类别 · ${filter.categories.join('/')}',
                    selected: filter.categories.isNotEmpty,
                    onTap: () => _openFilterSheet(context),
                  ),
                  _QuickChip(
                    label: '排序 · ${_sortLabel(filter.sort)}',
                    selected: false,
                    onTap: () => _openFilterSheet(context),
                  ),
                  if (filter.hasFilter)
                    _QuickChip(
                      label: '清除全部',
                      selected: false,
                      onTap: () {
                        filterNotifier.update(CompsFilter(sort: filter.sort));
                        setState(() {});
                      },
                    ),
                ],
              ),
            ),
          ),
          if (staleCount > 0) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.visibility_off_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '已隐藏 $staleCount 项过期比赛（已截止 5 天以上）',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        filterNotifier.update(filter.copyWith(showStale: true)),
                    child: const Text('撤销'),
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: visible.isEmpty
                ? EmptyView(
                    icon: Icons.emoji_events_outlined,
                    title: filter.hasFilter ? '没有符合筛选的比赛' : '还没有比赛',
                    hint: filter.hasFilter ? '试试调整筛选' : null,
                  )
                : wide
                ? _workspace(context, ref, visible)
                : _mobileList(context, visible),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 桌面工作区
  // ---------------------------------------------------------------------

  Widget _workspace(
    BuildContext context,
    WidgetRef ref,
    List<Competition> visible,
  ) {
    final selected = _selectedId == null
        ? null
        : ref.watch(repositoryProvider).getComp(_selectedId!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _table(context, visible)),
          const SizedBox(width: 16),
          SizedBox(
            width: 340,
            child: AnimatedSwitcher(
              duration: Duration(
                milliseconds:
                    ref.watch(reducedMotionProvider) ||
                        MediaQuery.disableAnimationsOf(context)
                    ? 0
                    : 300,
              ),
              layoutBuilder: (current, previous) =>
                  current ?? const SizedBox.shrink(),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.03, 0),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: selected == null
                  ? SizedBox(
                      key: const ValueKey('empty'),
                      height: 300,
                      child: const EmptyView(
                        icon: Icons.touch_app_outlined,
                        title: '选中一条记录查看详情',
                      ),
                    )
                  : _inspectionPanel(
                      context,
                      ref,
                      selected,
                      key: ValueKey(selected.id),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _table(BuildContext context, List<Competition> visible) {
    final scheme = Theme.of(context).colorScheme;
    final headerStyle = DesignTokens.mono(
      12,
      color: scheme.onSurfaceVariant,
      weight: FontWeight.w400,
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final idx = visible.indexWhere((c) => c.id == _selectedId);
          if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
              idx < visible.length - 1) {
            setState(() => _selectedId = visible[idx + 1].id);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp && idx > 0) {
            setState(() => _selectedId = visible[idx - 1].id);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter &&
              _selectedId != null) {
            Navigator.push(context, CompetitionDetailPage.route(_selectedId!));
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: [
                  Expanded(flex: 5, child: Text('名称', style: headerStyle)),
                  SizedBox(width: 72, child: Text('类别', style: headerStyle)),
                  SizedBox(width: 90, child: Text('临期线', style: headerStyle)),
                  SizedBox(width: 90, child: Text('官方截止', style: headerStyle)),
                  SizedBox(width: 76, child: Text('状态', style: headerStyle)),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: ListView.separated(
                key: const PageStorageKey('competition-table'),
                itemCount: visible.length,
                itemBuilder: (context, i) => _tableRow(
                  context,
                  visible[i],
                  visible[i].id == _selectedId,
                ),
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '共 ${visible.length} 项 · ↑↓ 选择 · Enter 打开',
                  style: DesignTokens.mono(
                    12,
                    color: scheme.onSurfaceVariant,
                    weight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tableRow(BuildContext context, Competition c, bool selected) {
    final scheme = Theme.of(context).colorScheme;
    final status = c.status();
    final cd = c.countdown();
    final suggestedColor = AppTheme.countdownColor(cd, scheme);
    return InkWell(
      onTap: () => setState(() => _selectedId = c.id),
      child: AnimatedContainer(
        duration: Duration(
          milliseconds:
              ref.watch(reducedMotionProvider) ||
                  MediaQuery.disableAnimationsOf(context)
              ? 0
              : 180,
        ),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.07) : null,
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.55)
                : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (c.organizer.isNotEmpty)
                    Text(
                      c.organizer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 72,
              child: Text(
                c.category.isEmpty ? '—' : c.category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            SizedBox(
              width: 90,
              child: Text(
                dateIso(c.effectiveSuggested()) ?? '—',
                style: DesignTokens.mono(12.5, color: suggestedColor),
              ),
            ),
            SizedBox(
              width: 90,
              child: Text(
                dateIso(c.deadline) ?? '—',
                style: DesignTokens.mono(
                  12.5,
                  color: scheme.onSurface,
                  weight: FontWeight.w400,
                ),
              ),
            ),
            SizedBox(
              width: 76,
              child: Text(
                statusLabels[status] ?? status,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.statusTextColor(status, scheme),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inspectionPanel(
    BuildContext context,
    WidgetRef ref,
    Competition c, {
    required Key key,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final status = c.status();
    return Card(
      key: key,
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '选中记录 / SELECTED',
                  style: DesignTokens.mono(12, color: scheme.onSurfaceVariant),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.more_horiz, size: 20),
                  onSelected: (v) async {
                    if (v == 'delete') {
                      final ok = await confirmDialog(
                        context,
                        '删除比赛',
                        '确定删除「${c.name}」？此操作不可撤销。',
                        okText: '删除',
                        danger: true,
                      );
                      if (ok == true) {
                        await ref
                            .read(libraryProvider.notifier)
                            .deleteCompById(c.id);
                        appToast('已删除「${c.name}」');
                      }
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppTheme.statusTextColor(status, scheme),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${statusLabels[status] ?? status} · 剩余 ${c.countdown().abs()} 天',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.statusTextColor(status, scheme),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              c.name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              [
                if (c.category.isNotEmpty) c.category,
                if (c.organizer.isNotEmpty) c.organizer,
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const Divider(height: 28),
            _panelRow(
              '临期线 · 内部',
              dateIso(c.effectiveSuggested()) ?? '—',
              color: AppTheme.countdownColor(c.countdown(), scheme),
              scheme: scheme,
            ),
            _panelRow('官方截止', dateIso(c.deadline) ?? '—', scheme: scheme),
          const SizedBox(height: 12),
          Text(
            '快捷标记',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final ov in validOverrides)
                FilterChip(
                  label: Text(
                    statusLabels[ov] ?? ov,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  selected: c.statusOverride == ov,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: (v) => ref
                      .read(libraryProvider.notifier)
                      .markStatus(c.id, v ? ov : null),
                ),
            ],
          ),
            if (c.signupStart != null || c.signupEnd != null) ...[
              const SizedBox(height: 14),
              Text(
                '报名与提交',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              _panelRow(
                '报名区间',
                '${dateIso(c.signupStart) ?? '…'} ~ ${dateIso(c.signupEnd) ?? '…'}',
                scheme: scheme,
              ),
              if (c.deadlineNote.isNotEmpty)
                _panelRow('说明', c.deadlineNote, scheme: scheme),
            ],
            if (c.requirements.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                '要求与交付',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                c.requirements,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
            if (c.notes.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                '备注',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              SelectableText(
                c.notes,
                maxLines: 4,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
            if (c.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  for (final t in c.tags)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#$t',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  CompetitionEditPage.route(existing: c),
                ),
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('编辑记录'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () =>
                    Navigator.push(context, CompetitionDetailPage.route(c.id)),
                child: const Text('展开完整详情'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelRow(
    String label,
    String value, {
    Color? color,
    required ColorScheme scheme,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: DesignTokens.mono(
                15,
                color: color ?? scheme.onSurface,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 手机列表（三行卡片）
  // ---------------------------------------------------------------------

  Widget _mobileList(BuildContext context, List<Competition> visible) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final c = visible[i];
        final status = c.status();
        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () =>
                Navigator.push(context, CompetitionDetailPage.route(c.id)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    [
                      statusLabels[status] ?? status,
                      if (c.category.isNotEmpty) c.category,
                      if (c.organizer.isNotEmpty) c.organizer,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '临期 ${dateIso(c.effectiveSuggested()) ?? '—'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesignTokens.mono(
                            11.5,
                            color: AppTheme.countdownColor(c.countdown(), scheme),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '官方 ${dateIso(c.deadline) ?? '—'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesignTokens.mono(
                            11.5,
                            color: scheme.onSurfaceVariant,
                            weight: FontWeight.w400,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        c.countdown() < 0
                            ? '已过 ${-c.countdown()} 天'
                            : '${c.countdown()} 天',
                        style: DesignTokens.mono(
                          12,
                          color: AppTheme.countdownColor(c.countdown(), scheme),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // 工具
  // ---------------------------------------------------------------------

  String _sortLabel(CompSort s) {
    switch (s) {
      case CompSort.suggested:
        return '临期线';
      case CompSort.deadline:
        return '官方截止';
      case CompSort.updatedDesc:
        return '最近编辑';
      case CompSort.name:
        return '名称';
    }
  }

  PreferredSizeWidget _appBar(BuildContext context, List<Competition> visible) {
    final wide = MediaQuery.sizeOf(context).width >= 1280;
    final all = ref.read(libraryProvider).comps;
    final submitting = all.where((c) => c.status() == 'submitting').length;
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      title: Row(
        children: [
          const Text('比赛'),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '当前显示 ${visible.length}',
              style: DesignTokens.mono(11, color: scheme.primary),
            ),
          ),
        ],
      ),
      actions: [
        if (wide)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                CountPill(label: '共 ${all.length} 项'),
                const SizedBox(width: 8),
                CountPill(
                  label: '待提交',
                  count: submitting,
                  tone: scheme.primary,
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.push(context, CompetitionEditPage.route()),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建比赛'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<Set<String>?> _pickStatuses(
    BuildContext context,
    CompsFilter filter,
  ) async {
    final selected = {...filter.statuses};
    const all = [
      'submitting',
      'not_started',
      'open',
      'urgent',
      'past_suggested',
      'overdue',
      'submitted',
      'done',
      'abandoned',
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('按状态筛选'),
          content: SizedBox(
            width: 360,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in all)
                  FilterChip(
                    label: Text(statusLabels[s] ?? s),
                    selected: selected.contains(s),
                    onSelected: (v) => setState(
                      () => v ? selected.add(s) : selected.remove(s),
                    ),
                  ),
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
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    return ok == true ? selected : null;
  }

  /// FocusSurface 筛选抽屉（设计稿 06）：状态 / 类别 / 排序 三组 + 底部结果数。
  void _openFilterSheet(BuildContext context) {
    final filter = ref.read(compsFilterProvider);
    final notifier = ref.read(compsFilterProvider.notifier);
    final categories = <String>{
      for (final c in ref.read(libraryProvider).comps)
        ...competitionDirections(c),
    }.toList()..sort();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, sheetSetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '筛选',
                    style: Theme.of(ctx).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      notifier.update(CompsFilter(sort: filter.sort));
                      sheetSetState(() {});
                    },
                    child: const Text('清除全部'),
                  ),
                ],
              ),
              _groupLabel(ctx, '状态'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in const [
                    'submitting',
                    'not_started',
                    'open',
                    'urgent',
                    'past_suggested',
                    'overdue',
                    'submitted',
                    'done',
                    'abandoned',
                  ])
                    Builder(
                      builder: (ctx) {
                        final isOn = ref
                            .watch(compsFilterProvider)
                            .statuses
                            .contains(s);
                        return FilterChip(
                          label: Text(statusLabels[s] ?? s),
                          selected: isOn,
                          onSelected: (v) {
                            final cur = ref.read(compsFilterProvider);
                            final next = {...cur.statuses};
                            v ? next.add(s) : next.remove(s);
                            notifier.update(cur.copyWith(statuses: next));
                          },
                        );
                      },
                    ),
                ],
              ),
              _groupLabel(ctx, '设计方向（可多选，保留原始类别）'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Builder(
                    builder: (ctx) {
                      final isOn = ref
                          .watch(compsFilterProvider)
                          .categories
                          .isEmpty;
                      return FilterChip(
                        label: const Text('全部类别'),
                        selected: isOn,
                        onSelected: (_) {
                          final cur = ref.read(compsFilterProvider);
                          notifier.update(cur.copyWith(categories: {}));
                        },
                      );
                    },
                  ),
                  for (final cat in categories)
                    Builder(
                      builder: (ctx) {
                        final isOn = ref
                            .watch(compsFilterProvider)
                            .categories
                            .contains(cat);
                        return FilterChip(
                          label: Text(cat),
                          selected: isOn,
                          onSelected: (v) {
                            final cur = ref.read(compsFilterProvider);
                            final next = {...cur.categories};
                            v ? next.add(cat) : next.remove(cat);
                            notifier.update(cur.copyWith(categories: next));
                          },
                        );
                      },
                    ),
                ],
              ),
              _groupLabel(ctx, '排序'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in CompSort.values)
                    Builder(
                      builder: (ctx) {
                        final isOn = ref.watch(compsFilterProvider).sort == s;
                        return ChoiceChip(
                          label: Text(_sortLabel(s)),
                          selected: isOn,
                          onSelected: (_) {
                            final cur = ref.read(compsFilterProvider);
                            notifier.update(cur.copyWith(sort: s));
                          },
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    '查看结果 · ${ref.watch(visibleCompsProvider).length} 项',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupLabel(BuildContext ctx, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
      child: Text(
        text,
        style: DesignTokens.mono(
          10,
          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
          weight: FontWeight.w400,
        ),
      ),
    );
  }
}

/// 快捷筛选入口胶囊。
class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.14)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.6)
                : scheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 计数小胶囊。
class CountPill extends StatelessWidget {
  const CountPill({super.key, required this.label, this.count, this.tone});
  final String label;
  final int? count;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: DesignTokens.mono(13, color: tone ?? scheme.primary),
            ),
          ],
        ],
      ),
    );
  }
}
