/// 获奖页：级别筛选、一作筛选、搜索，按关联比赛分组折叠展示。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../domain/classification.dart';
import '../domain/rules.dart';
import '../state/providers.dart';
import 'award_detail.dart';
import 'award_edit.dart';
import 'certificate_viewer.dart';
import 'theme.dart';
import 'motion.dart';
import 'widgets.dart';

class AwardsPage extends ConsumerStatefulWidget {
  const AwardsPage({super.key});

  @override
  ConsumerState<AwardsPage> createState() => _AwardsPageState();
}

class _AwardsPageState extends ConsumerState<AwardsPage> {
  /// 用户显式切换过的分组开合状态（持久化，重启保持——对齐 0.5.0）。
  /// 未出现在表中的组按旧版默认值：多条组折叠、单条组展开。
  Map<String, bool> _openOverrides = {};

  @override
  void initState() {
    super.initState();
    _loadGroupPrefs();
  }

  Future<void> _loadGroupPrefs() async {
    final raw = readAppSettings(ref.read(repositoryProvider))['awards_open'];
    if (raw is Map) {
      setState(() {
        _openOverrides = {
          for (final e in raw.entries)
            if (e.value is bool) '${e.key}': e.value as bool,
        };
      });
    }
  }

  Future<void> _toggleGroup(String key, bool currentlyOpen) async {
    setState(() => _openOverrides[key] = !currentlyOpen);
    await writeAppSetting(
      ref.read(repositoryProvider),
      'awards_open',
      _openOverrides,
    );
  }

  /// 全部展开/折叠（0.5.0 工具栏功能恢复）；记忆并持久化。
  Future<void> _setAllOpen(bool open) async {
    setState(() {
      for (final g in ref.read(groupedAwardsProvider)) {
        _openOverrides[g.key] = open;
      }
    });
    await writeAppSetting(
        ref.read(repositoryProvider), 'awards_open', _openOverrides);
  }

