import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:xassistant/models/task_enums.dart';
import 'package:xassistant/models/task_model.dart';
import 'package:xassistant/providers/task_provider.dart';
import 'package:xassistant/services/task_storage.dart';

void main() {
  group('TaskFilter and taskStatsProvider (任务列表页面状态)', () {
    late List<TaskModel> allTasks;

    setUp(() {
      allTasks = [
        TaskModel(title: 't1', status: TaskStatus.pending),
        TaskModel(title: 't2', status: TaskStatus.confirmed),
        TaskModel(title: 't3', status: TaskStatus.planned),
        TaskModel(title: 't4', status: TaskStatus.planning),
        TaskModel(title: 't5', status: TaskStatus.coding),
        TaskModel(title: 't6', status: TaskStatus.testing),
        TaskModel(title: 't7', status: TaskStatus.submitting),
        TaskModel(title: 't8', status: TaskStatus.inProgress),
        TaskModel(title: 't9', status: TaskStatus.failed),
        TaskModel(title: 't10', status: TaskStatus.completed),
        TaskModel(title: 't11', status: TaskStatus.cancelled),
      ];
    });

    test('全部：仅排除已完成，包含已取消、失败等', () {
      final container = ProviderContainer(
        overrides: [
          taskNotifierProvider.overrideWith((ref) => _FakeTaskNotifier(allTasks)),
        ],
      );
      addTearDown(container.dispose);

      container.read(taskFilterProvider.notifier).state = TaskFilter.all;
      final filtered = container.read(filteredTasksProvider);
      expect(filtered.length, 10);
      expect(filtered.any((t) => t.status == TaskStatus.completed), false);
      expect(filtered.any((t) => t.status == TaskStatus.cancelled), true);
      expect(filtered.any((t) => t.status == TaskStatus.failed), true);
    });

    test('执行中：含 inProgress/planning/coding/testing/submitting + planned + failed', () {
      final container = ProviderContainer(
        overrides: [
          taskNotifierProvider.overrideWith((ref) => _FakeTaskNotifier(allTasks)),
        ],
      );
      addTearDown(container.dispose);

      container.read(taskFilterProvider.notifier).state = TaskFilter.inProgress;
      final filtered = container.read(filteredTasksProvider);
      const inProgressStatuses = [
        TaskStatus.inProgress,
        TaskStatus.planning,
        TaskStatus.coding,
        TaskStatus.testing,
        TaskStatus.submitting,
        TaskStatus.planned,
        TaskStatus.failed,
      ];
      expect(filtered.length, 7);
      for (final t in filtered) {
        expect(inProgressStatuses.contains(t.status), true);
      }
    });

    test('taskStatsProvider 执行中数量与筛选一致，含 planned、failed', () {
      final container = ProviderContainer(
        overrides: [
          taskNotifierProvider.overrideWith((ref) => _FakeTaskNotifier(allTasks)),
        ],
      );
      addTearDown(container.dispose);

      final stats = container.read(taskStatsProvider);
      expect(stats['inProgress'], 7);
      expect(stats['pending'], 2);
      expect(stats['completed'], 1);
      expect(stats['total'], 11);
    });
  });

  group('TaskModel source 默认行为', () {
    test('新建任务未显式设置来源时，默认来源为 manual', () {
      final task = TaskModel(title: 'new task');
      expect(task.source, TaskSource.manual);
    });

    test('显式设置来源为其他值时，保存后的来源等于用户选择', () {
      final task = TaskModel(
        title: 'from cursor',
        source: TaskSource.cursor,
      );
      expect(task.source, TaskSource.cursor);
    });

    test('copyWith 显式修改来源时，结果来源等于新值', () {
      final original = TaskModel(title: 'original');
      final updated = original.copyWith(source: TaskSource.skill);
      expect(original.source, TaskSource.manual);
      expect(updated.source, TaskSource.skill);
    });
  });
}

class _FakeTaskStorage extends TaskStorage {
  final List<TaskModel> _tasks;
  _FakeTaskStorage(this._tasks);

  @override
  List<TaskModel> getAll() => _tasks;

  @override
  void initSync() {}

  @override
  Box<TaskModel> get box => throw UnimplementedError();
}

class _FakeTaskNotifier extends TaskNotifier {
  _FakeTaskNotifier(List<TaskModel> tasks)
      : super(_FakeTaskStorage(tasks), null);
}
