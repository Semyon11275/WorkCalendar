/// 领域规则测试：日期、归一化、旧版兼容 ID、状态机、过期隐藏、统计口径。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:workcalendar/domain/import_parsers.dart';
import 'package:workcalendar/domain/models.dart';
import 'package:workcalendar/domain/rules.dart';
import 'package:workcalendar/domain/stats.dart';

DateTime d(String s) => parseDate(s)!;

void main() {
  group('parseDate', () {
    test('标准与容错', () {
      expect(dateIso(parseDate('2026-11-30')), '2026-11-30');
      expect(dateIso(parseDate('2026-1-5')), '2026-01-05'); // 1 位月/日容错
      expect(parseDate('2026-02-30'), isNull); // 不存在的日期
      expect(parseDate('2026/11/30'), isNull);
      expect(parseDate(''), isNull);
      expect(parseDate(null), isNull);
      expect(parseDate(' 2026-03-01 '), isNotNull);
    });

    test('闰年与跨月', () {
      expect(dateIso(parseDate('2028-02-29')), '2028-02-29'); // 闰年
      expect(parseDate('2027-02-29'), isNull); // 平年无 2/29
      expect(dateIso(parseDate('2026-12-31')), '2026-12-31');
    });
  });

  group('normalizeName / dedupKey / 旧版兼容 ID', () {
    test('全角转半角 + 大小写 + 空白折叠', () {
      expect(normalizeName('ＡＤＣ国际设计奖'), 'adc国际设计奖');
      expect(normalizeName('Hello  World'), 'hello world');
      expect(normalizeName('  测试 ＡＢＣ  '), '测试 abc');
      expect(normalizeName(null), '');
    });

    test('去重键', () {
      expect(dedupKey('测试 比赛', '2026-02-28'), '测试 比赛|2026-02-28');
      expect(dedupKey('测试  比赛', '2026-2-28'), dedupKey('测试 比赛', '2026-02-28'));
      expect(dedupKey('x', null), 'x|');
    });

    test('与 0.5.0 Python make_id 黄金样例一致', () {
      // 基准值由旧版 app/models.py 实际运行生成
      expect(makeCompId('全国大学生工业设计大赛', '2026-11-30'), 'c_5d10dba6');
      expect(makeCompId('ＡＤＣ国际设计奖', '2026-12-05'), 'c_76a9c860');
      expect(makeCompId('Hello  World', '2026-01-01'), 'c_8041a7d9');
      expect(makeCompId('河南省大学生广告艺术大赛', '2027-03-15'), 'c_9b2c0895');
      expect(makeAwardId('某某大赛金奖', '2026-06-01'), 'a_62d0e8dc');
    });

    test('fromLegacyJson 缺 id 时按规则生成', () {
      final c = Competition.fromLegacyJson({'name': '全国大学生工业设计大赛', 'deadline': '2026-11-30'});
      expect(c.id, 'c_5d10dba6');
    });
  });

  group('状态机（与旧版 compStatus 一致）', () {
    final t = d('2026-10-23');

    Competition comp(Map<String, dynamic> j) =>
        Competition.fromLegacyJson({'name': 'x', 'deadline': '2026-12-31', ...j});

    test('未开始 / 报名中 / 进行中', () {
      expect(
          comp({'signup_start': '2026-11-01', 'signup_end': '2026-11-30'}).status(t),
          'not_started');
      expect(
          comp({'signup_start': '2026-10-01', 'signup_end': '2026-10-30'}).status(t),
          'open');
      expect(comp({}).status(t), 'submitting');
    });

    test('临期线：默认缓冲 3 天 / 自定义 / 即将截止', () {
      final c1 = comp({'deadline': '2026-10-25'}); // 临期线 10-22 → 已过
      expect(c1.status(t), 'past_suggested');
      final c2 = comp({'deadline': '2026-10-30'}); // 临期线 10-27，7 天内 → urgent
      expect(c2.status(t), 'urgent');
      final c3 = comp({'deadline': '2026-10-30', 'deadline_buffer_days': 0}); // 临期线=截止=10-30，差 7 天
      expect(c3.status(t), 'urgent');
      final c4 = comp({'deadline': '2026-10-31', 'deadline_buffer_days': 0}); // 临期线=10-31，差 8 天
      expect(c4.status(t), 'submitting');
      final c5 = comp({'deadline': '2026-11-30'});
      expect(c5.status(t), 'submitting');
    });

    test('覆盖优先级：submitted/done/abandoned 盖过一切', () {
      expect(comp({'deadline': '2026-01-01', 'status_override': 'submitted'}).status(t),
          'submitted');
      expect(comp({'deadline': '2026-01-01', 'status_override': 'done'}).status(t), 'done');
      expect(comp({'deadline': '2026-01-01', 'status_override': 'abandoned'}).status(t),
          'abandoned');
      // 非法覆盖值被校验拒绝
      expect(() => comp({'status_override': 'finished'}), throwsA(isA<ValidationError>()));
    });

    test('已截止', () {
      expect(comp({'deadline': '2026-10-01'}).status(t), 'overdue');
    });

    test('倒计时（自然日，含跨月）', () {
      final c = comp({'deadline': '2026-11-30', 'suggested_deadline': '2026-11-20'});
      expect(c.countdown(t), 28);
      expect(c.officialCountdown(t), 38);
      final c2 = comp({'deadline': '2026-03-01', 'deadline_buffer_days': 0});
      expect(c2.effectiveSuggested(), d('2026-03-01'));
    });

    test('非法日期逻辑被校验拒绝', () {
      expect(() => comp({'suggested_deadline': '2027-01-01'}), throwsA(isA<ValidationError>()));
      expect(
          () => comp({'signup_start': '2026-12-31', 'signup_end': '2026-12-01'}),
          throwsA(isA<ValidationError>()));
      expect(comp({'milestones': [{'name': '颁奖', 'date': '2027-01-01'}]}).milestones.length, 1);
      expect(() => comp({'name': ''}), throwsA(isA<ValidationError>()));
    });

    test('未知字段进 extra 原样保留（round-trip 不丢）', () {
      final raw = {'name': 'x', 'deadline': '2026-12-31', 'legacy_field': '重要信息'};
      final out = Competition.fromLegacyJson(raw).toLegacyJson();
      expect(out['legacy_field'], '重要信息');
    });
  });

  group('过期隐藏（旧版 isStaleHidden）', () {
    final t = d('2026-10-23');
    Competition comp(String deadline, {String? override}) =>
        Competition.fromLegacyJson(
            {'name': 'x', 'deadline': deadline, 'status_override': override});

    test('已截止 5 天以上隐藏，done 不隐藏', () {
      expect(comp('2026-10-18').isStaleHidden(t), isTrue); // 5 天前
      expect(comp('2026-10-19').isStaleHidden(t), isFalse); // 4 天前
      expect(comp('2026-09-01', override: 'done').isStaleHidden(t), isFalse);
    });
  });

  group('computeStats（口径与旧版 computeStats 一致）', () {
    test('统计与 upcoming 排序', () {
      final t = d('2026-10-23');
      Iterable<Competition> mk(List<Map<String, dynamic>> items) =>
          items.map((j) => Competition.fromLegacyJson({'name': 'x', ...j}));
      final comps = mk([
        {'deadline': '2026-10-25', 'name': 'a'}, // 临期线 10-22 已过 → past_suggested，不入 upcoming
        {'deadline': '2026-10-30', 'name': 'b'}, // 临期 10-27，urgent
        {'deadline': '2026-11-30', 'name': 'c'},
        {'deadline': '2026-01-01', 'name': 'd', 'status_override': 'done'},
      ]).toList();
      final s = computeStats(comps, t);
      expect(s.total, 4);
      expect(s.completed, 1);
      expect(s.byStatus['done'], 1);
      expect(s.byStatus['urgent'], 1);
      expect(s.upcoming.map((u) => u.comp.name), ['b', 'c']); // 按剩余天数升序
      expect(s.dueIn7, 1); // 只有 b（差 4 天）
      expect(s.dueIn30, 1); // c 差 35 天，不计入 30 天
      expect(s.weeks.length, 12);
      expect(s.months.length, 6);
      expect(s.months.first.month, '2026-10');
    });
  });

  group('Award 解析（宽松兼容）', () {
    test('级别回落与一作别名', () {
      final a = Award.fromLegacyJson({'name': 'x', 'level': '宇宙级', 'is_first_author': '是'});
      expect(a.level, '校级');
      expect(a.isFirstAuthor, isTrue);
      final b = Award.fromLegacyJson({'name': 'y', 'is_first_author': true});
      expect(b.isFirstAuthor, isTrue);
      final c = Award.fromLegacyJson({'name': 'z', 'is_first_author': 'no'});
      expect(c.isFirstAuthor, isFalse);
    });

    test('certificate/note 旧别名', () {
      final a = Award.fromLegacyJson({'name': 'x', 'certificate': 'a.jpg', 'note': '备注'});
      expect(a.certificateFiles, ['a.jpg']);
      expect(a.notes, '备注');
    });
  });

  group('导入解析器', () {
    test('JSON 三形态', () {
      expect(parseJsonText('[{"name":"a","deadline":"2026-01-01"}]').length, 1);
      expect(parseJsonText('{"competitions":[{"name":"a","deadline":"2026-01-01"}]}').length, 1);
      expect(parseJsonText('{"items":[{"name":"a","deadline":"2026-01-01"}]}').length, 1);
      expect(parseJsonText('{"name":"a","deadline":"2026-01-01"}').length, 1);
      expect(() => parseJsonText('not json'), throwsA(isA<ValidationError>()));
    });

    test('Markdown 表头别名', () {
      final recs = parseMarkdownTable(
          '| 名称 | 截止 | 类别 | 备注 |\n'
          '| --- | --- | --- | --- |\n'
          '| 大赛A | 2026-01-01 | 视觉传达 | ok |\n'
          '| 大赛B | 2026-02-01 |  | 含 |  竖线 |\n');
      expect(recs.length, 2);
      expect(recs[0]['name'], '大赛A');
      expect(recs[0]['deadline'], '2026-01-01');
      expect(recs[0]['notes'], 'ok');
    });

    test('自动探测：JSON 优先，失败落 Markdown', () {
      expect(parseText('[{"name":"a","deadline":"2026-01-01"}]').length, 1);
      expect(parseText('| 名称 | 截止 |\n| --- | --- |\n| a | 2026-01-01 |').length, 1);
      expect(() => parseText('随机文本'), throwsA(isA<ValidationError>()));
      expect(() => parseText('   '), throwsA(isA<ValidationError>()));
    });

    test('记录分流 looksLikeAward', () {
      expect(looksLikeAward({'name': 'x', 'level': '国家级'}), isTrue);
      expect(looksLikeAward({'name': 'x', 'award_date': '2026-01-01'}), isTrue);
      expect(looksLikeAward({'name': 'x', 'deadline': '2026-01-01'}), isFalse);
    });
  });
}
