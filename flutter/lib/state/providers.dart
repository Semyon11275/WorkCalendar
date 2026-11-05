/// 状态层：仓库单例 + 列表状态 + 筛选器 + 主题偏好。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/exchange.dart';
import '../data/repository.dart';
import '../domain/models.dart';
import '../domain/classification.dart';
import '../domain/stats.dart';

/// 在 main() 中 override：启动时打开仓库后注入。
final repositoryProvider = Provider<WcRepository>(
    (ref) => throw UnimplementedError('repositoryProvider 必须在启动时 override'));

/// 默认数据目录，按优先级：
/// 1) 环境变量 WC_DATA_DIR 显式指定；
/// 2) 便携模式：exe 同级存在 data/ 目录（含 .portable 标记或任意内容）时，
///    数据存工作区/程序目录内——与 0.5.0 便携版习惯一致，数据不进 C 盘；
/// 3) 系统用户数据目录（安装版默认）。
Future<String> defaultDataDir() async {
  final env = Platform.environment['WC_DATA_DIR'];
  if (env != null && env.trim().isNotEmpty) {
    return env.trim();
  }
  if (!Platform.isAndroid && !Platform.isIOS) {
    try {
      // 注意：Flutter Windows 包自带 data/（运行时资源），不能用作判断；
      // 便携模式以 userdata/.portable 标记为准，用户数据独立于运行时目录。
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final portableData = p.join(exeDir, 'userdata');
      if (File(p.join(portableData, '.portable')).existsSync()) {
        return portableData;
      }
    } on FileSystemException {
      // 解析失败按安装版处理
    }
  }
  final support = await getApplicationSupportDirectory();
  if (Platform.isAndroid || Platform.isIOS) {
    return p.join(support.path, 'data');
  }
  return p.join(support.path, 'WorkCalendar');
}

/// Android 上旧 0.5.0 的 wc_data 目录（Capacitor DATA = files 目录），
/// 存在则导入页提供一键迁移。返回 null 表示未检测到。
Future<String?> legacyAndroidDataDir() async {
  if (!Platform.isAndroid) return null;
  final support = await getApplicationSupportDirectory();
  final candidate = p.join(support.path, 'wc_data');
  if (await Directory(p.join(candidate, 'competitions.json')).parent.exists()) {
    return candidate;
  }
  return null;
}

// -----------------------------------------------------------------------------
// 库状态（写后自动刷新快照）
// -----------------------------------------------------------------------------

class LibraryState {
  const LibraryState(this.comps, this.awards, this.stats, this.awardStats);
  final List<Competition> comps;
  final List<Award> awards;
  final Stats stats;
  final AwardStats awardStats;
}

class LibraryNotifier extends Notifier<LibraryState> {
  @override
  LibraryState build() {
    final repo = ref.watch(repositoryProvider);
    final comps = repo.allComps();
    return LibraryState(
        comps, repo.allAwards(), computeStats(comps), computeAwardStats(repo.allAwards()));
  }

  WcRepository get _repo => ref.read(repositoryProvider);

  Future<void> _refresh() async {
    final comps = _repo.allComps();
    state = LibraryState(
        comps, _repo.allAwards(), computeStats(comps), computeAwardStats(_repo.allAwards()));
  }

  Future<void> saveComp(Competition c) async {
    await _repo.upsertComp(c);
    await _refresh();
  }

  Future<void> deleteCompById(String id) async {
    await _repo.deleteComp(id);
    await _refresh();
  }

  Future<void> saveAward(Award a) async {
    await _repo.upsertAward(a);
    await _refresh();
  }

  Future<void> deleteAwardById(String id) async {
    await _repo.deleteAward(id);
    await _refresh();
  }

  Future<ImportRecordReport> applyBundle(ImportBundle bundle,
      {bool updateExisting = true,
      void Function(ImportStage stage, int current, int total)? onProgress}) async {
    final report = await _repo.applyImport(
      compRecords: bundle.comps,
      awardRecords: bundle.awards,
      certificates: bundle.certificates,
      updateExisting: updateExisting,
      onProgress: onProgress,
    );
    await _refresh();
    return report;
  }

  /// 设置状态覆盖的快捷方式（详情页一键标记）。
  Future<void> markStatus(String compId, String? override) async {
    final c = _repo.getComp(compId);
    if (c == null) return;
    c.statusOverride = override;
    await _repo.upsertComp(c);
    await _refresh();
  }

