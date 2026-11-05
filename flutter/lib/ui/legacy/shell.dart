/// 旧版界面外壳：顶栏（品牌 + 全局搜索 + 类别/状态下拉 + 添加比赛 + 导入 +
/// 深浅切换）+ 左侧 192px 分组导航（浏览/管理）+ 底部端口信息卡。
/// 视图：总览/列表/时间线/AI 助手(禁用占位，登记于差异清单)/获奖/设置。
library;

import 'dart:io';
import '../management_page.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repository.dart' show ImportStage, WcRepository;
// ImportStage 实际定义于 repository.dart
import '../../data/exchange.dart' show parseSourceBytes;
import '../../domain/models.dart';
import '../../domain/classification.dart';
import '../../state/providers.dart';
import '../../domain/rules.dart';
import 'awards.dart';
import 'dialogs.dart';
import 'list.dart';
import 'drawer.dart';
import 'overview.dart';
import 'settings.dart';
import 'timeline.dart';
import '../widgets.dart' show appToast, confirmDialog;
import 'tokens.dart';
import 'widgets.dart';

class LegacyShell extends ConsumerStatefulWidget {
  const LegacyShell({super.key});

  @override
  ConsumerState<LegacyShell> createState() => _LegacyShellState();
}

enum _LegacyView { overview, list, timeline, awards, settings, ai }

