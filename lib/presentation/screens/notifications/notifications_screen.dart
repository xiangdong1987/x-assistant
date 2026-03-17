import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/notification_provider.dart';
import '../../../models/notification_model.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final service = ref.watch(notificationServiceProvider);
    final notifications = service.notifications;
    final unreadCount = service.unreadCount;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.messages),
            if (unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.done_all),
              onPressed: () => _showMarkAllReadDialog(context, ref),
              tooltip: l10n.markAllRead,
            ),
          if (notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _showClearDialog(context, ref),
              tooltip: l10n.clearMessages,
            ),
        ],
      ),
      body: notifications.isEmpty
          ? _buildEmptyState(context)
          : ListView.builder(
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return _NotificationListTile(
                  notification: notification,
                  onTap: () => _handleNotificationTap(context, ref, notification),
                  onDelete: () => service.delete(notification.id),
                );
              },
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 64,
            color: colorScheme.onSurfaceVariant.withAlpha(100),
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.noNotifications,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.notificationsHint,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant.withAlpha(150),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _handleNotificationTap(
    BuildContext context,
    WidgetRef ref,
    NotificationModel notification,
  ) async {
    // Mark as read
    final service = ref.read(notificationServiceProvider);
    await service.markAsRead(notification.id);

    // Navigate to task if has taskId
    if (notification.taskId != null) {
      if (!context.mounted) return;
      context.pushNamed('taskDetail', extra: notification.taskId);
    }
  }

  void _showMarkAllReadDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final service = ref.read(notificationServiceProvider);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.markAllRead),
        content: Text(l10n.markAllReadConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              await service.markAllAsRead();
              if (context.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }

  void _showClearDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final service = ref.read(notificationServiceProvider);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.clearMessages),
        content: Text(l10n.clearMessagesConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              await service.clearAll();
              if (context.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: Text(l10n.clear, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _NotificationListTile extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NotificationListTile({
    required this.notification,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRead = notification.isRead;

    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await _showDeleteConfirm(context);
      },
      onDismissed: (direction) => onDelete(),
      child: Container(
        decoration: BoxDecoration(
          color: isRead ? null : colorScheme.primaryContainer.withAlpha(50),
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant,
              width: 0.5,
            ),
          ),
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: _getIconBackgroundColor(colorScheme, notification.type),
            child: Icon(
              notification.icon,
              color: _getIconColor(colorScheme, notification.type),
            ),
          ),
          title: Text(
            notification.title,
            style: TextStyle(
              fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                notification.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                _formatTimestamp(context, notification.createdAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          trailing: isRead
              ? null
              : Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
          isThreeLine: true,
          onTap: onTap,
        ),
      ),
    );
  }

  Color _getIconBackgroundColor(ColorScheme colorScheme, NotificationType type) {
    switch (type) {
      case NotificationType.taskCompleted:
        return colorScheme.primaryContainer;
      case NotificationType.taskFailed:
        return colorScheme.errorContainer;
      case NotificationType.taskProgress:
        return colorScheme.tertiaryContainer;
      case NotificationType.system:
        return colorScheme.tertiaryContainer;
      case NotificationType.message:
        return colorScheme.primaryContainer;
    }
  }

  Color _getIconColor(ColorScheme colorScheme, NotificationType type) {
    switch (type) {
      case NotificationType.taskCompleted:
        return colorScheme.onPrimaryContainer;
      case NotificationType.taskFailed:
        return colorScheme.onErrorContainer;
      case NotificationType.taskProgress:
        return colorScheme.onTertiaryContainer;
      case NotificationType.system:
        return colorScheme.onTertiaryContainer;
      case NotificationType.message:
        return colorScheme.onPrimaryContainer;
    }
  }

  String _formatTimestamp(BuildContext context, DateTime timestamp) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) {
      return l10n.justNow;
    } else if (diff.inHours < 1) {
      return l10n.minutesAgo(diff.inMinutes);
    } else if (diff.inDays < 1) {
      return l10n.hoursAgo(diff.inHours);
    } else if (diff.inDays < 7) {
      return l10n.daysAgo(diff.inDays);
    } else {
      return '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
    }
  }

  Future<bool> _showDeleteConfirm(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.deleteMessage),
            content: Text(l10n.deleteMessageConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;
  }
}
