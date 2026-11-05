/// 动效包：对 0.5.0 motion_pack.js 的 Flutter 重实现（非逐帧复刻）。
///
/// - TabReveal：视图切换揭示（淡入 + 轻位移，300ms，可中断——快速连点只播最后一次）；
/// - PressableScale：点击弹性反馈（按下缩小 → 回弹，280ms）；
/// - 全部受「减少动效」设置降级：关闭后立即到位，保留状态变化本身。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

/// 切页揭示：包在壳层的内容区上，index 变化时重放。
class TabReveal extends ConsumerStatefulWidget {
  const TabReveal({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  ConsumerState<TabReveal> createState() => _TabRevealState();
}

class _TabRevealState extends ConsumerState<TabReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final Animation<double> _fade = _ctrl.drive(
    CurveTween(curve: Curves.easeOutCubic),
  );
  double _direction = 1; // +1 = 从右滑入（向右切页），-1 = 从左滑入

  @override
  void initState() {
    super.initState();
    _ctrl.value = 1;
  }

  @override
  void didUpdateWidget(TabReveal old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      if (ref.read(reducedMotionProvider)) {
        _ctrl.value = 1;
        return;
      }
      // 方向感：切到更右侧的页 → 内容从右滑入；可中断，连点只播最后一次
      _direction = widget.index > old.index ? 1 : -1;
      _ctrl.forward(from: _ctrl.isAnimating ? _ctrl.value : 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced =
        ref.watch(reducedMotionProvider) ||
        MediaQuery.disableAnimationsOf(context);
    if (reduced) return widget.child;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.72, end: 1).animate(_fade),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0.012 * _direction, 0),
          end: Offset.zero,
        ).animate(_fade),
        child: widget.child,
      ),
    );
  }
}

/// 错峰刷入：详情页各区块按 delay 依次淡入上移（对应 0.5.0
/// 「详情抽屉文字刷出」的等效简化，360ms/区块）。
class StaggerIn extends ConsumerStatefulWidget {
  const StaggerIn({super.key, required this.delay, required this.child});
  final Duration delay;
  final Widget child;

  @override
  ConsumerState<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends ConsumerState<StaggerIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  late final Animation<double> _anim = _ctrl.drive(
    CurveTween(curve: Curves.easeOutCubic),
  );

  @override
  void initState() {
    super.initState();
    if (ref.read(reducedMotionProvider)) {
      _ctrl.value = 1;
    } else {
      Future.delayed(widget.delay, () {
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
    final reduced =
        ref.watch(reducedMotionProvider) ||
        MediaQuery.disableAnimationsOf(context);
    if (reduced) return widget.child;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.85, end: 1).animate(_anim),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(_anim),
        child: widget.child,
      ),
    );
  }
}

/// 点击弹性反馈：按压缩小、松开回弹。
/// 用 Listener 观察指针而不参与手势竞技场，不会拦截内部 InkWell/ListTile 的点击。
class PressableScale extends ConsumerStatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.pressedScale = 0.985,
  });

  final Widget child;
  final double pressedScale;

  @override
  ConsumerState<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends ConsumerState<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced =
        ref.watch(reducedMotionProvider) ||
        MediaQuery.disableAnimationsOf(context);
    if (reduced) return widget.child;
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: Duration(milliseconds: _pressed ? 80 : 160),
        curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
