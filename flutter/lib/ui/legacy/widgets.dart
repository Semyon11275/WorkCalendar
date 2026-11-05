/// 旧版界面共享组件：徽标/倒计时/类别 chip/按钮/卡片/输入装饰。
/// 结构与配色按原版 HTML+wenku8 CSS 逐项对应；字体：正文思源宋体，数字 Segoe UI。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../domain/rules.dart';
import 'tokens.dart';

class LegacyPalette {
  LegacyPalette(this.dark);
  final bool dark;

  Color get bg => dark ? LegacyTokens.bgD : LegacyTokens.bgL;
  Color get headerBg => dark ? LegacyTokens.headerD : LegacyTokens.headerL;
  Color get navBg => dark ? LegacyTokens.navD : LegacyTokens.navL;
  Color get card => dark ? LegacyTokens.cardD : LegacyTokens.cardL;
  Color get hairline => dark ? LegacyTokens.hairlineD : LegacyTokens.hairlineL;
  Color get text => dark ? LegacyTokens.textD : LegacyTokens.textL;
  Color get muted => dark ? LegacyTokens.mutedD : LegacyTokens.mutedL;
  Color get primary => dark ? LegacyTokens.primaryD : LegacyTokens.primaryL;
  Color get onPrimary => dark ? LegacyTokens.onPrimaryD : LegacyTokens.onPrimaryL;
  Color get drawerBg => dark ? LegacyTokens.drawerD : LegacyTokens.drawerL;
  Color get portInfo => dark ? LegacyTokens.portInfoD : LegacyTokens.portInfoL;

  // 状态徽标
  (Color, Color) status(String status) {
    switch (status) {
      case 'urgent':
        return (dark ? LegacyTokens.urgentD : LegacyTokens.urgentL,
            dark ? LegacyTokens.urgentTextD : LegacyTokens.urgentTextL);
      case 'past_suggested':
        return (dark ? LegacyTokens.pastSuggD : LegacyTokens.pastSuggL,
            dark ? LegacyTokens.pastSuggTextD : LegacyTokens.pastSuggTextL);
      case 'overdue':
        return (dark ? LegacyTokens.overdueD : LegacyTokens.overdueL,
            dark ? LegacyTokens.overdueTextD : LegacyTokens.overdueTextL);
      case 'submitted':
        return (dark ? LegacyTokens.submittedD : LegacyTokens.submittedL,
            dark ? LegacyTokens.submittedTextD : LegacyTokens.submittedTextL);
      case 'done':
        return (dark ? LegacyTokens.doneD : LegacyTokens.doneL,
            dark ? LegacyTokens.doneTextD : LegacyTokens.doneTextL);
      case 'abandoned':
        return (dark ? LegacyTokens.abandonedD : LegacyTokens.abandonedL,
            dark ? LegacyTokens.abandonedTextD : LegacyTokens.abandonedTextL);
      case 'open':
        return (dark ? LegacyTokens.openD : LegacyTokens.openL,
            dark ? LegacyTokens.openTextD : LegacyTokens.openTextL);
      case 'not_started':
        return (dark ? LegacyTokens.notStartedD : LegacyTokens.notStartedL,
            dark ? LegacyTokens.notStartedTextD : LegacyTokens.notStartedTextL);
      default: // submitting
        return (dark ? LegacyTokens.submittingD : LegacyTokens.submittingL,
            dark ? LegacyTokens.submittingTextD : LegacyTokens.submittingTextL);
    }
  }

  Color barColor(Competition c) {
    final s = c.status();
    if (s == 'submitted' || s == 'done' || s == 'abandoned') {
      return LegacyTokens.barDone;
    }
    final d = c.countdown();
    if (d <= 3) return LegacyTokens.barUrgent;
    if (d <= 7) return LegacyTokens.barSoon;
    return LegacyTokens.barCalm;
  }

  /// 类别 chip 哈希取色（catColor 同款哈希）
  (Color, Color) cat(String cat) {
    var h = 0;
    for (final ch in (cat.isEmpty ? '未分类' : cat).codeUnits) {
      h = (h * 31 + ch) % 997;
    }
    final c = LegacyTokens.catChips[h % LegacyTokens.catChips.length];
    return dark ? (c.$3, c.$4) : (c.$1, c.$2);
  }

