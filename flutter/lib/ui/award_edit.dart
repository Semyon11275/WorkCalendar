/// 获奖新建/编辑：级别、等级、一作、关联比赛（联想）、凭证附件管理。
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../domain/rules.dart';
import '../state/providers.dart';
import 'certificate_viewer.dart';
import 'widgets.dart';

class AwardEditPage extends ConsumerStatefulWidget {
  const AwardEditPage({super.key, this.existing});
  final Award? existing;

  static Route<void> route({Award? existing}) =>
      MaterialPageRoute(builder: (_) => AwardEditPage(existing: existing));

  @override
  ConsumerState<AwardEditPage> createState() => _AwardEditPageState();
}

class _AwardEditPageState extends ConsumerState<AwardEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _rank;
  late final TextEditingController _role;
  late final TextEditingController _competition;
  late final TextEditingController _notes;
  DateTime? _date;
  String _level = '校级';
  bool _first = false;

  final _formKey = GlobalKey<FormState>();
  String _initialSnapshot = '';
  bool _bypassPop = false;

  bool get _dirty => _snapshot() != _initialSnapshot;

  String _snapshot() => [
    _name.text,
    _rank.text,
    _role.text,
    _competition.text,
    _notes.text,
    dateIso(_date),
    _level,
    _first ? '1' : '0',
  ].join('');

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

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
    _initialSnapshot = _snapshot();
    for (final ctrl in [_name, _rank, _role, _competition, _notes]) {
      ctrl.addListener(_onFieldChanged);
    }
  }

  void _leave() {
    _bypassPop = true;
    setState(() {});
    Navigator.of(context).pop();
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

  Future<void> _attachCerts() async {
    const typeGroup = XTypeGroup(
      label: '图片/PDF',
      extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'pdf'],
    );
    List<XFile> files;
    try {
      files = await openFiles(acceptedTypeGroups: [typeGroup]);
    } on Exception {
      return;
    }
    if (files.isEmpty) return;
    final a = widget.existing;
    final repo = ref.read(repositoryProvider);
    final lib = ref.read(libraryProvider.notifier);
    if (a == null) {
      // 新建场景：先建记录再挂凭证
      final created = await _createAward();
      if (created == null) return;
      for (final f in files) {
        final saved = await repo.certs.save(f.name, await f.readAsBytes());
        await lib.attachCerts(created.id, [saved]);
      }
      appToast('已添加获奖并挂上凭证');
      if (mounted) _leave();
      return;
    }
    final added = <String>[];
    for (final f in files) {
      final saved = await repo.certs.save(f.name, await f.readAsBytes());
      added.add(saved);
    }
    await lib.attachCerts(a.id, added);
    if (mounted) showSnack(context, '已添加 ${added.length} 个凭证');
  }

  Future<Award?> _createAward() async {
    if (!_formKey.currentState!.validate()) return null;
    final a = Award(
      id: makeAwardId(_name.text.trim(), _date),
      name: _name.text.trim(),
      level: _level,
      awardRank: _rank.text.trim(),
      isFirstAuthor: _first,
      role: _role.text.trim(),
      competition: _competition.text.trim(),
      awardDate: _date,
      notes: _notes.text.trim(),
      source: 'manual',
    );
    await ref.read(libraryProvider.notifier).saveAward(a);
    return a;
  }

  Future<void> _save() async {
    final a = widget.existing ?? await _createAward();
    if (widget.existing != null) {
      if (!_formKey.currentState!.validate()) return;
      a!.name = _name.text.trim();
      a.level = _level;
      a.awardRank = _rank.text.trim();
      a.isFirstAuthor = _first;
      a.role = _role.text.trim();
      a.competition = _competition.text.trim();
      a.awardDate = _date;
      a.notes = _notes.text.trim();
      await ref.read(libraryProvider.notifier).saveAward(a);
    }
    appToast('已保存「${_name.text.trim()}」');
    if (mounted) _leave();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    final certs = widget.existing?.certificateFiles ?? const <String>[];
    final compNames = ref
        .watch(libraryProvider)
        .comps
        .map((c) => c.name)
        .toList();

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
              Text(isNew ? '添加获奖' : '编辑获奖'),
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
                  labelText: '奖项名称 *',
                  hintText: '例：全国大学生工业设计大赛',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '名称必填' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _level,
                      decoration: const InputDecoration(
                        labelText: '级别',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final l in validAwardLevels)
                          DropdownMenuItem(value: l, child: Text(l)),
                      ],
                      onChanged: (v) => setState(() => _level = v ?? '校级'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _rank,
                      decoration: const InputDecoration(
                        labelText: '奖项等级',
                        hintText: '一等奖 / 金奖 / …',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _AwardDateField(
                      value: _date,
                      onPick: (d) => setState(() => _date = d),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _role,
                      decoration: const InputDecoration(
                        labelText: '角色',
                        hintText: '一作 / 队长 / 参与…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _competition.text),
                optionsBuilder: (v) => v.text.isEmpty
                    ? const Iterable.empty()
                    : compNames.where((n) => n.contains(v.text)),
                onSelected: (s) => _competition.text = s,
                fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextFormField(
                  controller: ctrl,
                  focusNode: focus,
                  onChanged: (v) => _competition.text = v,
                  decoration: const InputDecoration(
                    labelText: '关联比赛（自由文本，可联想）',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('第一作者 / 独立完成'),
                value: _first,
                onChanged: (v) => setState(() => _first = v),
              ),
              const SizedBox(height: 4),
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
                  Text('凭证', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _attachCerts,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('添加凭证'),
                  ),
                ],
              ),
              if (certs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '尚未添加凭证。支持图片与 PDF，原件保存在应用数据目录。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                ...certs.map(
                  (f) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.description_outlined),
                    title: Text(
                      f,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '查看',
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () => Navigator.push(
                            context,
                            CertificateViewerPage.route(
                              awardId: widget.existing!.id,
                              initialIndex: widget.existing!.certificateFiles
                                  .indexOf(f),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '移除引用',
                          icon: const Icon(Icons.link_off),
                          onPressed: () async {
                            final ok = await confirmDialog(
                              context,
                              '移除凭证引用',
                              '从该获奖记录移除「$f」？文件本体不会被删除。',
                              okText: '移除',
                            );
                            if (ok == true) {
                              await ref
                                  .read(libraryProvider.notifier)
                                  .removeCert(widget.existing!.id, f);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AwardDateField extends StatelessWidget {
  const _AwardDateField({required this.value, required this.onPick});
  final DateTime? value;
  final ValueChanged<DateTime?> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: '获奖日期',
        border: const OutlineInputBorder(),
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
            firstDate: DateTime(now.year - 30),
            lastDate: DateTime(now.year + 1),
          );
          if (picked != null) onPick(picked);
        },
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Text(value == null ? '选择日期' : dateIso(value)!),
          ],
        ),
      ),
    );
  }
}
