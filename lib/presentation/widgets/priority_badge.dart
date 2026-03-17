import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_enums.dart';

class PriorityBadge extends StatelessWidget {
  final TaskPriority priority;
  final bool compact;

  const PriorityBadge({
    super.key,
    required this.priority,
    this.compact = false,
  });

  Color get color {
    switch (priority) {
      case TaskPriority.p0:
        return const Color(0xFFEF4444); // Red
      case TaskPriority.p1:
        return const Color(0xFFF59E0B); // Amber
      case TaskPriority.p2:
        return const Color(0xFF3B82F6); // Blue
      case TaskPriority.p3:
        return const Color(0xFF9CA3AF); // Gray
    }
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        width: 4,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }

    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80), width: 1),
      ),
      child: Text(
        priority.label(l10n),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
