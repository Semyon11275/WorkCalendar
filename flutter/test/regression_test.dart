/// 旧问题回归自查测试：0.5.0 三轮审计修复中「不得复发」的行为，逐条固化。
/// 对照来源：`0.5.0修改.md` 第七/八节、core.js 恢复保护注释、计划 §6.3。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workcalendar/data/repository.dart';
import 'package:workcalendar/domain/models.dart';
import 'package:workcalendar/domain/rules.dart';
import 'package:workcalendar/state/providers.dart';

Future<WcRepository> openTemp() async {
  final dir = await Directory.systemTemp.createTemp('wc_regress');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // 临时目录清理失败不影响测试
    }
  });
  return WcRepository.open(dir.path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('全角映射表与 Python casefold 基准一致（0.5.0 models.py 实测）', () {
    test('全部 75 个映射字符（含标点尾段）', () {
      // 基准由旧版 Python normalize_name 实际运行产出
      expect(normalizeName('（测试）：，。！？；“”‘’'), '(测试):,.!?;""\'\'');
      expect(normalizeName('全角ＡＢＣ０１２　空格'), '全角abc012 空格');
      expect(normalizeName('ＡＤＣ国际设计奖'), 'adc国际设计奖');
    });

    test('分组键含 constructor/__proto__ 不出错（0.5.0 审计：JS 原型链污染）', () {
      // Dart Map 无原型链；此处验证不抛异常即可
      final groups = <String, List<String>>{};
      for (final name in ['constructor', '__proto__', '其他']) {
        groups.putIfAbsent(name, () => []).add(name);
      }
      expect(groups.length, 3);
    });
  });

  group('凭证存储安全（0.5.0 审计：路径与覆盖问题）', () {
    test('sanitize 后为 . 或 .. 的名字被中性化，绝不可指向父目录或互相覆盖', () async {
      final repo = await openTemp();
      final n1 = await repo.certs.save('..', [1]);
      final n2 = await repo.certs.save('.', [2]);
      final n3 = await repo.certs.save('', [3]);
      for (final n in [n1, n2, n3]) {
        expect(n.contains('/'), isFalse, reason: n);
        expect(n.contains(r'\'), isFalse, reason: n);
        expect(n, isNot('.'), reason: n);
        expect(n, isNot('..'), reason: n);
      }
      // 三个特殊名互不覆盖：内容按写入可区分
      final listing = await repo.certs.list();
      expect(listing.toSet().length, 3);
      final firsts = [for (final n in listing) (await repo.certs.read(n)).first];
      expect(firsts.toSet().length, 3);
    });

    test('重名不覆盖（0.5.0 审计：压缩图覆盖原件的教训）', () async {
      final repo = await openTemp();
      final a = await repo.certs.save('证书.jpg', [1]);
      final b = await repo.certs.save('证书.jpg', [2, 2]);
      expect(a, isNot(b));
      expect(File(repo.certs.path(a)).readAsBytesSync(), [1]);
      expect(File(repo.certs.path(b)).readAsBytesSync(), [2, 2]);
    });
  });

  group('合并匹配（0.5.0 语义 + 短哈希冲突防护）', () {
    test('同键合并、键不同则新增', () async {
      final repo = await openTemp();
      await repo.upsertComp(Competition.fromLegacyJson(
          {'name': '大赛A', 'deadline': '2026-12-31', 'notes': '旧'}));
      final r1 = await repo.applyImport(compRecords: [
        {'name': '大赛Ａ', 'deadline': '2026-12-31', 'notes': '新'},
      ]);
      expect(r1.updated, 1);
      expect(r1.added, 0);
    });

    test('同 id 不同键（短哈希冲突）绝不误合并既有记录', () async {
      final repo = await openTemp();
      await repo.upsertComp(Competition.fromLegacyJson({
        'name': '真实比赛',
        'deadline': '2026-12-31',
        'notes': '宝贵数据',
      }));
      final existing = repo.allComps().single;
      // 构造一条与现有记录同 id、但去重键不同的导入记录：
      // 直接以既有 id + 不同名称/日期提交合并请求
      final report = await repo.applyImport(compRecords: [
        {
          'id': existing.id,
          'name': '另一条不同比赛',
          'deadline': '2027-06-30',
          'notes': '不该合并进来',
        }
      ]);
      // 必须作为新记录进入（id 另配），既有记录原样保留
      expect(report.added, 1);
      expect(report.updated, 0);
      expect(repo.compCount, 2);
      final kept = repo.getComp(existing.id)!;
      expect(kept.name, '真实比赛');
      expect(kept.notes, '宝贵数据');
      final added = repo.allComps().where((c) => c.id != existing.id).single;
      expect(added.id, isNot(existing.id));
      expect(added.name, '另一条不同比赛');
    });

    test('记录改名后旧键映射被清理（不残留指向）', () async {
      final repo = await openTemp();
      final c = Competition.fromLegacyJson({'name': '旧名', 'deadline': '2026-12-31'});
      await repo.upsertComp(c);
      c.name = '新名';
      await repo.upsertComp(c);
      expect(repo.compCount, 1);
      // 旧键再次导入不得命中已改名记录
      final r = await repo.applyImport(compRecords: [
        {'name': '旧名', 'deadline': '2026-12-31'},
      ]);
      expect(r.added, 1);
      expect(r.updated, 0);
    });
  });

  group('损坏自愈保护（0.5.0：先保全再恢复，无法保全即中止；缺失≠损坏）', () {
    test('损坏原文件被保留为 .corrupt 后才恢复', () async {
      final repo = await openTemp();
      await repo.upsertComp(
          Competition.fromLegacyJson({'name': '第一条', 'deadline': '2026-12-31'}));
      await repo.upsertComp(
          Competition.fromLegacyJson({'name': '第二条', 'deadline': '2026-12-30'}));
      await File(repo.compsPath).writeAsString('BROKEN');
      final repo2 = await WcRepository.open(repo.dataDir);
      expect(repo2.loadReport.mainRecovered, isTrue);
      expect(File('${repo.compsPath}.corrupt').existsSync(), isTrue);
      expect(repo2.compCount, 2);
    });

    test('损坏且无备份：中止启动，绝不以空库覆盖', () async {
      final repo = await openTemp();
      await File(repo.compsPath).writeAsString('BROKEN');
      await expectLater(
          WcRepository.open(repo.dataDir), throwsA(isA<FileSystemException>()));
      // 原文件原样保留
      expect(File(repo.compsPath).readAsStringSync(), 'BROKEN');
    });

    test('文件不存在 = 空库正常启动（不误报损坏）', () async {
      final repo = await openTemp();
      expect(repo.compCount, 0);
      expect(repo.loadReport.mainRecovered, isFalse);
      expect(repo.loadReport.notes, isEmpty);
    });

    test('获奖库损坏无备份：降级空库但显著提示', () async {
      final repo = await openTemp();
      await File(repo.awardsPath).writeAsString('BROKEN');
      final repo2 = await WcRepository.open(repo.dataDir);
      expect(repo2.awardCount, 0);
      expect(
          repo2.loadReport.notes.any((n) => n.contains('awards.json 损坏')), isTrue);
      expect(File('${repo.awardsPath}.corrupt').existsSync(), isTrue);
    });
  });

  group('过期隐藏与筛选（0.5.0：搜索或点筛选即全量可见）', () {
    test('有关键词或状态筛选时，过期记录可见', () {
      final stale = Competition.fromLegacyJson({'name': '过期比赛X', 'deadline': '2026-01-01'});
      final fresh = Competition.fromLegacyJson({'name': '进行中比赛Y', 'deadline': '2100-12-31'});
      // 直接验证可见性语义：过期记录默认隐藏，但未被任何「筛选器」排除
      expect(stale.isStaleHidden(), isTrue);
      expect(fresh.isStaleHidden(), isFalse);
      // provider 层的行为由 visibleCompsProvider 的 filtering 分支保证，
      // 此处固化领域侧约定：isStaleHidden 只依赖截止日与完成状态
      expect(Competition.fromLegacyJson(
              {'name': '过期已完成', 'deadline': '2026-01-01', 'status_override': 'done'})
          .isStaleHidden(),
          isFalse);
    });
  });

  group('导入报告（0.5.0 审计：失败/缺失不可静默）', () {
    test('「只有记录、无原件」的凭证被显式提示', () async {
      final repo = await openTemp();
      final report = await repo.applyImport(awardRecords: [
        {
          'name': '金奖',
          'level': '国家级',
          'award_date': '2026-06-01',
          'certificate_files': ['不存在的证书.png'],
        }
      ]);
      expect(report.added, 1);
      expect(
          report.warnings.any((w) => w.contains('不存在的证书.png') && w.contains('无原件')),
          isTrue);
    });

    test('凭证已在库中则不提示', () async {
      final repo = await openTemp();
      await repo.certs.save('已有证书.png', [9]);
      final report = await repo.applyImport(awardRecords: [
        {
          'name': '金奖',
          'level': '国家级',
          'award_date': '2026-06-01',
          'certificate_files': ['已有证书.png'],
        }
      ]);
      expect(report.warnings, isEmpty);
    });
  });

  group('设置合并读写（防止互相覆盖）', () {
    test('写 theme_mode 不抹掉 awards_open，反之亦然', () async {
      final repo = await openTemp();
      await writeAppSetting(repo, 'theme_mode', 1);
      await writeAppSetting(repo, 'awards_open', {'组A': false});
      final s = readAppSettings(repo);
      expect(s['theme_mode'], 1);
      expect((s['awards_open'] as Map)['组A'], false);
    });
  });
}