  /// 生效的开合状态：筛选激活时全部展开（自动展开结果，对齐旧版）；
  /// 否则按用户记忆，无记忆时按条数默认。
  bool _isGroupOpen(MapEntry<String, List<Award>> g, AwardFilter filter) {
    if (filter.hasFilter) return true;
    return _openOverrides[g.key] ?? (g.value.length <= 1);
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupedAwardsProvider);
    final filter = ref.watch(awardFilterProvider);
    final notifier = ref.read(awardFilterProvider.notifier);
    final lib = ref.watch(libraryProvider);
    final stats = lib.awardStats;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('获奖'),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text('共 ${stats.total} · 一作 ${stats.firstAuthor}',
                style: DesignTokens.mono(11, color: scheme.primary)),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: '全部展开',
            icon: const Icon(Icons.unfold_more),
            onPressed: groups.isEmpty ? null : () => _setAllOpen(true),
          ),
          IconButton(
            tooltip: '全部折叠',
            icon: const Icon(Icons.unfold_less),
            onPressed: groups.isEmpty ? null : () => _setAllOpen(false),
          ),
          IconButton(
            tooltip: '筛选',
            icon: Badge(
              isLabelVisible: filter.hasFilter,
              child: const Icon(Icons.filter_list),
            ),
            onPressed: () => _openFilterSheet(context, filter, notifier),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, AwardEditPage.route()),
        icon: const Icon(Icons.add),
        label: const Text('添加获奖'),
      ),
      body: groups.isEmpty
          ? EmptyView(
              icon: Icons.workspace_premium_outlined,
              title: filter.hasFilter ? '没有符合条件的获奖记录' : '还没有获奖记录',
              hint: filter.hasFilter ? '试试调整筛选' : null,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                DropdownButton<AwardGrouping>(
    value: ref.watch(awardGroupingProvider),
    items: [for (final g in AwardGrouping.values)
      DropdownMenuItem(value: g, child: Text('按${awardGroupingLabels[g]}'))],
    onChanged: (g) { if (g != null) ref.read(awardGroupingProvider.notifier).select(g); },
  ),
                Row(
                  children: [
                    _Stat(text: '共 ${stats.total} 条'),
                    const SizedBox(width: 8),
                    _Stat(text: '一作 ${stats.firstAuthor} 条'),
                    const Spacer(),
                    if (filter.hasFilter)
                      TextButton(
                        onPressed: () => notifier.update(AwardFilter()),
                        child: const Text('清除筛选'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final g in groups)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [
                        PressableScale(
                          child: InkWell(
                            onTap: () =>
                                _toggleGroup(g.key, _isGroupOpen(g, filter)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  AnimatedRotation(
                                    turns: _isGroupOpen(g, filter) ? 0.25 : 0,
                                    duration: Duration(
                                      milliseconds:
                                          ref.watch(reducedMotionProvider) ||
                                              MediaQuery.disableAnimationsOf(
                                                context,
                                              )
                                          ? 0
                                          : 280,
                                    ),
                                    child: const Icon(Icons.chevron_right),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          g.key,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _groupMeta(g.value),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // 展开/收起 200ms；减少动效时零时长直接切换
                        AnimatedSize(
                          duration: Duration(
                            milliseconds:
                                ref.watch(reducedMotionProvider) ||
                                    MediaQuery.disableAnimationsOf(context)
                                ? 0
                                : 300,
                          ),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: _isGroupOpen(g, filter)
                              ? Column(
                                  children: g.value
                                      .map((a) => _AwardTile(award: a))
                                      .toList(),
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  String _groupMeta(List<Award> items) {
    final first = items.where((a) => a.isFirstAuthor).length;
    final levels = items.map((a) => a.level).toSet().join('/');
    final dates = items
        .where((a) => a.awardDate != null)
        .map((a) => a.awardDate!);
    final latest = dates.isEmpty
        ? ''
        : ' · 最近 ${dateIso(dates.reduce((a, b) => a.isAfter(b) ? a : b))}';
    return '${items.length} 条 · 一作 $first · $levels$latest';
  }

  void _openFilterSheet(
    BuildContext context,
    AwardFilter filter,
    AwardFilterNotifier notifier,
  ) {
    // 控制器只建一次（放在 builder 外），避免重建时光标跳动
    final keywordCtrl = TextEditingController(text: filter.keyword);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('筛选', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: keywordCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索名称 / 关联比赛 / 备注',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => notifier.update(filter.copyWith(keyword: v)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('全部'),
                    selected: filter.level.isEmpty,
                    onSelected: (_) =>
                        notifier.update(filter.copyWith(level: '')),
                  ),
                  for (final l in validAwardLevels)
                    ChoiceChip(
                      label: Text(l),
                      selected: filter.level == l,
                      onSelected: (_) =>
                          notifier.update(filter.copyWith(level: l)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('仅看一作'),
                value: filter.firstOnly,
                onChanged: (v) =>
                    notifier.update(filter.copyWith(firstOnly: v)),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(keywordCtrl.dispose);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _AwardTile extends ConsumerWidget {
  const _AwardTile({required this.award});
  final Award award;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      minVerticalPadding: 12,
      onTap: () => Navigator.push(context, AwardDetailPage.route(award.id)),
      title: Row(
        children: [
          Expanded(
            child: Text(
              award.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (award.isFirstAuthor)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '一作',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            LevelBadge(level: award.level),
            if (award.awardRank.isNotEmpty)
              Text(award.awardRank, style: const TextStyle(fontSize: 12)),
            if (award.awardDate != null)
              Text(
                dateIso(award.awardDate)!,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            if (award.certificateFiles.isNotEmpty) ...[
              Icon(Icons.attach_file, size: 13, color: scheme.primary),
              Text(
                '${award.certificateFiles.length}',
                style: TextStyle(fontSize: 12, color: scheme.primary),
              ),
            ],
          ],
        ),
      ),
      // 凭证缩略图直接放在列表尾部，点按进查看器
      trailing: award.certificateFiles.isEmpty
          ? null
          : _CertThumb(name: award.certificateFiles.first, awardId: award.id),
    );
  }
}

class _CertThumb extends ConsumerWidget {
  const _CertThumb({required this.name, required this.awardId});
  final String name;
  final String awardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final file = File(repo.certs.path(name));
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        CertificateViewerPage.route(awardId: awardId, initialIndex: 0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 56,
          height: 42,
          // 按缩略图尺寸解码，多 MB 原图不整幅进内存（等价旧版预览图的内存收益）
          child: file.existsSync()
              ? Image.file(
                  file,
                  fit: BoxFit.cover,
                  cacheWidth: 112,
                  errorBuilder: (_, _, _) => const _ThumbFallback(),
                )
              : const _ThumbFallback(),
        ),
      ),
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.description_outlined, size: 20, color: scheme.outline),
    );
  }
}
