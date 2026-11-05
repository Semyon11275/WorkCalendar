/// 旧版界面 · 时间线：原版图例与窗口说明 + 甘特条形（点击开抽屉） +
/// 图表分析区（倒计时排行 top15 渐变横条 + 到期分布按周）。
library;

import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../domain/rules.dart';
import 'tokens.dart';
import 'widgets.dart';

class LegacyTimeline extends StatelessWidget {
  const LegacyTimeline({
    super.key,
    required this.p,
    required this.visible,
    required this.onOpenDrawer,
  });

  final LegacyPalette p;
  final List<Competition> visible;
  final ValueChanged<String> onOpenDrawer;

  static const double _pxPerDay = 26;
  static const double _rowH = 30;
  static const double _labelW = 200;
  static const double _headerH = 40;

  @override
  Widget build(BuildContext context) {
    final dark = p.dark;
    final now = today();
    // 原版：窗口内含已结束项（灰色显示）。取活动项 + 窗口期内结束的项。
    final endedInWindow = visible
        .where((c) =>
            c.status(now) == 'overdue' &&
            !c.deadline.isBefore(now.subtract(const Duration(days: 45))))
        .toList();
    final active = visible
        .where((c) =>
            c.status(now) != 'submitted' &&
            c.status(now) != 'done' &&
            c.status(now) != 'abandoned' &&
            c.status(now) != 'overdue')
        .toList();
    final all = [...active, ...endedInWindow]
      ..sort((a, b) => a.deadline.compareTo(b.deadline));
    final endedCount = endedInWindow.length;
    var minD = now.subtract(const Duration(days: 7));
    var maxD = now.add(const Duration(days: 45));
    for (final c in all) {
      if (c.effectiveSuggested().isBefore(minD)) minD = c.effectiveSuggested();
      if (c.deadline.isAfter(maxD)) maxD = c.deadline;
    }
    minD = DateTime(minD.year, minD.month, minD.day)
        .subtract(const Duration(days: 2));
    maxD = maxD.add(const Duration(days: 2));
    final totalDays = maxD.difference(minD).inDays + 1;

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LSectionTitle(p: p, title: '时间线（甘特图）'),
        const SizedBox(height: 6),
        Text(
          '滑动窗口：${_md(minD)} → ${_md(maxD)}（随日期自动滑动）'
          ' · 窗口内 ${all.length} 个比赛'
          '${endedCount > 0 ? ' · $endedCount 个已结束（灰色）' : ''}',
          style: TextStyle(fontSize: 11.5, color: p.muted),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _legend(p, p.dark ? const Color(0xFF31406B) : const Color(0xFFC7D2FE), '准备期'),
          _legend(p, p.dark ? const Color(0xFF6366F1) : const Color(0xFF6366F1), '提交期'),
          _legend(p, const Color(0xFFE11D48), '临期线（数字）'),
          _legend(p, const Color(0xFF1E293B), '官方截止（数字）'),
          _legend(p, const Color(0xFFF59E0B), '里程碑'),
          _legend(p, const Color(0xFFE11D48), '今天'),
          _legend(p, dark ? const Color(0xFF475569) : const Color(0xFF94A3B8), '已结束（灰色）'),
        ]),
        const SizedBox(height: 10),
        LCard(
          padding: EdgeInsets.zero,
          child: SizedBox(
            height: all.isEmpty
                ? 120
                : all.length * _rowH + _headerH + 2,
            child: all.isEmpty
                ? Center(
                    child: Text('窗口内没有进行中的比赛',
                        style: TextStyle(fontSize: 13, color: p.muted)))
                : Row(children: [
                    SizedBox(
                      width: _labelW,
                      child: Column(children: [
                        SizedBox(height: _headerH),
                        for (final c in all)
                          SizedBox(
                            height: _rowH,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8, left: 12),
                                child: Tooltip(
                                  message: c.name,
                                  child: Text(c.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 11, color: p.text)),
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ),
                    Container(width: 1, color: p.hairline),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: totalDays * _pxPerDay,
                          height: all.length * _rowH + _headerH,
                          child: CustomPaint(
                            painter: _LegacyGanttPainter(
                              comps: all,
                              minDay: minD,
                              totalDays: totalDays,
                              now: now,
                              dark: p.dark,
                            ),
                            child: Column(children: [
                              SizedBox(height: _headerH),
                              for (final c in all)
                                GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTap: () => onOpenDrawer(c.id),
                                  child: SizedBox(
                                    width: totalDays * _pxPerDay,
                                    height: _rowH,
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
        const SizedBox(height: 6),
        Text('条形左浅=准备期、右深=提交期；▼ 临期线 · ◆ 官方截止 · ● 里程碑 · 红虚线=今天 · 点击条形行打开详情',
            style: TextStyle(fontSize: 10.5, color: p.muted)),
        const SizedBox(height: 18),
        LSectionTitle(p: p, title: '图表分析'),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _countdownRanking(context, now)),
          const SizedBox(width: 14),
          Expanded(child: _weeklyBars(context, now)),
        ]),
      ]),
    );
  }

  Widget _legend(LegacyPalette p, Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 12,
          height: 8,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 10.5, color: p.muted)),
    ]);
  }

  String _md(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  Widget _countdownRanking(BuildContext context, DateTime now) {
    final items = visible
        .where((c) =>
            c.status(now) != 'submitted' &&
            c.status(now) != 'done' &&
            c.status(now) != 'abandoned')
        .toList()
      ..sort((a, b) => a.countdown(now).compareTo(b.countdown(now)));
    final top = items.take(15).toList();
    return LCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('⏳ 倒计时排行',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
        const SizedBox(height: 10),
        if (top.isEmpty)
          Text('暂无', style: TextStyle(fontSize: 12.5, color: p.muted))
        else
          ...top.map((c) {
            final d = c.countdown(now);
            final grad = d <= 3
                ? LegacyTokens.cdToday
                : d <= 7
                    ? LegacyTokens.cdUrgent
                    : d <= 30
                        ? LegacyTokens.cdSoon
                        : LegacyTokens.cdCalm;
            final ratio = (1 - (d / 90)).clamp(0.12, 1.0);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GestureDetector(
                onTap: () => onOpenDrawer(c.id),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: p.text)),
                    ),
                    Text(d < 0 ? '已过 ${-d} 天' : '剩 $d 天',
                        style: lMono(11, color: p.text)),
                  ]),
                  const SizedBox(height: 3),
                  ClipRRect(
                    borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(6)),
                    child: Container(
                      height: 7,
                      width: double.infinity,
                      color: p.dark
                          ? Colors.white.withValues(alpha: 0.05)
                          : const Color(0xFFF1F3F7),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: ratio,
                        child: Container(
                            decoration: BoxDecoration(
                                gradient: LinearGradient(colors: grad))),
                      ),
                    ),
                  ),
                ]),
              ),
            );
          }),
      ]),
    );
  }

  Widget _weeklyBars(BuildContext context, DateTime now) {
    final buckets = List<int>.filled(12, 0);
    for (final c in visible) {
      final s = c.status(now);
      if (s == 'submitted' || s == 'done' || s == 'abandoned') continue;
      final d = c.countdown(now);
      if (d < 1) continue;
      final b = (d - 1) ~/ 7;
      if (b < 12) buckets[b]++;
    }
    final maxV = buckets.fold<int>(1, (a, b) => b > a ? b : a);
    return LCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📊 到期分布（按周，临期线口径）',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text)),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
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
                                style: TextStyle(fontSize: 10, color: p.muted)),
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
      ]),
    );
  }
}

