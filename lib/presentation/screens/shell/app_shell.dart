import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/connection_refresh_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../providers/task_provider.dart';
import '../../../services/websocket_service.dart';
import '../../../services/notification_service.dart';

class AppShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StreamSubscription? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _setupWebSocketListener();
  }

  void _setupWebSocketListener() {
    final wsService = ref.read(webSocketServiceProvider);

    _messageSubscription = wsService.messages.listen((message) {
      _handleWebSocketMessage(message);
    });
  }

  void _handleWebSocketMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;
    final payload = message['payload'] as Map<String, dynamic>?;

    if (type == 'task_update' || type == 'task') {
      _handleTaskUpdate(payload);
    }
  }

  void _handleTaskUpdate(Map<String, dynamic>? payload) {
    if (payload == null) return;

    try {
      final taskApiService = ref.read(taskApiServiceProvider);
      if (taskApiService == null) return;

      final task = taskApiService.taskFromJson(payload);
      final notificationService = ref.read(notificationServiceProvider);

      // Check if task is completed
      if (task.status.toString() == 'TaskStatus.completed') {
        final notification = NotificationService.fromTaskCompleted(
          task.id,
          task.title,
        );
        notificationService.add(notification);
      } else if (task.status.toString() == 'TaskStatus.failed') {
        final fallback = mounted ? AppLocalizations.of(context)!.unknownError : 'Unknown error';
        final notification = NotificationService.fromTaskFailed(
          task.id,
          task.title,
          task.feedback ?? fallback,
        );
        notificationService.add(notification);
      }
    } catch (e) {
      debugPrint('Failed to handle task update: $e');
    }
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 监听连接状态，连接成功时自动刷新技能和项目
    setupConnectionRefresh(ref, onRefreshed: (msg) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    });
    // 触发 connectionStatusProvider 的监听
    ref.watch(connectionStatusProvider);

    final unreadCount = ref.watch(unreadCountProvider);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final navigationShell = widget.navigationShell;

    return Scaffold(
      body: navigationShell,
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.pushNamed('agent'),
        backgroundColor: colorScheme.primaryContainer,
        child: const Icon(Icons.smart_toy),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: colorScheme.primaryContainer,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.checklist_outlined),
            selectedIcon: const Icon(Icons.checklist),
            label: l10n.navTasks,
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_today_outlined),
            selectedIcon: const Icon(Icons.calendar_today),
            label: l10n.navSchedule,
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
              child: Icon(Icons.notifications_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
              child: Icon(Icons.notifications),
            ),
            label: l10n.navMessages,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}
