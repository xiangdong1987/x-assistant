import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'models/task_model.dart';
import 'models/task_enums.dart';
import 'models/chat_history_model.dart';
import 'models/notification_model.dart';
import 'services/task_storage.dart';
import 'services/chat_history_storage.dart';
import 'providers/task_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize locale data for intl (date/number formatting for zh and en)
  await initializeDateFormatting('zh_CN', null);
  await initializeDateFormatting('en', null);

  // Initialize Hive for local storage
  await Hive.initFlutter();

  // Register Hive adapters
  Hive.registerAdapter(TaskModelAdapter());
  Hive.registerAdapter(TaskStatusAdapter());
  Hive.registerAdapter(TaskPriorityAdapter());
  Hive.registerAdapter(TaskSourceAdapter());
  Hive.registerAdapter(FeedbackTypeAdapter());
  Hive.registerAdapter(ChatHistoryItemAdapter());
  Hive.registerAdapter(ChatMessageAdapter());
  Hive.registerAdapter(NotificationTypeAdapter());
  Hive.registerAdapter(NotificationModelAdapter());

  // Open the tasks box
  await Hive.openBox<TaskModel>('tasks');
  await Hive.openBox<ChatHistoryItem>('chat_history');
  await Hive.openBox<NotificationModel>('notifications');

  runApp(
    ProviderScope(
      overrides: [
        // Pre-initialize taskStorage with the already-opened box
        taskStorageProvider.overrideWithValue(TaskStorage()..initSync()),
        chatHistoryStorageProvider.overrideWithValue(ChatHistoryStorage()..initSync()),
      ],
      child: const XAssistantApp(),
    ),
  );
}
