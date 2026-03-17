import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

part 'notification_model.g.dart';

@HiveType(typeId: 12)
enum NotificationType {
  @HiveField(0) taskCompleted,
  @HiveField(1) taskFailed,
  @HiveField(2) taskProgress,
  @HiveField(3) system,
  @HiveField(4) message,
}

@HiveType(typeId: 13)
class NotificationModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String content;

  @HiveField(3)
  final NotificationType type;

  @HiveField(4)
  final DateTime createdAt;

  @HiveField(5)
  bool isRead;

  @HiveField(6)
  String? taskId;

  @HiveField(7)
  String? actionUrl;

  NotificationModel({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    required this.createdAt,
    this.isRead = false,
    this.taskId,
    this.actionUrl,
  });

  NotificationModel copyWith({
    String? title,
    String? content,
    bool? isRead,
    String? taskId,
    String? actionUrl,
  }) {
    return NotificationModel(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      type: type,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      taskId: taskId ?? this.taskId,
      actionUrl: actionUrl ?? this.actionUrl,
    );
  }

  /// Get icon for notification type
  IconData get icon {
    switch (type) {
      case NotificationType.taskCompleted:
        return Icons.check_circle;
      case NotificationType.taskFailed:
        return Icons.error;
      case NotificationType.taskProgress:
        return Icons.trending_up;
      case NotificationType.system:
        return Icons.settings;
      case NotificationType.message:
        return Icons.message;
    }
  }

  /// Get color key for notification type
  String get colorKey {
    switch (type) {
      case NotificationType.taskCompleted:
        return 'success';
      case NotificationType.taskFailed:
        return 'error';
      case NotificationType.taskProgress:
        return 'info';
      case NotificationType.system:
        return 'warning';
      case NotificationType.message:
        return 'primary';
    }
  }
}
