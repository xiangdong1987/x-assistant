import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/task_model.dart';
import '../../../models/task_enums.dart';
import '../../../models/project_model.dart';
import '../../../providers/task_provider.dart';
import '../../../providers/project_provider.dart';

class AddTaskScreen extends ConsumerStatefulWidget {
  final String? editTaskId;

  const AddTaskScreen({super.key, this.editTaskId});

  @override
  ConsumerState<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends ConsumerState<AddTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  TaskPriority _priority = TaskPriority.p2;
  TaskSource _source = TaskSource.manual;
  String _backend = 'cursor'; // default backend
  String? _selectedProjectKey;
  DateTime? _dueDate;
  TimeOfDay? _dueTime;

  bool get isEditing => widget.editTaskId != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      // Load existing task data
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final tasks = ref.read(taskNotifierProvider).valueOrNull ?? [];
        final task =
            tasks.where((t) => t.id == widget.editTaskId).firstOrNull;
        if (task != null) {
          _titleController.text = task.title;
          _descriptionController.text = task.description ?? '';
          setState(() {
            _priority = task.priority;
            _source = task.source;
            _backend = task.backend ?? 'cursor';
            _selectedProjectKey = task.projectKey;
            _dueDate = task.dueAt;
            if (task.dueAt != null) {
              _dueTime = TimeOfDay.fromDateTime(task.dueAt!);
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? l10n.editTask : l10n.addTask),
        actions: [
          TextButton(
            onPressed: _saveTask,
            child: Text(
              l10n.save,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Title
            TextFormField(
              controller: _titleController,
              autofocus: !isEditing,
              decoration: InputDecoration(
                labelText: l10n.taskTitle,
                hintText: l10n.taskTitleHint,
                prefixIcon: const Icon(Icons.title),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l10n.taskTitleRequired;
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.descriptionOptional,
                hintText: l10n.descriptionHint,
                prefixIcon: const Icon(Icons.description_outlined),
                alignLabelWithHint: true,
              ),
            ),

            const SizedBox(height: 24),

            // Project selection
            Text(
              l10n.project,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            _buildProjectSelector(context),

            const SizedBox(height: 24),

            // Priority selection
            Text(
              l10n.priority,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: TaskPriority.values.map((p) {
                final isSelected = _priority == p;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _priority = p),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _priorityColor(p).withAlpha(25)
                            : colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? _priorityColor(p)
                              : colorScheme.outlineVariant.withAlpha(80),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _priorityColor(p),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            p.label(l10n),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isSelected
                                  ? _priorityColor(p)
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            if (isEditing) ...[
              const SizedBox(height: 24),

              // Source selection (edit mode only)
              Text(
                l10n.source,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<TaskSource>(
                segments: TaskSource.values
                    .map((s) => ButtonSegment(
                          value: s,
                          label: Text(s.label(l10n)),
                          icon: Icon(_sourceIcon(s), size: 18),
                        ))
                    .toList(),
                selected: {_source},
                onSelectionChanged: (selected) {
                  setState(() => _source = selected.first);
                },
              ),
            ],

            const SizedBox(height: 24),

            // Agent Backend selection
            Text(
              l10n.agentOptional,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'cursor',
                  label: Text(l10n.agentCursor),
                  icon: const Icon(Icons.code, size: 18),
                ),
                ButtonSegment(
                  value: 'ccr',
                  label: Text(l10n.agentCcr),
                  icon: const Icon(Icons.rocket_launch, size: 18),
                ),
                ButtonSegment(
                  value: 'claude',
                  label: Text(l10n.agentClaude),
                  icon: const Icon(Icons.smart_toy_outlined, size: 18),
                ),
              ],
              selected: {_backend},
              onSelectionChanged: (selected) {
                setState(() => _backend = selected.first);
              },
            ),

            if (isEditing) ...[
              const SizedBox(height: 24),

              // Due date (edit mode only)
              Text(
                l10n.deadlineOptional,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        _dueDate != null
                            ? '${_dueDate!.month}/${_dueDate!.day}'
                            : l10n.selectDate,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _dueDate != null ? _pickTime : null,
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text(
                        _dueTime != null
                            ? '${_dueTime!.hour.toString().padLeft(2, '0')}:${_dueTime!.minute.toString().padLeft(2, '0')}'
                            : l10n.selectTime,
                      ),
                    ),
                  ),
                  if (_dueDate != null)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        setState(() {
                          _dueDate = null;
                          _dueTime = null;
                        });
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProjectSelector(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final projectsAsync = ref.watch(projectsProvider);
    return projectsAsync.when(
      data: (List<ProjectModel> projects) {
        if (projects.isEmpty) {
          return TextFormField(
            initialValue: _selectedProjectKey,
            decoration: InputDecoration(
              labelText: l10n.projectKeyManualHint,
              hintText: l10n.projectKeyExample,
              prefixIcon: const Icon(Icons.folder_outlined),
            ),
            onChanged: (v) => setState(() => _selectedProjectKey = v.trim().isEmpty ? null : v.trim()),
          );
        }
        return DropdownButtonFormField<String>(
          value: _selectedProjectKey != null && projects.any((p) => p.key == _selectedProjectKey)
              ? _selectedProjectKey
              : null,
          decoration: InputDecoration(
            labelText: l10n.selectTaskProject,
            prefixIcon: const Icon(Icons.folder_outlined),
          ),
          hint: Text(l10n.selectTaskProject),
          items: [
            DropdownMenuItem<String>(
              value: null,
              child: Text(l10n.noProjectSelected),
            ),
            ...projects.map((p) => DropdownMenuItem<String>(
                  value: p.key,
                  child: Text('${p.name} (${p.key})', overflow: TextOverflow.ellipsis, maxLines: 1),
                )),
          ],
          onChanged: (v) => setState(() => _selectedProjectKey = v),
        );
      },
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
      error: (_, __) => TextFormField(
        initialValue: _selectedProjectKey,
        decoration: InputDecoration(
          labelText: l10n.projectKeyFallbackHint,
          hintText: l10n.projectKeyExample,
          prefixIcon: const Icon(Icons.folder_outlined),
        ),
        onChanged: (v) => setState(() => _selectedProjectKey = v.trim().isEmpty ? null : v.trim()),
      ),
    );
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => _dueDate = date);
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _dueTime ?? TimeOfDay.now(),
    );
    if (time != null) {
      setState(() => _dueTime = time);
    }
  }

  void _saveTask() {
    if (!_formKey.currentState!.validate()) return;

    DateTime? dueAt;
    if (_dueDate != null) {
      dueAt = DateTime(
        _dueDate!.year,
        _dueDate!.month,
        _dueDate!.day,
        _dueTime?.hour ?? 23,
        _dueTime?.minute ?? 59,
      );
    }

    final notifier = ref.read(taskNotifierProvider.notifier);

    if (isEditing) {
      final tasks = ref.read(taskNotifierProvider).valueOrNull ?? [];
      final existingTask =
          tasks.where((t) => t.id == widget.editTaskId).firstOrNull;
      if (existingTask != null) {
        final updated = existingTask.copyWith(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          priority: _priority,
          source: _source,
          dueAt: dueAt,
          backend: _backend,
          projectKey: _selectedProjectKey,
        );
        notifier.updateTask(updated);
      }
    } else {
      final task = TaskModel(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        priority: _priority,
        source: _source,
        dueAt: dueAt,
        backend: _backend,
        projectKey: _selectedProjectKey,
        status: TaskStatus.confirmed, // 默认 confirmed 以触发计划生成
      );
      notifier.addTask(task);
    }

    context.pop();
  }

  Color _priorityColor(TaskPriority p) {
    switch (p) {
      case TaskPriority.p0:
        return const Color(0xFFEF4444);
      case TaskPriority.p1:
        return const Color(0xFFF59E0B);
      case TaskPriority.p2:
        return const Color(0xFF3B82F6);
      case TaskPriority.p3:
        return const Color(0xFF9CA3AF);
    }
  }

  IconData _sourceIcon(TaskSource s) {
    switch (s) {
      case TaskSource.manual:
        return Icons.person;
      case TaskSource.openClaw:
        return Icons.smart_toy;
      case TaskSource.cursor:
        return Icons.code;
      case TaskSource.skill:
        return Icons.auto_awesome;
    }
  }
}
