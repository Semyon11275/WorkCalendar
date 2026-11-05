/// 旧版界面 · 右侧详情抽屉（500px，渐变头 + 分组正文 + 底部操作条）。
/// 比赛：indigo→purple 渐变头；获奖：amber→orange→rose 渐变头。
/// 结构逐段对应原版 drawerPanel innerHTML。
library;

import 'dart:io';
import '../certificate_viewer.dart';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../../state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tokens.dart';
import 'widgets.dart';

class LegacyCompDrawer extends StatelessWidget {
  const LegacyCompDrawer({
    super.key,
    required this.p,
    required this.comp,
    required this.onClose,
    required this.onEdit,
    required this.onDelete,
    required this.onOverride,
  });

  final LegacyPalette p;
  final Competition comp;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<String> onOverride;

  @override
  Widget build(BuildContext context) {
    final c = comp;
    final sub = c.submission;
    final fmt = c.format;
    return Column(children: [
      // 渐变头
      Container(
        // 原版 h-24 固定高会裁切长标题；改为自然高度保持完整可读
        padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: LegacyTokens.drawerCompGrad),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                '${c.category.isEmpty ? '未分类' : c.category}'
                '${c.organizer.isNotEmpty ? ' · ${c.organizer}' : ''}',
                style: TextStyle(
                    fontSize: 11.5, color: Colors.white.withValues(alpha: 0.75)),
              ),
            ),
            InkWell(
              onTap: onClose,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 15, color: Colors.white),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(c.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.2)),
          const SizedBox(height: 6),
          Row(children: [
            LStatusBadge(p: p, status: c.status()),
            const SizedBox(width: 8),
            LCountdownBadge(p: p, comp: c),
          ]),
        ]),
      ),
      // 正文
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: LegacyStaggerIn(
            delayMs: 0,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (c.website.isNotEmpty)
              InkWell(
                onTap: () => OpenFilex.open(c.website),
                child: Text('🔗 官网入口 →',
                    style: TextStyle(
                        fontSize: 13,
                        color: p.dark ? LegacyTokens.primaryD : LegacyTokens.primaryL,
                        decoration: TextDecoration.underline)),
              ),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: _box(
                  p,
                  tone: p.dark ? null : const Color(0xFFFFF1F2),
                  border: p.dark ? null : const Color(0xFFFFE4E6),
                  label: '⏰ 临期线（要赶的）',
                  value: dateIso(c.effectiveSuggested()) ?? '—',
                  valueColor: p.dark
                      ? LegacyTokens.urgentTextD
                      : const Color(0xFFE11D48),
                  note: c.suggestedDeadline == null ? '官方截止前预留缓冲' : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _box(
                  p,
                  tone: p.dark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                  border: p.hairline,
                  label: '📌 官方截止',
                  value: dateIso(c.deadline) ?? '—',
                  note: c.deadlineNote.isNotEmpty ? c.deadlineNote : null,
                ),
              ),
            ]),
            if (c.signupStart != null || c.signupEnd != null) ...[
              const SizedBox(height: 10),
              Text(
                  '报名：${dateIso(c.signupStart) ?? '—'} → ${dateIso(c.signupEnd) ?? '—'}',
                  style: TextStyle(fontSize: 11.5, color: p.muted)),
            ],
            const SizedBox(height: 18),
            _section(p, const Color(0xFFF59E0B), '提交链路（里程碑）'),
            const SizedBox(height: 6),
            if (c.milestones.isEmpty)
              Text('未设置里程碑', style: TextStyle(fontSize: 12.5, color: p.muted))
            else
              ...c.milestones.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Icon(Icons.flag_outlined, size: 14, color: p.muted),
                      const SizedBox(width: 6),
                      Text(m.name,
                          style: TextStyle(fontSize: 13, color: p.text)),
                      const Spacer(),
                      Text(dateIso(m.date) ?? '',
                          style: lMono(12, color: p.muted,
                              weight: FontWeight.w400)),
                    ]),
                  )),
            const SizedBox(height: 16),
            _section(p, const Color(0xFF6366F1), '作品要求'),
            const SizedBox(height: 6),
            SelectableText(
              c.requirements.isEmpty ? '未填写' : c.requirements,
              style: TextStyle(
                  fontSize: 13, height: 1.6, color: p.text),
            ),
            if (c.deliverables.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final d in c.deliverables)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(children: [
                    Icon(Icons.check_circle_outline,
                        size: 13, color: p.muted),
                    const SizedBox(width: 6),
                    Text('$d', style: TextStyle(fontSize: 13, color: p.text)),
                  ]),
                ),
            ],
            const SizedBox(height: 16),
            _section(p, const Color(0xFF10B981), '📮 去哪交'),
            const SizedBox(height: 6),
            _kv(p, '方式', '${sub['method'] ?? ''}'),
            _kv(p, '入口', '${sub['target'] ?? ''}', mono: true, copyable: true),
            _kv(p, '联系', '${sub['contact'] ?? ''}'),
            _kv(p, '费用', '${sub['fee'] ?? ''}'),
            const SizedBox(height: 16),
            _section(p, const Color(0xFF0EA5E9), '📐 格式'),
            const SizedBox(height: 6),
            _kv(p, '类型',
                (fmt['file_types'] is List && (fmt['file_types'] as List).isNotEmpty)
                    ? (fmt['file_types'] as List).join(', ')
                    : ''),
            if (fmt['max_size_mb'] != null)
              _kv(p, '上限', '${fmt['max_size_mb']} MB'),
            _kv(p, '命名', '${fmt['naming'] ?? ''}', mono: true, copyable: true),
            if (c.tags.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 6, children: [
                for (final t in c.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
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
                    child: Text('#$t',
                        style: TextStyle(
                            fontSize: 11,
                            color: p.dark
                                ? const Color(0xFFFCD34D)
                                : const Color(0xFFD97706))),
                  ),
              ]),
            ],
            if (c.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('备注：${c.notes}',
                  style: TextStyle(fontSize: 13, color: p.text, height: 1.5)),
            ],
            const SizedBox(height: 22),
            Divider(height: 1, color: p.hairline),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              LButton(
                  label: '✓ 标记已提交',
                  kind: LBtnKind.primary,
                  onPressed: () => onOverride('submitted')),
              LButton(
                  label: '🏁 已完成',
                  onPressed: () => onOverride('done')),
              LButton(
                  label: '🚫 放弃',
                  onPressed: () => onOverride('abandoned')),
              LButton(label: '✏️ 编辑', onPressed: onEdit),
              LButton(label: '🗑 删除', kind: LBtnKind.danger, onPressed: onDelete),
            ]),
          ]),
        ),
      ),
      ),
    ]);
  }

  Widget _section(LegacyPalette p, Color color, String title) {
    return Row(children: [
      Container(
          width: 4,
          height: 13,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(title,
          style: TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
    ]);
  }

  Widget _box(LegacyPalette p,
      {Color? tone, Color? border, required String label, required String value,
       Color? valueColor, String? note}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border ?? Colors.transparent),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: p.muted)),
        const SizedBox(height: 4),
        Text(value,
            style: lMono(18, color: valueColor ?? p.text, weight: FontWeight.w700)),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(note, style: TextStyle(fontSize: 10.5, color: p.muted)),
          ),
      ]),
    );
  }

  Widget _kv(LegacyPalette p, String label, String value,
      {bool mono = false, bool copyable = false}) {
    final hasValue = value.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 44,
            child: Text(label,
                style: TextStyle(fontSize: 12.5, color: p.muted))),
        Expanded(
          child: hasValue
              ? SelectableText(value,
                  style: mono
                      ? lMono(12, color: p.text, weight: FontWeight.w400)
                      : TextStyle(fontSize: 13, color: p.text))
              : Text('未填写', style: TextStyle(fontSize: 12.5, color: p.muted)),
        ),
      ]),
    );
  }
}

