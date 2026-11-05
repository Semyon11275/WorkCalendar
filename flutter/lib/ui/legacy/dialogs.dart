/// 旧版界面 · 编辑弹窗：居中限定宽度（≈640px）模态，双列日期行，
/// 内部滚动，底部取消/保存。字段顺序对齐原版 openForm。
library;

import 'package:flutter/material.dart';
import '../direction_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../../state/providers.dart';
import '../widgets.dart' show appToast;
import 'widgets.dart';

class LegacyCompDialog extends ConsumerStatefulWidget {
  const LegacyCompDialog({super.key, this.existing, required this.palette});
  final Competition? existing;
  final LegacyPalette palette;

  @override
  ConsumerState<LegacyCompDialog> createState() => _LegacyCompDialogState();
}

class _LegacyCompDialogState extends ConsumerState<LegacyCompDialog> {
  late final TextEditingController _name;
  late final TextEditingController _organizer;
  late final TextEditingController _website;
  Set<String> _directions = {};
  late final TextEditingController _category;
  late final TextEditingController _bufferDays;
  late final TextEditingController _deadlineNote;
  late final TextEditingController _requirements;
  late final TextEditingController _deliverables;
  late final TextEditingController _milestones;
  late final TextEditingController _subMethod;
  late final TextEditingController _subTarget;
  late final TextEditingController _subContact;
  late final TextEditingController _subFee;
  late final TextEditingController _fmtTypes;
  late final TextEditingController _fmtSize;
  late final TextEditingController _fmtNaming;
  late final TextEditingController _tags;
  late final TextEditingController _notes;
  DateTime? _deadline;
  DateTime? _suggested;
  DateTime? _signupStart;
  DateTime? _signupEnd;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _organizer = TextEditingController(text: c?.organizer ?? '');
    _website = TextEditingController(text: c?.website ?? '');
    _category = TextEditingController(text: c?.category ?? '');
    _directions = (c?.extra['directions'] as List? ?? []).map((v)=>'$v').toSet();
    _bufferDays = TextEditingController(text: c?.deadlineBufferDays?.toString() ?? '');
    _deadlineNote = TextEditingController(text: c?.deadlineNote ?? '');
    _requirements = TextEditingController(text: c?.requirements ?? '');
    _deliverables = TextEditingController(
        text: c?.deliverables.map((d) => '$d').join('\n') ?? '');
    _milestones = TextEditingController(
        text: c?.milestones
                .map((m) => '${m.name}:${dateIso(m.date)}')
                .join('\n') ??
            '');
    _subMethod = TextEditingController(text: '${c?.submission['method'] ?? ''}');
    _subTarget = TextEditingController(text: '${c?.submission['target'] ?? ''}');
    _subContact =
        TextEditingController(text: '${c?.submission['contact'] ?? ''}');
    _subFee = TextEditingController(text: '${c?.submission['fee'] ?? ''}');
    _fmtTypes = TextEditingController(
        text: (c?.format['file_types'] as List? ?? []).join(', '));
    _fmtSize =
        TextEditingController(text: c?.format['max_size_mb']?.toString() ?? '');
    _fmtNaming =
        TextEditingController(text: '${c?.format['naming'] ?? ''}');
    _tags =
        TextEditingController(text: c?.tags.map((t) => '$t').join(', ') ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
    _deadline = c?.deadline;
    _suggested = c?.suggestedDeadline;
    _signupStart = c?.signupStart;
    _signupEnd = c?.signupEnd;
  }

