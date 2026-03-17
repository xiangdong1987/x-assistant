import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_model.dart';
import '../../models/task_enums.dart';
import 'priority_badge.dart';

class TaskCard extends StatelessWidget {
  final TaskModel task;
  final VoidCallback? onTap;
  final VoidCallback? onComplete;
  final VoidCallback? onDelete;

  const TaskCard({
    super.key,
    required this.task,
    this.onTap,
    this.onComplete,
    this.onDelete,
  });

  IconData _statusIcon(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return Icons.radio_button_unchecked;
      case TaskStatus.confirmed:
        return Icons.check_circle_outline;
      case TaskStatus.inProgress:
      case TaskStatus.coding:
        return Icons.play_circle_outline;
      case TaskStatus.completed:
        return Icons.check_circle;
      case TaskStatus.cancelled:
        return Icons.cancel_outlined;
      case TaskStatus.planned:
        return Icons.assignment_outlined;
      case TaskStatus.planning:
        return Icons.edit_note_outlined;
      case TaskStatus.testing:
        return Icons.science_outlined;
      case TaskStatus.submitting:
        return Icons.publish_outlined;
      case TaskStatus.failed:
        return Icons.error_outline;
    }
  }

  Color _statusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return const Color(0xFF9CA3AF);
      case TaskStatus.confirmed:
        return const Color(0xFF3B82F6);
      case TaskStatus.inProgress:
      case TaskStatus.coding:
        return const Color(0xFF8B5CF6);
      case TaskStatus.completed:
        return const Color(0xFF10B981);
      case TaskStatus.cancelled:
        return const Color(0xFFEF4444);
      case TaskStatus.planned:
        return const Color(0xFF6366F1);
      case TaskStatus.planning:
        return const Color(0xFF6366F1);
      case TaskStatus.testing:
        return const Color(0xFFF59E0B);
      case TaskStatus.submitting:
        return const Color(0xFF10B981);
      case TaskStatus.failed:
        return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: Key(task.id),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.check, color: Colors.white, size: 28),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onComplete?.call();
          return false;
        } else {
          final l10n = AppLocalizations.of(context)!;
          return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l10n.deleteTask),
              content: Text(l10n.deleteTaskConfirmMessage(task.title)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: Text(l10n.delete),
                ),
              ],
            ),
          );
        }
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          onDelete?.call();
        }
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withAlpha(80),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(8),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Priority color bar
                PriorityBadge(priority: task.priority, compact: true),
                const SizedBox(width: 12),

                // Status icon
                Icon(
                  _statusIcon(task.status),
                  color: _statusColor(task.status),
                  size: 22,
                ),
                const SizedBox(width: 12),

                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                decoration: task.status == TaskStatus.completed
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: task.status == TaskStatus.completed
                                    ? colorScheme.onSurfaceVariant
                                    : colorScheme.onSurface,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            // Source tag
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer
                                    .withAlpha(120),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                task.source.label(l10n),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Status label
                            Text(
                              task.status.label(l10n),
                              style: TextStyle(
                                fontSize: 11,
                                color: _statusColor(task.status),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (task.isOverdue) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.warning_amber_rounded,
                                size: 14,
                                color: Color(0xFFEF4444),
                              ),
                              Text(
                                ' ${l10n.overdue}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFFEF4444),
                                ),
                              ),
                            ],
                            // Progress Text
                            if (task.totalItems > 0) ...[
                              const Spacer(),
                              Text(
                                '${task.completedItems} / ${task.totalItems}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                        // Progress Bar
                        if (task.totalItems > 0) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: task.completedItems / task.totalItems,
                              minHeight: 4,
                              backgroundColor: colorScheme.surfaceVariant,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                task.completedItems == task.totalItems
                                    ? const Color(0xFF10B981)
                                    : colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Due time or chevron
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: task.dueAt != null
                      ? Text(
                          _formatDueDate(context, task.dueAt!),
                          style: TextStyle(
                            fontSize: 11,
                            color: task.isOverdue
                                ? const Color(0xFFEF4444)
                                : colorScheme.onSurfaceVariant,
                          ),
                        )
                      : Icon(
                          Icons.chevron_right,
                          color: colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDueDate(BuildContext context, DateTime date) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final diff = date.difference(now);
    final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    if (diff.inDays == 0) {
      return l10n.todayAt(timeStr);
    } else if (diff.inDays == 1) {
      return l10n.tomorrow;
    } else if (diff.inDays == -1) {
      return l10n.yesterday;
    } else if (diff.inDays > 1 && diff.inDays < 7) {
      return l10n.daysLater(diff.inDays);
    } else {
      return '${date.month}/${date.day}';
    }
  }
}
