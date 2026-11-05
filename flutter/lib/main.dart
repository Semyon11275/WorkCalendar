import 'dart:async';
import 'dart:io';
import 'services/release_updater.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/repository.dart';
import 'state/providers.dart';
import 'ui/legacy/shell.dart' as legacy;
import 'ui/legacy/tokens.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart' show appMessengerKey;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await defaultDataDir();
  final repo = await WcRepository.open(dir);
  if (Platform.isWindows) unawaited(ReleaseUpdater.instance.check());
  runApp(ProviderScope(
    overrides: [repositoryProvider.overrideWithValue(repo)],
    child: const WorkCalendarApp(),
  ));
}

class WorkCalendarApp extends ConsumerWidget {
  const WorkCalendarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiMode = ref.watch(uiModeProvider);
    if (uiMode == 'legacy') {
      // 旧版界面：整棵界面树切换，业务数据/规则共用；深浅由旧版自身开关控制
      final legacyDark = ref.watch(legacyDarkProvider);
      final legacyTheme = legacyDark ? ThemeData.dark() : ThemeData.light();
      return MaterialApp(
        scaffoldMessengerKey: appMessengerKey,
        title: '工作日历',
        theme: legacyTheme.copyWith(
          textTheme: legacyTheme.textTheme.apply(
            fontFamily: 'SourceHanSerifCN',
            bodyColor: legacyDark ? LegacyTokens.textD : LegacyTokens.textL,
          ),
          colorScheme: legacyTheme.colorScheme.copyWith(
            primary: legacyDark ? LegacyTokens.primaryD : LegacyTokens.primaryL,
            onPrimary: legacyDark ? LegacyTokens.onPrimaryD : LegacyTokens.onPrimaryL,
            surface: legacyDark ? LegacyTokens.bgD : LegacyTokens.bgL,
          ),
        ),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const legacy.LegacyShell(),
      );
    }
    final mode = ref.watch(themeModeProvider);
    final preset = skinPresets[ref.watch(skinSeedProvider)];
    final serif = ref.watch(serifFontProvider);
    return MaterialApp(
      scaffoldMessengerKey: appMessengerKey,
      title: '工作日历',
      theme: preset.design
          ? AppTheme.design(Brightness.light)
          : AppTheme.light(seed: preset.seed, serif: serif),
      darkTheme: preset.design
          ? AppTheme.design(Brightness.dark)
          : AppTheme.dark(seed: preset.seed, serif: serif),
      themeMode: mode,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Shell(),
    );
  }
}
