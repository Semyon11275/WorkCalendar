/// 应用主题：双体系。
/// - design（默认）：「炭黑 / 暖白 / 荧光黄」设计稿 token——四级表面 E0–E3、
///   发丝描边、荧光黄强调、珊瑚橙紧急、灰绿归档、sans 正文 + mono 数字。
/// - seed：Material 3 fromSeed（wenku8 蓝 / 靛蓝 / 青碧 / 暮紫）。
library;

import 'package:flutter/material.dart';

/// 设计稿 token（来自 09-规范-材质与token）。
class DesignTokens {
  static const canvas = Color(0xFF141313); // E0 底层
  static const surface = Color(0xFF1E1D1E); // E1 正文
  static const raised = Color(0xFF312F30); // E2 浮层
  static const plate = Color(0xFFE9E7E4); // 暖白面板（hero/证书）
  static const ink = Color(0xFFF4F2EE);
  static const mut = Color(0xFFA8A49E);
  static const dim = Color(0xFF767370);
  static const line = Color(0x14FFFFFF);
  static const accent = Color(0xFFF6E71A); // 荧光黄
  static const onAccent = Color(0xFF171509);
  static const urgent = Color(0xFFFF9571); // 珊瑚橙
  static const ok = Color(0xFFA9CDAE); // 灰绿
  static const danger = Color(0xFFFF9A9A);
  // 浅色变体（暖白反相）
  static const canvasL = Color(0xFFECEAE6);
  static const surfaceL = Color(0xFFF7F6F3);
  static const raisedL = Color(0xFFFFFFFF);
  static const inkL = Color(0xFF1B1A17);
  static const mutL = Color(0xFF6E6A64);
  static const lineL = Color(0x1F141313);

  /// 设计稿正文字体链（HarmonyOS Sans 优先，逐级回退）。
  static const sansFallback = [
    'Noto Sans SC',
    'PingFang SC',
    'Microsoft YaHei',
  ];

  /// mono 数字/标签字体链。
  static const monoFallback = ['Consolas', 'Courier New', 'monospace'];

  static TextStyle mono(
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w600,
    double spacing = 0.3,
  }) {
    return TextStyle(
      fontFamily: 'Microsoft YaHei',
      fontFamilyFallback: sansFallback,
      fontFeatures: const [FontFeature.tabularFigures()],
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
    );
  }
}

