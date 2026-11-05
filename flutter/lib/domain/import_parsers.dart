/// 导入解析：JSON（单条/数组/{competitions:[]}）与 Markdown 表格。
///
/// 移植旧版 importer.py：表头别名、顶层结构键、格式自动探测顺序
/// （JSON 优先，失败落 Markdown 表格）保持一致。
library;

import 'dart:convert';

import 'rules.dart';

/// 比赛记录的原始字典（未定型），供合并与预览使用。
typedef RawRecord = Map<String, dynamic>;

const Set<String> _acceptedKeys = {'competitions', 'items', 'records', 'data'};

/// Markdown 表头 → 字段 的中英文别名（与 importer.py 一致）。
const Map<String, List<String>> mdColAliases = {
  'name': ['名称', 'name', '比赛', '比赛名称'],
  'deadline': ['截止', 'deadline', '截止日期', '截止时间', '提交截止'],
  'suggested_deadline': ['临期线', '建议死线', '建议截止', '校内截止', 'suggested_deadline'],
  'category': ['类别', 'category', '分类'],
  'organizer': ['主办方', 'organizer', '主办'],
  'website': ['官网', 'website', '网址', '链接', '官网链接'],
  'requirements': ['要求', 'requirements', '作品要求'],
  'notes': ['备注', 'notes', '说明'],
};

/// 解析 JSON 文本 → 记录字典列表。支持单条对象 / 数组 / {competitions:[...]}。
List<RawRecord> parseJsonText(String text) {
  final Object? data;
  try {
    data = const JsonDecoder().convert(text);
  } on FormatException catch (e) {
    throw ValidationError('JSON 解析失败: ${e.message}');
  }
  return jsonToRecords(data);
}

/// JSON 值 → 记录字典列表。dict 时按 _acceptedKeys 取内层数组，
/// 否则视为单条记录；内层仍为 dict 则也是单条（与旧版行为一致）。
List<RawRecord> jsonToRecords(Object? data) {
  if (data is Map<String, dynamic>) {
    for (final key in _acceptedKeys) {
      final inner = data[key];
      if (inner is List) return jsonToRecords(inner);
    }
    return [data];
  }
  if (data is List) {
    return [for (final d in data) if (d is Map<String, dynamic>) d];
  }
  throw ValidationError('JSON 顶层必须是对象或数组');
}

/// 解析 Markdown 表格 → 记录字典列表。首行表头按别名映射字段，未知列忽略。
/// 行首尾的管道符先剥除再分列（与旧版 strip('|') 一致），否则首末空单元格会错位。
List<RawRecord> parseMarkdownTable(String text) {
  final allLines = text.split('\n').map((l) => l.trim()).toList();
  final lines = allLines
      .where((l) => l.startsWith('|') && l.length > 1 && l.contains('|', 1))
      .toList();
  if (lines.length < 2) throw ValidationError('未找到 Markdown 表格');

  String stripPipes(String line) {
    var s = line;
    while (s.startsWith('|')) {
      s = s.substring(1);
    }
    while (s.endsWith('|')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  final cols = stripPipes(lines[0]).split('|').map((c) => c.trim()).toList();
  final sepRe = RegExp(r'^[\s\-:|]+$');
  if (stripPipes(lines[1]).split('|').every((c) => sepRe.hasMatch(c.trim()))) {
    lines.removeAt(1);
  }
  final fieldMap = <String?>[];
  for (final col in cols) {
    String? f;
    for (final e in mdColAliases.entries) {
      if (e.value.contains(col)) {
        f = e.key;
        break;
      }
    }
    fieldMap.add(f);
  }
  final records = <RawRecord>[];
  for (final ln in lines.skip(1)) {
    final cells = stripPipes(ln).split('|').map((c) => c.trim()).toList();
    final rec = <String, dynamic>{};
    for (var i = 0; i < cells.length; i++) {
      if (i < fieldMap.length && fieldMap[i] != null && cells[i].isNotEmpty) {
        rec[fieldMap[i]!] = cells[i];
      }
    }
    if ((rec['name'] as String? ?? '').isNotEmpty ||
        (rec['deadline'] as String? ?? '').isNotEmpty) {
      records.add(rec);
    }
  }
  if (records.isEmpty) throw ValidationError('未找到 Markdown 表格');
  return records;
}

/// 自动探测格式：JSON 优先（{ 或 [ 开头），失败尝试 Markdown 表格。
List<RawRecord> parseText(String text) {
  final stripped = text.trim();
  if (stripped.isEmpty) throw ValidationError('内容为空');
  if (stripped.startsWith('{') || stripped.startsWith('[')) {
    try {
      return parseJsonText(stripped);
    } on ValidationError {
      // 落到 Markdown 表格
    }
  }
  try {
    return parseMarkdownTable(stripped);
  } on ValidationError {
    throw ValidationError('无法识别内容格式（支持 JSON 或 Markdown 表格）');
  }
}

/// 判断记录字典更像比赛还是获奖（用于混合 JSON 的分流）。
bool looksLikeAward(RawRecord r) =>
    r.containsKey('level') ||
    r.containsKey('award_date') ||
    r.containsKey('award_rank') ||
    (!r.containsKey('deadline') && (r.containsKey('certificate_files') || r.containsKey('certificate')));
