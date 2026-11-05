/// 自适应外壳：<600 底部导航；≥600 自绘侧栏（设计稿 01/02）——
/// 分组导航（工作区/系统）、计数徽章、底部存储卡。
/// 切页带 TabReveal 揭示动效（可被「减少动效」关闭）；页面懒构建。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'awards.dart';
import 'competitions_list.dart';
import 'dashboard.dart';
import 'exchange_page.dart';
import 'motion.dart';
import 'settings.dart';
import 'timeline_page.dart';
import 'theme.dart';

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  int _index = 0;
  final Set<int> _visited = {0};

  void _select(int index) {
    if (index == _index) return;
    setState(() {
      _index = index;
      _visited.add(index);
    });
  }

  Widget _content(List<Widget> pages) => TabReveal(
    index: _index,
    child: IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < pages.length; i++)
          TickerMode(
            enabled: i == _index,
            child: _visited.contains(i) ? pages[i] : const SizedBox.shrink(),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pages = [
      const DashboardPage(),
      const CompetitionsListPage(),
      const TimelinePage(),
      const AwardsPage(),
      const ExchangePage(),
      const SettingsPage(),
    ];
    final content = _content(pages);

    if (width < 600) {
      return Scaffold(
        body: content,
        bottomNavigationBar: NavigationBar(
          selectedIndex:
              _mobileDestinations.indexWhere((d) => d.$3 == _index).clamp(0, 4),
          onDestinationSelected: (i) => _select(_mobileDestinations[i].$3),
          destinations: [
            for (final (icon, label, _) in _mobileDestinations)
              NavigationDestination(icon: Icon(icon), label: label),
          ],
        ),
      );
    }

    final extended = width >= 1000;
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            index: _index,
            extended: extended,
            onSelect: _select,
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// 设计稿风格侧栏：品牌头 + 分组导航（计数徽章）+ 底部存储卡。
class _Sidebar extends ConsumerStatefulWidget {
  const _Sidebar({
    required this.index,
    required this.extended,
    required this.onSelect,
  });

  final int index;
  final bool extended;
  final ValueChanged<int> onSelect;

  @override
  ConsumerState<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<_Sidebar> {
  String _lastBackup = '';

  @override
  void initState() {
    super.initState();
    _loadLastBackup();
  }

  Future<void> _loadLastBackup() async {
    try {
      final repo = ref.read(repositoryProvider);
      final dir = Directory(repo.backupDir);
      if (!await dir.exists()) {
        if (mounted) setState(() => _lastBackup = '尚未备份');
        return;
      }
      final files = await dir.list().toList();
      DateTime? newest;
      for (final e in files) {
        if (e is! File) continue;
        final st = await e.stat();
        if (newest == null || st.modified.isAfter(newest)) newest = st.modified;
      }
      if (!mounted) return;
      setState(() {
        _lastBackup = newest == null
            ? '尚未备份'
            : '${newest.month.toString().padLeft(2, '0')}-${newest.day.toString().padLeft(2, '0')} '
                '${newest.hour.toString().padLeft(2, '0')}:${newest.minute.toString().padLeft(2, '0')}';
      });
    } on FileSystemException {
      if (mounted) setState(() => _lastBackup = '尚未备份');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lib = ref.watch(libraryProvider);
    final activeCount = lib.stats.activeCount(); // 进行中，作为「比赛」徽章
    final awardCount = lib.awardStats.total;

    return Container(
      width: widget.extended ? 212 : 72,
      color: scheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 品牌头
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 12, 6),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.calendar_month,
                    size: 19,
                    color: scheme.onPrimary,
                  ),
                ),
                if (widget.extended) ...[
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '工作日历',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'WORK CALENDAR',
                        style: DesignTokens.mono(
                          8,
                          color: scheme.onSurfaceVariant,
                          weight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (widget.extended)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 12, 6),
              child: Text(
                '工作区',
                style: DesignTokens.mono(
                  9.5,
                  color: scheme.onSurfaceVariant,
                  weight: FontWeight.w400,
                ),
              ),
            ),
          for (var i = 0; i < 4; i++)
            _item(context, i, badge: i == 1 ? activeCount : (i == 3 ? awardCount : null)),
          if (widget.extended)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 6),
              child: Text(
                '系统',
                style: DesignTokens.mono(
                  9.5,
                  color: scheme.onSurfaceVariant,
                  weight: FontWeight.w400,
                ),
              ),
            ),
          SizedBox(height: widget.extended ? 0 : 14),
          for (var i = 4; i < 6; i++) _item(context, i, badge: null),
          const Spacer(),
          // 存储卡（仅展开态）
          if (widget.extended)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '本地存储',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '比赛 ${ref.watch(repositoryProvider).compCount} · 获奖 ${ref.watch(repositoryProvider).awardCount}',
                      style: DesignTokens.mono(
                        10.5,
                        color: scheme.onSurfaceVariant,
                        weight: FontWeight.w400,
                      ),
                    ),
                    Text(
                      '上次备份 $_lastBackup',
                      style: DesignTokens.mono(
                        10.5,
                        color: scheme.onSurfaceVariant,
                        weight: FontWeight.w400,
                      ),
                    ),
                    Text(
                      appVersion,
                      style: DesignTokens.mono(
                        9.5,
                        color: scheme.onSurfaceVariant,
                        weight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, int i, {int? badge}) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.index == i;
    final (icon, label, _) = _desktopDestinations[i];
    // 收起态：图标 + 文字纵向排列（纯图标无法辨认，测试曾在此失败）
    if (!widget.extended) {
      final compact = Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
                if (badge != null && badge > 0)
                  Positioned(
                    right: -7,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.onPrimary
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$badge',
                        style: DesignTokens.mono(
                          8.5,
                          color: selected ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
          ],
        ),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => widget.onSelect(i),
            child: compact,
          ),
        ),
      );
    }

    final row = Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Icon(
              icon,
              size: 20,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
          ),
          if (badge != null && badge > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.onPrimary.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$badge',
                style: DesignTokens.mono(
                  10.5,
                  color: scheme.onPrimary,
                ),
              ),
            ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => widget.onSelect(i),
          child: row,
        ),
      ),
    );
  }
}


/// 侧栏/底部导航共用目标。
/// 桌面侧栏目标（含时间线，对齐原版导航）。
const _desktopDestinations = [
  (Icons.dashboard_outlined, '总览', 0),
  (Icons.emoji_events_outlined, '比赛', 1),
  (Icons.view_timeline_outlined, '时间线', 2),
  (Icons.workspace_premium_outlined, '获奖', 3),
  (Icons.import_export, '数据', 4),
  (Icons.settings_outlined, '设置', 5),
];

/// 手机底部导航（5 项；时间线从总览页进入，避免拥挤）。
const _mobileDestinations = [
  (Icons.dashboard_outlined, '总览', 0),
  (Icons.emoji_events_outlined, '比赛', 1),
  (Icons.workspace_premium_outlined, '获奖', 3),
  (Icons.import_export, '数据', 4),
  (Icons.settings_outlined, '设置', 5),
];