class _LegacyGanttPainter extends CustomPainter {
  _LegacyGanttPainter({
    required this.comps,
    required this.minDay,
    required this.totalDays,
    required this.now,
    required this.dark,
  });

  final List<Competition> comps;
  final DateTime minDay;
  final int totalDays;
  final DateTime now;
  final bool dark;

  static const double _pxPerDay = LegacyTimeline._pxPerDay;
  static const double _rowH = LegacyTimeline._rowH;
  static const double _headerH = LegacyTimeline._headerH;

  double _x(DateTime d) => d.difference(minDay).inDays * _pxPerDay;

  @override
  void paint(Canvas canvas, Size size) {
    // 网格（每 7 天）
    final gridPaint = Paint()
      ..color = (dark ? const Color(0xFF2E323A) : const Color(0xFFE6E8EF))
      ..strokeWidth = 1;
    for (var d = 0; d <= totalDays; d += 7) {
      final x = d * _pxPerDay;
      canvas.drawLine(Offset(x, _headerH - 4),
          Offset(x, _headerH + comps.length * _rowH), gridPaint);
      final day = minDay.add(Duration(days: d));
      _text(canvas, '${day.month}/${day.day}', Offset(x + 2, _headerH - 16),
          const Color(0xFF94A3B8), 9);
    }
    // 今天红虚线
    final tx = _x(now) + _pxPerDay / 2;
    final redPaint = Paint()
      ..color = const Color(0xFFE11D48)
      ..strokeWidth = 1.3;
    var y = _headerH - 6;
    while (y < _headerH + comps.length * _rowH) {
      canvas.drawLine(Offset(tx, y), Offset(tx, y + 4), redPaint);
      y += 9;
    }
    // 行
    for (var i = 0; i < comps.length; i++) {
      _paintRow(canvas, i, comps[i]);
    }
  }

