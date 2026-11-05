/// 共享小组件：状态徽标、倒计时徽标、统计卡、空态。
library;

import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/rules.dart';
import 'theme.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.comp, this.todayDate});
  final Competition comp;
  final DateTime? todayDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = comp.status(todayDate);
    final (bg, fg) = AppTheme.statusColors(status, scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        statusLabels[status] ?? status,
        style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class CountdownBadge extends StatelessWidget {
  const CountdownBadge({super.key, required this.comp, this.official = false});
  final Competition comp;
  final bool official;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = official ? comp.officialCountdown() : comp.countdown();
    final color = official
        ? scheme.onSurfaceVariant
        : AppTheme.countdownColor(days, scheme);
    final text = days == 0 ? '今天' : (days > 0 ? '剩 $days 天' : '已过 ${-days} 天');
    return Text(
      '$text · ${official ? "官方截止" : "临期线"}',
      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
    );
  }
}

class LevelBadge extends StatelessWidget {
  const LevelBadge({super.key, required this.level});
  final String level;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        level.isEmpty ? '校级' : level,
        style: TextStyle(
          fontSize: 12,
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.icon,
    this.onTap,
  });
  final String label;
  final String value;
  final Color? color;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return Card(
      color: scheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, box) {
            final compact = box.maxWidth < 170; // 窄屏三卡一行时隐藏图标防溢出
            final number = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: compact ? 19 : 21,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
            if (compact) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: number,
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // 同色系柔色圆形图标（wenku8 手法：保留色相编码，不再刺眼）
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon ?? Icons.insights,
                      size: 19,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  number,
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
  });
  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(color: scheme.onSurfaceVariant)),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!, style: TextStyle(fontSize: 12, color: scheme.outline)),
          ],
        ],
      ),
    );
  }
}

/// 通用确认对话框；返回 null/true/false。
Future<bool?> confirmDialog(
  BuildContext context,
  String title,
  String content, {
  String okText = '确定',
  bool danger = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                )
              : null,
          child: Text(okText),
        ),
      ],
    ),
  );
}

/// 全局 ScaffoldMessenger：让 toast 在页面 pop 之后仍能显示
/// （保存/删除的反馈发生在「返回原页面」的瞬间）。
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// 跨页面 toast（不依赖当前 context 是否还在树上）。
void appToast(String message, {bool error = false}) {
  final ms = appMessengerKey.currentState;
  if (ms == null) return;
  ms.clearSnackBars();
  ms.showSnackBar(SnackBar(
    content: Text(message),
    duration: const Duration(seconds: 3),
  ));
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ),
  );
}
