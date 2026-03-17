import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/schedule_model.dart';
import 'skill_provider.dart';

/// When the user taps a calendar day on the home screen, this is set
/// so AgendaScreen can scroll to that date automatically.
final selectedScheduleDateProvider = StateProvider<DateTime?>((ref) => null);

/// Fetches the agenda for a specific date (cached for the session).
final agendaProvider = FutureProvider.autoDispose
    .family<List<AgendaItem>, ({DateTime from, DateTime to})>((ref, range) async {
  // Keep result alive so switching tabs doesn't re-fetch
  ref.keepAlive();

  final api = ref.watch(skillApiServiceProvider);
  if (api == null) {
    debugPrint('[AgendaProvider] not connected');
    return [];
  }

  final fromStr = range.from.toIso8601String().split('T')[0];
  final toStr = range.to.toIso8601String().split('T')[0];
  debugPrint('[AgendaProvider] fetch from=$fromStr to=$toStr');

  try {
    final raw = await api.getAgenda(fromStr, toStr);
    debugPrint('[AgendaProvider] got ${raw.length} items');
    return raw.map((e) => AgendaItem.fromJson(e as Map<String, dynamic>)).toList();
  } catch (e, stack) {
    debugPrint('[AgendaProvider] ERROR: $e\n$stack');
    return [];
  }
});

/// Fetches events for a whole month (cached for the session).
/// Returns Map<dayNumber, events> so calendar cells can show titles.
final agendaMonthProvider = FutureProvider.autoDispose
    .family<Map<int, List<AgendaItem>>, ({int year, int month})>((ref, ym) async {
  ref.keepAlive();

  final api = ref.watch(skillApiServiceProvider);
  if (api == null) return {};

  final from = DateTime(ym.year, ym.month, 1);
  final to   = DateTime(ym.year, ym.month + 1, 0);
  final fromStr = from.toIso8601String().split('T')[0];
  final toStr   = to.toIso8601String().split('T')[0];

  try {
    final raw = await api.getAgenda(fromStr, toStr);
    final map = <int, List<AgendaItem>>{};
    for (final e in raw) {
      final item = AgendaItem.fromJson(e as Map<String, dynamic>);
      if (item.time != null && item.type == 'event' &&
          item.status != ScheduleStatus.completed) {
        final day = item.time!.toLocal().day;
        map.putIfAbsent(day, () => []).add(item);
      }
    }
    return map;
  } catch (_) {
    return {};
  }
});
