import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task_model.dart';
import '../models/task_enums.dart';
import '../services/task_storage.dart';
import '../services/task_api_service.dart';
import '../services/connection_service.dart';
import '../services/websocket_service.dart';
import '../services/notification_service.dart';
import '../providers/notification_provider.dart';

// Storage provider (singleton)
final taskStorageProvider = Provider<TaskStorage>((ref) {
  return TaskStorage();
});

// Connection info (loads from storage on first access)
final connectionInfoProvider = FutureProvider<ConnectionInfo?>((ref) async {
  final service = ref.watch(connectionServiceProvider);
  return service.loadSavedConnection();
});

// TaskApiService when connected
final taskApiServiceProvider = Provider<TaskApiService?>((ref) {
  final conn = ref.watch(connectionInfoProvider).valueOrNull;
  if (conn == null) return null;
  return TaskApiService(baseUrl: conn.httpUrl, token: conn.token);
});

// Task list notifier - uses API when connected, else Hive
class TaskNotifier extends StateNotifier<AsyncValue<List<TaskModel>>> {
  final TaskStorage _storage;
  final TaskApiService? _api;
  bool _disposed = false;

  TaskNotifier(this._storage, this._api)
      : super(AsyncValue.data(_storage.getAll())) {
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _load() async {
    if (_api != null) {
      try {
        final tasks = await _api!.getTasks();
        if (!_disposed) state = AsyncValue.data(tasks);
      } catch (e) {
        // API 失败时回退到本地数据，避免一直 loading
        if (!_disposed) state = AsyncValue.data(_storage.getAll());
      }
    } else {
      if (!_disposed) state = AsyncValue.data(_storage.getAll());
    }
  }

  void refresh() {
    state = const AsyncValue.loading();
    _load();
  }

  /// Background refresh without loading state (for optimistic updates)
  void _backgroundRefresh() async {
    if (_api == null) return;
    try {
      final tasks = await _api!.getTasks();
      if (!_disposed) state = AsyncValue.data(tasks);
    } catch (_) {
      // Silent - local state is authoritative after optimistic update
    }
  }

  List<TaskModel> get _currentList =>
      state.valueOrNull ?? _storage.getAll();

  TaskModel? _getById(String id) {
    if (state.hasValue) {
      try {
        return state.value!.firstWhere((t) => t.id == id);
      } catch (_) {}
    }
    return _storage.getById(id);
  }

  Future<void> addTask(TaskModel task) async {
    if (_api != null) {
      // Optimistic: add to local list immediately
      final previousState = state;
      final list = List<TaskModel>.from(_currentList)..add(task);
      state = AsyncValue.data(list);
      try {
        await _api!.createTask(
          title: task.title,
          description: task.description,
          priority: task.priority,
          source: task.source,
          dueAt: task.dueAt,
          projectKey: task.projectKey,
          backend: task.backend,
        );
        _backgroundRefresh();
      } catch (e) {
        state = previousState;
        rethrow;
      }
    } else {
      await _storage.save(task);
      state = AsyncValue.data(_storage.getAll());
    }
  }

  Future<void> updateTask(TaskModel task) async {
    if (_api != null) {
      final previousState = state;
      final list = List<TaskModel>.from(_currentList);
      final idx = list.indexWhere((t) => t.id == task.id);
      if (idx >= 0) list[idx] = task;
      state = AsyncValue.data(list);
      try {
        await _api!.updateTask(task);
        _backgroundRefresh();
      } catch (e) {
        state = previousState;
        rethrow;
      }
    } else {
      await _storage.save(task);
      state = AsyncValue.data(_storage.getAll());
    }
  }

  Future<void> deleteTask(String id) async {
    if (_api != null) {
      final previousState = state;
      final list = List<TaskModel>.from(_currentList)
        ..removeWhere((t) => t.id == id);
      state = AsyncValue.data(list);
      try {
        await _api!.deleteTask(id);
        _backgroundRefresh();
      } catch (e) {
        state = previousState;
        rethrow;
      }
    } else {
      await _storage.delete(id);
      state = AsyncValue.data(_storage.getAll());
    }
  }

  Future<void> updateStatus(String id, TaskStatus newStatus) async {
    if (_api != null) {
      final previousState = state;
      final list = List<TaskModel>.from(_currentList);
      final idx = list.indexWhere((t) => t.id == id);
      if (idx >= 0) {
        list[idx] = list[idx].copyWith(
          status: newStatus,
          completedAt: newStatus == TaskStatus.completed ? DateTime.now() : null,
        );
        state = AsyncValue.data(list);
      }
      try {
        await _api!.updateStatus(id, newStatus);
        _backgroundRefresh();
      } catch (e) {
        state = previousState;
        rethrow;
      }
    } else {
      final task = _storage.getById(id);
      if (task != null) {
        task.status = newStatus;
        task.updatedAt = DateTime.now();
        if (newStatus == TaskStatus.completed) {
          task.completedAt = DateTime.now();
        }
        await _storage.save(task);
        state = AsyncValue.data(_storage.getAll());
      }
    }
  }

  Future<void> submitFeedback(
    String id,
    FeedbackType type,
    String? feedbackText,
  ) async {
    if (_api != null) {
      final previousState = state;
      final list = List<TaskModel>.from(_currentList);
      final idx = list.indexWhere((t) => t.id == id);
      if (idx >= 0) {
        list[idx] = list[idx].copyWith(
          feedbackType: type,
          feedback: feedbackText,
          status: type == FeedbackType.done
              ? TaskStatus.completed
              : TaskStatus.planned,
        );
        state = AsyncValue.data(list);
      }
      try {
        await _api!.submitFeedback(id, type, feedbackText);
        _backgroundRefresh();
      } catch (e) {
        state = previousState;
        rethrow;
      }
    } else {
      final task = _storage.getById(id);
      if (task != null) {
        task.feedbackType = type;
        task.feedback = feedbackText;
        task.updatedAt = DateTime.now();
        if (type == FeedbackType.done) {
          task.status = TaskStatus.completed;
          task.completedAt = DateTime.now();
        } else {
          task.status = TaskStatus.planned;
        }
        await _storage.save(task);
        state = AsyncValue.data(_storage.getAll());
      }
    }
  }

  /// Upsert task from OpenClaw (called when receiving openclaw_task via WebSocket)
  Future<void> upsertFromOpenClaw(Map<String, dynamic> taskData) async {
    final id = taskData['id'] as String?;
    final action = taskData['_action'] as String?; // create, update, complete, error

    if (id == null || id.isEmpty) return;

    if (_api != null) {
      // Optimistic update: merge WebSocket payload into state so UI reflects
      // backend state immediately, then refresh in background to reconcile.
      try {
        final taskModel = _api!.taskFromJson(taskData);
        final list = List<TaskModel>.from(_currentList);
        final idx = list.indexWhere((t) => t.id == id);
        if (idx >= 0) {
          list[idx] = taskModel;
        } else {
          list.add(taskModel);
        }
        if (!_disposed) state = AsyncValue.data(list);
      } catch (_) {
        // payload shape mismatch; fall back to full refresh
      }
      _backgroundRefresh();
      return;
    }

    final title = taskData['title'] as String? ?? '';
    final description = taskData['description'] as String? ?? '';
    final priority = TaskApiService.parsePriority(taskData['priority'] as String?);
    final statusStr = taskData['status'] as String? ?? 'pending';
    final completedItems = taskData['completedItems'] as int?;
    final totalItems = taskData['totalItems'] as int?;
    final projectKey = taskData['projectKey'] as String?;
    final planPath = taskData['planPath'] as String?;

    // Local mode: create or update in Hive
    var task = _storage.getById(id);
    if (task == null) {
      task = TaskModel(
        id: id,
        title: title,
        description: description.isEmpty ? null : description,
        priority: priority,
        status: TaskApiService.parseStatus(statusStr),
        source: TaskSource.openClaw,
        completedItems: completedItems ?? 0,
        totalItems: totalItems ?? 0,
        projectKey: projectKey,
        planPath: planPath,
      );
    } else {
      task = task.copyWith(
        title: title,
        description: description.isEmpty ? null : description,
        priority: priority,
        status: TaskApiService.parseStatus(statusStr),
        completedItems: completedItems ?? task.completedItems,
        totalItems: totalItems ?? task.totalItems,
        projectKey: projectKey ?? task.projectKey,
        planPath: planPath ?? task.planPath,
      );
    }
    if (action == 'complete') {
      task = task.copyWith(
        status: TaskStatus.completed,
        completedAt: DateTime.now(),
      );
    } else if (action == 'error') {
      task = task.copyWith(
        status: TaskStatus.planned,
        feedback: taskData['feedback'] as String?,
        feedbackType: FeedbackType.hasIssue,
      );
    }
    await _storage.save(task);
    state = AsyncValue.data(_storage.getAll());
  }
}

final taskNotifierProvider =
    StateNotifierProvider<TaskNotifier, AsyncValue<List<TaskModel>>>((ref) {
  final storage = ref.watch(taskStorageProvider);
  final api = ref.watch(taskApiServiceProvider);
  return TaskNotifier(storage, api);
});

/// Global listener for WebSocket task push messages (openclaw_task).
/// This ensures task list and progress bars refresh in real time, regardless of
/// which screen is currently visible.
/// Also creates notifications when tasks complete or fail.
final taskWebSocketListenerProvider = Provider<void>((ref) {
  final ws = ref.watch(webSocketServiceProvider);

  final sub = ws.messages.listen((message) {
    final type = message['type'] as String?;
    if (type == 'openclaw_task') {
      final action = message['action'] as String?;
      final taskPayload = message['task'];
      if (taskPayload is! Map<String, dynamic>) return;

      final taskData = Map<String, dynamic>.from(taskPayload);
      if (action != null) {
        taskData['_action'] = action;
      }

      // Create notification for task completion or failure
      if (action == 'complete' || action == 'error') {
        final taskId = taskData['id'] as String?;
        final taskTitle = taskData['title'] as String? ?? '未知任务';

        if (taskId != null) {
          final notificationService = ref.read(notificationServiceProvider);
          final notification = action == 'complete'
              ? NotificationService.fromTaskCompleted(taskId, taskTitle)
              : NotificationService.fromTaskFailed(
                  taskId,
                  taskTitle,
                  taskData['feedback'] as String? ?? '执行失败',
                );

          // Add notification (this will also update UI via notifyListeners)
          notificationService.add(notification);
        }
      }

      ref.read(taskNotifierProvider.notifier).upsertFromOpenClaw(taskData);
      return;
    }

    // 新增：当收到 OpenClaw 的 tick / 状态事件时，也主动刷新任务列表，
    // 确保 phaseWatcher / plan 同步等后台更新能及时反映到界面。
    if (type == 'openclaw_status' || type == 'tick' || type == 'openclaw_event') {
      ref.read(taskNotifierProvider.notifier).refresh();
    }
  });

  ref.onDispose(() {
    sub.cancel();
  });
});

// Filter provider
enum TaskFilter { all, pending, inProgress, completed }

final taskFilterProvider = StateProvider<TaskFilter>((ref) => TaskFilter.all);

final filteredTasksProvider = Provider<List<TaskModel>>((ref) {
  final asyncTasks = ref.watch(taskNotifierProvider);
  final filter = ref.watch(taskFilterProvider);

  final tasks = asyncTasks.valueOrNull ?? [];
  switch (filter) {
    case TaskFilter.all:
      // 全部：仅排除已完成，包含已取消、失败等，保证状态完整可见
      return tasks
          .where((t) => t.status != TaskStatus.completed)
          .toList();
    case TaskFilter.pending:
      return tasks
          .where((t) =>
              t.status == TaskStatus.pending ||
              t.status == TaskStatus.confirmed)
          .toList();
    case TaskFilter.inProgress:
      // 执行中：含进行中各阶段 + 已计划待执行 + 执行失败可重试
      return tasks.where((t) =>
          t.status == TaskStatus.inProgress ||
          t.status == TaskStatus.planning ||
          t.status == TaskStatus.coding ||
          t.status == TaskStatus.testing ||
          t.status == TaskStatus.submitting ||
          t.status == TaskStatus.planned ||
          t.status == TaskStatus.failed).toList();
    case TaskFilter.completed:
      return tasks.where((t) => t.status == TaskStatus.completed).toList();
  }
});

// Stats provider
final taskStatsProvider = Provider<Map<String, int>>((ref) {
  final asyncTasks = ref.watch(taskNotifierProvider);
  final tasks = asyncTasks.valueOrNull ?? [];
  return {
    'total': tasks.length,
    'pending': tasks
        .where((t) =>
            t.status == TaskStatus.pending || t.status == TaskStatus.confirmed)
        .length,
    'inProgress': tasks
        .where((t) =>
            t.status == TaskStatus.inProgress ||
            t.status == TaskStatus.planning ||
            t.status == TaskStatus.coding ||
            t.status == TaskStatus.testing ||
            t.status == TaskStatus.submitting ||
            t.status == TaskStatus.planned ||
            t.status == TaskStatus.failed)
        .length,
    'completed': tasks.where((t) => t.status == TaskStatus.completed).length,
  };
});

// Today's tasks
final todayTasksProvider = Provider<List<TaskModel>>((ref) {
  final asyncTasks = ref.watch(taskNotifierProvider);
  final tasks = asyncTasks.valueOrNull ?? [];
  final now = DateTime.now();
  return tasks.where((t) {
    if (t.status == TaskStatus.completed || t.status == TaskStatus.cancelled) {
      return false;
    }
    if (t.dueAt != null) {
      return t.dueAt!.year == now.year &&
          t.dueAt!.month == now.month &&
          t.dueAt!.day == now.day;
    }
    return t.createdAt.year == now.year &&
        t.createdAt.month == now.month &&
        t.createdAt.day == now.day;
  }).toList();
});
