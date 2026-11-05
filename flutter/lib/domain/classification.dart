/// Display classifications; original imported fields are never rewritten.
library;

import 'models.dart';

const directionKeywords = <String, List<String>>{
  '视觉传达': ['视觉', '平面', '海报', '字体', '标志', '品牌', '广告', '插画', 'vi'],
  '文创与IP': ['文创', 'ip', '形象', '吉祥物', '非遗', '礼物', '文旅'],
  '产品与工业': ['产品', '工业', '家具', '家居', '器物', '消费', '装备', '智能硬件'],
  '包装设计': ['包装'],
  '空间与环境': ['空间', '建筑', '景观', '室内', '环境', '展陈', '布景'],
  '服饰与工艺': ['服装', '服饰', '纺织', '首饰', '珠宝', '工艺', '陶瓷'],
  '数字与交互': ['交互', 'ui', 'ux', '数字', '游戏', '网页', '应用', '可视化'],
  '影像与动画': ['影像', '视频', '短剧', '电影', '摄影', '动画', '纪录片', '短片'],
  'AI与生成设计': ['ai', '人工智能', '生成'],
  '综合设计': ['综合', '综合设计'],
};

Set<String> competitionDirections(Competition c) {
  final manual = c.extra['directions'];
  if (manual is List && manual.isNotEmpty) {
    return manual.map((v) => '$v').toSet();
  }
  // Classify the category description, not arbitrary organizer/name text.
  final text = c.category.toLowerCase();
  final result = <String>{};
  for (final entry in directionKeywords.entries) {
    if (entry.value.any(text.contains)) result.add(entry.key);
  }
  return result.isEmpty ? {'待归类'} : result;
}

enum AwardGrouping { competition, level, year }

const awardGroupingLabels = {
  AwardGrouping.competition: '比赛系列',
  AwardGrouping.level: '获奖级别',
  AwardGrouping.year: '获奖年份',
};
String awardGroup(Award a, AwardGrouping grouping) => switch (grouping) {
  AwardGrouping.competition =>
    a.competition.trim().isEmpty ? '未关联比赛' : a.competition.trim(),
  AwardGrouping.level => a.level.isEmpty ? '未填写级别' : a.level,
  AwardGrouping.year => a.awardDate == null ? '未填写年份' : '${a.awardDate!.year}年',
};