  @override
  void dispose() {
    for (final c in [
      _name, _organizer, _website, _category, _bufferDays,
      _deadlineNote, _requirements, _deliverables, _milestones,
      _subMethod, _subTarget, _subContact, _subFee,
      _fmtTypes, _fmtSize, _fmtNaming, _tags, _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _deadline == null) {
      appToast('比赛名称与官方截止为必填', error: true);
      return;
    }
    if (_suggested != null && _suggested!.isAfter(_deadline!)) {
      appToast('临期线不能晚于官方截止', error: true);
      return;
    }
    final c = widget.existing ??
        Competition(id: '', name: '', deadline: today());
    c.name = _name.text.trim();
    c.deadline = _deadline!;
    c.suggestedDeadline = _suggested;
    c.deadlineBufferDays = int.tryParse(_bufferDays.text.trim());
    c.category = _category.text.trim();
    if (_directions.isEmpty) { c.extra.remove('directions'); } else { c.extra['directions'] = _directions.toList(); }
    c.organizer = _organizer.text.trim();
    c.website = _website.text.trim();
    c.signupStart = _signupStart;
    c.signupEnd = _signupEnd;
    c.deadlineNote = _deadlineNote.text.trim();
    c.requirements = _requirements.text.trim();
    c.deliverables = [
      for (final l in _deliverables.text.split('\n'))
        if (l.trim().isNotEmpty) l.trim(),
    ];
    // 里程碑：每行「名称:日期」（原版同格式）
    c.milestones = [
      for (final l in _milestones.text.split('\n'))
        if (l.trim().isNotEmpty)
          Milestone(
            name: l.split(':').first.trim(),
            date: parseDate(
                    l.contains(':') ? l.substring(l.indexOf(':') + 1).trim() : '') ??
                today(),
          ),
    ];
    c.submission = {
      'method': _subMethod.text.trim(),
      'target': _subTarget.text.trim(),
      'contact': _subContact.text.trim(),
      'fee': _subFee.text.trim(),
    };
    c.format = {
      'file_types': [
        for (final t in _fmtTypes.text.split(','))
          if (t.trim().isNotEmpty) t.trim(),
      ],
      'max_size_mb': int.tryParse(_fmtSize.text.trim()),
      'naming': _fmtNaming.text.trim(),
    };
    c.tags = [
      for (final t in _tags.text.split(','))
        if (t.trim().isNotEmpty) t.trim(),
    ];
    c.notes = _notes.text.trim();
    if (widget.existing == null) {
      c.id = makeCompId(c.name, c.deadline);
      c.source = 'manual';
    }
    await ref.read(libraryProvider.notifier).saveComp(c);
    appToast('已保存「${c.name}」');
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Dialog(
      backgroundColor: p.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.hairline),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
            child: Row(children: [
              Text(widget.existing == null ? '＋ 添加比赛' : '✏️ 编辑比赛',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: p.primary)),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close, size: 20, color: p.muted),
              ),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label(p, '比赛名称 *'),
                TextField(
                  controller: _name,
                  style: TextStyle(fontSize: 13.5, color: p.text),
                  decoration: lInputDeco(p, '如：2026 中国包装创意设计大赛'),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _date(p, '官方截止 *', _deadline,
                      (d) => setState(() => _deadline = d))),
                  const SizedBox(width: 12),
                  Expanded(child: _date(p, '临期线（留空=自动缓冲）', _suggested,
                      (d) => setState(() => _suggested = d))),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _textField(p, '缓冲天数（默认 3）', _bufferDays,
                      number: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _textField(p, '类别', _category,
                      hint: '视觉传达 / 工业设计…')),
                ]),
                const SizedBox(height: 12),
                DirectionPicker(selected: _directions, onChanged: (v) => setState(() => _directions = v)),
                const SizedBox(height: 12),
                _textField(p, '主办方', _organizer),
                const SizedBox(height: 12),
                _textField(p, '官网链接', _website, hint: 'https://…'),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _date(p, '报名开始', _signupStart,
                      (d) => setState(() => _signupStart = d))),
                  const SizedBox(width: 12),
                  Expanded(child: _date(p, '报名结束', _signupEnd,
                      (d) => setState(() => _signupEnd = d))),
                ]),
                const SizedBox(height: 12),
                _label(p, '作品要求'),
                TextField(
                  controller: _requirements,
                  maxLines: 3,
                  style: TextStyle(fontSize: 13, color: p.text),
                  decoration: lInputDeco(p, ''),
                ),
                const SizedBox(height: 12),
                _label(p, '交付物（每行一个）'),
                TextField(
                  controller: _deliverables,
                  maxLines: 2,
                  style: TextStyle(fontSize: 13, color: p.text),
                  decoration: lInputDeco(p, '展板 JPG 1920×1080 ×1'),
                ),
                const SizedBox(height: 12),
                _label(p, '里程碑（每行「名称:日期」）'),
                TextField(
                  controller: _milestones,
                  maxLines: 2,
                  style: TextStyle(fontSize: 13, color: p.text),
                  decoration: lInputDeco(p, '校内初评:2026-11-01'),
                ),
                const SizedBox(height: 12),
                _section(p, '📮 投稿方式'),
                _textField(p, '方式', _subMethod),
                const SizedBox(height: 8),
                _textField(p, '入口', _subTarget),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _textField(p, '联系', _subContact)),
                  const SizedBox(width: 12),
                  Expanded(child: _textField(p, '费用', _subFee)),
                ]),
                const SizedBox(height: 12),
                _section(p, '📐 格式'),
                Row(children: [
                  Expanded(
                      child: _textField(p, '类型（逗号分隔）', _fmtTypes)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _textField(p, '上限 MB', _fmtSize, number: true)),
                ]),
                const SizedBox(height: 8),
                _textField(p, '命名规则', _fmtNaming),
                const SizedBox(height: 12),
                _textField(p, '标签（逗号分隔）', _tags),
                const SizedBox(height: 12),
                _textField(p, '截止说明', _deadlineNote),
                const SizedBox(height: 12),
                _label(p, '备注'),
                TextField(
                  controller: _notes,
                  maxLines: 2,
                  style: TextStyle(fontSize: 13, color: p.text),
                  decoration: lInputDeco(p, ''),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
            child: Row(children: [
              const Spacer(),
              LButton(label: '取消', onPressed: () => Navigator.pop(context)),
              const SizedBox(width: 10),
              LButton(label: '💾 保存', kind: LBtnKind.primary, onPressed: _save),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _label(LegacyPalette p, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: p.text)),
    );
  }

  Widget _section(LegacyPalette p, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
      child: Row(children: [
        Container(
            width: 4,
            height: 13,
            decoration: BoxDecoration(
                color: p.primary, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
      ]),
    );
  }

  Widget _textField(LegacyPalette p, String label, TextEditingController ctrl,
      {bool number = false, String hint = ''}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(p, label),
      TextField(
        controller: ctrl,
        keyboardType: number ? TextInputType.number : null,
        style: TextStyle(fontSize: 13.5, color: p.text),
        decoration: lInputDeco(p, hint),
      ),
    ]);
  }

  Widget _date(LegacyPalette p, String label, DateTime? value,
      ValueChanged<DateTime?> onPick) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(p, label),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final now = today();
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? now,
            firstDate: DateTime(now.year - 5),
            lastDate: DateTime(now.year + 10),
          );
          if (picked != null) onPick(picked);
        },
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.hairline),
          ),
          child: Row(children: [
            Expanded(
              child: Text(
                value == null ? '年 / 月 / 日' : dateIso(value)!,
                style: value == null
                    ? TextStyle(fontSize: 13, color: p.muted.withValues(alpha: 0.7))
                    : lMono(13, color: p.text),
              ),
            ),
            Icon(Icons.calendar_today, size: 14, color: p.muted),
          ]),
        ),
      ),
    ]);
  }
}

