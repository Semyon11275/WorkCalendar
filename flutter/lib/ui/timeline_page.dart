/// 时间线（原版甘特图恢复，差异清单 6.1）：
/// 每比赛一行，准备期（浅条）/提交期（深条）+ 临期线菱形 + 官方截止方块 +
/// 里程碑圆点 + 今天红虚线；窗口覆盖所有可见比赛（前后各留 7 天），
/// 横向滚动；点击行打开详情。日期文字/行高/颜色走设计 token。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../domain/rules.dart';
import '../state/providers.dart';
import 'competitions_detail.dart';
import 'theme.dart';
import 'widgets.dart';

class TimelinePage extends ConsumerWidget {
  const TimelinePage({super.key});

  static const double _pxPerDay = 26;
  static const double _rowHeight = 34;
  static const double _labelWidth = 190;
  static const double _headerHeight = 44;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final scheme = Theme.of(context).colorScheme;
    final now = today();

    // 可见比赛：排除已完成/已放弃（原版窗口内已结束的灰显——这里简化为
    // 排除人工放弃，已截止仍显示以保留历史），按截止日排序。
    final comps = lib.comps
        .where((c) => c.statusOverride != 'abandoned')
        .toList()
      ..sort((a, b) => a.deadline.compareTo(b.deadline));

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('时间线'),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text('窗口 ${comps.length} 项 · 横向滚动',
                style: DesignTokens.mono(11, color: scheme.primary)),
          ),
        ]),
      ),
      body: comps.isEmpty
          ? const EmptyView(
              icon: Icons.view_timeline_outlined,
              title: '没有可显示的比赛',
              hint: '先到「比赛」页添加或导入')
          : _TimelineBody(comps: comps, now: now),
    );
  }
}

class _TimelineBody extends StatelessWidget {
  const _TimelineBody({required this.comps, required this.now});

  final List<Competition> comps;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 窗口：所有日期与今天的前后边界
    DateTime minD = now.subtract(const Duration(days: 7));
    DateTime maxD = now.add(const Duration(days: 45));
    for (final c in comps) {
      final sugg = c.effectiveSuggested();
      if (sugg.isBefore(minD)) minD = sugg;
      if (c.deadline.isAfter(maxD)) maxD = c.deadline;
      final ss = c.signupStart;
      if (ss != null && ss.isBefore(minD)) minD = ss;
    }
    minD = minD.subtract(const Duration(days: 2));
    maxD = maxD.add(const Duration(days: 2));
    final totalDays = maxD.difference(minD).inDays + 1;

    final chartWidth = totalDays * TimelinePage._pxPerDay;
    final chartHeight = comps.length * TimelinePage._rowHeight;

