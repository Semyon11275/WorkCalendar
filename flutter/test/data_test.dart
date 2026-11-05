/// 数据层与交换层测试：仓库 round-trip、损坏自愈、备份轮转、
/// 安卓备份 JSON / 桌面 ZIP / 新版 ZIP 往返、ZIP 安全、合并语义。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workcalendar/data/exchange.dart';
import 'package:workcalendar/data/repository.dart';
import 'package:workcalendar/domain/import_parsers.dart';
import 'package:workcalendar/domain/models.dart';

Future<WcRepository> openTemp() async {
  final dir = await Directory.systemTemp.createTemp('wc_test');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // 临时目录清理失败不影响测试结果
    }
  });
  return WcRepository.open(dir.path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WcRepository 基础', () {
    test('保存后重开 round-trip（字段与未知键不丢）', () async {
      final repo = await openTemp();
      final c = Competition.fromLegacyJson({
        'name': '大赛A',
        'deadline': '2026-12-31',
        'category': '视觉传达',
        'milestones': [
          {'name': '初审', 'date': '2026-12-01'}
        ],
        'custom_future_field': {'v': 1},
      });
      await repo.upsertComp(c);
      final a = Award.fromLegacyJson({
        'name': '大赛A金奖',
        'level': '国家级',
        'award_date': '2026-11-01',
        'certificate_files': ['cert.jpg'],
      });
      await repo.upsertAward(a);

      final repo2 = await WcRepository.open(repo.dataDir);
      expect(repo2.compCount, 1);
      expect(repo2.awardCount, 1);
      final c2 = repo2.getComp(c.id)!;
      expect(c2.category, '视觉传达');
      expect(c2.milestones.single.name, '初审');
      expect(c2.extra['custom_future_field'], {'v': 1});
      expect(repo2.getAward(a.id)!.certificateFiles, ['cert.jpg']);
    });

    test('坏记录跳过不拖垮整库并计数', () async {
      final repo = await openTemp();
      final bad = jsonEncode({
        'competitions': [
          {'name': '好记录', 'deadline': '2026-12-31'},
          {'name': '坏记录', 'deadline': 'not-a-date'},
        ]
      });
      await File(repo.compsPath).writeAsString(bad);
      final repo2 = await WcRepository.open(repo.dataDir);
      expect(repo2.compCount, 1);
      expect(repo2.loadReport.skippedComps, 1);
    });

    test('主文件损坏 → 保留现场并从备份恢复', () async {
      final repo = await openTemp();
      await repo.upsertComp(
          Competition.fromLegacyJson({'name': '宝贵数据', 'deadline': '2026-12-31'}));
      // 第二次写入会产生“最近备份”
      await repo.upsertComp(
          Competition.fromLegacyJson({'name': '第二条', 'deadline': '2026-12-30'}));
      // 破坏主文件
      await File(repo.compsPath).writeAsString('{corrupt!!');
      final repo2 = await WcRepository.open(repo.dataDir);
      expect(repo2.loadReport.mainRecovered, isTrue);
      expect(repo2.compCount, 2);
      expect(File('${repo.compsPath}.corrupt').existsSync(), isTrue);
    });

    test('备份轮转保留上限', () async {
      final repo = await openTemp();
      for (var i = 0; i < 25; i++) {
        await repo.upsertComp(
            Competition.fromLegacyJson({'name': 'n$i', 'deadline': '2026-12-31'}));
      }
      final backups = Directory(repo.backupDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('competitions_'))
          .toList();
      expect(backups.length, WcRepository.backupKeep);
    });
  });

  group('凭证存储', () {
    test('文件名安全化 + 重名不覆盖', () async {
      final repo = await openTemp();
      final n1 = await repo.certs.save('获奖证书 v1.jpg', [1, 2, 3]);
      final n2 = await repo.certs.save('获奖证书 v1.jpg', [4, 5]);
      // 空格按旧版规则替换为下划线（与 Python save_certificate 一致）
      expect(n1, '获奖证书_v1.jpg');
      expect(n2, isNot(n1));
      expect(await repo.certs.list().then((l) => l.length), 2);
      // 路径穿越尝试被中性化：不含任何路径分隔符，且文件落在证书目录内
      final n3 = await repo.certs.save(r'..\..\evil.png', [9]);
      expect(n3.contains('/'), isFalse);
      expect(n3.contains('\\'), isFalse);
      expect(File(repo.certificatesDir + Platform.pathSeparator + n3).existsSync(), isTrue);
    });
  });

  group('applyImport 合并语义', () {
    test('同键合并：非空覆盖、人工标记与创建时间保留', () async {
      final repo = await openTemp();
      final c = Competition.fromLegacyJson({
        'name': '大赛A',
        'deadline': '2026-12-31',
        'notes': '旧备注',
        'status_override': 'submitted',
        'created_at': '2026-01-01T00:00:00',
      });
      await repo.upsertComp(c);
      final report = await repo.applyImport(compRecords: [
        {'name': '大赛A', 'deadline': '2026-12-31', 'notes': '新备注', 'category': '视觉传达'},
      ]);
      expect(report.updated, 1);
      final merged = repo.allComps().single;
      expect(merged.notes, '新备注'); // 非空覆盖
      expect(merged.category, '视觉传达');
      expect(merged.statusOverride, 'submitted'); // 人工标记保留
      expect(merged.createdAt, '2026-01-01T00:00:00'); // 创建时间保留
      // 名称含空格 → 归一化后是不同的键（与旧版一致），不会被误合并；
      // 全角Ａ与半角A 归一化后同键 → 命中同一条。
      final report2 = await repo.applyImport(compRecords: [
        {'name': '大赛Ａ', 'deadline': '2026-12-31', 'notes': '再覆盖'},
        {'name': '大赛 A', 'deadline': '2026-12-31', 'notes': '不应合并'},
      ]);
      expect(report2.updated, 1);
      expect(report2.added, 1);
      expect(repo.compCount, 2);
    });

    test('坏记录进错误明细', () async {
      final repo = await openTemp();
      final report = await repo.applyImport(compRecords: [
        {'name': '无截止', 'deadline': '2026-13-99'},
      ]);
      expect(report.added, 0);
      expect(report.skipped, 1);
      expect(report.errors.single['name'], '无截止');
    });
  });

  group('交换：安卓备份 JSON', () {
    test('往返：导出可重新导入，base64 凭证还原', () async {
      final repo = await openTemp();
      await repo.upsertAward(Award.fromLegacyJson(
          {'name': '金奖', 'level': '国家级', 'award_date': '2026-06-01'}));
      final certName = await repo.certs.save('证书.png', [11, 22, 33]);
      await repo.upsertAward(Award.fromLegacyJson({
        'name': '金奖2',
        'level': '省级',
        'award_date': '2026-06-02',
        'certificate_files': [certName],
      }));
      final result = await exportAndroidBackup(repo);
      final bytes = await File(result.path).readAsBytes();

      final bundle = parseSourceBytes(bytes, 'backup.json');
      expect(bundle.comps, isEmpty);
      expect(bundle.awards.length, 2);
      expect(bundle.certificates[certName], [11, 22, 33]);

      final repo2 = await openTemp();
      final report = await repo2.applyImport(
          awardRecords: bundle.awards,
          certificates: bundle.certificates,
          updateExisting: true);
      expect(report.added, 2);
      expect(report.certsImported, 1);
      // allAwards 按日期倒序：金奖2（06-02）在前
      expect(repo2.allAwards().first.certificateFiles, [certName]);
      expect(await repo2.certs.exists(certName), isTrue);
    });

    test('损坏的 base64 凭证被拒绝并说明原因', () async {
      final text = jsonEncode({
        'kind': 'workcalendar_full_backup',
        'competitions': [],
        'awards': [],
        'certificates': {'x.png': '!!!!not-base64!!!!'},
      });
      expect(() => parseSourceBytes(utf8.encode(text), 'b.json'),
          throwsA(isA<ExchangeException>()));
    });
  });

  group('交换：桌面 ZIP（旧版布局）', () {
    test('导入桌面备份 ZIP 并应用', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile.bytes('competitions.json', utf8.encode(jsonEncode({
        'competitions': [
          {'name': '桌面大赛', 'deadline': '2026-12-01'}
        ]
      }))));
      archive.addFile(ArchiveFile.bytes('awards.json', utf8.encode(jsonEncode({
        'awards': [
          {
            'name': '桌面金奖',
            'level': '省级',
            'award_date': '2026-07-01',
            'certificate_files': ['桌面证书.jpg'],
          }
        ]
      }))));
      archive.addFile(ArchiveFile.bytes(
          'certificates/桌面证书.jpg', Uint8List.fromList([1, 2, 3])));
      final zip = ZipEncoder().encode(archive);

      final bundle = parseSourceBytes(zip, '桌面备份.zip');
      expect(bundle.comps.single['name'], '桌面大赛');
      expect(bundle.awards.single['name'], '桌面金奖');
      expect(bundle.certificates.containsKey('桌面证书.jpg'), isTrue);

      final repo = await openTemp();
      final report = await repo.applyImport(
          compRecords: bundle.comps,
          awardRecords: bundle.awards,
          certificates: bundle.certificates);
      expect(report.added, 2);
      expect(report.certsImported, 1);
      expect(repo.allAwards().single.certificateFiles, ['桌面证书.jpg']);
    });

    test('ZIP 路径穿越被拒绝', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile.bytes('competitions.json', utf8.encode('{"competitions":[]}')));
      archive.addFile(ArchiveFile.bytes(
          'certificates/../../evil.txt', Uint8List.fromList([1])));
      final zip = ZipEncoder().encode(archive);
      expect(() => parseSourceBytes(zip, 'evil.zip'), throwsA(isA<ExchangeException>()));
    });
  });

  group('交换：新版 v2 备份 ZIP', () {
    test('manifest 哈希与内容校验、完整往返', () async {
      final repo = await openTemp();
      await repo.upsertComp(
          Competition.fromLegacyJson({'name': 'V2大赛', 'deadline': '2026-12-31'}));
      final result = await exportV2Backup(repo);
      final bytes = await File(result.path).readAsBytes();

      final bundle = parseSourceBytes(bytes, 'v2.zip');
      expect(bundle.comps.single['name'], 'V2大赛');
      expect(bundle.warnings, isEmpty);

      final repo2 = await openTemp();
      final report = await repo2.applyImport(compRecords: bundle.comps);
      expect(report.added, 1);
      // 旧版兼容 ID：导出再导入后 id 保持一致（同名同截止）
      expect(repo2.allComps().single.id, repo.allComps().single.id);
    });

    test('篡改 ZIP 内容时给出哈希警告（可抢救导入）', () async {
      final repo = await openTemp();
      await repo.upsertComp(
          Competition.fromLegacyJson({'name': '篡改测试', 'deadline': '2026-12-31'}));
      final result = await exportV2Backup(repo);
      final bytes = await File(result.path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final rebuilt = Archive();
      for (final f in archive) {
        var content = f.content as List<int>;
        if (f.name == 'competitions.json') {
          content = utf8.encode(utf8.decode(content).replaceFirst('篡改测试', '篡改测试改'));
        }
        rebuilt.addFile(ArchiveFile.bytes(f.name, Uint8List.fromList(content)));
      }
      final zip2 = ZipEncoder().encode(rebuilt);
      final bundle = parseSourceBytes(zip2, 'tampered.zip');
      expect(bundle.warnings.any((w) => w.contains('哈希')), isTrue);
      expect(bundle.comps.single['name'], '篡改测试改');
    });
  });

  group('交换：Markdown 导出可再导入', () {
    test('导出表格 → parseText 识别', () async {
      final repo = await openTemp();
      await repo.upsertComp(Competition.fromLegacyJson({
        'name': '表格大赛|特殊',
        'deadline': '2026-12-31',
        'category': '综合',
        'notes': '备注|含竖线',
      }));
      final result = await exportMarkdown(repo);
      final text = await File(result.path).readAsString();
      final recs = parseMarkdownTable(text);
      expect(recs.single['name'], contains('表格大赛'));
      expect(recs.single['deadline'], '2026-12-31');
    });
  });
}

