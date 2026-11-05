/// 领域模型：Competition / Award / 里程碑。
///
/// 序列化字段名与 0.5.0 的 competitions.json / awards.json 完全一致，
/// 未知字段收入 extra 原样保留（向前兼容，不丢弃）；旧版别名
/// （certificate→certificate_files、note→notes）在解析时兼容。
library;

import 'rules.dart';

/// 里程碑：{name, date}，date 为 YYYY-MM-DD。
class Milestone {
  Milestone({required this.name, required this.date});
  final String name;
  final DateTime date;

  Map<String, dynamic> toJson() => {'name': name, 'date': dateIso(date)};

  static Milestone fromJson(Map<String, dynamic> m) {
    final d = parseDate(m['date']);
    if (d == null) {
      throw ValidationError('milestone 日期非法: ${m['date']}');
    }
    return Milestone(name: '${m['name'] ?? ''}', date: d);
  }

  @override
  bool operator ==(Object other) =>
      other is Milestone && other.name == name && other.date == date;

  @override
  int get hashCode => Object.hash(name, date);
}

/// 一条比赛记录。name/deadline 必填，其余可选。
class Competition {
  Competition({
    required this.id,
    required this.name,
    required this.deadline,
    this.suggestedDeadline,
    this.deadlineBufferDays,
    List<Milestone>? milestones,
    this.category = '',
    this.organizer = '',
    this.website = '',
    this.signupStart,
    this.signupEnd,
    this.deadlineNote = '',
    this.requirements = '',
    List<dynamic>? deliverables,
    Map<String, dynamic>? submission,
    Map<String, dynamic>? format,
    List<dynamic>? tags,
    this.statusOverride,
    List<dynamic>? reminderDays,
    this.notes = '',
    this.source = 'manual',
    this.sourceUrl = '',
    this.createdAt = '',
    this.updatedAt = '',
    Map<String, dynamic>? extra,
  })  : milestones = List<Milestone>.from(milestones ?? const []),
        deliverables = List<dynamic>.from(deliverables ?? const []),
        submission = Map<String, dynamic>.from(submission ?? const {}),
        format = Map<String, dynamic>.from(format ?? const {}),
        tags = List<dynamic>.from(tags ?? const []),
        reminderDays = List<dynamic>.from(reminderDays ?? const [7, 1]),
        extra = Map<String, dynamic>.from(extra ?? const {});

  String id;
  String name;
  DateTime deadline;
  DateTime? suggestedDeadline;
  int? deadlineBufferDays;
  List<Milestone> milestones;
  String category;
  String organizer;
  String website;
  DateTime? signupStart;
  DateTime? signupEnd;
  String deadlineNote;
  String requirements;
  List<dynamic> deliverables;
  Map<String, dynamic> submission;
  Map<String, dynamic> format;
  List<dynamic> tags;
  String? statusOverride;
  List<dynamic> reminderDays;
  String notes;
  String source;
  String sourceUrl;
  String createdAt;
  String updatedAt;

  /// 旧版未知字段原样保留。
  Map<String, dynamic> extra;

  /// 临期线（计算属性，永不落盘；导出时旧版会另存一份 suggested_deadline）。
  DateTime effectiveSuggested() => effectiveSuggestedImpl(      deadline: deadline,
      suggestedDeadline: suggestedDeadline,
      deadlineBufferDays: deadlineBufferDays);

  /// 距临期线剩余自然日（今天=0，已过=负）。
  int countdown([DateTime? from]) =>
      daysBetween(effectiveSuggested(), from ?? today());

  /// 距官方截止剩余自然日。
  int officialCountdown([DateTime? from]) =>
      daysBetween(deadline, from ?? today());

  /// 自动状态 + 人工覆盖。
  String status([DateTime? from]) => computeStatus(
      deadline: deadline,
      suggestedDeadline: suggestedDeadline,
      deadlineBufferDays: deadlineBufferDays,
      signupStart: signupStart,
      signupEnd: signupEnd,
      statusOverride: statusOverride,
      todayDate: from);