class LegacyAwardDrawer extends ConsumerWidget {
  const LegacyAwardDrawer({
    super.key,
    required this.p,
    required this.award,
    required this.onClose,
    required this.onEdit,
    required this.onDelete,
  });

  final LegacyPalette p;
  final Award award;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = award;
    final repo = ref.watch(repositoryProvider);
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 16, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: LegacyTokens.drawerAwardGrad),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                '${a.level}${a.awardRank.isNotEmpty ? ' · ${a.awardRank}' : ''}'
                '${a.isFirstAuthor ? ' · ✍️ 一作' : (a.role.isNotEmpty ? ' · ${a.role}' : '')}',
                style: TextStyle(
                    fontSize: 11.5, color: Colors.white.withValues(alpha: 0.8)),
              ),
            ),
            InkWell(
              onTap: onClose,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 15, color: Colors.white),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(a.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.2)),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: LegacyStaggerIn(
            delayMs: 0,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: p.dark
                        ? const Color(0xFF453011)
                        : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: p.dark
                            ? const Color(0xFF6B5518)
                            : const Color(0xFFF1E4C0)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('🏆 级别',
                        style: TextStyle(fontSize: 11, color: p.muted)),
                    const SizedBox(height: 4),
                    Text(a.level,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: p.text)),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: p.dark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('📅 获奖日期',
                        style: TextStyle(fontSize: 11, color: p.muted)),
                    const SizedBox(height: 4),
                    Text(dateIso(a.awardDate) ?? '—',
                        style: lMono(16, color: p.text, weight: FontWeight.w700)),
                  ]),
                ),
              ),
            ]),
            if (a.competition.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('关联比赛：',
                  style: TextStyle(fontSize: 12.5, color: p.muted)),
              Text(a.competition,
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Container(
                  width: 4,
                  height: 13,
                  decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Text('📎 获奖凭证（${a.certificateFiles.length} 个）',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: p.text)),
            ]),
            const SizedBox(height: 8),
            if (a.certificateFiles.isEmpty)
              Text('无', style: TextStyle(fontSize: 12.5, color: p.muted))
            else
              ...a.certificateFiles.map((name) {
                final file = File(repo.certs.path(name));
                final exists = file.existsSync();
                final isImg = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp']
                    .any((e) => name.toLowerCase().endsWith(e));
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: exists
                        ? () => Navigator.push(
                            context,
                            CertificateViewerPage.route(awardId: a.id,
                              initialIndex: a.certificateFiles.indexOf(name)))
                        : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: p.dark
                            ? Colors.white.withValues(alpha: 0.04)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: p.hairline),
                      ),
                      child: Row(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: exists && isImg
                              ? Image.file(file,
                                  width: 64,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  cacheWidth: 128,
                                  errorBuilder: (_, _, _) => _ph(p))
                              : _ph(p),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12.5, color: p.text)),
                            if (!exists)
                              Text('原件缺失，可从备份恢复',
                                  style: TextStyle(
                                      fontSize: 10.5, color: p.muted)),
                          ]),
                        ),
                        if (exists)
                          Icon(Icons.open_in_new,
                              size: 15, color: p.muted),
                      ]),
                    ),
                  ),
                );
              }),
            if (a.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('备注：${a.notes}',
                  style: TextStyle(fontSize: 13, color: p.text, height: 1.5)),
            ],
            const SizedBox(height: 22),
            Divider(height: 1, color: p.hairline),
            const SizedBox(height: 14),
            Row(children: [
              LButton(label: '✏️ 编辑', onPressed: onEdit),
              const SizedBox(width: 8),
              LButton(label: '🗑 删除', kind: LBtnKind.danger, onPressed: onDelete),
            ]),
          ]),
          ),
        ),
      ),
    ]);
  }

  Widget _ph(LegacyPalette p) {
    return Container(
      width: 64,
      height: 48,
      color: p.dark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFEEF0F4),
      alignment: Alignment.center,
      child: Text('PDF', style: lMono(9, color: p.muted, weight: FontWeight.w400)),
    );
  }
}