class AppTheme {
  /// 设计稿体系（皮肤预设 0 携带）。
  static ThemeData design(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: DesignTokens.accent,
      onPrimary: DesignTokens.onAccent,
      primaryContainer: dark
          ? const Color(0xFF3A3810)
          : const Color(0xFFEFEBB8),
      onPrimaryContainer: dark ? DesignTokens.accent : const Color(0xFF4A440A),
      secondary: dark ? DesignTokens.ok : const Color(0xFF4E7A54),
      onSecondary: dark ? const Color(0xFF10150F) : Colors.white,
      secondaryContainer: dark ? DesignTokens.raised : const Color(0xFFE2EBE0),
      onSecondaryContainer: dark ? DesignTokens.ink : const Color(0xFF27402A),
      tertiary: DesignTokens.urgent,
      onTertiary: const Color(0xFF2A130A),
      tertiaryContainer: dark
          ? const Color(0xFF4A2A1E)
          : const Color(0xFFF6D7CB),
      onTertiaryContainer: dark ? DesignTokens.urgent : const Color(0xFF7A3517),
      error: dark ? DesignTokens.danger : const Color(0xFFB3402A),
      onError: dark ? const Color(0xFF2A0E0E) : Colors.white,
      errorContainer: dark ? const Color(0xFF3E1C1C) : const Color(0xFFF6D3CB),
      onErrorContainer: dark ? DesignTokens.danger : const Color(0xFF7A2A1A),
      surface: dark ? DesignTokens.canvas : DesignTokens.canvasL,
      onSurface: dark ? DesignTokens.ink : DesignTokens.inkL,
      onSurfaceVariant: dark ? DesignTokens.mut : DesignTokens.mutL,
      outline: dark ? const Color(0xFF4A4746) : const Color(0xFFC9C6C0),
      outlineVariant: dark ? DesignTokens.line : DesignTokens.lineL,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: dark ? DesignTokens.plate : DesignTokens.inkL,
      onInverseSurface: dark ? const Color(0xFF1B1A17) : DesignTokens.plate,
      inversePrimary: dark ? const Color(0xFF4A440A) : DesignTokens.accent,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: dark
          ? const Color(0xFF171616)
          : const Color(0xFFE4E2DD),
      surfaceContainerLow: dark ? DesignTokens.surface : DesignTokens.surfaceL,
      surfaceContainer: dark
          ? const Color(0xFF242323)
          : const Color(0xFFFBFAF8),
      surfaceContainerHigh: dark ? DesignTokens.raised : DesignTokens.raisedL,
      surfaceContainerHighest: dark
          ? const Color(0xFF3A3738)
          : const Color(0xFFFFFFFF),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Microsoft YaHei',
      fontFamilyFallback: DesignTokens.sansFallback,
    );
    return _applyShared(base, scheme, radius: 16);
  }

  /// 旧 seed 体系（wenku8 蓝 / 靛蓝 / 青碧 / 暮紫）。
  static ThemeData light({
    Color seed = const Color(0xFF2F6FBF),
    bool serif = false,
  }) => _seed(Brightness.light, seed, serif);

  static ThemeData dark({
    Color seed = const Color(0xFF2F6FBF),
    bool serif = false,
  }) => _seed(Brightness.dark, seed, serif);

  static ThemeData _seed(Brightness brightness, Color seed, bool serif) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: serif ? 'SourceHanSerifCN' : 'Microsoft YaHei',
      fontFamilyFallback: DesignTokens.sansFallback,
    );
    return _applyShared(base, scheme, radius: 20);
  }

  // -------------------------------------------------------------------------

  static ThemeData _applyShared(
    ThemeData base,
    ColorScheme scheme, {
    required double radius,
  }) {
    final hairline = BorderSide(
      color: scheme.outlineVariant.withValues(alpha: 0.9),
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          fontSize: 16,
          height: 1.5,
          letterSpacing: 0,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          height: 1.5,
          letterSpacing: 0,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          height: 1.45,
          letterSpacing: 0,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontSize: 22,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontSize: 16,
          height: 1.4,
          letterSpacing: 0,
        ),
      ),
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: hairline,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.7),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHigh,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, 44),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          side: hairline,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: const StadiumBorder(),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.9)),
        selectedColor: scheme.primary,
        checkmarkColor: scheme.onPrimary,
        labelStyle: WidgetStateTextStyle.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: hairline,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primary,
        indicatorShape: const StadiumBorder(),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w400,
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primary,
        indicatorShape: const StadiumBorder(),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 400),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// 状态文字色（设计稿语义：进行中黄、紧急橙、归档灰绿、失效弱化）。
  static Color statusTextColor(String status, ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    switch (status) {
      case 'submitting':
        return scheme.primary;
      case 'urgent':
        return scheme.tertiary;
      case 'open':
        return scheme.secondary;
      case 'submitted':
      case 'done':
        return dark ? DesignTokens.ok : const Color(0xFF4E7A54);
      case 'overdue':
      case 'past_suggested':
      case 'not_started':
      case 'abandoned':
      default:
        return scheme.onSurfaceVariant;
    }
  }

  /// 状态徽标配色。
  static (Color, Color) statusColors(String status, ColorScheme scheme) {
    switch (status) {
      case 'urgent':
        return (scheme.tertiaryContainer, scheme.onTertiaryContainer);
      case 'overdue':
      case 'past_suggested':
        return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
      case 'submitted':
      case 'done':
        return (scheme.secondaryContainer, scheme.onSecondaryContainer);
      case 'abandoned':
        return (scheme.surfaceContainerHighest, scheme.outline);
      case 'open':
        return (scheme.secondaryContainer, scheme.onSecondaryContainer);
      case 'not_started':
        return (scheme.surfaceContainerHigh, scheme.onSurfaceVariant);
      default: // submitting
        return (scheme.primaryContainer, scheme.onPrimaryContainer);
    }
  }

  static Color countdownColor(int days, ColorScheme scheme) {
    if (days < 0) return scheme.onSurfaceVariant;
    if (days <= 3) return scheme.tertiary;
    if (days <= 7) return scheme.primary;
    return scheme.onSurfaceVariant;
  }
}
