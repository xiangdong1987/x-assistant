import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/task_provider.dart';
import '../../../models/task_enums.dart';
import '../../widgets/task_card.dart';

class TaskListScreen extends ConsumerWidget {
  const TaskListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final filter = ref.watch(taskFilterProvider);
    final tasks = ref.watch(filteredTasksProvider);
    final asyncTasks = ref.watch(taskNotifierProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.taskList),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.pushNamed('addTask'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.pushNamed('settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: TaskFilter.values.map((f) {
                final isSelected = filter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(_filterLabel(f, l10n)),
                    selected: isSelected,
                    onSelected: (_) {
                      ref.read(taskFilterProvider.notifier).state = f;
                    },
                    selectedColor: colorScheme.primaryContainer,
                    showCheckmark: false,
                  ),
                );
              }).toList(),
            ),
          ),

          // Task list
          Expanded(
            child: asyncTasks.isLoading && tasks.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () async {
                      ref.read(taskNotifierProvider.notifier).refresh();
                    },
                    child: tasks.isEmpty
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height - 200,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 56,
                              color: colorScheme.onSurfaceVariant.withAlpha(100),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _emptyMessage(filter, l10n),
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return TaskCard(
                        task: task,
                        onTap: () => context.pushNamed(
                          'taskDetail',
                          extra: task.id,
                        ),
                        onComplete: () {
                          ref
                              .read(taskNotifierProvider.notifier)
                              .updateStatus(task.id, TaskStatus.completed);
                        },
                        onDelete: () {
                          ref
                              .read(taskNotifierProvider.notifier)
                              .deleteTask(task.id);
                        },
                      );
                    },
                  ),
                ),
          ),
        ],
      ),
    );
  }

  String _filterLabel(TaskFilter filter, AppLocalizations l10n) {
    switch (filter) {
      case TaskFilter.all:
        return l10n.filterAll;
      case TaskFilter.pending:
        return l10n.filterPending;
      case TaskFilter.inProgress:
        return l10n.filterInProgress;
      case TaskFilter.completed:
        return l10n.filterCompleted;
    }
  }

  String _emptyMessage(TaskFilter filter, AppLocalizations l10n) {
    switch (filter) {
      case TaskFilter.all:
        return l10n.emptyTasksAll;
      case TaskFilter.pending:
        return l10n.emptyTasksPending;
      case TaskFilter.inProgress:
        return l10n.emptyTasksInProgress;
      case TaskFilter.completed:
        return l10n.emptyTasksCompleted;
    }
  }
}
