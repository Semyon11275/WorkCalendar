/// 比赛新建/编辑表单。校验规则与领域层一致：
/// name/deadline 必填；报名区间不得倒置；临期线不得晚于截止；里程碑不得晚于截止。
library;

import 'package:flutter/material.dart';
import 'direction_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../domain/rules.dart';
import '../state/providers.dart';
import 'widgets.dart';

class CompetitionEditPage extends ConsumerStatefulWidget {
  const CompetitionEditPage({super.key, this.existing});
  final Competition? existing;

  static Route<void> route({Competition? existing}) => MaterialPageRoute(
    builder: (_) => CompetitionEditPage(existing: existing),
  );

  @override
  ConsumerState<CompetitionEditPage> createState() =>
      _CompetitionEditPageState();
}

class _CompetitionEditPageState extends ConsumerState<CompetitionEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _organizer;
  late final TextEditingController _website;
  Set<String> _directions = {};
  late final TextEditingController _category;
  late final TextEditingController _tags;
  late final TextEditingController _deadlineNote;
  late final TextEditingController _requirements;
  late final TextEditingController _notes;
  late final TextEditingController _bufferDays;

  DateTime? _deadline;
  DateTime? _suggested;
  DateTime? _signupStart;
  DateTime? _signupEnd;
  String? _override;
  bool _useSuggested = false;
  List<(TextEditingController, DateTime?)> _milestones = [];

  final _formKey = GlobalKey<FormState>();
  String _initialSnapshot = '';
  bool _bypassPop = false; // 确认放弃后放行 pop

  bool get _dirty => _snapshot() != _initialSnapshot;

  String _snapshot() {
    return [
      _name.text,
      _organizer.text,
      _website.text,
      _category.text,
      (_directions.toList()..sort()).join(","),
      _tags.text,
      _deadlineNote.text,
      _requirements.text,
      _notes.text,
      _bufferDays.text,
      dateIso(_deadline),
      dateIso(_suggested),
      dateIso(_signupStart),
      dateIso(_signupEnd),
      _override ?? '',
      _useSuggested ? '1' : '0',
      for (final (ctrl, d) in _milestones) '${ctrl.text}|${dateIso(d)}',
    ].join('');
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _organizer = TextEditingController(text: c?.organizer ?? '');
    _website = TextEditingController(text: c?.website ?? '');
    _category = TextEditingController(text: c?.category ?? '');
    _directions = (c?.extra['directions'] as List? ?? []).map((v)=>'$v').toSet();
    _tags = TextEditingController(
      text: c?.tags.map((t) => '$t').join(', ') ?? '',
    );
    _deadlineNote = TextEditingController(text: c?.deadlineNote ?? '');
    _requirements = TextEditingController(text: c?.requirements ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
    _bufferDays = TextEditingController(
      text: c?.deadlineBufferDays?.toString() ?? '',
    );
    _deadline = c?.deadline;
    _suggested = c?.suggestedDeadline;
    _signupStart = c?.signupStart;
    _signupEnd = c?.signupEnd;
    _override = c?.statusOverride;
    _useSuggested = c?.suggestedDeadline != null;
    _milestones = [
      for (final m in c?.milestones ?? const <Milestone>[])
        (TextEditingController(text: m.name), m.date),
    ];
    _initialSnapshot = _snapshot();
    for (final ctrl in [
      _name,
      _organizer,
      _website,
      _category,
      _tags,
      _deadlineNote,
      _requirements,
      _notes,
      _bufferDays,
      ..._milestones.map((m) => m.$1),
    ]) {
      ctrl.addListener(_onFieldChanged);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _organizer,
      _website,
      _category,
      _tags,
      _deadlineNote,
      _requirements,
      _notes,
      _bufferDays,
      ..._milestones.map((m) => m.$1),
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 离开本页：绕过未保存拦截（保存成功或用户确认放弃后调用）。
  void _leave() {
    _bypassPop = true;
    // Marking dirty as clean so PopScope allows the pop on next frame.
    setState(() {});
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // 领域级复核（日期逻辑），给出可读错误
    if (_suggested != null &&
        _deadline != null &&
        _suggested!.isAfter(_deadline!)) {
      showSnack(context, '临期线不能晚于官方截止', error: true);
      return;
    }
    if (_signupStart != null &&
        _signupEnd != null &&
        _signupStart!.isAfter(_signupEnd!)) {
      showSnack(context, '报名开始不能晚于报名结束', error: true);
      return;
    }
    final c =
        widget.existing ?? Competition(id: '', name: '', deadline: today());
    c.name = _name.text.trim();
    c.deadline = _deadline!;
    c.suggestedDeadline = _useSuggested ? _suggested : null;
    c.deadlineBufferDays = int.tryParse(
      _bufferDays.text.trim(),
    ); // null/非法 → 默认缓冲
    c.milestones = [
      for (final (ctrl, d) in _milestones)
        if (d != null) Milestone(name: ctrl.text.trim(), date: d),
    ];
    c.category = _category.text.trim();
    if (_directions.isEmpty) { c.extra.remove('directions'); } else { c.extra['directions'] = _directions.toList(); }
    c.organizer = _organizer.text.trim();
    c.website = _website.text.trim();
    c.signupStart = _signupStart;
    c.signupEnd = _signupEnd;
    c.deadlineNote = _deadlineNote.text.trim();
    c.requirements = _requirements.text.trim();
    c.tags = [
      for (final t in _tags.text.split(RegExp('[,，]')))
        if (t.trim().isNotEmpty) t.trim(),
    ];
    c.notes = _notes.text.trim();
    c.statusOverride = _override;
    if (widget.existing == null) {
      c.id = makeCompId(c.name, c.deadline);
      c.source = 'manual';
    }
    await ref.read(libraryProvider.notifier).saveComp(c);
    appToast('已保存「${c.name}」');
    if (mounted) _leave();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return PopScope(
      canPop: _bypassPop || !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !_dirty || _bypassPop) return;
        final ok = await confirmDialog(
          context,
          '放弃修改？',
          '有未保存的修改，离开后将丢失。',
          okText: '放弃修改',
          danger: true,
        );
        if (ok == true && context.mounted) {
          _bypassPop = true;
          setState(() {});
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Text(isNew ? '添加比赛' : '编辑比赛'),
              if (_dirty) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '有未保存修改',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ),
        // 底部固定保存栏：贴底、避开手势条、拇指可达（0.5.0 移动端布局修复的延续）
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: _leave,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(88, 48),
                ),
                child: const Text('取消'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          ),
        ),
        body: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '名称 *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '名称必填' : null,
              ),
              const SizedBox(height: 12),
              _DateField(
                label: '官方截止 *',
                value: _deadline,
                onPick: (d) => setState(() => _deadline = d),
                validator: (d) => d == null ? '截止日期必填' : null,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('单独设置临期线'),
                subtitle: const Text('关闭时按 截止 − 缓冲天数 自动计算'),
                value: _useSuggested,
                onChanged: (v) => setState(() {
                  _useSuggested = v;
                  if (v && _suggested == null && _deadline != null) {
                    _suggested = _deadline!.subtract(
                      const Duration(days: defaultBufferDays),
                    );
                  }
                }),
              ),
              if (_useSuggested)
                _DateField(
                  label: '临期线',
                  value: _suggested,
                  onPick: (d) => setState(() => _suggested = d),
                ),
              if (!_useSuggested)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: 180,
                    child: TextFormField(
                      controller: _bufferDays,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '缓冲天数（默认 $defaultBufferDays）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: '报名开始',
                      value: _signupStart,
                      onPick: (d) => setState(() => _signupStart = d),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateField(
                      label: '报名结束',
                      value: _signupEnd,
                      onPick: (d) => setState(() => _signupEnd = d),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DirectionPicker(selected: _directions, onChanged: (v) => setState(() => _directions = v)),
                const SizedBox(height: 12),
                              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _category,
                      decoration: const InputDecoration(
                        labelText: '类别',
                        hintText: '视觉传达 / 工业设计 / …',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _organizer,
                      decoration: const InputDecoration(
                        labelText: '主办方',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _website,
                decoration: const InputDecoration(
                  labelText: '官网 / 链接',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tags,
                decoration: const InputDecoration(
                  labelText: '标签（逗号分隔）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _deadlineNote,
                decoration: const InputDecoration(
                  labelText: '截止说明',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _requirements,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '要求',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '备注',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('里程碑', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      final ctrl = TextEditingController();
                      ctrl.addListener(_onFieldChanged);
                      _milestones.add((ctrl, null));
                    }),
                    icon: const Icon(Icons.add),
                    label: const Text('添加'),
                  ),
                ],
              ),
              for (var i = 0; i < _milestones.length; i++)
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _milestones[i].$1,
                        decoration: InputDecoration(
                          labelText: '里程碑 ${i + 1} 名称',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateField(
                        label: '日期',
                        value: _milestones[i].$2,
                        dense: true,
                        onPick: (d) => setState(() {
                          _milestones[i] = (_milestones[i].$1, d);
                        }),
                      ),
                    ),
                    IconButton(
                      tooltip: '删除里程碑',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => setState(() {
                        final removed = _milestones.removeAt(i);
                        removed.$1.dispose();
                      }),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _override,
                decoration: const InputDecoration(
                  labelText: '人工状态标记（可选，优先于自动状态）',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('跟随自动状态')),
                  for (final s in validOverrides)
                    DropdownMenuItem(
                      value: s,
                      child: Text(statusLabels[s] ?? s),
                    ),
                ],
                onChanged: (v) => setState(() => _override = v),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    this.validator,
    this.dense = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onPick;
  final String? Function(DateTime?)? validator;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecorator(
      decoration: InputDecoration(
        isDense: dense,
        labelText: label,
        border: const OutlineInputBorder(),
        errorText: validator?.call(value),
        suffixIcon: value == null
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => onPick(null),
              ),
      ),
      child: InkWell(
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
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Text(
              value == null ? '选择日期' : dateIso(value)!,
              style: TextStyle(
                fontSize: 14,
                color: value == null ? scheme.outline : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
