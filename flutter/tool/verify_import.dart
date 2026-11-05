/// 只读导入验证（命令行工具，不属于应用运行时）：
/// 对旧版数据目录做「解析 → 试导入到临时仓库 → 与源逐条核对」，全程不写源目录。
///
library;
/// 用法：dart run tool/verify_import.dart <旧版数据目录> <临时仓库目录>
import 'dart:io';

import 'package:workcalendar/data/exchange.dart';
import 'package:workcalendar/data/repository.dart';
import 'package:workcalendar/domain/models.dart';
import 'package:workcalendar/domain/rules.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('用法: dart run tool/verify_import.dart <旧版数据目录> <临时仓库目录>');
    exit(2);
  }
  final source = args[0];
  final sandbox = args[1];

  stdout.writeln('== 旧版导入只读验证 ==');
  stdout.writeln('源目录: $source');
  final bundle = await parseLegacyDirectory(source);
  stdout.writeln('解析: ${bundle.description}');
  for (final w in bundle.warnings) {
    stdout.writeln('警告: $w');
  }

  // 源文件指纹（导入后复核，证明未触碰源）
  final sourceHashes = <String, String>{};
  for (final f in const ['competitions.json', 'awards.json']) {
    final p = '$source\\$f';
    if (File(p).existsSync()) sourceHashes[f] = _fingerprint(p);
  }

  // 试导入到独立临时仓库（沙箱，可整体删除）
  final repo = await WcRepository.open(sandbox);
  final report = await repo.applyImport(
    compRecords: bundle.comps,
    awardRecords: bundle.awards,
    certificates: bundle.certificates,
    updateExisting: true,
  );
  stdout.writeln('导入报告: ${report.summary()}');
  for (final e in report.errors.take(10)) {
    stdout.writeln('  跳过: ${e['name']} —— ${e['reason']}');
  }
  for (final w in report.warnings) {
    stdout.writeln('  提示: $w');
  }

  // 逐条核对：源记录关键字段 vs 导入结果
  var checked = 0;
  var mismatch = 0;
  for (final raw in bundle.comps) {
    final c = Competition.fromLegacyJson(raw);
    final got = repo.getComp(c.id);
    if (got == null) {
      stdout.writeln('缺失比赛: ${c.name} (${c.id})');
      mismatch++;
      continue;
    }
    if (got.name != c.name || dateIso(got.deadline) != dateIso(c.deadline)) {
      stdout.writeln('不一致比赛: ${c.name}');
      mismatch++;
    }
    checked++;
  }
  for (final raw in bundle.awards) {
    final a = Award.fromLegacyJson(raw);
    final got = repo.getAward(a.id);
    if (got == null) {
      stdout.writeln('缺失获奖: ${a.name} (${a.id})');
      mismatch++;
      continue;
    }
    if (got.name != a.name ||
        got.level != a.level ||
        got.certificateFiles.length != a.certificateFiles.length) {
      stdout.writeln('不一致获奖: ${a.name}');
      mismatch++;
    }
    checked++;
  }
  stdout.writeln('逐条核对: $checked 条，不一致 $mismatch 条');
  stdout.writeln('凭证落盘: ${report.certsImported} 个 → $sandbox\\certificates');
  stdout.writeln('仓库统计: 比赛 ${repo.compCount} · 获奖 ${repo.awardCount}');

  for (final e in sourceHashes.entries) {
    final now = _fingerprint('$source\\${e.key}');
    stdout.writeln('源文件未变动 ${e.key}: ${now == e.value ? '一致 ✓' : '发生变化 ✗'}');
  }
  exit(mismatch == 0 ? 0 : 1);
}

/// FNV-1a 64 位指纹 + 长度，用于前后一致性对比（非密码学用途）。
String _fingerprint(String path) {
  final bytes = File(path).readAsBytesSync();
  var h = 0xcbf29ce484222325;
  for (final b in bytes) {
    h ^= b;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return '${h.toRadixString(16).padLeft(16, '0')}@${bytes.length}';
}