  void _paintRow(Canvas canvas, int index, Competition c) {
    final yTop = _headerH + index * _rowH + 6;
    final barH = _rowH - 12;
    final r = Radius.circular(4);
    final sugg = c.effectiveSuggested();
    final prepStart = c.signupStart ?? sugg.subtract(const Duration(days: 14));
    // 准备期（浅 indigo）
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(
          Offset(_x(prepStart) + _pxPerDay / 2, yTop),
          Offset(_x(sugg) + _pxPerDay / 2, yTop + barH),
        ),
        r,
      ),
      Paint()
        ..color = (dark ? const Color(0xFF31406B) : const Color(0xFFC7D2FE)),
    );
    // 提交期（深 indigo）
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(
          Offset(_x(sugg) + _pxPerDay / 2, yTop),
          Offset(_x(c.deadline) + _pxPerDay / 2, yTop + barH),
        ),
        r,
      ),
      Paint()..color = const Color(0xFF6366F1),
    );
    // 里程碑橙点
    final cy = yTop + barH / 2;
    for (final m in c.milestones) {
      canvas.drawCircle(Offset(_x(m.date) + _pxPerDay / 2, cy), 3,
          Paint()..color = const Color(0xFFF59E0B));
    }
    // 官方截止深方块 + 日期
    final ex = _x(c.deadline) + _pxPerDay / 2;
    canvas.drawRect(
        Rect.fromCenter(center: Offset(ex, cy), width: 6, height: 6),
        Paint()..color = dark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B));
    _text(canvas, _md(c.deadline), Offset(ex + 5, cy - 6),
        dark ? const Color(0xFF94A3B8) : const Color(0xFF475569), 9);
    // 临期线红 ▼ + 日期
    final sx = _x(sugg) + _pxPerDay / 2;
    final tri = Path()
      ..moveTo(sx - 4, yTop - 5)
      ..lineTo(sx + 4, yTop - 5)
      ..lineTo(sx, yTop + 1)
      ..close();
    canvas.drawPath(tri, Paint()..color = const Color(0xFFE11D48));
    _text(canvas, _md(sugg), Offset(sx + 6, yTop - 13),
        const Color(0xFFE11D48), 9);
  }

  void _text(Canvas canvas, String s, Offset at, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  String _md(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  @override
  bool shouldRepaint(covariant _LegacyGanttPainter old) =>
      old.comps != comps || old.minDay != minDay;
}
