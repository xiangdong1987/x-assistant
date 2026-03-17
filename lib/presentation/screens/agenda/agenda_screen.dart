import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/schedule_model.dart';
import '../../../providers/agenda_provider.dart';
import '../../../providers/skill_provider.dart';

class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  late DateTime _selectedDate;
  bool _showWeekView = false;

  @override
  void initState() {
    super.initState();
    // Jump to the date set from the calendar home page (if any)
    final jumpTo = ref.read(selectedScheduleDateProvider);
    _selectedDate = jumpTo ?? DateTime.now();

    // Clear the jump-to date so next open starts fresh
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(selectedScheduleDateProvider.notifier).state = null;
    });
  }

  void _refresh() {
    // Invalidate entire families to ensure all screens (like Dashboard calendar) update
    ref.invalidate(agendaProvider);
    ref.invalidate(agendaMonthProvider);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedScheduleDateProvider, (previous, next) {
      if (next != null && next != _selectedDate) {
        setState(() => _selectedDate = next);
        Future.microtask(() {
          ref.read(selectedScheduleDateProvider.notifier).state = null;
        });
      }
    });

    final cs = Theme.of(context).colorScheme;
    final locs = AppLocalizations.of(context)!;
    final agendaAsync =
        ref.watch(agendaProvider((from: _selectedDate, to: _selectedDate)));

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(locs.scheduleTitle),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: () => setState(() => _showWeekView = !_showWeekView),
            child: Text(_showWeekView ? locs.byDay : locs.weekView, style: TextStyle(color: cs.primary)),
          ),
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refresh,
              tooltip: locs.refresh),
          IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showEditSheet(context, null),
              tooltip: locs.newSchedule),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.pushNamed('settings'),
            tooltip: locs.settings,
          ),
        ],
        bottom: _DayPicker(
          selected: _selectedDate,
          onChanged: (d) => setState(() => _selectedDate = d),
        ),
      ),
      body: _showWeekView
          ? _buildWeekView(context)
          : _buildDayView(context, agendaAsync, locs),
    );
  }

  // ── Day view ─────────────────────────────────────────────────────────────

  Widget _buildDayView(
      BuildContext context, AsyncValue<List<AgendaItem>> async, AppLocalizations locs) {
    final cs = Theme.of(context).colorScheme;
    return async.when(
      data: (items) {
        final events = items.where((i) => i.type == 'event').toList();
        if (events.isEmpty) {
          return Center(
            child: Text(locs.noScheduleToday, style: TextStyle(color: cs.onSurfaceVariant)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: events.length,
          itemBuilder: (ctx, i) => _EventCard(
            item: events[i],
            onEdit: () => _showEditSheet(ctx, events[i]),
            onDelete: () => _confirmDelete(ctx, events[i], locs),
            onStatusChange: (newStatus) => _changeItemStatus(events[i], newStatus),
            onTap: () async {
              final refreshNeeded = await context.pushNamed<bool>(
                'scheduleDetail',
                extra: events[i],
              );
              if (refreshNeeded == true) _refresh();
            },
          ),
        );
      },
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => Center(
          child: Text('$e', style: TextStyle(color: cs.error, fontSize: 12))),
    );
  }

  // ── 7-day overview ───────────────────────────────────────────────────────

  Widget _buildWeekView(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 7,
      itemBuilder: (ctx, i) {
        final date = _selectedDate.add(Duration(days: i));
        final async = ref.watch(agendaProvider((from: date, to: date)));
        return _WeekDaySection(date: date, agendaAsync: async);
      },
    );
  }

  // ── Edit bottom sheet ────────────────────────────────────────────────────

  Future<void> _changeItemStatus(AgendaItem item, String newStatus) async {
    final id = item.scheduleItemId;
    if (id == null) return;
    final api = ref.read(skillApiServiceProvider);
    if (api == null) return;
    await api.updateScheduleItem(id, {'status': newStatus});
    _refresh();
  }

  void _showEditSheet(BuildContext ctx, AgendaItem? item) {
    showModalBottomSheet(
      context: ctx,
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
          _refresh();
        },
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, AgendaItem item, AppLocalizations locs) {
    final id = item.scheduleItemId;
    if (id == null) return;
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: Text(locs.deleteScheduleTitle),
        content: Text(locs.deleteScheduleConfirm(item.title)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(locs.cancel)),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final api = ref.read(skillApiServiceProvider);
              if (api != null) await api.deleteScheduleItem(id);
              _refresh();
            },
            child: Text(locs.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ── Day picker AppBar bottom ─────────────────────────────────────────────────

class _DayPicker extends StatefulWidget implements PreferredSizeWidget {
  final DateTime selected;
  final ValueChanged<DateTime> onChanged;

  const _DayPicker({required this.selected, required this.onChanged});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  State<_DayPicker> createState() => _DayPickerState();
}

class _DayPickerState extends State<_DayPicker> {
  late ScrollController _sc;
  static const _days = 60;

  @override
  void initState() {
    super.initState();
    // Start scroll so today is roughly centred
    final todayOffset = _days ~/ 2;
    _sc = ScrollController(initialScrollOffset: todayOffset * 56.0);
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locs = AppLocalizations.of(context)!;
    final base = DateTime.now().subtract(Duration(days: _days ~/ 2));
    final weekdays = locs.weekdayShort.split(',');

    return SizedBox(
      height: 56,
      child: ListView.builder(
        controller: _sc,
        scrollDirection: Axis.horizontal,
        itemCount: _days,
        itemBuilder: (ctx, i) {
          final date = base.add(Duration(days: i));
          final isSelected = date.year == widget.selected.year &&
              date.month == widget.selected.month &&
              date.day == widget.selected.day;
          final isToday = date.year == DateTime.now().year &&
              date.month == DateTime.now().month &&
              date.day == DateTime.now().day;

          return GestureDetector(
            onTap: () => widget.onChanged(date),
            child: Container(
              width: 48,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? cs.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: isToday && !isSelected
                    ? Border.all(color: cs.primary, width: 1.5)
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    weekdays[date.weekday % 7],
                    style: TextStyle(
                        fontSize: 10,
                        color: isSelected ? cs.onPrimary : cs.onSurfaceVariant),
                  ),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? cs.onPrimary : cs.onSurface),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Event card (with edit / delete actions) ──────────────────────────────────

class _EventCard extends StatelessWidget {
  final AgendaItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Future<void> Function(String newStatus) onStatusChange;
  final VoidCallback? onTap;

  const _EventCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.onStatusChange,
    this.onTap,
  });

  static const _statusColors = {
    'scheduled': Color(0xFF78909C),
    'in_progress': Color(0xFFFF9800),
    'completed': Color(0xFF4CAF50),
    'cancelled': Color(0xFF9E9E9E),
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locs = AppLocalizations.of(context)!;
    final typeColors = {
      'meeting': const Color(0xFF3B82F6),
      'deadline': const Color(0xFFEF4444),
      'social': const Color(0xFF10B981),
      'review': const Color(0xFF8B5CF6),
    };
    final color = typeColors[item.eventType ?? ''] ?? cs.primary;
    final status = item.status ?? ScheduleStatus.scheduled;
    final statusColor = _statusColors[status] ?? cs.onSurfaceVariant;
    final isCancelled = status == ScheduleStatus.cancelled;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
        leading: item.time != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(DateFormat('HH:mm').format(item.time!.toLocal()),
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: color)),
                  if (item.endTime != null)
                    Text(DateFormat('HH:mm').format(item.endTime!.toLocal()),
                        style: TextStyle(
                            fontSize: 10, color: cs.onSurfaceVariant)),
                ],
              )
            : null,
        title: Text(
          item.title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: isCancelled ? TextDecoration.lineThrough : null,
            color: isCancelled ? cs.onSurfaceVariant : null,
          ),
        ),
        subtitle: (item.description != null && item.description!.isNotEmpty) ||
                (item.projectKey != null && item.projectKey != 'none')
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.description != null &&
                      item.description!.trim().isNotEmpty)
                    Text(
                      item.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  if (item.projectKey != null &&
                      item.projectKey != 'none' &&
                      item.projectKey!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        item.projectKey!,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant.withOpacity(0.9),
                        ),
                      ),
                    ),
                ],
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => _showStatusSheet(context, locs, status),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withAlpha(80), width: 0.5),
                ),
                child: Text(
                  _statusLabel(status, locs),
                  style: TextStyle(fontSize: 10, color: statusColor),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(_typeLabel(item.eventType, locs),
                  style: TextStyle(fontSize: 10, color: color)),
            ),
            const SizedBox(width: 4),
            IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints()),
            IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                color: Colors.red,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints()),
          ],
        ),
      ),
    ),
    );
  }

  void _showStatusSheet(BuildContext context, AppLocalizations locs, String currentStatus) {
    final allowed = ScheduleStatus.allowedTransitions(currentStatus);
    if (allowed.isEmpty) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(locs.changeScheduleStatus,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...allowed.map((s) {
              final color = _statusColors[s] ?? Colors.grey;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                title: Text(_statusLabel(s, locs)),
                onTap: () {
                  Navigator.pop(ctx);
                  onStatusChange(s);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String s, AppLocalizations locs) {
    switch (s) {
      case ScheduleStatus.scheduled:   return locs.scheduleStatusScheduled;
      case ScheduleStatus.inProgress:  return locs.scheduleStatusInProgress;
      case ScheduleStatus.completed:   return locs.scheduleStatusCompleted;
      case ScheduleStatus.cancelled:   return locs.scheduleStatusCancelled;
      default: return s;
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

// ── 7-day section ─────────────────────────────────────────────────────────────

class _WeekDaySection extends StatelessWidget {
  final DateTime date;
  final AsyncValue<List<AgendaItem>> agendaAsync;
  const _WeekDaySection({required this.date, required this.agendaAsync});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locs = AppLocalizations.of(context)!;
    final today = DateTime.now();
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    final events = agendaAsync.valueOrNull
        ?.where((i) => i.type == 'event')
        .toList() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: isToday ? cs.primaryContainer : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _formatDate(date, locs),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isToday ? cs.onPrimaryContainer : cs.onSurface),
              ),
            ),
          ]),
        ),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 4),
            child: Text(locs.noItems,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          )
        else
          ...events.map((e) => _CompactEventRow(item: e)),
      ],
    );
  }

  String _formatDate(DateTime date, AppLocalizations locs) {
    return locs.dateFormatFull(locs.weekdayShort.split(',')[date.weekday % 7], '${date.month}', '${date.day}');
  }
}

