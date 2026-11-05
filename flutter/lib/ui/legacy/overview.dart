/// 旧版界面 · 总览：紧急横幅 + 4 统计卡 + 紧急区（7 天内截止） +
/// 未来 12 周到期分布 + 最近导入。结构对齐原版 01-总览截图。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../../state/providers.dart';
import 'tokens.dart';
import 'widgets.dart';

class LegacyOverview extends ConsumerWidget {
  const LegacyOverview({
    super.key,
    required this.p,
    required this.visible,
    required this.all,
    required this.bannerDismissed,
    required this.onDismissBanner,
    required this.onOpenComp,
    required this.portText,
  });

  final LegacyPalette p;
  final List<Competition> visible;
  final List<Competition> all;
  final bool bannerDismissed;
  final VoidCallback onDismissBanner;
  final ValueChanged<String> onOpenComp;
  final String portText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = today();
    final stats = _Stats.compute(all, now);
    final urgent = stats.upcoming.where((u) => u.days <= 7).toList();

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 紧急横幅
        if (urgent.isNotEmpty && !bannerDismissed)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFE11D48), Color(0xFFF43F5E)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              const Icon(Icons.notifications_active, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${urgent.length} 个比赛 7 天内截止（按临期线），抓紧安排！',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
              ),
              InkWell(
                onTap: () => onOpenComp(urgent.first.comp.id),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('查看',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: onDismissBanner,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 15, color: Colors.white),
                ),
              ),
            ]),
          ),
        // 4 统计卡
        Row(children: [
          Expanded(child: _statCard(context, Icons.track_changes, const Color(0xFF4338CA),
              const Color(0xFFE5E7FC), '${stats.active}', '进行中')),
          const SizedBox(width: 12),
          Expanded(child: _statCard(context, Icons.warning_amber_rounded,
              const Color(0xFFBE123C), const Color(0xFFFCE3E1),
              '${stats.dueIn7}', '7 天内截止')),
          const SizedBox(width: 12),
          Expanded(child: _statCard(context, Icons.calendar_month,
              const Color(0xFFB45309), const Color(0xFFFDEFD9),
              '${stats.dueThisMonth}', '本月截止')),
          const SizedBox(width: 12),
          Expanded(child: _statCard(context, Icons.task_alt,
              const Color(0xFF047857), const Color(0xFFDCF3EA),
              '${stats.submittedOrDone}', '已提交 / 完成')),
        ]),
        const SizedBox(height: 16),
        // 紧急区
        LCard(
          padding: const EdgeInsets.all(18),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.local_fire_department,
                  color: Color(0xFFE11D48), size: 18),
              const SizedBox(width: 6),
              Text('紧急区（7 天内截止）',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: p.text)),
              const Spacer(),
              Text('共 ${urgent.length} 条',
                  style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
            const SizedBox(height: 10),
            if (urgent.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('近期没有 7 天内截止的比赛',
                    style: TextStyle(fontSize: 13, color: p.muted)),
              )
            else
              ...urgent.map((u) {
                final c = u.comp;
                return InkWell(
                  onTap: () => onOpenComp(c.id),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: p.dark
                          ? Colors.white.withValues(alpha: 0.03)
                          : const Color(0xFFFAFAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: p.hairline.withValues(alpha: 0.6)),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: p.text)),
                              const SizedBox(height: 3),
                              Row(children: [
                                LCatChip(p: p, category: c.category, small: true),
                                const SizedBox(width: 8),
                                Text(
                                    '临期线 ${_md(c.effectiveSuggested())} · 官方 ${_md(c.deadline)}',
                                    style: TextStyle(
                                        fontSize: 11.5, color: p.muted)),
                              ]),
                            ]),
                      ),
                      LCountdownBadge(p: p, comp: c),
                    ]),
                  ),
                );
              }),
          ]),
        ),
        const SizedBox(height: 16),
        // 12 周分布 + 最近导入
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: LCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          width: 4,
                          height: 14,
                          decoration: BoxDecoration(
                              color: p.primary,
                              borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 8),
                      Text('未来 12 周到期分布（按临期线）',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: p.text)),
                    ]),
                    const SizedBox(height: 14),
                    SizedBox(height: 160, child: _WeekChart(p: p, now: now, comps: all)),
                  ]),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: LCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          width: 4,
                          height: 14,
                          decoration: BoxDecoration(
                              color: p.primary,
                              borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 8),
                      Text('最近导入',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: p.text)),
                    ]),
                    const SizedBox(height: 10),
                    _recentImports(context, ref),
                  ]),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _statCard(BuildContext context, IconData icon, Color iconColor,
      Color iconBg, String value, String label) {
    return LCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
          child: Icon(icon, size: 19, color: iconColor),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: p.text,
                  fontFamily: 'Segoe UI',
                  fontFamilyFallback: LegacyTokens.monoFallback)),
          Text(label, style: TextStyle(fontSize: 11.5, color: p.muted)),
        ]),
      ]),
    );
  }

  Widget _recentImports(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final dir = Directory(repo.exportsDir);
    final List<File> files;
    if (dir.existsSync()) {
      files = dir.listSync().whereType<File>().toList();
      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    } else {
      files = <File>[];
    }
    if (files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: Text('暂无导入记录',
                style: TextStyle(fontSize: 12.5, color: p.muted))),
      );
    }
    return Column(children: [
      for (final f in files.take(5))
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Icon(Icons.insert_drive_file_outlined,
                size: 14, color: p.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(f.uri.pathSegments.last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.text)),
            ),
          ]),
        ),
    ]);
  }

  String _md(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

class _Stats {
  _Stats._(this.active, this.dueIn7, this.dueThisMonth, this.submittedOrDone,
      this.upcoming);

  final int active;
  final int dueIn7;
  final int dueThisMonth;
  final int submittedOrDone;
  final List<_Upcoming> upcoming;

  static _Stats compute(List<Competition> comps, DateTime now) {
    var active = 0, dueIn7 = 0, dueThisMonth = 0, done = 0;
    final upcoming = <_Upcoming>[];
    for (final c in comps) {
      final s = c.status(now);
      if (s != 'submitted' && s != 'done' && s != 'abandoned') active++;
      if (s == 'submitted' || s == 'done') done++;
      final d = c.countdown(now);
      if (d >= 0 &&
          s != 'submitted' &&
          s != 'done' &&
          s != 'abandoned') {
        upcoming.add(_Upcoming(c, d));
        if (d <= 7) dueIn7++;
        if (c.deadline.year == now.year && c.deadline.month == now.month) {
          dueThisMonth++;
        }
      }
    }
    upcoming.sort((a, b) => a.days.compareTo(b.days));
    return _Stats._(active, dueIn7, dueThisMonth, done, upcoming);
  }
}

class _Upcoming {
  _Upcoming(this.comp, this.days);
  final Competition comp;
  final int days;
}

/// 12 周分布图：分桶 1-7 天 / 8-14 …（原版 echarts 分桶口径）
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.p, required this.now, required this.comps});
  final LegacyPalette p;
  final DateTime now;
  final List<Competition> comps;

  @override
  Widget build(BuildContext context) {
    final buckets = List<int>.filled(12, 0);
    for (final c in comps) {
      final s = c.status(now);
      if (s == 'submitted' || s == 'done' || s == 'abandoned') continue;
      final d = c.countdown(now);
      if (d < 1) continue;
      final bucket = (d - 1) ~/ 7;
      if (bucket < 12) buckets[bucket]++;
    }
    final maxV = buckets.fold<int>(1, (a, b) => b > a ? b : a);
    return Column(children: [
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < 12; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: LayoutBuilder(builder: (ctx, box) {
                  final h = buckets[i] == 0
                      ? 0.0
                      : (buckets[i] / maxV) * (box.maxHeight - 16);
                  return Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (buckets[i] > 0)
                          Text('${buckets[i]}',
                              style: TextStyle(
                                  fontSize: 10, color: p.muted)),
                        Container(
                          height: h,
                          decoration: BoxDecoration(
                            color: p.primary.withValues(alpha: 0.75),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4)),
                          ),
                        ),
                      ]);
                }),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 6),
      Row(children: [
        for (var i = 0; i < 12; i++)
          Expanded(
            child: Text(
              i == 0 ? '1-7天' : '${i * 7 + 1}-${i * 7 + 7}天',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 8.5, color: p.muted),
            ),
          ),
      ]),
    ]);
  }
}