  String statusLabel([DateTime? from]) =>
      statusLabels[status(from)] ?? status(from);

  /// 过期隐藏（展示层语义）。
  bool isStaleHidden([DateTime? from]) =>
      isStaleHiddenImpl(deadline: deadline, status: status(from), todayDate: from);

  // ----- 序列化 -----

  Map<String, dynamic> toLegacyJson() {
    final d = <String, dynamic>{
      'id': id,
      'name': name,
      'deadline': dateIso(deadline),
      'suggested_deadline': dateIso(suggestedDeadline),
      'deadline_buffer_days': deadlineBufferDays,
      'milestones': milestones.map((m) => m.toJson()).toList(),
      'category': category,
      'organizer': organizer,
      'website': website,
      'signup_start': dateIso(signupStart),
      'signup_end': dateIso(signupEnd),
      'deadline_note': deadlineNote,
      'requirements': requirements,
      'deliverables': deliverables,
      'submission': submission,
      'format': format,
      'tags': tags,
      'status_override': statusOverride,
      'reminder_days': reminderDays,
      'notes': notes,
      'source': source,
      'source_url': sourceUrl,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
    d.addAll(extra);
    return d;
  }

  static const Set<String> _knownKeys = {
    'id', 'name', 'deadline', 'suggested_deadline', 'deadline_buffer_days',
    'milestones', 'category', 'organizer', 'website', 'signup_start',
    'signup_end', 'deadline_note', 'requirements', 'deliverables',
    'submission', 'format', 'tags', 'status_override', 'reminder_days',
    'notes', 'source', 'source_url', 'created_at', 'updated_at',
  };

  /// 从旧版 JSON 构造。strict=true 校验必填与日期逻辑（导入用）；
  /// 未知字段进 extra；status_override 非法、报名区间倒置、临期线晚于截止、
  /// 里程碑晚于截止均视为非法。
  static Competition fromLegacyJson(Map<String, dynamic> data,
      {bool strict = true}) {
    final name = '${data['name'] ?? ''}'.trim();
    final deadline = parseDate(data['deadline']);
    if (name.isEmpty) throw ValidationError('name 不能为空');
    if (deadline == null) {
      throw ValidationError('deadline 不是有效日期: ${data['deadline']}');
    }
    for (final key in ['suggested_deadline', 'signup_start', 'signup_end']) {
      if (data[key] != null && data[key] != '' && parseDate(data[key]) == null) {
        throw ValidationError('$key 不是有效日期，请勿填写推测日期');
      }
    }
    final suggested = parseDate(data['suggested_deadline']);
    final signupStart = parseDate(data['signup_start']);
    final signupEnd = parseDate(data['signup_end']);
    final overrideRaw = data['status_override'];
    final override =
        (overrideRaw == null || overrideRaw == '') ? null : '$overrideRaw';
    if (override != null && !validOverrides.contains(override)) {
      throw ValidationError('status_override 非法: $override');
    }
    if (signupStart != null && signupEnd != null && signupStart.isAfter(signupEnd)) {
      throw ValidationError('报名开始晚于报名结束');
    }
    if (suggested != null && suggested.isAfter(deadline)) {
      throw ValidationError('临期线晚于官方截止');
    }
    final milestones = <Milestone>[];
    for (final ms in (data['milestones'] as List? ?? const [])) {
      if (ms is! Map<String, dynamic>) {
        throw ValidationError('milestones 项必须是对象 {name, date}');
      }
      final m = Milestone.fromJson(ms);
      milestones.add(m);
    }
    final extra = <String, dynamic>{
      for (final e in data.entries)
        if (!_knownKeys.contains(e.key)) e.key: e.value,
    };
    return Competition(
      id: '${data['id'] ?? ''}'.isEmpty
          ? makeCompId(name, deadline)
          : '${data['id']}',
      name: name,
      deadline: deadline,
      suggestedDeadline: suggested,
      deadlineBufferDays: _intOrNull(data['deadline_buffer_days']),
      milestones: milestones,
      category: '${data['category'] ?? ''}',
      organizer: '${data['organizer'] ?? ''}',
      website: '${data['website'] ?? ''}',
      signupStart: signupStart,
      signupEnd: signupEnd,
      deadlineNote: '${data['deadline_note'] ?? ''}',
      requirements: '${data['requirements'] ?? ''}',
      deliverables: (data['deliverables'] as List? ?? const []).toList(),
      submission: Map<String, dynamic>.from(data['submission'] as Map? ?? const {}),
      format: Map<String, dynamic>.from(data['format'] as Map? ?? const {}),
      tags: (data['tags'] as List? ?? const []).toList(),
      statusOverride: override,
      reminderDays: (data['reminder_days'] as List? ?? const [7, 1]).toList(),
      notes: '${data['notes'] ?? ''}',
      source: '${data['source'] ?? 'manual'}'.isEmpty
          ? 'manual'
          : '${data['source']}',
      sourceUrl: '${data['source_url'] ?? ''}',
      createdAt: '${data['created_at'] ?? ''}',
      updatedAt: '${data['updated_at'] ?? ''}',
      extra: extra,
    );
  }

  /// 字段级合并（旧版 _merge_records）：仅用非空字段覆盖；
  /// 人工状态标记与创建时间永不被导入覆盖。
  Competition mergedWith(Map<String, dynamic> newData) {
    final merged = toLegacyJson();
    for (final e in newData.entries) {
      final v = e.value;
      if (v == null || v == '' || (v is List && v.isEmpty) || (v is Map && v.isEmpty)) {
        continue;
      }
      merged[e.key] = v;
    }
    if (statusOverride != null) merged['status_override'] = statusOverride;
    merged['id'] = id;
    merged['created_at'] = createdAt;
    merged['updated_at'] = nowIso();
    return Competition.fromLegacyJson(merged);
  }

  Competition copyWith({String? updatedAt}) => Competition(
      id: id, name: name, deadline: deadline,
      suggestedDeadline: suggestedDeadline,
      deadlineBufferDays: deadlineBufferDays,
      milestones: milestones, category: category, organizer: organizer,
      website: website, signupStart: signupStart, signupEnd: signupEnd,
      deadlineNote: deadlineNote, requirements: requirements,
      deliverables: deliverables, submission: submission, format: format,
      tags: tags, statusOverride: statusOverride, reminderDays: reminderDays,
      notes: notes, source: source, sourceUrl: sourceUrl,
      createdAt: createdAt, updatedAt: updatedAt ?? this.updatedAt,
      extra: extra);
}

/// 一条获奖记录。name 必填。
class Award {
  Award({
    required this.id,
    required this.name,
    this.level = '校级',
    this.awardRank = '',
    this.isFirstAuthor = false,
    this.role = '',
    this.competition = '',
    this.awardDate,
    List<String>? certificateFiles,
    this.notes = '',
    this.source = 'manual',
    this.sourceUrl = '',
    this.createdAt = '',
    this.updatedAt = '',
    Map<String, dynamic>? extra,
  })  : certificateFiles = List<String>.from(certificateFiles ?? const []),
        extra = Map<String, dynamic>.from(extra ?? const {});

