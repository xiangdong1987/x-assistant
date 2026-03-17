import 'package:hive_flutter/hive_flutter.dart';

import '../models/task_model.dart';
import '../models/task_enums.dart';

class TaskStorage {
  static const String _boxName = 'tasks';
  Box<TaskModel>? _box;

  /// Initialize asynchronously (registers adapters and opens box)
  Future<void> init() async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(TaskModelAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(TaskStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(TaskPriorityAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(TaskSourceAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(FeedbackTypeAdapter());
    }

    _box = await Hive.openBox<TaskModel>(_boxName);
  }

  /// Initialize synchronously when box is already opened (called from main.dart)
  void initSync() {
    _box = Hive.box<TaskModel>(_boxName);
  }

  Box<TaskModel> get box {
    if (_box == null) {
      throw StateError('TaskStorage not initialized. Call init() first.');
    }
    return _box!;
  }

  List<TaskModel> getAll() {
    return box.values.toList()
      ..sort((a, b) {
        // Sort by priority first, then by creation date
        final priorityCompare = a.priority.index.compareTo(b.priority.index);
        if (priorityCompare != 0) return priorityCompare;
        return b.createdAt.compareTo(a.createdAt);
      });
  }

  List<TaskModel> getByStatus(TaskStatus status) {
    return getAll().where((t) => t.status == status).toList();
  }

  List<TaskModel> getActive() {
    return getAll()
        .where((t) =>
            t.status != TaskStatus.completed &&
            t.status != TaskStatus.cancelled)
        .toList();
  }

  List<TaskModel> getTodayTasks() {
    final now = DateTime.now();
    return getAll().where((t) {
      if (t.status == TaskStatus.completed || t.status == TaskStatus.cancelled) {
        return false;
      }
      if (t.dueAt != null) {
        return t.dueAt!.year == now.year &&
            t.dueAt!.month == now.month &&
            t.dueAt!.day == now.day;
      }
      // Also include tasks created today that have no due date
      return t.createdAt.year == now.year &&
          t.createdAt.month == now.month &&
          t.createdAt.day == now.day;
    }).toList();
  }

  Future<void> save(TaskModel task) async {
    await box.put(task.id, task);
  }

  Future<void> delete(String id) async {
    await box.delete(id);
  }

  TaskModel? getById(String id) {
    return box.get(id);
  }

  Map<TaskStatus, int> getStatusCounts() {
    final counts = <TaskStatus, int>{};
    for (final status in TaskStatus.values) {
      counts[status] = 0;
    }
    for (final task in box.values) {
      counts[task.status] = (counts[task.status] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> clear() async {
    await box.clear();
  }
}
