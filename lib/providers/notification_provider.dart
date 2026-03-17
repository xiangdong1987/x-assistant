import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/notification_service.dart';
import '../models/notification_model.dart';

/// Notification service provider
final notificationServiceProvider = ChangeNotifierProvider<NotificationService>((ref) {
  final service = NotificationService();
  service.initSync();
  return service;
});

/// Unread notifications count provider
final unreadCountProvider = Provider<int>((ref) {
  final service = ref.watch(notificationServiceProvider);
  return service.unreadCount;
});

/// Unread notifications list provider
final unreadNotificationsProvider = Provider<List<NotificationModel>>((ref) {
  final service = ref.watch(notificationServiceProvider);
  return service.notifications.where((n) => !n.isRead).toList();
});
