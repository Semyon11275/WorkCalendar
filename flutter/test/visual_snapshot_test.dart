/// 新版各页实际渲染截图（生成新旧并排对照素材）。
/// 默认跳过；以 WC_SNAPSHOT=1 运行：
///   WC_SNAPSHOT=1 flutter test test/visual_snapshot_test.dart
/// 输出到 process/screenshots/new/。数据为合成，不含真实个人资料。
library;

import 'dart:io' as io;
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workcalendar/data/repository.dart';
import 'package:workcalendar/domain/models.dart';
import 'package:flutter/rendering.dart';
import 'package:workcalendar/main.dart';
import 'package:workcalendar/state/providers.dart';

Future<WcRepository> _syntheticRepo() async {
  final dir = await io.Directory.systemTemp.createTemp('wc_snap');
  final repo = await WcRepository.open(dir.path);
  final today = DateTime.now();
  DateTime d(int days) => DateTime(today.year, today.month, today.day + days);
  String ds(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  final names = [
    ('全国大学生数学建模竞赛', '竞赛', '中国工业与应用数学学会', -4, 'submitted'),
    ('中国高校计算机大赛·微信小程序应用开发赛', '开发', '全国高等学校计算机教育研究会', 3, null),
    ('蓝桥杯全国软件和信息技术专业人才大赛', '竞赛', '工业和信息化部人才交流中心', 6, null),
    ('全国大学生广告艺术大赛', '设计', '全国高校广告教育研究会', 0, null),
    ('全国大学生节能减排社会实践与科技竞赛', '科技', '教育部高等教育司', 3, null),
    ('校园创新创业大赛·项目孵化组（超长名称测试·含括号与副标题·用于验证截断与换行行为）', '校内', '创新创业学院', 14, 'abandoned'),
    ('全国大学生电子商务三创赛', '商科', '教育部', 21, null),
    ('RoboMaster 机甲大师高校联盟赛', '科技', '大疆创新', 30, null),
    ('全国高校数字艺术设计未来之星大赛', '设计', '工业和信息化部', 45, null),
    ('外研社·国才杯全国英语写作大赛', '文科', '外语教学与研究出版社', 60, 'done'),
  ];
  var i = 0;
  for (final (name, cat, org, off, ov) in names) {
    final deadline = d(off);
    await repo.upsertComp(Competition.fromLegacyJson({
      'name': name,
      'deadline': ds(deadline),
      'suggested_deadline': ds(deadline.subtract(Duration(days: 3 + i % 5))),
      'milestones': [
        {'name': '校内初评', 'date': ds(deadline.subtract(const Duration(days: 10)))},
        {'name': '省赛', 'date': ds(deadline.subtract(const Duration(days: 5)))},
      ],
      'category': cat,
      'organizer': org,
      'website': i % 3 == 0 ? 'https://example.org/contest' : '',
      'signup_start': ds(deadline.subtract(const Duration(days: 40))),
      'signup_end': ds(deadline.subtract(const Duration(days: 7))),
      'requirements': '作品说明书 ≤3000 字；演示视频 ≤3 分钟；需附源码与上体贴',
      'notes': '合成数据条目 $i',
      'tags': i % 6 == 0 ? ['重点'] : [],
      'status_override': ov,
    }));
    i++;
  }
  final levels = ['省级', '省级', '国家级', '校级'];
  final ranks = ['一等奖', '二等奖', '三等奖', '优秀奖'];
  for (var k = 0; k < 12; k++) {
    final c = repo.allComps()[k % 8];
    await repo.upsertAward(Award.fromLegacyJson({
      'name': c.name,
      'level': levels[k % 4],
      'award_rank': ranks[k % 4],
      'is_first_author': k % 2 == 0,
      'role': k % 3 == 0 ? '队长' : '一作',
      'competition': c.name,
      'award_date': ds(d(-20 - k * 9)),
      'notes': '合成获奖条目 $k',
    }));
  }
  return repo;
}

Future<void> _shot(WidgetTester tester, String name,
    GlobalKey boundaryKey) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.runAsync(() async {
    final boundary = boundaryKey.currentContext!.findRenderObject()
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    final out = 'process/screenshots/new/$name.png';
    io.File(out)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
    debugPrint('saved $out');
  });
}

void main() {
  if (io.Platform.environment['WC_SNAPSHOT'] != '1') {
    return; // 默认跳过：仅在交付时以 WC_SNAPSHOT=1 运行
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  final boundaryKey = GlobalKey();

  testWidgets('生成新版各页渲染截图', (tester) async {
    late WcRepository repo;
    await tester.runAsync(() async {
      repo = await _syntheticRepo();
    });
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repo)],
          child: const WorkCalendarApp(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await _shot(tester, '01-总览', boundaryKey);

    Future<void> nav(String label) async {
      await tester.tap(find.text(label).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await nav('比赛');
    await _shot(tester, '02-比赛工作区', boundaryKey);
    await nav('时间线');
    await _shot(tester, '03-时间线', boundaryKey);
    await nav('获奖');
    await _shot(tester, '04-获奖', boundaryKey);
    await nav('数据');
    await _shot(tester, '05-数据', boundaryKey);
    await nav('设置');
    await _shot(tester, '06-设置', boundaryKey);

    // 手机尺寸：比赛列表
    tester.view.physicalSize = const Size(390, 844);
    await nav('总览');
    await nav('比赛');
    await _shot(tester, '07-手机-比赛列表', boundaryKey);

    // —— 旧版界面（ui_mode=legacy）：设置切换后逐页截图 ——
    tester.view.physicalSize = const Size(1440, 900);
    await nav('总览');
    await nav('设置');
    // 找到「旧版界面」chip（在皮肤区内，可能需滚动）
    for (var i = 0;
        i < 8 && find.text('旧版界面').evaluate().isEmpty;
        i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.tap(find.text('旧版界面'));
    await tester.pump(const Duration(milliseconds: 500));
    await _shot(tester, 'L01-旧版-总览', boundaryKey);
    await tester.tap(find.text('列表'));
    await _shot(tester, 'L02-旧版-列表', boundaryKey);
    await tester.tap(find.text('时间线'));
    await _shot(tester, 'L03-旧版-时间线', boundaryKey);
    await tester.tap(find.text('获奖'));
    await _shot(tester, 'L04-旧版-获奖', boundaryKey);
    await tester.tap(find.text('设置'));
    await _shot(tester, 'L05-旧版-设置', boundaryKey);
    // 抽屉状态：列表 → 点行
    await tester.tap(find.text('列表'));
    await tester.pump(const Duration(milliseconds: 300));
    final rows = find.textContaining('全国大学生数学建模竞赛');
    if (rows.evaluate().isNotEmpty) {
      await tester.tap(rows.first);
      await tester.pump(const Duration(milliseconds: 400));
      await _shot(tester, 'L06-旧版-详情抽屉', boundaryKey);
    }
  });
}