  /// 倒计时徽标渐变（返回 null = 浅底样式）
  List<Color>? countdownGradient(Competition c) {
    final d = c.countdown();
    final s = c.status();
    if (s == 'submitted' || s == 'done') return LegacyTokens.cdDone;
    if (s == 'abandoned') return null;
    if (d == 0) return LegacyTokens.cdToday;
    if (d < 0) {
      return s == 'overdue' ? null : LegacyTokens.cdSoon; // 已过临期线=amber 渐变
    }
    if (d <= 3) return LegacyTokens.cdToday;
    if (d <= 7) return LegacyTokens.cdUrgent;
    if (d <= 30) return LegacyTokens.cdSoon;
    return LegacyTokens.cdCalm;
  }
}

/// 状态徽标（statusBadge）
class LStatusBadge extends StatelessWidget {
  const LStatusBadge({super.key, required this.p, required this.status});
  final LegacyPalette p;
  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = p.status(status);
    return _pill(bg, fg, statusLabels[status] ?? status, border: false);
  }
}

/// 倒计时徽标（countdownBadge，含渐变与文案）
class LCountdownBadge extends StatelessWidget {
  const LCountdownBadge({super.key, required this.p, required this.comp});
  final LegacyPalette p;
  final Competition comp;

  @override
  Widget build(BuildContext context) {
    final d = comp.countdown();
    final s = comp.status();
    String text;
    List<Color>? grad = p.countdownGradient(comp);
    Color? flatBg, flatFg;
    if (s == 'submitted') {
      text = '✓ 已提交';
      flatBg = p.dark ? LegacyTokens.submittedD : LegacyTokens.cdDone[0];
      flatFg = p.dark ? LegacyTokens.submittedTextD : LegacyTokens.cdDoneTextL;
    } else if (s == 'done') {
      text = '✓ 已完成';
      flatBg = p.dark ? LegacyTokens.doneD : LegacyTokens.cdDone[1];
      flatFg = p.dark ? LegacyTokens.doneTextD : LegacyTokens.cdDoneTextL;
    } else if (s == 'abandoned') {
      text = '已放弃';
      flatBg = p.dark ? LegacyTokens.abandonedD : LegacyTokens.abandonedL;
      flatFg = p.dark ? LegacyTokens.abandonedTextD : LegacyTokens.abandonedTextL;
    } else if (d == 0) {
      text = '⏰ 今天截止！';
    } else if (d < 0) {
      if (s == 'overdue') {
        text = '已过 ${-d} 天';
        flatBg = p.dark ? LegacyTokens.overdueD : LegacyTokens.overdueL;
        flatFg = p.dark ? LegacyTokens.overdueTextD : LegacyTokens.overdueTextL;
      } else {
        text = '⚠ 已过临期线 ${-d} 天';
      }
    } else {
      text = '剩 $d 天';
    }
    return _pill(
      grad != null ? null : (flatBg ?? Colors.transparent),
      grad != null ? Colors.white : flatFg ?? Colors.transparent,
      text,
      gradient: grad,
    );
  }
}

/// 类别 chip（catColor 哈希）
class LCatChip extends StatelessWidget {
  const LCatChip({super.key, required this.p, required this.category, this.small = false});
  final LegacyPalette p;
  final String category;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = p.cat(category);
    return _pill(bg, fg, category.isEmpty ? '未分类' : category,
        fontSize: small ? 10 : 11);
  }
}

Widget _pill(Color? bg, Color? fg, String text,
    {List<Color>? gradient, double fontSize = 11.5, bool border = false}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      gradient: gradient == null
          ? null
          : LinearGradient(colors: gradient),
      color: gradient == null ? bg : null,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
          color: border
              ? (fg ?? Colors.transparent).withValues(alpha: 0.35)
              : Colors.transparent),
    ),
    child: Text(text,
        style: TextStyle(
            fontSize: fontSize,
            color: fg,
            fontWeight: FontWeight.w500,
            height: 1.1)),
  );
}