  /// 向获奖记录追加凭证文件名。
  Future<void> attachCerts(String awardId, List<String> names) async {
    final a = _repo.getAward(awardId);
    if (a == null) return;
    a.certificateFiles = [...a.certificateFiles, ...names];
    await _repo.upsertAward(a);
    await _refresh();
  }

  Future<void> removeCert(String awardId, String name) async {
    final a = _repo.getAward(awardId);
    if (a == null) return;
    a.certificateFiles = a.certificateFiles.where((f) => f != name).toList();
    await _repo.upsertAward(a);
    await _refresh();
  }
}

final libraryProvider =
    NotifierProvider<LibraryNotifier, LibraryState>(LibraryNotifier.new);

// -----------------------------------------------------------------------------
// 比赛筛选/搜索/排序
// -----------------------------------------------------------------------------

enum CompSort { deadline, suggested, updatedDesc, name }

class CompsFilter {
  CompsFilter({
    this.keyword = '',
    this.statuses = const {},
    this.categories = const {},
    this.showStale = false,
    this.sort = CompSort.suggested,
  });

  final String keyword;
  final Set<String> statuses;
  final Set<String> categories; // 空集 = 全部类别
  final bool showStale;
  final CompSort sort;

  bool get hasFilter =>
      keyword.isNotEmpty || statuses.isNotEmpty || categories.isNotEmpty || showStale;

  CompsFilter copyWith({
    String? keyword,
    Set<String>? statuses,
    Set<String>? categories,
    bool? showStale,
    CompSort? sort,
  }) =>
      CompsFilter(
          keyword: keyword ?? this.keyword,
          statuses: statuses ?? this.statuses,
          categories: categories ?? this.categories,
          showStale: showStale ?? this.showStale,
          sort: sort ?? this.sort);
}

class CompsFilterNotifier extends Notifier<CompsFilter> {
  @override
  CompsFilter build() => CompsFilter();

  void update(CompsFilter f) => state = f;
}

final compsFilterProvider =
    NotifierProvider<CompsFilterNotifier, CompsFilter>(CompsFilterNotifier.new);

/// 应用筛选与过期隐藏后的可见比赛（导出/备份不经过这里）。
/// 过期隐藏仅对「无任何筛选」的默认列表生效——关键词搜索或点任何状态
/// 筛选即穿透隐藏（对齐 0.5.0 的行为：不能让用户在筛选时疑惑数据丢失）。
final visibleCompsProvider = Provider<List<Competition>>((ref) {
  final lib = ref.watch(libraryProvider);
  final f = ref.watch(compsFilterProvider);
  final kw = f.keyword.trim().toLowerCase();
  final filtering = kw.isNotEmpty || f.statuses.isNotEmpty || f.categories.isNotEmpty;
  Iterable<Competition> out = lib.comps;
  if (!f.showStale && !filtering) {
    out = out.where((c) => !c.isStaleHidden());
  }
  if (f.statuses.isNotEmpty) {
    out = out.where((c) => f.statuses.contains(c.status()));
  }
  if (f.categories.isNotEmpty) {
    out = out.where((c) => competitionDirections(c).any(f.categories.contains));
  }
  if (kw.isNotEmpty) {
    out = out.where((c) =>
        c.name.toLowerCase().contains(kw) ||
        c.notes.toLowerCase().contains(kw) ||
        c.category.toLowerCase().contains(kw) ||
        c.organizer.toLowerCase().contains(kw) ||
        c.tags.any((t) => '$t'.toLowerCase().contains(kw)));
  }
  final list = out.toList();
  switch (f.sort) {
    case CompSort.deadline:
      list.sort((a, b) => a.deadline.compareTo(b.deadline));
    case CompSort.suggested:
      list.sort((a, b) => a.effectiveSuggested().compareTo(b.effectiveSuggested()));
    case CompSort.updatedDesc:
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    case CompSort.name:
      list.sort((a, b) => a.name.compareTo(b.name));
  }
  return list;
});

/// 被过期隐藏隐藏的条数（列表页提示用）。
final staleHiddenCountProvider = Provider<int>((ref) {
  final lib = ref.watch(libraryProvider);
  return lib.comps.where((c) => c.isStaleHidden()).length;
});

// -----------------------------------------------------------------------------
// 获奖筛选
// -----------------------------------------------------------------------------

