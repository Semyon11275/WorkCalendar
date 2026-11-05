/// 获奖详情（设计稿 03/08）：证书大图占主区，右侧档案信息；窄屏纵向堆叠。
/// 查看原件进全屏查看器；系统打开交给 OS。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../data/repository.dart';
import '../domain/models.dart';
import '../domain/rules.dart';
import '../state/providers.dart';
import 'award_edit.dart';
import 'certificate_viewer.dart';
import 'theme.dart';
import 'widgets.dart';

const _imgExts = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'];

class AwardDetailPage extends ConsumerWidget {
  const AwardDetailPage({super.key, required this.awardId});
  final String awardId;

  static Route<void> route(String awardId) =>
      MaterialPageRoute(builder: (_) => AwardDetailPage(awardId: awardId));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final repo = ref.watch(repositoryProvider);
    final a = lib.awards.where((x) => x.id == awardId).firstOrNull;
    if (a == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyView(icon: Icons.error_outline, title: '记录不存在或已被删除'),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final stage = _CertStage(repo: repo, award: a);

    final info = _infoPanel(context, ref, repo, a);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        leading: BackButton(onPressed: () => Navigator.pop(context)),
        title: wide
            ? Text(
                '获奖档案 / ${[if (a.awardRank.isNotEmpty) a.awardRank, a.name].join(' · ')}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              )
            : const Text('获奖详情'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton.icon(
              onPressed: () =>
                  Navigator.push(context, AwardEditPage.route(existing: a)),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('编辑'),
            ),
          ),
        ],
      ),
      body: wide
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 58, child: stage),
                  const SizedBox(width: 16),
                  SizedBox(width: 400, child: info),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                Text(
                  [if (a.awardRank.isNotEmpty) a.awardRank else a.name].join(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  a.competition,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: schemeOf(context).onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    LevelBadge(level: a.level),
                    if (a.isFirstAuthor)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: schemeOf(context).surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '独立完成 / 一作',
                          style: TextStyle(
                            fontSize: 11,
                            color: schemeOf(context).onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(height: 320, child: stage),
                const SizedBox(height: 14),
                info,
              ],
            ),
    );
  }

  ColorScheme schemeOf(BuildContext context) => Theme.of(context).colorScheme;
}

/// 证书舞台：主图 + 页码指示（占位为暖白 plate）。
class _CertStage extends StatelessWidget {
  const _CertStage({required this.repo, required this.award});
  final WcRepository repo;
  final Award award;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final certs = award.certificateFiles;
    if (certs.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        alignment: Alignment.center,
        child: Text(
          '未附证书',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
      );
    }
    final name = certs.first;
    final file = File(repo.certs.path(name));
    final isImg = _imgExts.any((e) => name.toLowerCase().endsWith(e));
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Center(
            child: file.existsSync() && isImg
                ? InteractiveViewer(
                    maxScale: 8,
                    child: Image.file(
                      file,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => _platePlaceholder(context),
                    ),
                  )
                : _platePlaceholder(
                    context,
                    label: file.existsSync() ? 'PDF / 其他格式' : '原件缺失',
                  ),
          ),
          if (certs.length > 1)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '1 / ${certs.length}',
                  style: DesignTokens.mono(10.5, color: scheme.onSurface),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _platePlaceholder(BuildContext context, {String? label}) {
    return Container(
      width: 230,
      height: 320,
      decoration: BoxDecoration(
        color: DesignTokens.plate,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label ?? '证书',
        style: DesignTokens.mono(11, color: const Color(0xFF6E6A64)),
      ),
    );
  }
}

/// 档案信息面板。
Widget _infoPanel(
  BuildContext context,
  WidgetRef ref,
  WcRepository repo,
  Award a,
) {
  final scheme = Theme.of(context).colorScheme;
  return Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AWARD RECORD · ${a.awardDate?.year ?? ''}',
            style: DesignTokens.mono(9.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          if (a.awardRank.isNotEmpty)
            SelectableText(
              a.awardRank,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          SelectableText(
            a.name,
            style: TextStyle(
              fontSize: a.awardRank.isEmpty ? 22 : 15,
              fontWeight: FontWeight.w700,
              color: a.awardRank.isEmpty ? null : scheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              LevelBadge(level: a.level),
              if (a.isFirstAuthor)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '独立完成 / 一作',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 26),
          _kv('关联比赛', a.competition.isEmpty ? '—' : a.competition, scheme),
          _kv(
            '获奖日期',
            a.awardDate == null ? '—' : '${dateIso(a.awardDate)} · 已归档',
            scheme,
          ),
          _kv(
            '原件状态',
            a.certificateFiles.isEmpty
                ? '未附原件'
                : '已加密保存 · ${a.certificateFiles.length} 份',
            scheme,
          ),
          if (a.role.isNotEmpty) _kv('角色', a.role, scheme),
          if (a.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '备注',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            SelectableText(
              a.notes,
              style: TextStyle(fontSize: 12.5, height: 1.5),
            ),
          ],
          if (a.certificateFiles.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  '附件 · ${a.certificateFiles.length} 份',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '全部展开',
                  style: TextStyle(fontSize: 11.5, color: scheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < a.certificateFiles.length; i++)
                  _certCell(context, repo, a, i),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: a.certificateFiles.isEmpty
                      ? null
                      : () => Navigator.push(
                          context,
                          CertificateViewerPage.route(
                            awardId: a.id,
                            initialIndex: 0,
                          ),
                        ),
                  child: const Text('查看原件'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: a.certificateFiles.isEmpty
                    ? null
                    : () async {
                        final r = await OpenFilex.open(
                          repo.certs.path(a.certificateFiles.first),
                        );
                        if (r.type != ResultType.done && context.mounted) {
                          showSnack(context, '打开失败：${r.message}', error: true);
                        }
                      },
                child: const Text('系统打开'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget _kv(String label, String value, ColorScheme scheme) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: SelectableText(value, style: const TextStyle(fontSize: 12.5)),
        ),
      ],
    ),
  );
}

Widget _certCell(BuildContext context, WcRepository repo, Award a, int index) {
  final scheme = Theme.of(context).colorScheme;
  final name = a.certificateFiles[index];
  final file = File(repo.certs.path(name));
  final isImg = _imgExts.any((e) => name.toLowerCase().endsWith(e));
  return InkWell(
    onTap: () => Navigator.push(
      context,
      CertificateViewerPage.route(awardId: a.id, initialIndex: index),
    ),
    borderRadius: BorderRadius.circular(8),
    child: Container(
      width: 64,
      height: 84,
      decoration: BoxDecoration(
        color: DesignTokens.plate,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(4),
      alignment: Alignment.center,
      child: file.existsSync() && isImg
          ? Image.file(
              file,
              fit: BoxFit.cover,
              cacheWidth: 128,
              errorBuilder: (_, _, _) => Text(
                '图片',
                style: DesignTokens.mono(9, color: const Color(0xFF6E6A64)),
              ),
            )
          : Text(
              isImg ? '缺失' : 'PDF',
              style: DesignTokens.mono(9, color: const Color(0xFF6E6A64)),
            ),
    ),
  );
}