class LegacyAwardDialog extends ConsumerStatefulWidget {
  const LegacyAwardDialog({super.key, this.existing, required this.palette});
  final Award? existing;
  final LegacyPalette palette;

  @override
  ConsumerState<LegacyAwardDialog> createState() => _LegacyAwardDialogState();
}

class _LegacyAwardDialogState extends ConsumerState<LegacyAwardDialog> {
  late final TextEditingController _name;
  late final TextEditingController _rank;
  late final TextEditingController _role;
  late final TextEditingController _competition;
  late final TextEditingController _notes;
  DateTime? _date;
  String _level = '校级';
  bool _first = false;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _name = TextEditingController(text: a?.name ?? '');
    _rank = TextEditingController(text: a?.awardRank ?? '');
    _role = TextEditingController(text: a?.role ?? '');
    _competition = TextEditingController(text: a?.competition ?? '');
    _notes = TextEditingController(text: a?.notes ?? '');
    _date = a?.awardDate;
    _level = a?.level ?? '校级';
    _first = a?.isFirstAuthor ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _rank.dispose();
    _role.dispose();
    _competition.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      appToast('奖项名称必填', error: true);
      return;
    }
    final a = widget.existing ??
        Award(id: makeAwardId(_name.text.trim(), _date), name: _name.text.trim());
    a.name = _name.text.trim();
    a.level = _level;
    a.awardRank = _rank.text.trim();
    a.isFirstAuthor = _first;
    a.role = _role.text.trim();
    a.competition = _competition.text.trim();
    a.awardDate = _date;
    a.notes = _notes.text.trim();
    await ref.read(libraryProvider.notifier).saveAward(a);
    appToast('已保存「${a.name}」');
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final compNames = ref
        .watch(libraryProvider)
        .comps
        .map((c) => c.name)
        .toList();
    return Dialog(
      backgroundColor: p.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.hairline),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
            child: Row(children: [
              Text(widget.existing == null ? '＋ 添加获奖' : '✏️ 编辑获奖',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: p.primary)),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close, size: 20, color: p.muted),
              ),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label(p, '奖项名称 *'),
                TextField(
                  controller: _name,
                  style: TextStyle(fontSize: 13.5, color: p.text),
                  decoration: lInputDeco(p, '如：全国大学生广告艺术大赛 省级一等奖'),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _label(p, '级别'),
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
                            style: TextStyle(fontSize: 13, color: p.text),
                            dropdownColor: p.card,
                            borderRadius: BorderRadius.circular(12),
                            items: [
                              for (final l in validAwardLevels)
                                DropdownMenuItem(value: l, child: Text(l)),
                            ],
                            onChanged: (v) => setState(() => _level = v ?? '校级'),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _textField(p, '奖项等级', _rank,
                      hint: '一等奖 / 金奖…')),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _label(p, '获奖日期'),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          final now = today();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date ?? now,
                            firstDate: DateTime(now.year - 30),
                            lastDate: DateTime(now.year + 1),
                          );
                          if (picked != null) setState(() => _date = picked);
                        },
                        child: Container(
                          height: 38,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: p.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: p.hairline),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: Text(
                                _date == null ? '年 / 月 / 日' : dateIso(_date)!,
                                style: _date == null
                                    ? TextStyle(
                                        fontSize: 13,
                                        color: p.muted.withValues(alpha: 0.7))
                                    : lMono(13, color: p.text),
                              ),
                            ),
                            Icon(Icons.calendar_today,
                                size: 14, color: p.muted),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _textField(p, '作者角色', _role,
                      hint: '队长 / 参与…')),
                ]),
                const SizedBox(height: 12),
                _label(p, '关联比赛（自由文本）'),
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: _competition.text),
                  optionsBuilder: (v) => v.text.isEmpty
                      ? const Iterable.empty()
                      : compNames.where((n) => n.contains(v.text)),
                  onSelected: (s) => setState(() => _competition.text = s),
                  fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextField(
                    controller: ctrl,
                    focusNode: focus,
                    onChanged: (v) => _competition.text = v,
                    style: TextStyle(fontSize: 13.5, color: p.text),
                    decoration: lInputDeco(p, '开始输入可联想已有比赛'),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _first,
                  onChanged: (v) => setState(() => _first = v ?? false),
                  title: Text('✍️ 一作 / 独立完成',
                      style: TextStyle(fontSize: 13, color: p.text)),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                _label(p, '备注'),
                TextField(
                  controller: _notes,
                  maxLines: 2,
                  style: TextStyle(fontSize: 13, color: p.text),
                  decoration: lInputDeco(p, ''),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
            child: Row(children: [
              const Spacer(),
              LButton(label: '取消', onPressed: () => Navigator.pop(context)),
              const SizedBox(width: 10),
              LButton(label: '💾 保存', kind: LBtnKind.primary, onPressed: _save),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _label(LegacyPalette p, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: p.text)),
    );
  }

  Widget _textField(LegacyPalette p, String label, TextEditingController ctrl,
      {String hint = ''}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(p, label),
      TextField(
        controller: ctrl,
        style: TextStyle(fontSize: 13.5, color: p.text),
        decoration: lInputDeco(p, hint),
      ),
    ]);
  }
}
