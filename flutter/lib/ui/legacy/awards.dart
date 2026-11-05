/// 旧版界面 · 获奖管理：5 统计卡 + 工具栏（搜索/级别/只看一作/全部展开折叠）
/// + 分组（组头 + 组内表格：奖项/级别/奖项等级/作者/获奖日期/凭证/操作）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../domain/classification.dart';
import '../../domain/rules.dart';
import '../../state/providers.dart';
import 'tokens.dart';
import 'widgets.dart';

class LegacyAwards extends ConsumerStatefulWidget {
  const LegacyAwards({
    super.key,
    required this.p,
    required this.onOpenDrawer,
    required this.onEdit,
  });

  final LegacyPalette p;
  final ValueChanged<String> onOpenDrawer;
  final ValueChanged<Award> onEdit;

  @override
  ConsumerState<LegacyAwards> createState() => _LegacyAwardsState();
}

class _LegacyAwardsState extends ConsumerState<LegacyAwards> {
  final _searchCtrl = TextEditingController();
  String _level = '';
  bool _firstOnly = false;
  final Set<String> _closedGroups = {};
  bool _allOpen = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final lib = ref.watch(libraryProvider);
    final stats = lib.awardStats;

    var awards = lib.awards;
    if (_level.isNotEmpty) {
      awards = awards.where((a) => a.level == _level).toList();
    }
    if (_firstOnly) awards = awards.where((a) => a.isFirstAuthor).toList();
    final kw = _searchCtrl.text.trim().toLowerCase();
    if (kw.isNotEmpty) {
      awards = awards
          .where((a) =>
              a.name.toLowerCase().contains(kw) ||
              a.competition.toLowerCase().contains(kw) ||
              a.notes.toLowerCase().contains(kw) ||
              a.awardRank.toLowerCase().contains(kw))
          .toList();
    }