    return Column(children: [
      // 图例
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(spacing: 14, runSpacing: 4, children: [
            _legend(scheme, scheme.primary.withValues(alpha: 0.28), '准备期'),
            _legend(scheme, scheme.primary.withValues(alpha: 0.75), '提交期'),
            _legend(scheme, scheme.tertiary, '临期线（菱形）'),
            _legend(scheme, scheme.onSurface, '官方截止（方块）'),
            _legend(scheme, scheme.secondary, '里程碑（圆点）'),
            _legend(scheme, scheme.error, '今天（虚线）'),
          ]),
        ),
      ),
      Expanded(
        child: SingleChildScrollView(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 左侧固定标签列
            SizedBox(
              width: TimelinePage._labelWidth,
              child: Column(
                children: [
                  SizedBox(height: TimelinePage._headerHeight),
                  for (final c in comps)
                    SizedBox(
                      height: TimelinePage._rowHeight,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8, left: 12),
                          child: Tooltip(
                            message: c.name,
                            child: Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: c.status() == 'overdue'
                                    ? scheme.onSurfaceVariant
                                    : scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 右侧可横向滚动的甘特区
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: chartWidth,
                  height: chartHeight + TimelinePage._headerHeight,
                  child: CustomPaint(
                    painter: _TimelinePainter(
                      comps: comps,
                      minDay: minD,
                      totalDays: totalDays,
                      now: now,
                      scheme: scheme,
                    ),
                    child: Column(children: [
                      SizedBox(height: TimelinePage._headerHeight),
                      // 行点击层（透明）
                      for (final c in comps)
                        SizedBox(
                          width: chartWidth,
                          height: TimelinePage._rowHeight,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () => Navigator.push(
                                context, CompetitionDetailPage.route(c.id)),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
      // 底部说明
      Padding(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '窗口 ${dateIso(minD)} ~ ${dateIso(maxD)} · 今天 ${dateIso(now)} · 点击行打开比赛详情',
            style: DesignTokens.mono(10.5,
                color: scheme.onSurfaceVariant, weight: FontWeight.w400),
          ),
        ),
      ),
    ]);
  }

  Widget _legend(ColorScheme scheme, Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 12,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
    ]);
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.comps,
    required this.minDay,
    required this.totalDays,
    required this.now,
    required this.scheme,
  });

  final List<Competition> comps;
  final DateTime minDay;
  final int totalDays;
  final DateTime now;
  final ColorScheme scheme;

  static const double _pxPerDay = TimelinePage._pxPerDay;
  static const double _rowHeight = TimelinePage._rowHeight;
  static const double _headerHeight = TimelinePage._headerHeight;

  double _x(DateTime d) =>
      d.difference(minDay).inDays * _pxPerDay;

  @override
  void paint(Canvas canvas, Size size) {
    _paintAxis(canvas);
    _paintToday(canvas);
    for (var i = 0; i < comps.length; i++) {
      _paintRow(canvas, i, comps[i]);
    }
  }

  void _paintAxis(Canvas canvas) {
    // 日期轴：每 7 天一条竖线 + 日期标签（月.日）
    final tp = TextDirection.ltr;
    for (var d = 0; d <= totalDays; d += 7) {
      final x = d * _pxPerDay;
      canvas.drawLine(Offset(x, _headerHeight - 6),
          Offset(x, _headerHeight + comps.length * _rowHeight),
          Paint()
            ..color = scheme.outlineVariant.withValues(alpha: 0.5)
            ..strokeWidth = 1);
      final day = minDay.add(Duration(days: d));
      final tp2 = TextPainter(
        text: TextSpan(
            text: '${day.month}/${day.day}',
            style: DesignTokens.mono(9, color: scheme.onSurfaceVariant,
                weight: FontWeight.w400)),
        textDirection: tp,
      )..layout();
      tp2.paint(canvas, Offset(x + 2, _headerHeight - 20));
    }
    // 顶部轴线
    canvas.drawLine(Offset(0, _headerHeight - 6),
        Offset(totalDays * _pxPerDay, _headerHeight - 6),
        Paint()
          ..color = scheme.outlineVariant
          ..strokeWidth = 1);
  }

  void _paintToday(Canvas canvas) {
    final x = _x(now) + _pxPerDay / 2;
    final paint = Paint()
      ..color = scheme.error
      ..strokeWidth = 1.4;
    final dash = 5.0;
    var y = _headerHeight - 8;
    final bottom = _headerHeight + comps.length * _rowHeight;
    while (y < bottom) {
      canvas.drawLine(Offset(x, y), Offset(x, y + dash), paint);
      y += dash * 2;
    }
    final tp = TextPainter(
      text: TextSpan(
          text: '今天', style: TextStyle(fontSize: 9, color: scheme.error)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x + 3, _headerHeight - 16));
  }

  void _paintRow(Canvas canvas, int index, Competition c) {
    final yTop = _headerHeight + index * _rowHeight + 7;
    final barH = _rowHeight - 14;
    final r = Radius.circular(4);
    final sugg = c.effectiveSuggested();
    final overdue = c.status() == 'overdue';

    // 准备期：报名开始(或临期线-14天) → 临期线
    final prepStart = c.signupStart ?? sugg.subtract(const Duration(days: 14));
    final prepRect = Rect.fromPoints(
      Offset(_x(prepStart) + _pxPerDay / 2, yTop),
      Offset(_x(sugg) + _pxPerDay / 2, yTop + barH),
    );
    canvas.drawRRect(
        RRect.fromRectAndRadius(prepRect, r),
        Paint()
          ..color = scheme.primary.withValues(alpha: overdue ? 0.10 : 0.28));

    // 提交期：临期线 → 官方截止
    final subRect = Rect.fromPoints(
      Offset(_x(sugg) + _pxPerDay / 2, yTop),
      Offset(_x(c.deadline) + _pxPerDay / 2, yTop + barH),
    );
    if (!subRect.width.isNegative && subRect.width >= 1) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(subRect, r),
          Paint()
            ..color =
                scheme.primary.withValues(alpha: overdue ? 0.30 : 0.75));
    }

    // 临期线菱形
    final dx = _x(sugg) + _pxPerDay / 2;
    final cy = yTop + barH / 2;
    final diamond = Path()
      ..moveTo(dx, cy - 5)
      ..lineTo(dx + 5, cy)
      ..lineTo(dx, cy + 5)
      ..lineTo(dx - 5, cy)
      ..close();
    canvas.drawPath(diamond, Paint()..color = scheme.tertiary);

    // 官方截止方块
    final ex = _x(c.deadline) + _pxPerDay / 2;
    canvas.drawRect(Rect.fromCenter(center: Offset(ex, cy), width: 7, height: 7),
        Paint()..color = scheme.onSurface);

    // 里程碑圆点
    for (final m in c.milestones) {
      final mx = _x(m.date) + _pxPerDay / 2;
      canvas.drawCircle(Offset(mx, cy), 3.2, Paint()..color = scheme.secondary);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      old.comps != comps || old.minDay != minDay || old.scheme != scheme;
}
