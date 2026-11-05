/// 总览统计：移植旧版 core.js computeStats（口径一致，测试固化）。
library;

import 'models.dart';
import 'rules.dart';

class UpcomingItem {
  UpcomingItem(this.comp, this.days);
  final Competition comp;
  final int days;
}

class MonthCount {
  MonthCount(this.month, this.count);
  final String month; // YYYY-MM
  final int count;
}

class Stats {
  Stats({
    required this.total,
    required this.byStatus,
    required this.byCategory,
    required this.upcoming,
    required this.dueIn7,
    required this.dueIn30,
    required this.completed,
    required this.weeks,
    required this.months,
  });

  final int total;
  final Map<String, int> byStatus;
  final Map<String, int> byCategory;
  final List<UpcomingItem> upcoming; // 按剩余天数升序
  final int dueIn7;
  final int dueIn30;
  final int completed; // submitted + done
  final List<int> weeks; // 未来 12 周各周临期数
  final List<MonthCount> months; // 未来 6 个月各月临期数

  int activeCount() =>
      total - (byStatus['submitted'] ?? 0) - (byStatus['done'] ?? 0) - (byStatus['abandoned'] ?? 0);
}

/// 与旧版一致：已提交/已完成/已放弃/已截止之外、临期线在今天及以后的记录
/// 计入 upcoming（上限 30 条）；weekly 按整周数分桶（0–11），monthly 按 YYYY-MM（0–5）。
Stats computeStats(List<Competition> comps, [DateTime? todayDate]) {
  final now = todayDate ?? today();
  final byStatus = <String, int>{};
  final byCategory = <String, int>{};
  final weekly = <int, int>{};
  final monthly = <String, int>{};
  final upcoming = <UpcomingItem>[];
  var completed = 0;

  for (final c in comps) {
    final s = c.status(now);
    byStatus[s] = (byStatus[s] ?? 0) + 1;
    if (s == 'submitted' || s == 'done') completed++;
    final cat = c.category.isEmpty ? '未分类' : c.category;
    byCategory[cat] = (byCategory[cat] ?? 0) + 1;
    const finished = {'submitted', 'done', 'abandoned', 'overdue'};
    if (!finished.contains(s)) {
      final d = c.effectiveSuggested();
      if (!d.isBefore(now)) {
        upcoming.add(UpcomingItem(c, daysBetween(d, now)));
        final wk = (daysBetween(d, now) / 7).floor();
        weekly[wk] = (weekly[wk] ?? 0) + 1;
        final ym = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
        monthly[ym] = (monthly[ym] ?? 0) + 1;
      }
    }
  }
  upcoming.sort((a, b) => a.days.compareTo(b.days));
  final weeks = List<int>.generate(12, (i) => weekly[i] ?? 0);
  final months = <MonthCount>[];
  for (var i = 0; i < 6; i++) {
    final m = DateTime(now.year, now.month + i);
    final ym = '${m.year.toString().padLeft(4, '0')}-${m.month.toString().padLeft(2, '0')}';
    months.add(MonthCount(ym, monthly[ym] ?? 0));
  }
  return Stats(
    total: comps.length,
    byStatus: byStatus,
    byCategory: byCategory,
    upcoming: upcoming.take(30).toList(),
    dueIn7: upcoming.where((u) => u.days <= 7).length,
    dueIn30: upcoming.where((u) => u.days <= 30).length,
    completed: completed,
    weeks: weeks,
    months: months,
  );
}

/// 获奖统计：总数、各级别数量、一作数量（旧版 stats 口径）。
class AwardStats {
  AwardStats({required this.total, required this.byLevel, required this.firstAuthor});
  final int total;
  final Map<String, int> byLevel;
  final int firstAuthor;
}

AwardStats computeAwardStats(List<Award> awards) {
  final byLevel = <String, int>{};
  var first = 0;
  for (final a in awards) {
    byLevel[a.level] = (byLevel[a.level] ?? 0) + 1;
    if (a.isFirstAuthor) first++;
  }
  return AwardStats(total: awards.length, byLevel: byLevel, firstAuthor: first);
}