class _CompactEventRow extends StatelessWidget {
  final AgendaItem item;
  const _CompactEventRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = {'meeting': const Color(0xFF3B82F6), 'deadline': const Color(0xFFEF4444), 'social': const Color(0xFF10B981)}[item.eventType ?? ''] ?? cs.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 0, 2),
      child: Row(
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          if (item.time != null) ...[
            Text(DateFormat('HH:mm').format(item.time!.toLocal()),
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
          ],
          Expanded(child: Text(item.title, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

// ── Edit bottom sheet ──────────────────────────────────────────────────────────

class EditEventSheet extends StatefulWidget {
  final AgendaItem? item;
  final Future<void> Function(Map<String, String> fields, String? id) onSave;

  const EditEventSheet({this.item, required this.onSave});

  @override
  State<EditEventSheet> createState() => EditEventSheetState();
}

class EditEventSheetState extends State<EditEventSheet> {
  late TextEditingController _title;
  late TextEditingController _projectKey;
  late TextEditingController _startTime;
  late TextEditingController _endTime;
  late TextEditingController _description;
  String _eventType = 'meeting';
  String _status = ScheduleStatus.scheduled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _title = TextEditingController(text: item?.title ?? '');
    _projectKey = TextEditingController(text: item?.projectKey ?? '');
    _startTime = TextEditingController(
      text: item?.time != null
          ? item!.time!.toLocal().toIso8601String().substring(0, 16)
          : '',
    );
    _endTime = TextEditingController(
      text: item?.endTime != null
          ? item!.endTime!.toLocal().toIso8601String().substring(0, 16)
          : '',
    );
    _eventType = item?.eventType ?? 'meeting';
    _description = TextEditingController(text: item?.description ?? '');
    const validTypes = ['meeting', 'deadline', 'social', 'review', 'other'];
    if (!validTypes.contains(_eventType)) {
      _eventType = 'other';
    }
    _status = item?.status ?? ScheduleStatus.scheduled;
    const validStatuses = ['scheduled', 'in_progress', 'completed', 'cancelled'];
    if (!validStatuses.contains(_status)) {
      _status = ScheduleStatus.scheduled;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _projectKey.dispose();
    _startTime.dispose();
    _endTime.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locs = AppLocalizations.of(context)!;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final isEdit = widget.item != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isEdit ? locs.editSchedule : locs.newSchedule,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: InputDecoration(
                labelText: locs.titleLabel, border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _eventType,
            decoration: InputDecoration(
                labelText: locs.typeLabel, border: OutlineInputBorder()),
            items: [
              DropdownMenuItem(value: 'meeting', child: Text(locs.eventTypeMeeting)),
              DropdownMenuItem(value: 'deadline', child: Text(locs.eventTypeDeadline)),
              DropdownMenuItem(value: 'social', child: Text(locs.eventTypeSocial)),
              DropdownMenuItem(value: 'review', child: Text(locs.eventTypeReview)),
              DropdownMenuItem(value: 'other', child: Text(locs.eventTypeOther)),
            ],
            onChanged: (v) => setState(() => _eventType = v!),
          ),
          if (isEdit) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: InputDecoration(
                  labelText: locs.scheduleStatusLabel, border: OutlineInputBorder()),
              items: [
                DropdownMenuItem(value: ScheduleStatus.scheduled, child: Text(locs.scheduleStatusScheduled)),
                DropdownMenuItem(value: ScheduleStatus.inProgress, child: Text(locs.scheduleStatusInProgress)),
                DropdownMenuItem(value: ScheduleStatus.completed, child: Text(locs.scheduleStatusCompleted)),
                DropdownMenuItem(value: ScheduleStatus.cancelled, child: Text(locs.scheduleStatusCancelled)),
              ],
              onChanged: (v) => setState(() => _status = v!),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startTime,
                  decoration: InputDecoration(
                      labelText: locs.startTimeLabel,
                      border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _endTime,
                  decoration: InputDecoration(
                      labelText: locs.endTimeLabel,
                      border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: locs.descriptionPlaceholder,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _projectKey,
            decoration: InputDecoration(
                labelText: locs.projectKeyPlaceholder,
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Spacer(),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(locs.cancel)),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(isEdit ? locs.save : locs.createLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final isEdit = widget.item != null;
    final fields = <String, String>{
      'title': _title.text.trim(),
      'type': _eventType,
    };
    if (isEdit) {
      fields['status'] = _status;
    }
    if (_description.text.trim().isNotEmpty) {
      fields['description'] = _description.text.trim();
    }
    if (_projectKey.text.trim().isNotEmpty) {
      fields['projectKey'] = _projectKey.text.trim();
    }
    // Convert local datetime to UTC ISO
    if (_startTime.text.trim().isNotEmpty) {
      try {
        final dt = DateTime.parse(_startTime.text.trim());
        fields['startTime'] = dt.toUtc().toIso8601String();
      } catch (_) {}
    }
    if (_endTime.text.trim().isNotEmpty) {
      try {
        final dt = DateTime.parse(_endTime.text.trim());
        fields['endTime'] = dt.toUtc().toIso8601String();
      } catch (_) {}
    }

    await widget.onSave(fields, widget.item?.scheduleItemId);
    if (mounted) Navigator.pop(context);
    setState(() => _saving = false);
  }
}
