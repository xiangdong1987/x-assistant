import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/schedule_model.dart';
import '../../../providers/skill_provider.dart';
import 'agenda_screen.dart';

class ScheduleDetailScreen extends ConsumerStatefulWidget {
  final AgendaItem item;

  const ScheduleDetailScreen({super.key, required this.item});

  @override
  ConsumerState<ScheduleDetailScreen> createState() =>
      _ScheduleDetailScreenState();
}

class _ScheduleDetailScreenState extends ConsumerState<ScheduleDetailScreen> {
  static const _typeColors = {
    'meeting': Color(0xFF3B82F6),
    'deadline': Color(0xFFEF4444),
    'social': Color(0xFF10B981),
    'review': Color(0xFF8B5CF6),
  };

  static const _statusColors = {
    'scheduled': Color(0xFF78909C),
    'in_progress': Color(0xFFFF9800),
    'completed': Color(0xFF4CAF50),
    'cancelled': Color(0xFF9E9E9E),
  };

  late String _currentStatus;
  bool _isChangingStatus = false;
  bool _needsRefresh = false;

  AgendaItem get item => widget.item;

  @override
  void initState() {
    super.initState();
    _currentStatus = item.status ?? ScheduleStatus.scheduled;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locs = AppLocalizations.of(context)!;
    final color = _typeColors[item.eventType ?? ''] ?? cs.primary;
    final statusColor = _statusColors[_currentStatus] ?? cs.onSurfaceVariant;
    final isCancelled = _currentStatus == ScheduleStatus.cancelled;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.pop(_needsRefresh);
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(locs.scheduleDetailTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: locs.editSchedule,
              onPressed: () => _showEditSheet(context, locs),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: Colors.red,
              tooltip: locs.deleteScheduleTitle,
              onPressed: () => _confirmDelete(context, locs),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header card
            Container(
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border(left: BorderSide(color: color, width: 4)),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _Badge(
                        label: _typeLabel(item.eventType, locs),
                        color: color,
                      ),
                      const SizedBox(width: 8),
                      _Badge(
                        label: _statusLabel(_currentStatus, locs),
                        color: statusColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          decoration:
                              isCancelled ? TextDecoration.lineThrough : null,
                          color: isCancelled ? cs.onSurfaceVariant : null,
                        ),
                  ),
                ],
              ),
            ),

            // Status action buttons
            _buildStatusActions(cs, locs),

            const SizedBox(height: 12),

            // Time section
            _InfoCard(
              children: [
                if (item.time != null)
                  _InfoRow(
                    icon: Icons.access_time,
                    label: locs.startTimeLabel,
                    value: DateFormat('yyyy-MM-dd HH:mm')
                        .format(item.time!.toLocal()),
                    color: color,
                  ),
                if (item.endTime != null)
                  _InfoRow(
                    icon: Icons.timer_outlined,
                    label: locs.endTimeLabel,
                    value: DateFormat('yyyy-MM-dd HH:mm')
                        .format(item.endTime!.toLocal()),
                    color: color,
                  ),
              ],
            ),

            // Description
            if (item.description != null &&
                item.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              _InfoCard(
                children: [
                  _SectionLabel(locs.description),
                  const SizedBox(height: 6),
                  Text(
                    item.description!,
                    style: TextStyle(color: cs.onSurface, height: 1.5),
                  ),
                ],
              ),
            ],

            // Project
            if (item.projectKey != null &&
                item.projectKey != 'none' &&
                item.projectKey!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              _InfoCard(
                children: [
                  _InfoRow(
                    icon: Icons.folder_outlined,
                    label: locs.projectKey,
                    value: item.projectKey!,
                    color: cs.primary,
                  ),
                ],
              ),
            ],

            // Linked tasks
            ...[
              const SizedBox(height: 12),
              _InfoCard(
                children: [
                  _SectionLabel(locs.linkedTasks),
                  const SizedBox(height: 6),
                  if (item.linkedTasks == null || item.linkedTasks!.isEmpty)
                    Text(
                      locs.noLinkedTasks,
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    )
                  else
                    ...item.linkedTasks!.map((t) => _LinkedTaskRow(task: t)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusActions(ColorScheme cs, AppLocalizations locs) {
    final allowed = ScheduleStatus.allowedTransitions(_currentStatus);
    if (allowed.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: allowed.map((targetStatus) {
          final color = _statusColors[targetStatus] ?? cs.primary;
          final label = _statusLabel(targetStatus, locs);
          final icon = _statusIcon(targetStatus);

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: targetStatus != allowed.last ? 8 : 0,
              ),
              child: FilledButton.tonal(
                onPressed: _isChangingStatus
                    ? null
                    : () => _changeStatus(targetStatus, locs),
                style: FilledButton.styleFrom(
                  backgroundColor: color.withAlpha(30),
                  foregroundColor: color,
                  disabledBackgroundColor: color.withAlpha(15),
                  disabledForegroundColor: color.withAlpha(100),
                  side: BorderSide(color: color.withAlpha(80), width: 0.5),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                child: _isChangingStatus
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 16),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _changeStatus(String newStatus, AppLocalizations locs) async {
    final id = item.scheduleItemId;
    if (id == null) return;

    setState(() => _isChangingStatus = true);
    try {
      final api = ref.read(skillApiServiceProvider);
      if (api == null) return;
      await api.updateScheduleItem(id, {'status': newStatus});
      _needsRefresh = true;
      setState(() => _currentStatus = newStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              locs.scheduleStatusChangeSuccess(_statusLabel(newStatus, locs)),
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(locs.scheduleStatusChangeFailed),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isChangingStatus = false);
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case ScheduleStatus.inProgress:
        return Icons.play_circle_outline;
      case ScheduleStatus.completed:
        return Icons.check_circle_outline;
      case ScheduleStatus.cancelled:
        return Icons.cancel_outlined;
      default:
        return Icons.schedule;
    }
  }

  void _showEditSheet(BuildContext context, AppLocalizations locs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => EditEventSheet(
        item: item,
        onSave: (fields, id) async {
          final api = ref.read(skillApiServiceProvider);
          if (api == null) return;
          if (id != null) {
            await api.updateScheduleItem(id, fields);
          } else {
            await api.createScheduleItem(fields);
          }
          if (context.mounted) context.pop(true);
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppLocalizations locs) {
    final id = item.scheduleItemId;
    if (id == null) return;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(locs.deleteScheduleTitle),
        content: Text(locs.deleteScheduleConfirm(item.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(locs.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final api = ref.read(skillApiServiceProvider);
              if (api != null) await api.deleteScheduleItem(id);
              if (context.mounted) context.pop(true);
            },
            child:
                Text(locs.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String s, AppLocalizations locs) {
    switch (s) {
      case ScheduleStatus.scheduled:
        return locs.scheduleStatusScheduled;
      case ScheduleStatus.inProgress:
        return locs.scheduleStatusInProgress;
      case ScheduleStatus.completed:
        return locs.scheduleStatusCompleted;
      case ScheduleStatus.cancelled:
        return locs.scheduleStatusCancelled;
      default:
        return s;
    }
  }

  String _typeLabel(String? t, AppLocalizations locs) {
    final typeMap = {
      'meeting': locs.eventTypeMeeting,
      'deadline': locs.eventTypeDeadline,
      'social': locs.eventTypeSocial,
      'review': locs.eventTypeReview,
    };
    return typeMap[t ?? ''] ?? t ?? locs.eventTypeOther;
  }
}

// ── Small reusable widgets ─────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80), width: 0.5),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _LinkedTaskRow extends StatelessWidget {
  final AgendaLinkedTask task;
  const _LinkedTaskRow({required this.task});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDone = task.status == 'completed' || task.status == 'cancelled';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            isDone ? Icons.check_circle_outline : Icons.radio_button_unchecked,
            size: 16,
            color: isDone ? Colors.green : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              task.title,
              style: TextStyle(
                fontSize: 13,
                decoration: isDone ? TextDecoration.lineThrough : null,
                color: isDone ? cs.onSurfaceVariant : cs.onSurface,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(task.status,
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
