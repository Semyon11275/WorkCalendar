/// 旧版界面 · 列表：原版列结构（名称+里程碑副行 / 类别 / 临期线(官方副行) /
/// 官方截止 / 倒计时 / 状态 / 操作[详情·编辑]）、快捷 chips、排序切换。
library;

import 'package:flutter/material.dart';

import '../../domain/models.dart';
import 'widgets.dart';

class LegacyList extends StatefulWidget {
  const LegacyList({
    super.key,
    required this.p,
    required this.visible,
    required this.onOpenDrawer,
    required this.onEdit,
  });

  final LegacyPalette p;
  final List<Competition> visible;
  final ValueChanged<String> onOpenDrawer;
  final ValueChanged<Competition> onEdit;

  @override
  State<LegacyList> createState() => _LegacyListState();
}

enum _SortMode { deadline, name, added }

class _LegacyListState extends State<LegacyList> {
  LegacyPalette get p => widget.p;
  String _quick = ''; // '' 全部 | active 进行中 | overdue 已过期
  _SortMode _sort = _SortMode.deadline;
  bool _sortAsc = true;

  List<Competition> get _sorted {
    var out = widget.visible.toList();
    if (_quick == 'active') {
      out = out
          .where((c) =>
              c.status() != 'overdue' &&
              c.status() != 'submitted' &&
              c.status() != 'done' &&
              c.status() != 'abandoned')
          .toList();
    } else if (_quick == 'overdue') {
      out = out.where((c) => c.status() == 'overdue').toList();
    }
    switch (_sort) {
      case _SortMode.deadline:
        out.sort((a, b) => _sortAsc
            ? a.deadline.compareTo(b.deadline)
            : b.deadline.compareTo(a.deadline));
      case _SortMode.name:
        out.sort((a, b) => _sortAsc
            ? a.name.compareTo(b.name)
            : b.name.compareTo(a.name));
      case _SortMode.added:
        out.sort((a, b) => _sortAsc
            ? a.createdAt.compareTo(b.createdAt)
            : b.createdAt.compareTo(a.createdAt));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final rows = _sorted;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 标题 + 快捷 chips + 排序
      Row(children: [
        Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
                color: p.primary, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text('全部比赛',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
        const SizedBox(width: 6),
        Text('${rows.length} 条',
            style: TextStyle(fontSize: 12, color: p.muted)),
        const SizedBox(width: 14),
        _quickChip('全部', _quick == ''),
        _quickChip('🔥 进行中', _quick == 'active'),
        _quickChip('☠️ 已过期', _quick == 'overdue'),
        const Spacer(),
        InkWell(
          onTap: () => setState(() {
            if (_sort == _SortMode.deadline) {
              _sortAsc = !_sortAsc;
            } else {
              _sort = _SortMode.deadline;
              _sortAsc = true;
            }
          }),
          child: Text('截止 ${_sort == _SortMode.deadline && _sortAsc ? '↑' : (_sort == _SortMode.deadline ? '↓' : '')}',
              style: TextStyle(
                  fontSize: 12,
                  color: _sort == _SortMode.deadline ? p.primary : p.muted,
                  fontWeight: _sort == _SortMode.deadline
                      ? FontWeight.w700
                      : FontWeight.w400)),
        ),
        const SizedBox(width: 14),
        InkWell(
          onTap: () => setState(() => _sort = _SortMode.name),
          child: Text('名称',
              style: TextStyle(
                  fontSize: 12,
                  color: _sort == _SortMode.name ? p.primary : p.muted,
                  fontWeight:
                      _sort == _SortMode.name ? FontWeight.w700 : FontWeight.w400)),
        ),
        const SizedBox(width: 14),
        InkWell(
          onTap: () => setState(() => _sort = _SortMode.added),
          child: Text('添加',
              style: TextStyle(
                  fontSize: 12,
                  color: _sort == _SortMode.added ? p.primary : p.muted,
                  fontWeight:
                      _sort == _SortMode.added ? FontWeight.w700 : FontWeight.w400)),
        ),
      ]),
      const SizedBox(height: 8),
      // 表头
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: p.dark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFFAFAFC),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          border: Border.all(color: p.hairline),
        ),
        child: Row(children: [
          const SizedBox(width: 4),
          Expanded(flex: 42, child: _th('名称')),
          Expanded(flex: 10, child: _th('类别')),
          Expanded(flex: 14, child: _th('临期线')),
          Expanded(flex: 12, child: _th('官方截止')),
          Expanded(flex: 12, child: _th('倒计时')),
          Expanded(flex: 12, child: _th('状态')),
          SizedBox(width: 108, child: _th('操作')),
        ]),
      ),
      // 行
      Expanded(
        child: rows.isEmpty
            ? Center(
                child: Text('没有符合条件的比赛',
                    style: TextStyle(fontSize: 13, color: p.muted)))
            : Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: p.hairline),
                    right: BorderSide(color: p.hairline),
                    bottom: BorderSide(color: p.hairline),
                  ),
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(14)),
                ),
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => Divider(
                      height: 1, color: p.hairline.withValues(alpha: 0.6)),
                  itemBuilder: (context, i) => _row(context, rows[i]),
                ),
              ),
      ),
    ]);
  }

  Widget _th(String text) => Text(text,
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: p.muted));

  Widget _quickChip(String label, bool on) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() => _quick = on ? '' : label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: on ? p.primary.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: on ? p.primary.withValues(alpha: 0.5) : p.hairline),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                  color: on ? p.primary : p.muted)),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Competition c) {
    final p = widget.p;
    final sugg = c.effectiveSuggested();
    final ms = c.milestones.isEmpty
        ? (c.organizer.isNotEmpty ? c.organizer : '')
        : '⛳ ${c.milestones.map((m) => m.name).join('，')}';
    return InkWell(
      onTap: () => widget.onOpenDrawer(c.id),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: p.barColor(c), width: 4)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(children: [
          Expanded(
            flex: 42,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: p.text)),
              if (ms.isNotEmpty)
                Text(ms,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: p.muted)),
            ]),
          ),
          Expanded(flex: 10, child: LCatChip(p: p, category: c.category)),
          Expanded(
            flex: 14,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_md(sugg),
                  style: lMono(
                    13,
                    color: lSuggestedColor(c.countdown(), p),
                  )),
              Text(
                '官方 ${_md(c.deadline)}',
                style: TextStyle(fontSize: 10.5, color: p.muted),
              ),
            ]),
          ),
          Expanded(
            flex: 12,
            child: Text(
              _md(c.deadline),
              style: lMono(12.5, color: p.text, weight: FontWeight.w400),
            ),
          ),
          Expanded(flex: 12, child: LCountdownBadge(p: p, comp: c)),
          Expanded(flex: 12, child: LStatusBadge(p: p, status: c.status())),
          SizedBox(
            width: 108,
            child: Row(children: [
              LButton(
                  label: '详情',
                  dense: true,
                  onPressed: () => widget.onOpenDrawer(c.id)),
              const SizedBox(width: 6),
              LButton(
                  label: '编辑',
                  dense: true,
                  onPressed: () => widget.onEdit(c)),
            ]),
          ),
        ]),
      ),
    );
  }

  String _md(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}
