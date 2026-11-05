import 'package:flutter/material.dart';

import '../domain/classification.dart';

class DirectionPicker extends StatelessWidget {
  const DirectionPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('设计方向（可多选）'),
      const Text(
        '不选时根据原始类别自动归类；手动选择只修改方向，不改原始描述。',
        style: TextStyle(fontSize: 12),
      ),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final name in directionKeywords.keys)
            FilterChip(
              label: Text(name),
              selected: selected.contains(name),
              onSelected: (v) {
                final next = {...selected};
                v ? next.add(name) : next.remove(name);
                onChanged(next);
              },
            ),
          if (selected.isNotEmpty)
            ActionChip(
              label: const Text('恢复自动归类'),
              onPressed: () => onChanged({}),
            ),
        ],
      ),
    ],
  );
}