class _LegacyShellState extends ConsumerState<LegacyShell> {
  _LegacyView _view = _LegacyView.overview;
  final _searchCtrl = TextEditingController();
  String _category = ''; // '' = 全部类别
  String _statusFilter = ''; // '' = 全部状态（隐藏过期）| 'all' = 全览 | 具体状态
  bool _bannerDismissed = false;
  final _drawerComp = ValueNotifier<String?>(null);
  final _drawerAward = ValueNotifier<String?>(null);
  bool _busyImport = false;
  final bool _includeCerts = true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _drawerComp.dispose();
    _drawerAward.dispose();
    super.dispose();
  }

  /// 全局筛选（类别/状态/搜索）作用于列表、时间线与总览紧急区。
  List<Competition> _visible(List<Competition> comps) {
    var out = comps;
    if (_category.isNotEmpty) {
      out = out.where((c) => competitionDirections(c).contains(_category)).toList();
    }
    final today0 = today();
    if (_statusFilter == 'all') {
      // 全览（含过期）
    } else if (_statusFilter.isNotEmpty) {
      out = out.where((c) => c.status(today0) == _statusFilter).toList();
    } else {
      // 默认：隐藏过期（已截止≥5 天且未完成）
      out = out
          .where((c) => !(c.status(today0) == 'overdue' &&
              c.statusOverride != 'done'))
          .toList();
    }
    final kw = _searchCtrl.text.trim().toLowerCase();
    if (kw.isNotEmpty) {
      out = out
          .where((c) =>
              c.name.toLowerCase().contains(kw) ||
              c.notes.toLowerCase().contains(kw) ||
              c.organizer.toLowerCase().contains(kw))
          .toList();
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.legacy;
    final lib = ref.watch(libraryProvider);
    final repo = ref.watch(repositoryProvider);
    final visible = _visible(lib.comps);

    final wallpaperOn = ref.watch(legacyWallpaperProvider) == 1;
    final pet = ref.watch(legacyPetProvider);
    final wallpaperFile =
        File('${repo.dataDir}${Platform.pathSeparator}wallpaper.img');
    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(children: [
        // 壁纸层（自动淡化保证内容可读——原版行为）
        if (wallpaperOn && wallpaperFile.existsSync())
          Positioned.fill(
            child: Image.file(
              wallpaperFile,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        if (wallpaperOn && wallpaperFile.existsSync())
          Positioned.fill(
            child: ColoredBox(
              color: p.dark
                  ? Colors.black.withValues(alpha: 0.78)
                  : Colors.white.withValues(alpha: 0.78),
            ),
          ),
        Column(children: [
        _header(context, p),
        Divider(height: 1, thickness: 1, color: p.hairline),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _nav(context, p, lib, repo),
            Container(width: 1, color: p.hairline),
            Expanded(
              child: ClipRect(
                child: Stack(children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: AnimatedSwitcher(
                      duration: ref.watch(reducedMotionProvider)
                          ? Duration.zero
                          : const Duration(
                              milliseconds: LegacyTokens.revealMs),
                      switchInCurve: const Cubic(0.18, 0.72, 0.18, 1),
                      child: KeyedSubtree(
                        key: ValueKey(_view),
                        child: _viewBody(context, p, visible),
                      ),
                    ),
                  ),
                  // 右侧抽屉层（原版 drawerPanel：500px，max 94vw）
                  ValueListenableBuilder<String?>(
                    valueListenable: _drawerComp,
                    builder: (ctx, compId, _) {
                      final awardId = _drawerAward.value;
                      final open = compId != null || awardId != null;
                      return Positioned.fill(
                        child: IgnorePointer(
                          ignoring: !open,
                          child: AnimatedOpacity(
                            opacity: open ? 1 : 0,
                            duration: const Duration(
                                milliseconds: LegacyTokens.drawerMs),
                            child: open
                                ? GestureDetector(
                                    onTap: _closeDrawer,
                                    child: Container(
                                        color:
                                            Colors.black.withValues(alpha: 0.35)),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      );
                    },
                  ),
                  ValueListenableBuilder<String?>(
                    valueListenable: _drawerComp,
                    builder: (ctx, compId, _) {
                      if (compId == null) return const SizedBox.shrink();
                      final c = lib.comps.where((x) => x.id == compId).firstOrNull;
                      if (c == null) return const SizedBox.shrink();
                      return _drawerPanel(
                        context,
                        LegacyCompDrawer(
                          p: p,
                          comp: c,
                          onClose: _closeDrawer,
                          onEdit: () => _openCompDialog(existing: c),
                          onDelete: () => _deleteComp(c),
                          onOverride: (s) async {
                            await ref
                                .read(libraryProvider.notifier)
                                .markStatus(c.id, s);
                            appToast(s == 'submitted'
                                ? '已标记为已提交 🎉'
                                : s == 'done'
                                    ? '已完成 🏁'
                                    : '已标记放弃');
                          },
                        ),
                      );
                    },
                  ),
                  ValueListenableBuilder<String?>(
                    valueListenable: _drawerAward,
                    builder: (ctx, awardId, _) {
                      if (awardId == null) return const SizedBox.shrink();
                      final a = lib.awards.where((x) => x.id == awardId).firstOrNull;
                      if (a == null) return const SizedBox.shrink();
                      return _drawerPanel(
                        context,
                        LegacyAwardDrawer(
                          p: p,
                          award: a,
                          onClose: _closeDrawer,
                          onEdit: () => _openAwardDialog(existing: a),
                          onDelete: () => _deleteAward(a),
                        ),
                      );
                    },
                  ),
                ]),
              ),
            ),
          ]),
        ),
        ]),
        // 桌面宠物（原版外观开关）
        if (pet)
          Positioned(
            right: 18,
            bottom: 18,
            child: InkWell(
              onTap: () {
                final lines = [
                  '喵～今天也要加油鸭！',
                  '喵？临期线快到了哦，看看总览的紧急区吧。',
                  '喵呜～记得给辛苦的自己一点奖励。',
                  '喵！数据都好好备份着呢，放心～',
                ];
                appToast(lines[DateTime.now().second % lines.length]);
              },
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: p.card,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.hairline),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 3)),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text('🐱', style: TextStyle(fontSize: 24)),
              ),
            ),
          ),
      ]),
    );
  }

  void _openCompDrawer(String id) => _drawerComp.value = id;
  void _openAwardDrawer(String id) => _drawerAward.value = id;
  void _closeDrawer() {
    _drawerComp.value = null;
    _drawerAward.value = null;
  }

  void _openCompDialog({Competition? existing}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => LegacyCompDialog(
        existing: existing,
        palette: context.legacy,
      ),
    ).then((saved) {
      if (saved == true) _closeDrawer();
    });
  }

  void _openAwardDialog({Award? existing}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => LegacyAwardDialog(existing: existing, palette: context.legacy),
    ).then((saved) {
      if (saved == true) _closeDrawer();
    });
  }

  Future<void> _deleteComp(Competition c) async {
    final ok = await confirmDialog(context, '删除比赛',
        '确定删除「${c.name}」？删除前会自动备份。', okText: '删除', danger: true);
    if (ok == true) {
      await ref.read(libraryProvider.notifier).deleteCompById(c.id);
      appToast('已删除');
      _closeDrawer();
    }
  }

  Future<void> _deleteAward(Award a) async {
    final ok = await confirmDialog(context, '删除获奖记录',
        '确定删除这条获奖记录？删除前会自动备份。', okText: '删除', danger: true);
    if (ok == true) {
      await ref.read(libraryProvider.notifier).deleteAwardById(a.id);
      appToast('已删除');
      _closeDrawer();
    }
  }

  Future<void> _importFile() async {
    if (_busyImport) return;
    const group = XTypeGroup(
        label: '备份与数据', extensions: ['zip', 'json', 'md', 'markdown', 'txt']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    setState(() => _busyImport = true);
    final progress = ValueNotifier<String>('准备导入…');
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: context.legacy.card,
            content: ValueListenableBuilder<String>(
              valueListenable: progress,
              builder: (ctx, text, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(text),
                ],
              ),
            ),
          ),
        ),
      );
    }
    try {
      final bytes = await file.readAsBytes();
      final bundle = parseSourceBytes(bytes, file.name, includeCerts: _includeCerts);
      final report = await ref.read(libraryProvider.notifier).applyBundle(
            bundle,
            onProgress: (stage, cur, total) {
              final names = {
                ImportStage.parse: '解析记录',
                ImportStage.certs: '复制凭证',
                ImportStage.records: '写入记录',
                ImportStage.verify: '校验引用',
                ImportStage.done: '完成',
              };
              progress.value =
                  '${names[stage]} $cur / $total';
            },
          );
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        appToast('导入完成：${report.summary()}'
            '${report.warnings.isEmpty ? '' : '（含 ${report.warnings.length} 项提示）'}');
      }
    } catch (err) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        appToast('导入失败：$err', error: true);
      }
    } finally {
      if (mounted) setState(() => _busyImport = false);
    }
  }

  // -------------------------------------------------------------------

  Widget _header(BuildContext context, LegacyPalette p) {
    final lib = ref.watch(libraryProvider);
    final dark = ref.watch(legacyDarkProvider);
    final darkNotifier = ref.read(legacyDarkProvider.notifier);
    final categories = <String>{
      for (final c in lib.comps)
        ...competitionDirections(c),
    }.toList()
      ..sort();
    return Container(
      color: p.headerBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration:
              BoxDecoration(color: p.primary, shape: BoxShape.circle),
          child: Icon(Icons.calendar_month, size: 18, color: p.onPrimary),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('工作日历',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: p.primary)),
          Text('WorkCalendar · 本地单机',
              style: TextStyle(fontSize: 10, color: p.muted)),
        ]),
        const Spacer(),
        SizedBox(
          width: 200,
          child: TextField(
            controller: _searchCtrl,
            style: TextStyle(fontSize: 13, color: p.text),
            decoration: lInputDeco(p, '搜索…',
                prefixIcon: Icon(Icons.search,
                    size: 18, color: p.muted)),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 10),
        _dropdown(p, _category, categories,
            (v) => setState(() => _category = v)),
        const SizedBox(width: 10),
        _statusDropdown(p),
        const SizedBox(width: 10),
        LButton(
            label: '＋ 添加比赛',
            kind: LBtnKind.primary,
            onPressed: () => _openCompDialog()),
        const SizedBox(width: 10),
        LButton(
            label: _busyImport ? '导入中…' : '导入',
            onPressed: _busyImport ? null : _importFile),
        const SizedBox(width: 10),
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => darkNotifier.set(!dark),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: p.dark ? const Color(0xFF2A2E36) : const Color(0xFFEDF0F7),
              shape: BoxShape.circle,
            ),
            child: Icon(
              dark ? Icons.light_mode : Icons.dark_mode,
              size: 17,
              color: p.muted,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _statusDropdown(LegacyPalette p) {
    const options = <(String, String)>[
      ('', '全部状态（隐藏过期）'),
      ('all', '👁 全览（含过期）'),
      ('urgent', '🚨 即将截止'),
      ('past_suggested', '⚠️ 已过临期线'),
      ('submitting', '进行中'),
      ('open', '报名中'),
      ('not_started', '未开始'),
      ('overdue', '已截止'),
      ('submitted', '已提交'),
      ('done', '已完成'),
      ('abandoned', '已放弃'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.hairline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _statusFilter,
          isDense: true,
          style: TextStyle(fontSize: 12.5, color: p.text),
          dropdownColor: p.card,
          borderRadius: BorderRadius.circular(12),
          items: [
            for (final (v, label) in options)
              DropdownMenuItem(value: v, child: Text(label)),
          ],
          onChanged: (v) => setState(() => _statusFilter = v ?? ''),
        ),
      ),
    );
  }

  Widget _dropdown(LegacyPalette p, String current, List<String> options,
      ValueChanged<String> onPick) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.hairline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: current,
          isDense: true,
          style: TextStyle(fontSize: 12.5, color: p.text),
          dropdownColor: p.card,
          borderRadius: BorderRadius.circular(12),
          items: [
            const DropdownMenuItem(value: '', child: Text('全部类别')),
            for (final c in options) DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) => onPick(v ?? ''),
        ),
      ),
    );
  }

  Widget _nav(BuildContext context, LegacyPalette p, LibraryState lib, WcRepository repo) {
    Widget item(_LegacyView view, IconData icon, String label,
        {bool enabled = true, String? badge, String? tooltip}) {
      final selected = _view == view;
      final row = Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? (p.dark ? LegacyTokens.navActiveBgD : LegacyTokens.navActiveBgL)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(children: [
          Icon(icon,
              size: 18,
              color: enabled
                  ? (selected
                      ? (p.dark
                          ? LegacyTokens.navActiveTextD
                          : LegacyTokens.navActiveTextL)
                      : (p.dark ? LegacyTokens.navTextD : LegacyTokens.navTextL))
                  : p.muted.withValues(alpha: 0.6)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: enabled
                        ? (selected
                            ? (p.dark
                                ? LegacyTokens.navActiveTextD
                                : LegacyTokens.navActiveTextL)
                            : (p.dark
                                ? LegacyTokens.navTextD
                                : LegacyTokens.navTextL))
                        : p.muted.withValues(alpha: 0.6))),
          ),
          if (badge != null && badge.isNotEmpty)
            Text(badge,
                style: TextStyle(
                    fontSize: 10.5, color: p.muted, fontWeight: FontWeight.w600)),
        ]),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: enabled
            ? InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => setState(() => _view = view),
                child: row,
              )
            : Tooltip(message: tooltip ?? '', child: row),
      );
    }

    return Container(
      width: 192,
      color: p.navBg,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 12, 6),
          child: Text('浏览',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.6,
                  color: p.dark ? const Color(0xFF6B7079) : const Color(0xFF8A8F9E))),
        ),
        item(_LegacyView.overview, Icons.grid_view_outlined, '总览'),
        item(_LegacyView.list, Icons.list, '列表',
            badge: '${repo.compCount}'),
        item(_LegacyView.timeline, Icons.calendar_today_outlined, '时间线'),
        item(_LegacyView.ai, Icons.smart_toy_outlined, 'AI 助手'),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 12, 6),
          child: Text('管理',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.6,
                  color: p.dark ? const Color(0xFF6B7079) : const Color(0xFF8A8F9E))),
        ),
        item(_LegacyView.awards, Icons.workspace_premium_outlined, '获奖',
            badge: '${repo.awardCount}'),
        item(_LegacyView.settings, Icons.settings_outlined, '设置'),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: p.portInfo,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('📦 ${repo.compCount} 个比赛 · ${repo.awardCount} 获奖',
                  style: TextStyle(fontSize: 11, color: p.muted)),
              const SizedBox(height: 2),
              Text('本地优先 · 同步需手动开启',
                  style: TextStyle(fontSize: 10, color: p.muted)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _viewBody(BuildContext context, LegacyPalette p, List<Competition> visible) {
    final lib = ref.watch(libraryProvider);
    switch (_view) {
      case _LegacyView.ai: return const ManagementPage();
      case _LegacyView.overview:
        return LegacyOverview(
          p: p,
          visible: visible,
          all: lib.comps,
          bannerDismissed: _bannerDismissed,
          onDismissBanner: () => setState(() => _bannerDismissed = true),
          onOpenComp: _openCompDrawer,
          portText: '本地单机',
        );
      case _LegacyView.list:
        return LegacyList(
          p: p,
          visible: visible,
          onOpenDrawer: _openCompDrawer,
          onEdit: (c) => _openCompDialog(existing: c),
        );
      case _LegacyView.timeline:
        return LegacyTimeline(p: p, visible: visible, onOpenDrawer: _openCompDrawer);
      case _LegacyView.awards:
        return LegacyAwards(
          p: p,
          onOpenDrawer: _openAwardDrawer,
          onEdit: (a) => _openAwardDialog(existing: a),
        );
      case _LegacyView.settings:
        return LegacySettingsPage(p: p);
    }
  }

  Widget _drawerPanel(BuildContext context, Widget child) {
    final width = MediaQuery.sizeOf(context).width;
    final panelWidth = width < 540 ? width * 0.94 : 500.0;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: panelWidth,
        height: double.infinity,
        decoration: BoxDecoration(
          color: context.legacy.drawerBg,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(-4, 0)),
          ],
        ),
        child: child,
      ),
    );
  }
}
