/// 核心业务规则：日期解析、名称归一化、去重键、旧版兼容 ID、状态与倒计时。
///
/// 规则自 0.5.0 的 app/models.py 与 web/core.js 逐条移植；两处旧实现
/// 有差异的地方（大小写折叠、倒计时取整）以 Python 版为准并在测试中固化。
/// 所有函数为纯函数，不依赖 Flutter 与 IO。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

/// 未填临期线时的默认缓冲天数。
const int defaultBufferDays = 3;

/// 临期线前 N 天进入「即将截止」。
const int urgentDays = 7;

/// 允许的人工状态覆盖。
const Set<String> validOverrides = {'submitted', 'done', 'abandoned'};

/// 记录来源。
const Set<String> validSources = {'agent', 'manual', 'file'};

/// 合法获奖级别（宽松原则：非法值回落「校级」不报错，与旧版一致）。
const List<String> validAwardLevels = ['校级', '市级', '省级', '国家级', '国际级'];

/// 自动状态与覆盖状态的中文标签。
const Map<String, String> statusLabels = {
  'not_started': '未开始',
  'open': '报名中',
  'submitting': '待提交',
  'urgent': '即将截止',
  'past_suggested': '已过临期线',
  'overdue': '已截止',
  'submitted': '已提交',
  'done': '已归档',
  'abandoned': '已放弃',
};

/// 单条记录校验失败（携带可读中文原因）。
class ValidationError implements Exception {
  ValidationError(this.message);
  final String message;

  @override
  String toString() => message;
}

final RegExp _dateRe = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');

/// 解析 YYYY-MM-DD（容错 1 位月/日）；非法输入返回 null，不抛异常。
DateTime? parseDate(Object? value) {
  if (value == null || value == '') return null;
  if (value is DateTime) {
    return DateTime(value.year, value.month, value.day);
  }
  final s = value.toString().trim();
  final m = _dateRe.firstMatch(s);
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  try {
    final parsed = DateTime(y, mo, d);
    // DateTime 会溢出进位（如 2026-02-31），必须回验。
    if (parsed.year != y || parsed.month != mo || parsed.day != d) return null;
    return parsed;
  } on ArgumentError {
    return null;
  }
}

/// 日期 → ISO 字符串（YYYY-MM-DD）。
String? dateIso(DateTime? d) =>
    d == null ? null : '${_two(d.year)}-${_two(d.month)}-${_two(d.day)}';

String _two(int n) => n.toString().padLeft(2, '0');

/// 自然日差：a − b（与旧版 daysBetween 一致，按日历日计算，无时区换算）。
/// 用分钟差再取整，避免夏令时 ±1 小时导致整天差偏移。
int daysBetween(DateTime a, DateTime b) {
  final ea = DateTime(a.year, a.month, a.day);
  final eb = DateTime(b.year, b.month, b.day);
  return (ea.difference(eb).inMinutes / 1440).round();
}

/// 今天（本地时区的零点，日期语义）。
DateTime today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

// ---------------------------------------------------------------------------
// 名称归一化与去重键（对齐 models.normalize_name / core.normalizeName）
// ---------------------------------------------------------------------------

const String _fwSrc =
    'ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺ'
    'ａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ'
    '０１２３４５６７８９　（）：，。！？；‘’“”';
const String _fwDst =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    'abcdefghijklmnopqrstuvwxyz'
    '0123456789 ():,.!?;\'\'""';

final Map<String, String> _fullwidthMap = Map.fromIterables(
    _fwSrc.split(''), _fwDst.split(''));

/// 去重键用：去首尾空白、全角转半角（含字母数字）、折叠空白、大小写折叠。
///
/// Python 的 casefold 与 JS 的 toLowerCase 并不完全一致（如 ß）；
/// 这里显式补上最常见的 ß→ss，其余按 toLowerCase，差异已记录在交付报告。
String normalizeName(Object? name) {
  if (name == null) return '';
  var s = name.toString().trim();
  s = s.split('').map((ch) => _fullwidthMap[ch] ?? ch).join();
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  s = s.replaceAll('ß', 'ss');
  return s.toLowerCase();
}