class AwardGroupingNotifier extends Notifier<AwardGrouping> {
  @override
  AwardGrouping build() {
    final saved = readAppSettings(ref.watch(repositoryProvider))['award_grouping'];
    return AwardGrouping.values.where((v) => v.name == saved).firstOrNull ?? AwardGrouping.competition;
  }
  Future<void> select(AwardGrouping value) async {
    state = value;
    await writeAppSetting(ref.read(repositoryProvider), 'award_grouping', value.name);
  }
}
final awardGroupingProvider = NotifierProvider<AwardGroupingNotifier, AwardGrouping>(AwardGroupingNotifier.new);

class AwardFilter {
  AwardFilter({this.keyword = '', this.level = '', this.firstOnly = false});
  final String keyword;
  final String level; // '' = 全部
  final bool firstOnly;

  bool get hasFilter => keyword.isNotEmpty || level.isNotEmpty || firstOnly;

  AwardFilter copyWith({String? keyword, String? level, bool? firstOnly}) =>
      AwardFilter(
          keyword: keyword ?? this.keyword,
          level: level ?? this.level,
          firstOnly: firstOnly ?? this.firstOnly);
}

class AwardFilterNotifier extends Notifier<AwardFilter> {
  @override
  AwardFilter build() => AwardFilter();

  void update(AwardFilter f) => state = f;
}

final awardFilterProvider =
    NotifierProvider<AwardFilterNotifier, AwardFilter>(AwardFilterNotifier.new);

/// 按关联比赛分组（旧版规则：competition 文本分组，空为「其他」，按组内条数降序）。
final groupedAwardsProvider = Provider<List<MapEntry<String, List<Award>>>>((ref) {
  final lib = ref.watch(libraryProvider);
  final f = ref.watch(awardFilterProvider);
  final kw = f.keyword.trim().toLowerCase();
  var list = lib.awards;
  if (f.level.isNotEmpty) list = list.where((a) => a.level == f.level).toList();
  if (f.firstOnly) list = list.where((a) => a.isFirstAuthor).toList();
  if (kw.isNotEmpty) {
    list = list
        .where((a) =>
            a.name.toLowerCase().contains(kw) ||
            a.competition.toLowerCase().contains(kw) ||
            a.notes.toLowerCase().contains(kw) ||
            a.awardRank.toLowerCase().contains(kw))
        .toList();
  }
  final groups = <String, List<Award>>{};
  for (final a in list) {
    groups.putIfAbsent(awardGroup(a, ref.watch(awardGroupingProvider)), () => []).add(a);
  }
  final keys = groups.keys.toList()
    ..sort((x, y) => groups[y]!.length.compareTo(groups[x]!.length));
  return [for (final k in keys) MapEntry(k, groups[k]!)];
});

// -----------------------------------------------------------------------------
// 应用偏好（数据目录 settings.json；统一合并读写，避免各设置项互相覆盖）
// -----------------------------------------------------------------------------

Map<String, dynamic> readAppSettings(WcRepository repo) {
  try {
    final f = File(p.join(repo.dataDir, 'settings.json'));
    if (f.existsSync()) {
      final v = jsonDecode(f.readAsStringSync());
      if (v is Map<String, dynamic>) return v;
    }
  } on Exception {
    // 读取失败按默认
  }
  return {};
}

Future<void> writeAppSetting(
    WcRepository repo, String key, Object? value) async {
  try {
    final m = readAppSettings(repo)
      ..[key] = value;
    final f = File(p.join(repo.dataDir, 'settings.json'));
    await f.writeAsString(jsonEncode(m), flush: true);
  } on Exception {
    // 写入失败不影响运行
  }
}

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final v = int.tryParse('${readAppSettings(ref.watch(repositoryProvider))['theme_mode']}');
    if (v != null) return ThemeMode.values[v.clamp(0, 2)];
    return ThemeMode.system;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await writeAppSetting(ref.read(repositoryProvider), 'theme_mode', mode.index);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

// -----------------------------------------------------------------------------
// 界面模式：design（新设计稿体系）| legacy（旧版界面 0.4.2 wenku8 完整还原）
// 切换只改界面表现，共用同一套业务数据与规则。
// -----------------------------------------------------------------------------

class UiModeNotifier extends Notifier<String> {
  @override
  String build() {
    final v = readAppSettings(ref.watch(repositoryProvider))['ui_mode'];
    return v == 'legacy' ? 'legacy' : 'design';
  }

  Future<void> set(String mode) async {
    state = mode == 'legacy' ? 'legacy' : 'design';
    await writeAppSetting(ref.read(repositoryProvider), 'ui_mode', state);
  }
}

