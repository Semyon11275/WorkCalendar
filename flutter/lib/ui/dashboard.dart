/// 总览（设计稿 01/04）：最优先事项 hero（暖白 plate）+ 日期分组近期安排 +
/// 右列今日摘要/最近获奖；窄屏为纵向堆叠 + 三联数字统计。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repository.dart';
import '../domain/models.dart';
import '../domain/rules.dart';
import '../domain/stats.dart';
import '../state/providers.dart';
import 'certificate_viewer.dart';
import 'competitions_detail.dart';
import 'theme.dart';
import 'widgets.dart';

const _weekdays = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final stats = lib.stats;
    final wide = MediaQuery.sizeOf(context).width >= 1200;

    if (lib.comps.isEmpty && lib.awards.isEmpty) {
      return Scaffold(
        appBar: _appBar(context, stats),
        body: const EmptyView(
          icon: Icons.event_note_outlined,
          title: '还没有数据',
          hint: '到「比赛」或「数据」页添加、导入旧版数据',
        ),
      );
    }

    final upcoming = stats.upcoming;
    final hero = upcoming.isEmpty ? null : upcoming.first;

    final workColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heroCard(context, ref, hero),
        const SizedBox(height: 20),
        _upcomingSection(context, ref, upcoming),
      ],
    );

    final rightColumn = SizedBox(
      width: 340,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _todaySummary(context, lib, stats),
          const SizedBox(height: 16),
          _recentAwards(context, ref, lib, wide: true),
        ],
      ),
    );

    return Scaffold(
      appBar: _appBar(context, stats),
      body: wide
          ? ListView(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: workColumn),
                    const SizedBox(width: 20),
                    rightColumn,
                  ],
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                workColumn,
                const SizedBox(height: 16),
                _statTrio(context, lib, stats),
                const SizedBox(height: 16),
                _recentAwards(context, ref, lib, wide: false),
              ],
            ),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context, Stats stats) {
    final scheme = Theme.of(context).colorScheme;
    final n =
        stats.total -
        (stats.byStatus['submitted'] ?? 0) -
        (stats.byStatus['done'] ?? 0) -
        (stats.byStatus['abandoned'] ?? 0);
    return AppBar(
      title: Row(
        children: [
          const Text('总览'),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '$n 项待处理',
              style: DesignTokens.mono(11, color: scheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Hero：最优先事项（暖白 plate）
  // -------------------------------------------------------------------

  Widget _heroCard(BuildContext context, WidgetRef ref, UpcomingItem? hero) {
    final scheme = Theme.of(context).colorScheme;
    final onPlate = const Color(0xFF1B1A17);
    final onPlateMut = const Color(0xFF6E6A64);
    if (hero == null) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(Icons.check_circle_outline, color: scheme.primary),
          title: const Text('暂无临期事项'),
          subtitle: const Text('所有进行中的比赛临期线都在未来'),
        ),
      );
    }
    final c = hero.comp;
    final sug = c.effectiveSuggested();
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: DesignTokens.plate,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '最优先事项 / PRIORITY',
                style: DesignTokens.mono(12, color: onPlateMut),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF171509),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '剩余 ${hero.days} 天',
                  style: DesignTokens.mono(12, color: DesignTokens.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            c.name,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.2,
              color: onPlate,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            [
              c.statusLabel(),
              if (c.organizer.isNotEmpty) c.organizer,
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: onPlateMut),
          ),
          const SizedBox(height: 16),
          // Wrap 而非 Row：窄屏（390）下双日期自动换行，不溢出
          Wrap(
            spacing: 28,
            runSpacing: 12,
            children: [
              _bigDate(
                onPlate,
                onPlateMut,
                '临期线 · 内部',
                dateIso(sug) ?? '—',
                sug,
              ),
              _bigDate(
                onPlate,
                onPlateMut,
                '官方截止',
                dateIso(c.deadline) ?? '—',
                c.deadline,
                note: c.suggestedDeadline == null
                    ? '缓冲 ${c.deadlineBufferDays ?? defaultBufferDays} 天'
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: onPlate,
              foregroundColor: DesignTokens.plate,
              minimumSize: const Size(0, 42),
            ),
            onPressed: () =>
                Navigator.push(context, CompetitionDetailPage.route(c.id)),
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('查看详情'),
          ),
        ],
      ),
    );
  }

  Widget _bigDate(
    Color ink,
    Color mut,
    String label,
    String value,
    DateTime d, {
    String? note,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: DesignTokens.mono(12, color: mut)),
        const SizedBox(height: 3),
        Text(
          value,
          style: DesignTokens.mono(23, color: ink, weight: FontWeight.w700),
        ),
        if (note != null)
          Text(note, style: TextStyle(fontSize: 12, color: mut))
        else
          Text(
            _weekdays[d.weekday],
            style: TextStyle(fontSize: 12, color: mut),
          ),
      ],
    );
  }

  // -------------------------------------------------------------------
  // 近期安排：按临期线日期分组
  // -------------------------------------------------------------------

  Widget _upcomingSection(
    BuildContext context,
    WidgetRef ref,
    List<UpcomingItem> upcoming,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final groups = <String, List<UpcomingItem>>{};
    for (final u in upcoming.take(12)) {
      groups
          .putIfAbsent(dateIso(u.comp.effectiveSuggested()) ?? '—', () => [])
          .add(u);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '近期安排',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 10),
            Text(
              '未来 14 天 · ${upcoming.length} 项',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (upcoming.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.check_circle_outline, color: scheme.primary),
              title: const Text('暂无临期事项'),
            ),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  for (final date in groups.keys) ...[
                    _dateGroupHeader(context, date, groups[date]!),
                    for (final u in groups[date]!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: false,
                        minVerticalPadding: 10,
                        onTap: () => Navigator.push(
                          context,
                          CompetitionDetailPage.route(u.comp.id),
                        ),
                        title: Text(
                          u.comp.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          [
                            u.comp.statusLabel(),
                            if (u.comp.organizer.isNotEmpty) u.comp.organizer,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Text(
                          u.days < 0 ? '已过 ${-u.days} 天' : '${u.days} 天',
                          style: DesignTokens.mono(
                            13,
                            color: AppTheme.countdownColor(u.days, scheme),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _dateGroupHeader(
    BuildContext context,
    String date,
    List<UpcomingItem> items,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final d = parseDate(date);
    final wd = d == null ? '' : ' ${_weekdays[d.weekday]}';
    final days = items.first.days;
    final phase = days <= 7
        ? '本周'
        : days <= 14
        ? '下周'
        : '稍后';
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Row(
        children: [
          Text(
            date.replaceAll('-', '.'),
            style: DesignTokens.mono(12.5, color: scheme.primary),
          ),
          Text(
            wd,
            style: DesignTokens.mono(
              12,
              color: scheme.onSurfaceVariant,
              weight: FontWeight.w400,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${items.length} 项 · $phase',
            style: DesignTokens.mono(
              12,
              color: scheme.onSurfaceVariant,
              weight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // 右列：今日摘要 + 最近获奖
  // -------------------------------------------------------------------

  Widget _todaySummary(BuildContext context, LibraryState lib, Stats stats) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final archivedThisMonth = lib.comps
        .where(
          (c) =>
              c.status() == 'done' &&
              c.updatedAt.length >= 7 &&
              c.updatedAt.substring(0, 7) ==
                  '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}',
        )
        .length;
    Widget row(String label, String value, {Color? color}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            Text(
              value,
              style: DesignTokens.mono(19, color: color ?? scheme.onSurface),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '今日摘要',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  'W${_weekOfYear(now)}',
                  style: DesignTokens.mono(
                    10,
                    color: scheme.onSurfaceVariant,
                    weight: FontWeight.w400,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            row(
              '待提交',
              '${stats.byStatus['submitting'] ?? 0}',
              color: scheme.primary,
            ),
            row('临期 · 7 天内', '${stats.dueIn7}', color: scheme.tertiary),
            row('本月归档', '$archivedThisMonth', color: scheme.secondary),
          ],
        ),
      ),
    );
  }

  String _weekOfYear(DateTime d) {
    final first = DateTime(d.year, 1, 1);
    return ((d.difference(first).inDays + first.weekday - 1) / 7)
        .ceil()
        .toString()
        .padLeft(2, '0');
  }

  Widget _recentAwards(
    BuildContext context,
    WidgetRef ref,
    LibraryState lib, {
    required bool wide,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final awards = lib.awards.take(wide ? 5 : 4).toList();
    final repo = ref.watch(repositoryProvider);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '最近获奖',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '查看全部',
                  style: TextStyle(fontSize: 12, color: scheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (awards.isEmpty)
              Text(
                '还没有获奖记录',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              )
            else
              ...awards.map(
                (a) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: false,
                  minVerticalPadding: 8,
                  leading: _certThumb(context, repo, a),
                  title: Text(
                    [
                      if (a.awardRank.isNotEmpty) a.awardRank,
                      a.name,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    [
                      if (a.competition.isNotEmpty) a.competition,
                      if (a.awardDate != null)
                        '${a.awardDate!.year}.${a.awardDate!.month.toString().padLeft(2, '0')}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: a.awardDate == null
                      ? null
                      : Text(
                          '${a.awardDate!.month.toString().padLeft(2, '0')}.${a.awardDate!.day.toString().padLeft(2, '0')}',
                          style: DesignTokens.mono(
                            11,
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

  Widget _certThumb(BuildContext context, WcRepository repo, Award a) {
    final name = a.certificateFiles.isEmpty ? null : a.certificateFiles.first;
    final file = name == null ? null : File(repo.certs.path(name));
    const imgExts = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];
    final isImg =
        name != null && imgExts.any((e) => name.toLowerCase().endsWith(e));
    Widget child = Container(
      width: 52,
      height: 40,
      decoration: BoxDecoration(
        color: DesignTokens.plate,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        'PDF',
        style: DesignTokens.mono(8.5, color: const Color(0xFF6E6A64)),
      ),
    );
    if (file != null && isImg && file.existsSync()) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          file,
          width: 52,
          height: 40,
          fit: BoxFit.cover,
          cacheWidth: 104,
          errorBuilder: (_, _, _) => child,
        ),
      );
    }
    return GestureDetector(
      onTap: name == null
          ? null
          : () => Navigator.push(
              context,
              CertificateViewerPage.route(
                awardId: a.id,
                initialIndex: a.certificateFiles.indexOf(name),
              ),
            ),
      child: child,
    );
  }

  // -------------------------------------------------------------------
  // 手机：三联数字统计
  // -------------------------------------------------------------------

  Widget _statTrio(BuildContext context, LibraryState lib, Stats stats) {
    final scheme = Theme.of(context).colorScheme;
    Widget cell(String label, String value, Color color) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text(value, style: DesignTokens.mono(21, color: color)),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Row(
        children: [
          cell('待提交', '${stats.byStatus['submitting'] ?? 0}', scheme.primary),
          Container(width: 1, height: 40, color: scheme.outlineVariant),
          cell('7 天内', '${stats.dueIn7}', scheme.tertiary),
          Container(width: 1, height: 40, color: scheme.outlineVariant),
          cell(
            '本月归档',
            '${lib.comps.where((c) => c.status() == 'done').length}',
            scheme.secondary,
          ),
        ],
      ),
    );
  }
}
