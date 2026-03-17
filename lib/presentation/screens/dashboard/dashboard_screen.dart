import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/task_provider.dart';
import '../../../providers/agenda_provider.dart';
import '../../../models/schedule_model.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DateTime _focusedMonth = DateTime.now();

  void _refreshMonth() {
    ref.invalidate(agendaMonthProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context);
    final dateLocale = locale.languageCode == 'zh' ? 'zh_CN' : 'en';
    final datePattern = dateLocale == 'zh_CN' ? 'M月d日 EEEE' : 'M/d EEEE';
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final stats = ref.watch(taskStatsProvider);
    final today = DateTime.now();

    final monthAsync = ref.watch(agendaMonthProvider(
        (year: _focusedMonth.year, month: _focusedMonth.month)));
    final eventsByDay = monthAsync.valueOrNull ?? {};

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _greeting(today.hour, l10n),
                              style: tt.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              DateFormat(datePattern, dateLocale).format(today),
                              style: tt.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Task status chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _Chip(
                          label: l10n.filterAll,
                          count: stats['total'] ?? 0,
                          color: cs.primary,
                          onTap: () {
                            ref.read(taskFilterProvider.notifier).state =
                                TaskFilter.all;
                            context.goNamed('tasks');
                          },
                        ),
                        const SizedBox(width: 6),
                        _Chip(
                          label: l10n.dashboardPending,
                          count: stats['pending'] ?? 0,
                          color: const Color(0xFFF59E0B),
                          onTap: () {
                            ref.read(taskFilterProvider.notifier).state =
                                TaskFilter.pending;
                            context.goNamed('tasks');
                          },
                        ),
                        const SizedBox(width: 6),
                        _Chip(
                          label: l10n.dashboardInProgress,
                          count: stats['inProgress'] ?? 0,
                          color: const Color(0xFF8B5CF6),
                          onTap: () {
                            ref.read(taskFilterProvider.notifier).state =
                                TaskFilter.inProgress;
                            context.goNamed('tasks');
                          },
                        ),
                        const SizedBox(width: 6),
                        _Chip(
                          label: l10n.filterCompleted,
                          count: stats['completed'] ?? 0,
                          color: const Color(0xFF10B981),
                          onTap: () {
                            ref.read(taskFilterProvider.notifier).state =
                                TaskFilter.completed;
                            context.goNamed('tasks');
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Calendar (fills the rest of the screen) ──────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: _InlineCalendar(
                  focusedMonth: _focusedMonth,
                  eventsByDay: eventsByDay,
                  today: today,
                  dateLocale: dateLocale,
                  onMonthChanged: (d) => setState(() => _focusedMonth = d),
                  onRefresh: _refreshMonth,
                  onScheduleTap: () => context.goNamed('schedule'),
                  onDayTap: (date) {
                    ref.read(selectedScheduleDateProvider.notifier).state =
                        date;
                    context.goNamed('schedule');
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _greeting(int hour, AppLocalizations l10n) {
    if (hour < 6) return l10n.greetingNight;
    if (hour < 12) return l10n.greetingMorning;
    if (hour < 14) return l10n.greetingNoon;
    if (hour < 18) return l10n.greetingAfternoon;
    return l10n.greetingEvening;
  }
}

// ── Calendar with inline events ──────────────────────────────────────────────

class _InlineCalendar extends StatelessWidget {
  final DateTime focusedMonth;
  final Map<int, List<AgendaItem>> eventsByDay;
  final DateTime today;
  final String dateLocale;
  final ValueChanged<DateTime> onMonthChanged;
  final VoidCallback? onRefresh;
  final VoidCallback onScheduleTap;
  final ValueChanged<DateTime>? onDayTap;

  const _InlineCalendar({
    required this.focusedMonth,
    required this.eventsByDay,
    required this.today,
    required this.dateLocale,
    required this.onMonthChanged,
    this.onRefresh,
    required this.onScheduleTap,
    this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final firstDay = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final weekdayOffset = firstDay.weekday % 7; // 0=Sunday
    final daysInMonth =
        DateTime(focusedMonth.year, focusedMonth.month + 1, 0).day;
    final rows = ((weekdayOffset + daysInMonth) / 7).ceil();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Month navigation header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _IconTap(
                icon: Icons.chevron_left,
                onTap: () => onMonthChanged(
                    DateTime(focusedMonth.year, focusedMonth.month - 1)),
              ),
              GestureDetector(
                onTap: () => onMonthChanged(DateTime.now()),
                child: Text(
                  dateLocale == 'zh_CN'
                      ? DateFormat('yyyy年M月', dateLocale).format(focusedMonth)
                      : DateFormat('MMM yyyy', dateLocale).format(focusedMonth),
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: onScheduleTap,
                    child: Text(
                      l10n.scheduleArrow,
                      style: TextStyle(fontSize: 11, color: cs.primary),
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (onRefresh != null)
                    _IconTap(
                      icon: Icons.refresh,
                      onTap: onRefresh!,
                    ),
                  _IconTap(
                    icon: Icons.chevron_right,
                    onTap: () => onMonthChanged(
                        DateTime(focusedMonth.year, focusedMonth.month + 1)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Weekday labels
          Row(
            children: [
              l10n.weekdaySun,
              l10n.weekdayMon,
              l10n.weekdayTue,
              l10n.weekdayWed,
              l10n.weekdayThu,
              l10n.weekdayFri,
              l10n.weekdaySat,
            ]
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d.toString(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),

          // Day grid
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final cellW = constraints.maxWidth / 7;
                final cellH = constraints.maxHeight / rows;

                return Wrap(
                  children: List.generate(rows * 7, (index) {
                    final day = index - weekdayOffset + 1;

                    // Empty cell
                    if (day < 1 || day > daysInMonth) {
                      return SizedBox(
                        key: ValueKey('cal-empty-$index'),
                        width: cellW,
                        height: cellH,
                      );
                    }

                    final date =
                        DateTime(focusedMonth.year, focusedMonth.month, day);
                    final isToday = date.year == today.year &&
                        date.month == today.month &&
                        date.day == today.day;
                    final events = eventsByDay[day] ?? [];

                    Color bg = Colors.transparent;
                    Color fg = cs.onSurface;
                    if (isToday) {
                      bg = cs.primaryContainer;
                      fg = cs.onPrimaryContainer;
                    }

                    return GestureDetector(
                      key: ValueKey('cal-$day-${focusedMonth.month}-${focusedMonth.year}'),
                      onTap: () => onDayTap?.call(date),
                      child: SizedBox(
                        width: cellW,
                        height: cellH,
                        child: Container(
                          margin: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.fromLTRB(4, 3, 4, 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Day number
                              Text(
                                '$day',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isToday
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: fg,
                                ),
                              ),
                              // Events (up to 2)
                              ...events.take(2).map((e) {
                                final c = _typeColor(e.eventType);
                                return Container(
                                  margin: const EdgeInsets.only(top: 1),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 3, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: c.withAlpha(40),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 4,
                                        height: 4,
                                        decoration: BoxDecoration(
                                            color: c, shape: BoxShape.circle),
                                      ),
                                      const SizedBox(width: 2),
                                      Expanded(
                                        child: Text(
                                          e.time != null
                                              ? '${DateFormat('HH:mm').format(e.time!.toLocal())} ${e.title}'
                                              : e.title,
                                          style: TextStyle(
                                              fontSize: 9, color: c),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              // +N more
                              if (events.length > 2)
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Text(
                                    '+${events.length - 2}',
                                    style: TextStyle(
                                        fontSize: 8,
                                        color: cs.onSurfaceVariant),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ); // GestureDetector
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _typeColor(String? type) {
    switch (type) {
      case 'meeting':
        return const Color(0xFF3B82F6);
      case 'deadline':
        return const Color(0xFFEF4444);
      case 'social':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF8B5CF6);
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _IconTap extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconTap({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;
  const _Chip(
      {required this.label,
      required this.count,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withAlpha(22),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withAlpha(60)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text('$count',
                  style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 2),
              Text(label, style: TextStyle(fontSize: 10, color: color)),
            ],
          ),
        ),
      );
}