/// 旧版按钮（btn / btn-primary / btn-ghost / btn-danger）
class LButton extends StatelessWidget {
  const LButton({
    super.key,
    required this.label,
    this.kind = LBtnKind.ghost,
    this.onPressed,
    this.dense = false,
  });
  final String label;
  final LBtnKind kind;
  final VoidCallback? onPressed;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = context.legacy;
    final disabled = onPressed == null;
    Color bg;
    Color fg;
    switch (kind) {
      case LBtnKind.primary:
        bg = p.primary;
        fg = p.onPrimary;
      case LBtnKind.danger:
        bg = p.dark ? const Color(0xFF4A2C2A) : const Color(0xFFF9DEDE);
        fg = p.dark ? const Color(0xFFF2B8B5) : const Color(0xFFB3261E);
      case LBtnKind.ghost:
        bg = p.dark ? const Color(0xFF2A2E36) : const Color(0xFFEDF0F7);
        fg = p.dark ? const Color(0xFFD5D7DE) : const Color(0xFF3A3F4B);
    }
    if (disabled) {
      bg = bg.withValues(alpha: 0.45);
      fg = fg.withValues(alpha: 0.55);
    }
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: p.hairline)),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: dense ? 10 : 16, vertical: dense ? 5 : 8),
            child: Text(label,
                style: TextStyle(
                    fontSize: dense ? 11.5 : 13,
                    fontWeight: FontWeight.w600,
                    color: fg)),
          ),
        ),
      ),
    );
  }
}

enum LBtnKind { primary, ghost, danger }

/// 旧版卡片（card：白底 20px 圆角 + 发丝描边）
class LCard extends StatelessWidget {
  const LCard({super.key, required this.child, this.padding, this.onTap});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.legacy;
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.hairline),
        boxShadow: p.dark
            ? null
            : [
                BoxShadow(
                    color: const Color(0xFF0B2249).withValues(alpha: 0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1)),
              ],
      ),
      child: onTap == null
          ? padding == null
              ? child
              : Padding(padding: padding!, child: child)
          : InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Padding(padding: padding ?? EdgeInsets.zero, child: child)),
    );
  }
}

/// 视图小节标题（h3 带蓝色竖条）
class LSectionTitle extends StatelessWidget {
  const LSectionTitle({super.key, required this.p, required this.title, this.trailing});
  final LegacyPalette p;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
              color: p.primary, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(title,
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
      const Spacer(),
      ?trailing,
    ]);
  }
}

/// 数字/日期等宽文字（wenku8.css：数字保持无衬线 Segoe UI）
TextStyle lMono(double size, {Color? color, FontWeight weight = FontWeight.w600}) {
  return TextStyle(
      fontFamily: 'Segoe UI',
      fontFamilyFallback: LegacyTokens.monoFallback,
      fontSize: size,
      fontWeight: weight,
      color: color);
}

/// 临期线日期颜色（原版列表口径：过期灰、≤3 红、≤7 橙、≤30 琥珀、其余绿）
Color lSuggestedColor(int countdown, LegacyPalette p) {
  if (countdown < 0) return p.muted;
  if (countdown <= 3) return const Color(0xFFE11D48);
  if (countdown <= 7) return const Color(0xFFF43F5E);
  if (countdown <= 30) return const Color(0xFFD97706);
  return const Color(0xFF059669);
}

/// 旧版输入装饰（input 12px 圆角）
InputDecoration lInputDeco(LegacyPalette p, String hint, {Widget? prefixIcon}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: p.muted.withValues(alpha: 0.7), fontSize: 13),
    prefixIcon: prefixIcon,
    isDense: true,
    filled: true,
    fillColor: p.card,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.hairline)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.hairline)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.primary, width: 1.4)),
  );
}

extension LegacyPaletteOf on BuildContext {
  LegacyPalette get legacy =>
      LegacyPalette(Theme.of(this).brightness == Brightness.dark);
}


/// 抽屉文字刷出（motion_pack #3 等效）：块级错峰淡入+上移，总时长 420ms；
/// 「减少动效」时直接显示。
class LegacyStaggerIn extends ConsumerStatefulWidget {
  const LegacyStaggerIn({
    super.key,
    required this.delayMs,
    required this.child,
  });

  final int delayMs;
  final Widget child;

  @override
  ConsumerState<LegacyStaggerIn> createState() => _LegacyStaggerInState();
}

class _LegacyStaggerInState extends ConsumerState<LegacyStaggerIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _anim =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    if (ref.read(reducedMotionProvider)) {
      _ctrl.value = 1;
    } else {
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(reducedMotionProvider)) return widget.child;
    return FadeTransition(
      opacity: _anim,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
            .animate(_anim),
        child: widget.child,
      ),
    );
  }
}