    // 分组（按关联比赛，组大小降序，与原版一致）
    final groups = <String, List<Award>>{};
    for (final a in awards) {
      groups.putIfAbsent(awardGroup(a, ref.watch(awardGroupingProvider)), () => []).add(a);
    }
    final keys = groups.keys.toList()
      ..sort((x, y) => groups[y]!.length.compareTo(groups[x]!.length));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 标题 + 添加
      Row(children: [
        Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
                color: p.primary, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text('获奖管理',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
        const SizedBox(width: 6),
        Text('${stats.total} 条', style: TextStyle(fontSize: 12, color: p.muted)),
        const Spacer(),
        LButton(
            label: '＋ 添加获奖',
            kind: LBtnKind.primary,
            onPressed: () =>
                widget.onEdit(Award(id: '', name: ''))),
      ]),
      const SizedBox(height: 12),
      // 5 统计卡
      Row(children: [
        Expanded(child: _statCard(context, Icons.emoji_events_outlined,
            const Color(0xFFB45309), const Color(0xFFFDEFD9),
            '${stats.total}', '全部获奖')),
        const SizedBox(width: 10),
        Expanded(child: _statCard(context, Icons.public,
            const Color(0xFF4338CA), const Color(0xFFE5E7FC),
            '${stats.byLevel['国家级'] ?? 0}', '国家级')),
        const SizedBox(width: 10),
        Expanded(child: _statCard(context, Icons.workspace_premium_outlined,
            const Color(0xFF7C3AED), const Color(0xFFF5F3FF),
            '${stats.byLevel['省级'] ?? 0}', '省级')),
        const SizedBox(width: 10),
        Expanded(child: _statCard(context, Icons.school_outlined,
            const Color(0xFF475569), const Color(0xFFEBEEF3),
            '${stats.byLevel['校级'] ?? 0}', '校级')),
        const SizedBox(width: 10),
        Expanded(child: _statCard(context, Icons.edit_outlined,
            const Color(0xFFBE123C), const Color(0xFFFCE3E1),
            '${stats.firstAuthor}', '一作 / 独立')),
      ]),
      const SizedBox(height: 12),
      // 分类维度
      DropdownButton<AwardGrouping>(
    value: ref.watch(awardGroupingProvider),
    items: [for (final g in AwardGrouping.values)
      DropdownMenuItem(value: g, child: Text('按${awardGroupingLabels[g]}'))],
    onChanged: (g) { if (g != null) ref.read(awardGroupingProvider.notifier).select(g); },
  ),
      // 工具栏
      Row(children: [
        SizedBox(
          width: 220,
          child: TextField(
            controller: _searchCtrl,
            style: TextStyle(fontSize: 13, color: p.text),
            decoration: lInputDeco(p, '搜奖项/比赛/备注…',
                prefixIcon: Icon(Icons.search, size: 17, color: p.muted)),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.hairline),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _level,
              isDense: true,
              style: TextStyle(fontSize: 12.5, color: p.text),
              dropdownColor: p.card,
              borderRadius: BorderRadius.circular(12),
              items: [
                const DropdownMenuItem(value: '', child: Text('全部级别')),
                for (final l in validAwardLevels)
                  DropdownMenuItem(value: l, child: Text(l)),
              ],
              onChanged: (v) => setState(() => _level = v ?? ''),
            ),
          ),
        ),
        const SizedBox(width: 10),
        InkWell(
          onTap: () => setState(() => _firstOnly = !_firstOnly),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              Icon(
                _firstOnly
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                size: 17,
                color: _firstOnly ? p.primary : p.muted,
              ),
              const SizedBox(width: 6),
              Text('只看一作/独立',
                  style: TextStyle(fontSize: 12.5, color: p.text)),
            ]),
          ),
        ),
        const Spacer(),
        LButton(
            label: '⊞ 全部展开',
            dense: true,
            onPressed: () => setState(() {
                  _allOpen = true;
                  _closedGroups.clear();
                })),
        const SizedBox(width: 8),
        LButton(
            label: '⊟ 全部折叠',
            dense: true,
            onPressed: () => setState(() {
                  _allOpen = false;
                  for (final k in keys) {
                    _closedGroups.add(k);
                  }
                })),
      ]),
      const SizedBox(height: 12),
      // 分组
      Expanded(
        child: groups.isEmpty
            ? Center(
                child: Text(awards.isEmpty && lib.awardStats.total == 0
                    ? '还没有获奖记录'
                    : '没有符合条件的获奖记录',
                    style: TextStyle(fontSize: 13, color: p.muted)))
            : SingleChildScrollView(
                child: Column(children: [
                  for (final key in keys)
                    _group(context, key, groups[key]!),
                ]),
              ),
      ),
    ]);
  }

  Widget _statCard(BuildContext context, IconData icon, Color iconColor,
      Color iconBg, String value, String label) {
    final p = widget.p;
    return LCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: p.text,
                  fontFamily: 'Segoe UI',
                  fontFamilyFallback: LegacyTokens.monoFallback)),
          Text(label, style: TextStyle(fontSize: 11, color: p.muted)),
        ]),
      ]),
    );
  }

  Widget _group(BuildContext context, String key, List<Award> items) {
    final p = widget.p;
    final open = _allOpen || !_closedGroups.contains(key);
    final firstCnt = items.where((a) => a.isFirstAuthor).length;
    final levels = <String, int>{};
    for (final a in items) {
      levels[a.level] = (levels[a.level] ?? 0) + 1;
    }
    final levelsText = levels.entries.map((e) => '${e.key}×${e.value}').join(' · ');
    final dates = items.where((a) => a.awardDate != null).map((a) => a.awardDate!);
    final latest = dates.isEmpty
        ? ''
        : '${dates.reduce((a, b) => a.isAfter(b) ? a : b).month.toString().padLeft(2, '0')}/'
            '${dates.reduce((a, b) => a.isAfter(b) ? a : b).day.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          // 组头
          InkWell(
            onTap: () => setState(() {
              open ? _closedGroups.add(key) : _closedGroups.remove(key);
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                AnimatedRotation(
                  turns: open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_more, size: 17, color: p.muted),
                ),
                const SizedBox(width: 6),
                Icon(Icons.link, size: 14, color: p.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: p.text)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: p.dark
                        ? const Color(0xFF27306B)
                        : const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${items.length} 条',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: p.dark
                              ? const Color(0xFFA5B4FC)
                              : const Color(0xFF4F46E5))),
                ),
                if (firstCnt > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: p.dark
                          ? const Color(0xFF453011)
                          : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('✍️ 一作 $firstCnt',
                        style: TextStyle(
                            fontSize: 10.5,
                            color: p.dark
                                ? const Color(0xFFFCD34D)
                                : const Color(0xFFD97706))),
                  ),
                ],
                if (levelsText.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(levelsText,
                      style: TextStyle(fontSize: 11, color: p.muted)),
                ],
                const SizedBox(width: 8),
                Text(latest,
                    style: lMono(11, color: p.muted, weight: FontWeight.w400)),
              ]),
            ),
          ),
          if (open) ...[
            Divider(height: 1, color: p.hairline),
            // 组内表格头
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(children: [
                Expanded(flex: 34, child: _th(p, '奖项')),
                Expanded(flex: 10, child: _th(p, '级别')),
                Expanded(flex: 14, child: _th(p, '奖项等级')),
                Expanded(flex: 12, child: _th(p, '作者')),
                Expanded(flex: 12, child: _th(p, '获奖日期')),
                Expanded(flex: 10, child: _th(p, '凭证')),
                SizedBox(width: 104, child: _th(p, '操作')),
              ]),
            ),
            for (final a in items) _awardRow(context, a),
          ],
        ]),
      ),
    );
  }

  Widget _th(LegacyPalette p, String text) => Text(text,
      style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: p.muted));

  Widget _awardRow(BuildContext context, Award a) {
    final p = widget.p;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.hairline.withValues(alpha: 0.6))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Expanded(
          flex: 34,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
            if (a.notes.isNotEmpty)
              Text(a.notes,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: p.muted)),
          ]),
        ),
        Expanded(
          flex: 10,
          child: LStatusBadge(p: p, status: a.level == '国家级'
              ? 'submitting' // 级别复用 chip 视觉：国家级 indigo
              : a.level == '省级'
                  ? 'done'
                  : a.level == '市级'
                      ? 'open'
                      : 'not_started'),
        ),
        Expanded(
          flex: 14,
          child: Text(a.awardRank.isEmpty ? '—' : a.awardRank,
              style: TextStyle(fontSize: 12.5, color: p.text)),
        ),
        Expanded(
          flex: 12,
          child: a.isFirstAuthor
              ? Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: p.dark
                        ? const Color(0xFF453011)
                        : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: p.dark
                            ? const Color(0xFF6B5518)
                            : const Color(0xFFE7D8A8)),
                  ),
                  child: Text('✍️ 一作',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: p.dark
                              ? const Color(0xFFFCD34D)
                              : const Color(0xFFD97706))),
                )
              : Text(a.role.isEmpty ? '参与' : a.role,
                  style: TextStyle(fontSize: 11.5, color: p.muted)),
        ),
        Expanded(
          flex: 12,
          child: Text(dateIso(a.awardDate) ?? '—',
              style: lMono(12, color: p.text, weight: FontWeight.w400)),
        ),
        Expanded(
          flex: 10,
          child: a.certificateFiles.isEmpty
              ? Text('无', style: TextStyle(fontSize: 11.5, color: p.muted))
              : Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: p.dark
                        ? const Color(0xFF0B3B2E)
                        : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('📎 ${a.certificateFiles.length} 个',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: p.dark
                              ? const Color(0xFF6EE7B7)
                              : const Color(0xFF059669))),
                ),
        ),
        SizedBox(
          width: 104,
          child: Row(children: [
            LButton(
                label: '详情',
                dense: true,
                onPressed: () => widget.onOpenDrawer(a.id)),
            const SizedBox(width: 6),
            LButton(label: '编辑', dense: true, onPressed: () => widget.onEdit(a)),
          ]),
        ),
      ]),
    );
  }
}
