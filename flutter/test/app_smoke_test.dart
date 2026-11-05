/// 应用冒烟测试：真实仓库（临时目录）+ 完整外壳能渲染，主流程页面可达。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workcalendar/data/repository.dart';
import 'package:workcalendar/domain/models.dart';
import 'package:workcalendar/main.dart';
import 'package:workcalendar/ui/competitions_list.dart';
import 'package:workcalendar/ui/legacy/widgets.dart';
import 'package:workcalendar/ui/theme.dart';
import 'package:workcalendar/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WcRepository repo;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('wc_smoke');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // 临时目录清理失败不影响测试
      }
    });
    repo = await WcRepository.open(dir.path);
    await repo.upsertComp(
      Competition.fromLegacyJson({
        'name': '冒烟测试大赛',
        'deadline': '2100-12-31',
        'category': '综合',
      }),
    );
    await repo.upsertAward(
      Award.fromLegacyJson({
        'name': '冒烟测试金奖',
        'level': '国家级',
        'award_date': '2099-01-01',
      }),
    );
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const WorkCalendarApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('总览渲染最优先事项与近期安排', (tester) async {
    await pumpApp(tester);
    expect(find.text('总览'), findsWidgets);
    expect(find.textContaining('最优先事项'), findsOneWidget);
    // 近期安排列表在首屏下方，ListView 懒构建需滚动后才可见
    for (var i = 0; i < 6 && find.text('冒烟测试大赛').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -220));
      await tester.pumpAndSettle();
    }
    expect(find.text('冒烟测试大赛'), findsWidgets);
  });

  testWidgets('比赛列表与获奖分组可达', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('比赛').last);
    await tester.pumpAndSettle();
    expect(find.text('冒烟测试大赛'), findsOneWidget);

    await tester.tap(find.text('获奖').last);
    await tester.pumpAndSettle();
    expect(find.text('冒烟测试金奖'), findsOneWidget);
  });

  testWidgets('桌面多记录可滚动且单击立即切换详情', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      for (var i = 0; i < 35; i++) {
        await repo.upsertComp(
          Competition.fromLegacyJson({
            'name': '布局测试比赛${i.toString().padLeft(2, '0')}',
            'deadline': '2100-12-31',
            'organizer': '较长的主办方名称用于检查排版',
          }),
        );
      }
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: AppTheme.design(Brightness.light),
          home: const CompetitionsListPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('布局测试比赛01').first);
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (w) => w is SelectableText && w.data == '布局测试比赛01',
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const PageStorageKey('competition-table')),
      const Offset(0, -2400),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('中等窗口与放大字体不会挤出表格', (tester) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: AppTheme.design(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const CompetitionsListPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const PageStorageKey('competition-table')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面工作区：99 行可滚动且面板含快捷标记', (tester) async {
    // 真实数据规模（99 条比赛）灌入，防长列表溢出回归；
    // 真实文件 IO 必须包在 runAsync 里（testWidgets 的 FakeAsync 会卡死）
    await tester.runAsync(() async {
      for (var i = 0; i < 99; i++) {
        await repo.upsertComp(Competition.fromLegacyJson({
          'name': '批量比赛${i.toString().padLeft(2, '0')}',
          'deadline': '2026-12-${(i % 28 + 1).toString().padLeft(2, '0')}',
          'category': i % 2 == 0 ? '竞赛' : '设计',
        }));
      }
    });
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: AppTheme.design(Brightness.dark),
          home: const CompetitionsListPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const PageStorageKey('competition-table')), findsOneWidget);
    // 检查面板出现且带快捷标记（就地改状态，免跳详情）
    expect(find.text('快捷标记'), findsOneWidget);
    expect(find.byType(FilterChip), findsWidgets);
    // 长列表拖动到中段无异常
    await tester.drag(
      find.byKey(const PageStorageKey('competition-table')),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('时间线：桌面侧栏可达且渲染甘特', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester);
    await tester.tap(find.text('时间线'));
    await tester.pumpAndSettle();
    expect(find.textContaining('窗口'), findsWidgets);
    expect(find.text('准备期'), findsOneWidget);
    expect(find.text('提交期'), findsOneWidget);
    // 冒烟数据 1 条比赛 → 甘特里应可见
    expect(find.text('冒烟测试大赛'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('旧版界面：设置切换后完整呈现原版结构', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester);
    // 切换：设置 → 皮肤 → 旧版界面
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('旧版界面'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('旧版界面'));
    await tester.pumpAndSettle();
    // Legacy 外壳特征：导航分组「浏览」+ 全局工具栏 + 总览统计
    expect(find.text('浏览'), findsOneWidget);
    expect(find.text('管理'), findsOneWidget);
    expect(find.text('进行中'), findsWidgets);
    expect(find.text('最近导入'), findsOneWidget);
    // 列表视图：原版表格 + 行内操作
    await tester.tap(find.text('列表'));
    await tester.pumpAndSettle();
    expect(find.text('全部比赛'), findsOneWidget);
    expect(find.text('详情'), findsWidgets);
    // 点击行 → 右侧抽屉（非全屏页）：抽屉内出现「提交链路（里程碑）」
    await tester.tap(find.text('冒烟测试大赛'));
    await tester.pumpAndSettle();
    expect(find.text('提交链路（里程碑）'), findsOneWidget);
    expect(find.text('✓ 标记已提交'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // 关抽屉（右上角 ✕ 图标钮）→ 设置页：原版 5 卡全量还原
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('💾 数据管理'), findsOneWidget);
    expect(find.text('📥 导入比赛（JSON / Markdown）'), findsOneWidget);
    expect(find.text('设备配对与数据同步'), findsOneWidget);
    expect(find.text('🖼️ 外观'), findsOneWidget);
    expect(find.text('🎨 偏好'), findsOneWidget);
    expect(find.text('ℹ️ 关于'), findsOneWidget);
    // 同步按钮如实禁用
    expect(
        tester
            .widgetList<LButton>(find.byType(LButton))
            .where((b) => b.label.contains('扫一扫配对'))
            .every((b) => b.onPressed == null),
        isTrue);
    expect(tester.takeException(), isNull);
  });
}
