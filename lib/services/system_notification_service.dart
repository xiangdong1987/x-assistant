import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';

import '../models/notification_model.dart';

final _logger = Logger(
  printer: PrettyPrinter(methodCount: 0, printEmojis: false),
);

/// System notification service for local push notifications
class SystemNotificationService {
  static final SystemNotificationService _instance =
      SystemNotificationService._internal();
  factory SystemNotificationService() => _instance;
  SystemNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  /// Initialize the notification service
  Future<void> init() async {
    if (_isInitialized) return;

    // Android initialization settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    // Request permissions on iOS/macOS
    await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _isInitialized = true;
    _logger.i('SystemNotificationService initialized');
  }

  /// Handle notification tap
  void _handleNotificationResponse(NotificationResponse response) {
    _logger.i('Notification tapped: ${response.payload}');
    // Can add navigation logic here if needed
  }

  /// Show a notification for task completion
  Future<void> showTaskCompleted(String taskId, String taskTitle) async {
    if (!_isInitialized) {
      _logger.w('SystemNotificationService not initialized');
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'task_completed_channel',
      '任务完成通知',
      channelDescription: '当任务完成时显示的通知',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      category: AndroidNotificationCategory.reminder,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id: taskId.hashCode,
      title: '任务已完成',
      body: '"$taskTitle" 已完成',
      notificationDetails: details,
      payload: taskId,
    );

    _logger.i('Task completed notification shown: $taskTitle');
  }

  /// Show a notification for task failure
  Future<void> showTaskFailed(String taskId, String taskTitle, String error) async {
    if (!_isInitialized) {
      _logger.w('SystemNotificationService not initialized');
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'task_failed_channel',
      '任务失败通知',
      channelDescription: '当任务执行失败时显示的通知',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      category: AndroidNotificationCategory.error,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id: taskId.hashCode,
      title: '任务执行失败',
      body: '"$taskTitle" 执行失败：$error',
      notificationDetails: details,
      payload: taskId,
    );

    _logger.i('Task failed notification shown: $taskTitle');
  }

  /// Show a notification for task progress
  Future<void> showTaskProgress(String taskId, String taskTitle, String progress) async {
    if (!_isInitialized) {
      _logger.w('SystemNotificationService not initialized');
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'task_progress_channel',
      '任务进度通知',
      channelDescription: '当任务进度更新时显示的通知',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
      category: AndroidNotificationCategory.progress,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id: taskId.hashCode,
      title: '任务进度更新',
      body: '"$taskTitle" $progress',
      notificationDetails: details,
      payload: taskId,
    );
  }

  /// Show a system notification
  Future<void> showSystem(String title, String content, {String? payload}) async {
    if (!_isInitialized) {
      _logger.w('SystemNotificationService not initialized');
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'system_channel',
      '系统通知',
      channelDescription: '系统级别的通知',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
      category: AndroidNotificationCategory.system,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id: title.hashCode,
      title: title,
      body: content,
      notificationDetails: details,
      payload: payload,
    );
  }

  /// Cancel a notification
  Future<void> cancel(int id) async {
    if (!_isInitialized) return;
    await _notifications.cancel(id: id);
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    if (!_isInitialized) return;
    await _notifications.cancelAll();
  }

  /// Check if initialized
  bool get isInitialized => _isInitialized;
}

/// Extension on NotificationModel to show system notification
extension NotificationModelExtension on NotificationModel {
  Future<void> showSystemNotification() async {
    final service = SystemNotificationService();
    if (!service.isInitialized) {
      await service.init();
    }

    switch (type) {
      case NotificationType.taskCompleted:
        await service.showTaskCompleted(taskId ?? id, title);
        break;
      case NotificationType.taskFailed:
        await service.showTaskFailed(
          taskId ?? id,
          title,
          content.replaceAll(RegExp(r'^"[^"]*" 执行失败：'), ''),
        );
        break;
      case NotificationType.taskProgress:
        await service.showTaskProgress(taskId ?? id, title, content);
        break;
      case NotificationType.system:
      case NotificationType.message:
        await service.showSystem(title, content, payload: id);
        break;
    }
  }
}