  String id;
  String name;
  String level;
  String awardRank;
  bool isFirstAuthor;
  String role;
  String competition;
  DateTime? awardDate;
  List<String> certificateFiles;
  String notes;
  String source;
  String sourceUrl;
  String createdAt;
  String updatedAt;
  Map<String, dynamic> extra;

  Map<String, dynamic> toLegacyJson() {
    final d = <String, dynamic>{
      'id': id,
      'name': name,
      'level': level,
      'award_rank': awardRank,
      'is_first_author': isFirstAuthor,
      'role': role,
      'competition': competition,
      'award_date': dateIso(awardDate),
      'certificate_files': certificateFiles,
      'notes': notes,
      'source': source,
      'source_url': sourceUrl,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
    d.addAll(extra);
    return d;
  }

  static const Set<String> _knownKeys = {
    'id', 'name', 'level', 'award_rank', 'is_first_author', 'role',
    'competition', 'award_date', 'certificate_files', 'notes',
    'source', 'source_url', 'created_at', 'updated_at',
  };

  /// 宽松解析与旧版一致：非法级别回落「校级」；is_first_author 兼容
  /// true/1/yes/是/一作/第一作者；certificate/note 为旧别名。
  static Award fromLegacyJson(Map<String, dynamic> data, {bool strict = true}) {
    final name = '${data['name'] ?? ''}'.trim();
    if (name.isEmpty) throw ValidationError('name 不能为空');
    if (data['award_date'] != null && data['award_date'] != '' && parseDate(data['award_date']) == null) {
      throw ValidationError('获奖日期不是有效日期；仅知年月请留空，并在备注注明原文');
    }
    var level = '${data['level'] ?? '校级'}'.trim();
    if (!validAwardLevels.contains(level)) level = '校级';
    final first = data['is_first_author'];
    final isFirst = first == true ||
        const ['true', '1', 'yes', '是', '一作', '第一作者']
            .contains('$first'.toLowerCase());
    final certsRaw = data['certificate_files'] ?? data['certificate'];
    final certs = <String>[];
    if (certsRaw is List) {
      certs.addAll(certsRaw.map((c) => '$c'));
    } else if (certsRaw != null && '$certsRaw'.isNotEmpty) {
      certs.add('$certsRaw');
    }
    final extra = <String, dynamic>{
      for (final e in data.entries)
        if (!_knownKeys.contains(e.key)) e.key: e.value,
    };
    return Award(
      id: '${data['id'] ?? ''}'.isEmpty
          ? makeAwardId(name, data['award_date'])
          : '${data['id']}',
      name: name,
      level: level,
      awardRank: '${data['award_rank'] ?? ''}',
      isFirstAuthor: isFirst,
      role: '${data['role'] ?? ''}',
      competition: '${data['competition'] ?? ''}',
      awardDate: parseDate(data['award_date']),
      certificateFiles: certs,
      notes: '${data['notes'] ?? data['note'] ?? ''}',
      source: '${data['source'] ?? 'manual'}'.isEmpty
          ? 'manual'
          : '${data['source']}',
      sourceUrl: '${data['source_url'] ?? ''}',
      createdAt: '${data['created_at'] ?? ''}',
      updatedAt: '${data['updated_at'] ?? ''}',
      extra: extra,
    );
  }

  Award copyWith({String? updatedAt}) => Award(
      id: id, name: name, level: level, awardRank: awardRank,
      isFirstAuthor: isFirstAuthor, role: role, competition: competition,
      awardDate: awardDate, certificateFiles: certificateFiles, notes: notes,
      source: source, sourceUrl: sourceUrl, createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt, extra: extra);
}

DateTime effectiveSuggestedImpl({
  required DateTime deadline,
  DateTime? suggestedDeadline,
  int? deadlineBufferDays,
}) =>
    effectiveSuggested(
        deadline: deadline,
        suggestedDeadline: suggestedDeadline,
        deadlineBufferDays: deadlineBufferDays);

bool isStaleHiddenImpl(
        {required DateTime deadline, String? status, DateTime? todayDate}) =>
    isStaleHidden(deadline: deadline, status: status, todayDate: todayDate);

int? _intOrNull(Object? v) {
  if (v == null || v == '') return null;
  final n = v is int ? v : int.tryParse('$v');
  if (n == null) return null;
  return n < 0 ? 0 : n;
}
