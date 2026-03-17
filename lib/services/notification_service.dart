import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/notification_model.dart';
import 'system_notification_service.dart';

class NotificationService extends ChangeNotifier {
  static const String _boxName = 'notifications';
  Box<NotificationModel>? _box;
  List<NotificationModel> _notifications = [];
  final SystemNotificationService _systemNotificationService = SystemNotificationService();
  bool _systemNotificationEnabled = true;

  /// Initialize asynchronously
  Future<void> init() async {
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(NotificationTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(13)) {
      Hive.registerAdapter(NotificationModelAdapter());
    }

    _box = await Hive.openBox<NotificationModel>(_boxName);
    _loadNotifications();

    // Initialize system notification service
    await _systemNotificationService.init();
  }

  /// Initialize synchronously when box is already opened
  void initSync() {
    _box = Hive.box<NotificationModel>(_boxName);
    _loadNotifications();
  }

  Box<NotificationModel> get box {
    if (_box == null) {
      throw StateError('NotificationService not initialized. Call init() first.');
    }
    return _box!;
  }

  void _loadNotifications() {
    _notifications = box.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  /// Get all notifications
  List<NotificationModel> get notifications => List.unmodifiable(_notifications);

  /// Get unread notifications count
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// Get notification by ID
  NotificationModel? getById(String id) {
    return box.get(id);
  }

  /// Add a new notification
  Future<void> add(NotificationModel notification) async {
    await box.put(notification.id, notification);
    _loadNotifications();

    // Show system notification if enabled
    if (_systemNotificationEnabled && _systemNotificationService.isInitialized) {
      await notification.showSystemNotification();
    }
  }

  /// Mark notification as read
  Future<void> markAsRead(String id) async {
    final notification = box.get(id);
    if (notification != null) {
      final updated = notification.copyWith(isRead: true);
      await box.put(id, updated);
      _loadNotifications();
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    for (final notification in _notifications) {
      if (!notification.isRead) {
        final updated = notification.copyWith(isRead: true);
        await box.put(notification.id, updated);
      }
    }
    _loadNotifications();
  }

  /// Delete a notification
  Future<void> delete(String id) async {
    await box.delete(id);
    _loadNotifications();
  }

  /// Clear all notifications
  Future<void> clearAll() async {
    await box.clear();
    _loadNotifications();
  }

  /// Clear all read notifications
  Future<void> clearRead() async {
    final readNotifications = _notifications.where((n) => n.isRead).toList();
    for (final notification in readNotifications) {
      await box.delete(notification.id);
    }
    _loadNotifications();
  }

  /// Enable or disable system notifications
  void setSystemNotificationEnabled(bool enabled) {
    _systemNotificationEnabled = enabled;
  }

  /// Check if system notifications are enabled
  bool get isSystemNotificationEnabled => _systemNotificationEnabled;

  /// Request notification permissions (iOS/macOS)
  Future<bool> requestPermissions() async {
    if (!_systemNotificationService.isInitialized) {
      await _systemNotificationService.init();
    }
    // Permissions are requested during init on iOS/macOS
    return true;
  }

  /// Create notification from task completion
  static NotificationModel fromTaskCompleted(String taskId, String taskTitle) {
    return NotificationModel(
      id: 'task_${taskId}_${DateTime.now().millisecondsSinceEpoch}',
      title: '任务已完成',
      content: '"$taskTitle" 已完成',
      type: NotificationType.taskCompleted,
      createdAt: DateTime.now(),
      taskId: taskId,
    );
  }

  /// Create notification from task failed
  static NotificationModel fromTaskFailed(String taskId, String taskTitle, String error) {
    return NotificationModel(
      id: 'task_${taskId}_${DateTime.now().millisecondsSinceEpoch}',
      title: '任务执行失败',
      content: '"$taskTitle" 执行失败：$error',
      type: NotificationType.taskFailed,
      createdAt: DateTime.now(),
      taskId: taskId,
    );
  }

  /// Create notification from task progress
  static NotificationModel fromTaskProgress(String taskId, String taskTitle, String progress) {
    return NotificationModel(
      id: 'task_${taskId}_${DateTime.now().millisecondsSinceEpoch}',
      title: '任务进度更新',
      content: '"$taskTitle" $progress',
      type: NotificationType.taskProgress,
      createdAt: DateTime.now(),
      taskId: taskId,
    );
  }

  /// Create system notification
  static NotificationModel createSystem(String title, String content) {
    return NotificationModel(
      id: 'system_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      content: content,
      type: NotificationType.system,
      createdAt: DateTime.now(),
    );
  }
}