final uiModeProvider = NotifierProvider<UiModeNotifier, String>(UiModeNotifier.new);

/// 旧版界面自身的深浅色开关（原版 header 右上角切换按钮）。
class LegacyDarkNotifier extends Notifier<bool> {
  @override
  bool build() {
    final v = readAppSettings(ref.watch(repositoryProvider))['legacy_dark'];
    return v is bool ? v : false;
  }

  Future<void> set(bool on) async {
    state = on;
    await writeAppSetting(ref.read(repositoryProvider), 'legacy_dark', on);
  }
}

final legacyDarkProvider =
    NotifierProvider<LegacyDarkNotifier, bool>(LegacyDarkNotifier.new);

/// 旧版界面：桌面宠物开关。
class LegacyPetNotifier extends Notifier<bool> {
  @override
  bool build() {
    final v = readAppSettings(ref.watch(repositoryProvider))['legacy_pet'];
    return v is bool ? v : false;
  }

  Future<void> set(bool on) async {
    state = on;
    await writeAppSetting(ref.read(repositoryProvider), 'legacy_pet', on);
  }
}

final legacyPetProvider =
    NotifierProvider<LegacyPetNotifier, bool>(LegacyPetNotifier.new);

/// 旧版界面：壁纸刷新信号（壁纸文件存在即显示）。
class LegacyWallpaperNotifier extends Notifier<int> {
  @override
  int build() {
    final v = readAppSettings(ref.watch(repositoryProvider))['wallpaper'];
    return v == '1' ? 1 : 0;
  }

  void bump() {
    final v = readAppSettings(ref.watch(repositoryProvider))['wallpaper'];
    state = v == '1' ? 1 : 0;
  }
}

final legacyWallpaperProvider =
    NotifierProvider<LegacyWallpaperNotifier, int>(LegacyWallpaperNotifier.new);

// -----------------------------------------------------------------------------
// 外观：皮肤种子色 / 思源宋体 / 减少动效（对齐 0.5.0 的 wenku8 主题体系）
// -----------------------------------------------------------------------------

/// 皮肤预设：design=true 走设计稿 token 体系（炭黑/暖白/荧光黄），
/// 其余走 M3 seed 体系。
const skinPresets = [
  (name: '炭黑荧光黄', seed: Color(0xFFF6E71A), design: true),
  (name: 'wenku8 蓝', seed: Color(0xFF2F6FBF), design: false),
  (name: '靛蓝', seed: Color(0xFF3B5BDB), design: false),
  (name: '青碧', seed: Color(0xFF0F766E), design: false),
  (name: '暮紫', seed: Color(0xFF6D5BA6), design: false),
];

class SkinSeedNotifier extends Notifier<int> {
  @override
  int build() {
    final v = int.tryParse('${readAppSettings(ref.watch(repositoryProvider))['skin_seed']}');
    if (v != null) return v.clamp(0, skinPresets.length - 1);
    return 0; // wenku8 蓝为默认（0.5.0 观感）
  }

  Future<void> set(int index) async {
    state = index.clamp(0, skinPresets.length - 1);
    await writeAppSetting(ref.read(repositoryProvider), 'skin_seed', state);
  }
}

final skinSeedProvider = NotifierProvider<SkinSeedNotifier, int>(SkinSeedNotifier.new);

class SerifFontNotifier extends Notifier<bool> {
  @override
  bool build() {
    final v = readAppSettings(ref.watch(repositoryProvider))['serif_font'];
    return v is bool ? v : false; // 设计稿正文为 sans；宋体可手动开启
  }

  Future<void> set(bool on) async {
    state = on;
    await writeAppSetting(ref.read(repositoryProvider), 'serif_font', on);
  }
}

final serifFontProvider = NotifierProvider<SerifFontNotifier, bool>(SerifFontNotifier.new);

/// 减少动效（对齐旧版 prefers-reduced-motion / motion-reduced 降级）。
class ReducedMotionNotifier extends Notifier<bool> {
  @override
  bool build() {
    final v = readAppSettings(ref.watch(repositoryProvider))['reduced_motion'];
    return v is bool ? v : false;
  }

  Future<void> set(bool on) async {
    state = on;
    await writeAppSetting(ref.read(repositoryProvider), 'reduced_motion', on);
  }
}

final reducedMotionProvider =
    NotifierProvider<ReducedMotionNotifier, bool>(ReducedMotionNotifier.new);