/// 去重键 = 归一化名称 + '|' + 截止日期。同一条记录永远同键。
String dedupKey(Object? name, Object? deadline) {
  final d = parseDate(deadline);
  return '${normalizeName(name)}|${d == null ? '' : dateIso(d)}';
}

String _sha1Hex(String s) =>
    crypto.sha1.convert(utf8.encode(s)).toString();

/// 比赛 id = 'c_' + 去重键 SHA-1 前 8 位（与旧版 Python/JS 完全一致，
/// 保证与 0.5.0 数据互导时按 id 匹配合并）。
String makeCompId(Object? name, Object? deadline) =>
    'c_${_sha1Hex(dedupKey(name, deadline)).substring(0, 8)}';

/// 获奖 id = 'a_' + 归一化名称|获奖日期 的 SHA-1 前 8 位。
String makeAwardId(Object? name, Object? awardDate) {
  final d = parseDate(awardDate);
  return 'a_${_sha1Hex('${normalizeName(name)}|${d == null ? '' : dateIso(d)}').substring(0, 8)}';
}

/// 本地时间戳（与旧版 now_iso 同为本地时区带偏移的 ISO 串；简化为秒级本地时间）。
String nowIso() {
  final n = DateTime.now();
  final off = n.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  return '${_two(n.year)}-${_two(n.month)}-${_two(n.day)}'
      'T${_two(n.hour)}:${_two(n.minute)}:${_two(n.second)}'
      '$sign${_two(off.inHours.abs())}:${_two(off.inMinutes.abs() % 60)}';
}

// ---------------------------------------------------------------------------
// 状态与倒计时（输入为已解析的模型字段，见 models.dart 的扩展）
// ---------------------------------------------------------------------------

/// 临期线日期：suggested_deadline 优先，否则 deadline − bufferDays（默认 3，最小 0）。
DateTime effectiveSuggested({
  required DateTime deadline,
  DateTime? suggestedDeadline,
  int? deadlineBufferDays,
}) {
  if (suggestedDeadline != null) return suggestedDeadline;
  final buf = deadlineBufferDays == null
      ? defaultBufferDays
      : deadlineBufferDays.clamp(0, 2147483647).toInt();
  return deadline.subtract(Duration(days: buf));
}

/// 自动状态 + 人工覆盖叠加。today 为本地零点日期。
String computeStatus({
  required DateTime deadline,
  DateTime? suggestedDeadline,
  int? deadlineBufferDays,
  DateTime? signupStart,
  DateTime? signupEnd,
  String? statusOverride,
  DateTime? todayDate,
}) {
  final now = todayDate ?? today();
  if (statusOverride != null && validOverrides.contains(statusOverride)) {
    return statusOverride;
  }
  final s = effectiveSuggested(
      deadline: deadline, suggestedDeadline: suggestedDeadline, deadlineBufferDays: deadlineBufferDays);
  if (now.isAfter(deadline)) return 'overdue';
  if (now.isAfter(s)) return 'past_suggested';
  if (daysBetween(s, now) <= urgentDays) return 'urgent';
  if (signupStart != null && now.isBefore(signupStart)) return 'not_started';
  if (signupEnd != null && !now.isAfter(signupEnd)) return 'open';
  return 'submitting';
}

/// 过期隐藏（旧版 isStaleHidden）：已截止 ≥5 天且未标记完成的记录默认隐藏，
/// 仅影响展示，不影响导出/备份/统计取数。
bool isStaleHidden({
  required DateTime deadline,
  String? status,
  DateTime? todayDate,
}) {
  if (status == 'done') return false;
  return daysBetween(todayDate ?? today(), deadline) >= 5;
}
