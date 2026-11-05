import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workcalendar/data/repository.dart';
import 'package:workcalendar/state/providers.dart';
import 'package:workcalendar/ui/management_page.dart';
import 'package:workcalendar/ui/sync_page.dart';

void main() {
  for (final width in [360.0, 1280.0]) {
    testWidgets('AI 和同步页在 $width 宽度可访问且默认关闭', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('wc_layout'));
      final repo = await tester.runAsync(() => WcRepository.open(dir!.path));
      for (final page in [const ManagementPage(), const SyncPage()]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [repositoryProvider.overrideWithValue(repo!)],
            child: MaterialApp(home: page),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text(page is ManagementPage ? '开启本机 API' : '开启局域网接收'),
          findsOneWidget,
        );
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      await tester.runAsync(() => dir!.delete(recursive: true));
    });
  }
}
