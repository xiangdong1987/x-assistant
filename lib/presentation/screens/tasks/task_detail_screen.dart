import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/task_model.dart';
import '../../../models/task_enums.dart';
import '../../../providers/task_provider.dart';
import '../../widgets/priority_badge.dart';
import '../../widgets/code_element_builder.dart';

class TaskDetailScreen extends ConsumerStatefulWidget {
  final String taskId;

  const TaskDetailScreen({super.key, required this.taskId});

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  final _feedbackController = TextEditingController();
  FeedbackType? _selectedFeedbackType;
  Timer? _pollingTimer;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      final tasks = ref.read(taskNotifierProvider).valueOrNull ?? [];
      final task = tasks.where((t) => t.id == widget.taskId).firstOrNull;
      if (task != null &&
          (task.status == TaskStatus.inProgress ||
           task.status == TaskStatus.planned ||
           task.status == TaskStatus.confirmed)) {
        ref.read(taskNotifierProvider.notifier).refresh();
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _feedbackController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncTasks = ref.watch(taskNotifierProvider);
    final tasks = asyncTasks.valueOrNull ?? [];
    final task = tasks.where((t) => t.id == widget.taskId).firstOrNull;

    final l10n = AppLocalizations.of(context)!;
    if (asyncTasks.isLoading && tasks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.taskDetail)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (task == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.taskDetail)),
        body: Center(child: Text(l10n.taskNotFound)),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.taskDetail),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.pushNamed('editTask', extra: task.id),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'open_cursor':
                  final api = ref.read(taskApiServiceProvider);
                  if (api != null) {
                    api.openInCursor(task.id).then((success) {
                      if (!context.mounted) return;
                      final l10n = AppLocalizations.of(context)!;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(success ? l10n.openInCursor : l10n.cannotOpenCursor)),
                      );
                    });
                  }
                  break;
                case 'execute_cursor':
                  final apiCursor = ref.read(taskApiServiceProvider);
                  if (apiCursor != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.startingCursorAgent)),
                    );
                    apiCursor.agentStart(task.id, 'cursor').then((result) {
                      if (!context.mounted) return;
                      final ok = result['success'] == true;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok ? '✅ ${l10n.cursorAgentStartedInTmux}' : l10n.startFailedShort),
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }).catchError((e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.startFailed(e))),
                      );
                    });
                  }
                  break;
                case 'execute_ccr':
                  final apiCcr = ref.read(taskApiServiceProvider);
                  if (apiCcr != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.startingCcrAgent)),
                    );
                    apiCcr.agentStart(task.id, 'ccr').then((result) {
                      if (!context.mounted) return;
                      final ok = result['success'] == true;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok ? '✅ ${l10n.ccrAgentStartedInTmux}' : l10n.startFailedShort),
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }).catchError((e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.startFailed(e))),
                      );
                    });
                  }
                  break;
                case 'view_agent':
                  final apiTmux = ref.read(taskApiServiceProvider);
                  if (apiTmux != null) {
                    apiTmux.tmuxFocus(task.id).then((success) {
                      if (!context.mounted) return;
                      final l10nTmux = AppLocalizations.of(context)!;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(success ? l10nTmux.openingIterm2 : l10nTmux.cannotOpenTmux),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }).catchError((e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.loadFailed(e.toString()))),
                      );
                    });
                  }
                  break;
                case 'delete':
                  _confirmDelete(context, ref, task);
                  break;
                case 'cancel':
                  ref.read(taskNotifierProvider.notifier).updateStatus(
                        task.id,
                        TaskStatus.cancelled,
                      );
                  break;
              }
            },
            itemBuilder: (context) => [
              if (task.planPath != null && task.planPath!.isNotEmpty)
                PopupMenuItem(
                  value: 'open_cursor',
                  child: Row(
                    children: [
                      const Icon(Icons.code_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text(l10n.openInCursorLabel),
                    ],
                  ),
                ),
              // planned 或 failed（有 planPath 时可重试执行）
              if ((task.status == TaskStatus.planned || task.status == TaskStatus.failed) &&
                  task.planPath != null &&
                  task.planPath!.isNotEmpty) ...[
                PopupMenuItem(
                  value: 'execute_cursor',
                  child: Row(
                    children: [
                      const Icon(Icons.play_arrow_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text('💻 ${l10n.runWithCursor}'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'execute_ccr',
                  child: Row(
                    children: [
                      const Icon(Icons.smart_toy_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text('🤖 ${l10n.runWithCcr}'),
                    ],
                  ),
                ),
              ],
              if (task.status == TaskStatus.inProgress ||
                  task.status == TaskStatus.confirmed ||
                  task.status == TaskStatus.planned ||
                  task.status == TaskStatus.planning ||
                  task.status == TaskStatus.coding ||
                  task.status == TaskStatus.testing ||
                  task.status == TaskStatus.submitting ||
                  task.status == TaskStatus.failed)
                PopupMenuItem(
                  value: 'view_agent',
                  child: Row(
                    children: [
                      const Icon(Icons.terminal_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text('🖥️ ${l10n.viewAgent}'),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'cancel',
                child: Row(
                  children: [
                    const Icon(Icons.cancel_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text(l10n.cancelTask),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(l10n.delete, style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title and priority
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                const SizedBox(width: 12),
                PriorityBadge(priority: task.priority),
              ],
            ),

            const SizedBox(height: 16),

            // Meta info
            _MetaRow(icon: Icons.source, label: l10n.source, value: task.source.label(l10n)),
            if (task.backend != null)
              _MetaRow(
                icon: Icons.smart_toy,
                label: l10n.preferredAgent,
                value: task.backend == 'cursor' ? l10n.agentCursor : (task.backend == 'claude' ? l10n.agentClaude : l10n.agentCcr),
              ),
            if (task.source == TaskSource.openClaw && task.projectKey != null)
              _MetaRow(
                icon: Icons.vpn_key_outlined,
                label: l10n.projectKey,
                value: task.projectKey!,
              ),
            _MetaRow(
              icon: Icons.calendar_today_outlined,
              label: l10n.createdAt,
              value: _formatDateTime(task.createdAt),
            ),
            if (task.dueAt != null)
              _MetaRow(
                icon: Icons.event_outlined,
                label: l10n.deadline,
                value: _formatDateTime(task.dueAt!),
                valueColor: task.isOverdue ? const Color(0xFFEF4444) : null,
              ),
            if (task.completedAt != null)
              _MetaRow(
                icon: Icons.check_circle_outline,
                label: l10n.completedAt,
                value: _formatDateTime(task.completedAt!),
                valueColor: const Color(0xFF10B981),
              ),

            const SizedBox(height: 20),

            // Status flow
            _StatusSection(task: task, ref: ref),

            const SizedBox(height: 20),

            if (task.planPath != null && task.planPath!.isNotEmpty) ...[
              Text(
                l10n.executionPlan,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withAlpha(80),
                  ),
                ),
                child: FutureBuilder<String?>(
                  future: ref.read(taskApiServiceProvider)?.getTaskPlanText(task.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError || snapshot.data == null) {
                      return Text(
                        l10n.planLoadFailed,
                        style: TextStyle(color: colorScheme.error, height: 1.4),
                      );
                    }
                    return MarkdownBody(
                      data: snapshot.data!,
                      selectable: true,
                      checkboxBuilder: (bool checked) {
                        return Icon(
                          checked ? Icons.check_box : Icons.check_box_outline_blank,
                          color: Theme.of(context).colorScheme.onSurface,
                          size: 18,
                        );
                      },
                      builders: {
                        'code': CodeElementBuilder(context),
                      },
                      styleSheet: MarkdownStyleSheet(
                        p: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
                        h1: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        h2: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        h3: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        code: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              backgroundColor: Colors.transparent,
                            ),
                        codeblockDecoration: const BoxDecoration(
                          color: Colors.transparent,
                        ),
                        blockquoteDecoration: BoxDecoration(
                          color: colorScheme.surfaceVariant.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(4),
                          border: Border(left: BorderSide(color: colorScheme.primary, width: 4)),
                        ),
                        listBullet: TextStyle(color: colorScheme.onSurface),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
            ] else if (task.description != null && task.description!.isNotEmpty) ...[
              Text(
                l10n.description,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withAlpha(80),
                  ),
                ),
                child: MarkdownBody(
                  data: task.description!,
                  selectable: true,
                  checkboxBuilder: (bool checked) {
                    return Icon(
                      checked ? Icons.check_box : Icons.check_box_outline_blank,
                      color: Theme.of(context).colorScheme.onSurface,
                      size: 18,
                    );
                  },
                  builders: {
                    'code': CodeElementBuilder(context),
                  },
                  styleSheet: MarkdownStyleSheet(
                    p: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
                    h1: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    h2: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    h3: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    code: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          backgroundColor: Colors.transparent,
                        ),
                    codeblockDecoration: const BoxDecoration(
                      color: Colors.transparent,
                    ),
                    blockquoteDecoration: BoxDecoration(
                      color: colorScheme.surfaceVariant.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(4),
                      border: Border(left: BorderSide(color: colorScheme.primary, width: 4)),
                    ),
                    listBullet: TextStyle(color: colorScheme.onSurface),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Feedback section
            if (task.status != TaskStatus.cancelled) ...[
              Text(
                l10n.feedback,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),

              if (task.feedback != null || task.feedbackType != null) ...[
                // Show existing feedback
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: task.feedbackType == FeedbackType.done
                        ? const Color(0xFF10B981).withAlpha(15)
                        : const Color(0xFFF59E0B).withAlpha(15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: task.feedbackType == FeedbackType.done
                          ? const Color(0xFF10B981).withAlpha(60)
                          : const Color(0xFFF59E0B).withAlpha(60),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            task.feedbackType == FeedbackType.done
                                ? Icons.check_circle
                                : Icons.warning_amber_rounded,
                            size: 18,
                            color: task.feedbackType == FeedbackType.done
                                ? const Color(0xFF10B981)
                                : const Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            task.feedbackType?.label(l10n) ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: task.feedbackType == FeedbackType.done
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ),
                      if (task.feedback != null &&
                          task.feedback!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(task.feedback!),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Submit feedback form (for active tasks)
              if (task.status != TaskStatus.completed &&
                  task.status != TaskStatus.pending) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withAlpha(80),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.submitFeedback,
                        style:
                            Theme.of(context).textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _FeedbackOption(
                              icon: Icons.check_circle,
                              label: l10n.completed,
                              color: const Color(0xFF10B981),
                              isSelected:
                                  _selectedFeedbackType == FeedbackType.done,
                              onTap: () => setState(() =>
                                  _selectedFeedbackType = FeedbackType.done),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _FeedbackOption(
                              icon: Icons.warning_amber_rounded,
                              label: l10n.hasIssue,
                              color: const Color(0xFFF59E0B),
                              isSelected: _selectedFeedbackType ==
                                  FeedbackType.hasIssue,
                              onTap: () => setState(() =>
                                  _selectedFeedbackType =
                                      FeedbackType.hasIssue),
                            ),
                          ),
                        ],
                      ),
                      if (_selectedFeedbackType != null) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _feedbackController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: _selectedFeedbackType ==
                                    FeedbackType.hasIssue
                                ? l10n.describeIssue
                                : l10n.addNoteOptional,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () {
                              ref
                                  .read(taskNotifierProvider.notifier)
                                  .submitFeedback(
                                    task.id,
                                    _selectedFeedbackType!,
                                    _feedbackController.text.isEmpty
                                        ? null
                                        : _feedbackController.text,
                                  );
                              _feedbackController.clear();
                              setState(() => _selectedFeedbackType = null);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(l10n.feedbackSubmitted)),
                              );
                            },
                            child: Text(l10n.submitFeedback),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, TaskModel task) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteTask),
        content: Text(l10n.deleteTaskConfirmMessage(task.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              ref.read(taskNotifierProvider.notifier).deleteTask(task.id);
              Navigator.pop(ctx);
              context.pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: valueColor ?? Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// 阶段显示文案（与后端 plan/code/test/done 一致）
String _phaseLabel(AppLocalizations l10n, String? phase) {
  if (phase == null || phase.isEmpty) return l10n.pinDash;
  switch (phase) {
    case 'plan': return l10n.phasePlan;
    case 'code': return l10n.phaseCode;
    case 'test': return l10n.phaseTest;
    case 'done': return l10n.phaseDone;
    default: return phase;
  }
}

class _StatusSection extends StatefulWidget {
  final TaskModel task;
  final WidgetRef ref;

  const _StatusSection({required this.task, required this.ref});

  @override
  State<_StatusSection> createState() => _StatusSectionState();
}

class _StatusSectionState extends State<_StatusSection> {
  late String _selectedBackend;

  @override
  void initState() {
    super.initState();
    _selectedBackend = widget.task.backend ?? 'cursor';
  }

  @override
  void didUpdateWidget(covariant _StatusSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.backend != widget.task.backend && widget.task.backend != null) {
      _selectedBackend = widget.task.backend!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final ref = widget.ref;
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(80)),
      ),
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l10n.statusLabel}: ${task.status.label(l10n)}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (task.phase != null && task.phase!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${l10n.phaseLabel}: ${_phaseLabel(l10n, task.phase)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopupMenuButton<String>(
                    tooltip: l10n.changePhase,
                    icon: Icon(
                      Icons.flag_outlined,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    onSelected: (newPhase) {
                      ref.read(taskNotifierProvider.notifier).updateTask(
                            task.copyWith(phase: newPhase),
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.phaseUpdated(_phaseLabel(l10n, newPhase)))),
                        );
                      }
                    },
                    itemBuilder: (context) => ['plan', 'code', 'test', 'done'].map((phase) {
                      return PopupMenuItem<String>(
                        value: phase,
                        child: Row(
                          children: [
                            Icon(
                              task.phase == phase
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              size: 16,
                              color: task.phase == phase
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _phaseLabel(l10n, phase),
                              style: TextStyle(
                                color: task.phase == phase
                                    ? colorScheme.primary
                                    : null,
                                fontWeight: task.phase == phase
                                    ? FontWeight.bold
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  PopupMenuButton<TaskStatus>(
                    tooltip: l10n.changeStatus,
                    icon: Icon(
                      Icons.edit_note,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    onSelected: (newStatus) {
                      ref.read(taskNotifierProvider.notifier).updateStatus(
                            task.id,
                            newStatus,
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.statusUpdated(newStatus.label(l10n)))),
                        );
                      }
                    },
                    itemBuilder: (context) => TaskStatus.values.map((status) {
                      return PopupMenuItem<TaskStatus>(
                        value: status,
                        child: Row(
                          children: [
                            Icon(
                              status == task.status
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              size: 16,
                              color: status == task.status
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              status.label(l10n),
                              style: TextStyle(
                                color: status == task.status
                                    ? colorScheme.primary
                                    : null,
                                fontWeight: status == task.status
                                    ? FontWeight.bold
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Backend selector for next operation (if plan exists and not completed)
          if ((task.status == TaskStatus.inProgress || task.status == TaskStatus.planned || task.status == TaskStatus.planning || task.status == TaskStatus.coding || task.status == TaskStatus.testing || task.status == TaskStatus.submitting || task.status == TaskStatus.failed) && task.planPath != null && task.planPath!.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  l10n.executionUses,
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedBackend,
                    isDense: true,
                    style: TextStyle(fontSize: 13, color: colorScheme.primary, fontWeight: FontWeight.bold),
                    items: [
                      DropdownMenuItem(value: 'cursor', child: Text(l10n.agentCursor)),
                      DropdownMenuItem(value: 'ccr', child: Text(l10n.agentCcr)),
                      DropdownMenuItem(value: 'claude', child: Text(l10n.agentClaude)),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedBackend = val);
                        // Optional: save preference to task
                        ref.read(taskNotifierProvider.notifier).updateTask(task.copyWith(backend: val));
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          // Action buttons based on current status
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _getActionButtons(context, task, ref, _selectedBackend),
          ),
        ],
      ),
    );
  }

  List<Widget> _getActionButtons(BuildContext context, TaskModel task, WidgetRef ref, String selectedBackend) {
    final l10n = AppLocalizations.of(context)!;
    final buttons = <Widget>[];

    switch (task.status) {
      case TaskStatus.completed:
        break;
      case TaskStatus.pending:
        final cmd = 'node skills/software-dev/openclaw-integration.js generate-plan ${task.id}';
        buttons.add(
          FilledButton.tonalIcon(
            onPressed: () => _copyCommand(context, cmd),
            icon: const Icon(Icons.copy, size: 18),
            label: Text(l10n.planOnly),
          ),
        );
        buttons.add(
          OutlinedButton.icon(
            onPressed: () {
              ref.read(taskNotifierProvider.notifier).updateStatus(
                    task.id,
                    TaskStatus.confirmed,
                  );
            },
            icon: const Icon(Icons.check, size: 18),
            label: Text(l10n.confirmTaskSkipPlan),
          ),
        );
        break;
      case TaskStatus.confirmed:
        buttons.add(
          FilledButton.icon(
            onPressed: () {
              ref.read(taskNotifierProvider.notifier).updateStatus(
                    task.id,
                    TaskStatus.inProgress,
                  );
              _startAgent(context, task, ref, selectedBackend, phase: 'code');
            },
            icon: const Icon(Icons.play_arrow, size: 18),
            label: Text(l10n.startExecution),
          ),
        );
        break;
      case TaskStatus.inProgress:
        if (task.planPath != null && task.planPath!.isNotEmpty) {
             if (task.phase == 'test') {
               buttons.add(
                 FilledButton.icon(
                   style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)), // Green color for submit
                   onPressed: () => _phaseAdvanceAndStartAgent(context, task, ref, selectedBackend, 'done'),
                   icon: const Icon(Icons.publish, size: 18),
                   label: Text(l10n.submitLabel),
                 ),
               );
             } else {
               buttons.add(
                 FilledButton.tonalIcon(
                   onPressed: () => _phaseAdvanceAndStartAgent(context, task, ref, selectedBackend, 'test'),
                   icon: const Icon(Icons.science, size: 18),
                   label: Text(l10n.runTestLabel),
                 ),
               );
             }
        }
        buttons.add(
          FilledButton.icon(
            onPressed: () {
              ref.read(taskNotifierProvider.notifier).updateStatus(
                    task.id,
                    TaskStatus.completed,
                  );
            },
            icon: const Icon(Icons.check_circle, size: 18),
            label: Text(l10n.markComplete),
          ),
        );
        break;
      case TaskStatus.testing:
        if (task.planPath != null && task.planPath!.isNotEmpty) {
          buttons.add(
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              onPressed: () => _phaseAdvanceAndStartAgent(context, task, ref, selectedBackend, 'done'),
              icon: const Icon(Icons.publish, size: 18),
              label: Text(l10n.submitLabel),
            ),
          );
          buttons.add(
            FilledButton.tonalIcon(
              onPressed: () => _phaseAdvanceAndStartAgent(context, task, ref, selectedBackend, 'test'),
              icon: const Icon(Icons.science, size: 18),
              label: Text(l10n.runTestLabel),
            ),
          );
        }
        buttons.add(
          FilledButton.icon(
            onPressed: () {
              ref.read(taskNotifierProvider.notifier).updateStatus(task.id, TaskStatus.completed);
            },
            icon: const Icon(Icons.check_circle, size: 18),
            label: Text(l10n.markComplete),
          ),
        );
        break;
      case TaskStatus.submitting:
        if (task.planPath != null && task.planPath!.isNotEmpty) {
          buttons.add(
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              onPressed: () => _phaseAdvanceAndStartAgent(context, task, ref, selectedBackend, 'done'),
              icon: const Icon(Icons.publish, size: 18),
              label: Text(l10n.submitLabel),
            ),
          );
        }
        buttons.add(
          FilledButton.icon(
            onPressed: () {
              ref.read(taskNotifierProvider.notifier).updateStatus(task.id, TaskStatus.completed);
            },
            icon: const Icon(Icons.check_circle, size: 18),
            label: Text(l10n.markComplete),
          ),
        );
        break;
      case TaskStatus.planning:
      case TaskStatus.coding:
        buttons.add(
          FilledButton.icon(
            onPressed: () {
              ref.read(taskNotifierProvider.notifier).updateStatus(task.id, TaskStatus.completed);
            },
            icon: const Icon(Icons.check_circle, size: 18),
            label: Text(l10n.markComplete),
          ),
        );
        break;
      case TaskStatus.planned:
        // 手动版本按钮 (只提供复制命令)
        if (task.planPath != null && task.planPath!.isNotEmpty) {
             buttons.add(
               FilledButton.icon(
                 style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                 onPressed: () => _startAgent(context, task, ref, 'ccr', phase: 'code'),
                 icon: const Icon(Icons.rocket_launch, size: 18),
                 label: Text('🤖 ${l10n.ccrExecute}'),
               ),
             );
             buttons.add(
               FilledButton.tonalIcon(
                 onPressed: () => _startAgent(context, task, ref, 'cursor', phase: 'code'),
                 icon: const Icon(Icons.code, size: 18),
                 label: Text('💻 ${l10n.cursorExecute}'),
               ),
             );
        }
        break;
      case TaskStatus.failed:
        // 失败后可重试
        if (task.planPath != null && task.planPath!.isNotEmpty) {
          buttons.add(
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
              onPressed: () => _startAgent(context, task, ref, 'ccr', phase: task.phase),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text('🤖 ${l10n.retryCcr}'),
            ),
          );
          buttons.add(
            FilledButton.tonalIcon(
              onPressed: () => _startAgent(context, task, ref, 'cursor', phase: task.phase),
              icon: const Icon(Icons.refresh_outlined, size: 18),
              label: Text('💻 ${l10n.retryCursor}'),
            ),
          );
        }
        break;
      default:
        break;
    }

    // 查看 Agent 按钮：阶段进行中时显示
    if (task.status == TaskStatus.inProgress ||
        task.status == TaskStatus.coding ||
        task.status == TaskStatus.testing ||
        task.status == TaskStatus.submitting ||
        task.status == TaskStatus.planning) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: () {
            final api = ref.read(taskApiServiceProvider);
            if (api != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.openingIterm2),
                  duration: const Duration(seconds: 2),
                ),
              );
              api.tmuxFocus(task.id).then((ok) {
                if (!context.mounted) return;
                if (!ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.cannotOpenTmux),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }).catchError((_) {});
            }
          },
          icon: const Icon(Icons.terminal, size: 18),
          label: Text(l10n.openInCursorLabel),
        ),
      );
    }

    return buttons;
  }

  void _copyCommand(BuildContext context, String command) {
    final l10n = AppLocalizations.of(context)!;
    Clipboard.setData(ClipboardData(text: command));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.commandCopied(command)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _startAgent(BuildContext context, TaskModel task, WidgetRef ref, String backend, {String? phase}) {
    final l10n = AppLocalizations.of(context)!;
    final api = ref.read(taskApiServiceProvider);
    if (api != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.startingAgent(backend.toUpperCase()))),
      );
      api.agentStart(task.id, backend, phase: phase).then((result) {
        if (!context.mounted) return;
        final ok = result['success'] == true;
        final l10nSnack = AppLocalizations.of(context)!;
        if (ok) {
          if (phase != 'done') {
            ref.read(taskNotifierProvider.notifier).updateStatus(task.id, TaskStatus.inProgress);
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? l10n.openInCursor : l10nSnack.startFailed('')),
            duration: const Duration(seconds: 4),
          ),
        );
      }).catchError((e) {
        if (!context.mounted) return;
        final l10nErr = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10nErr.startFailed(e.toString()))),
        );
      });
    }
  }

  void _generatePlan(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final task = widget.task;
    final ref = widget.ref;
    final api = ref.read(taskApiServiceProvider);
    if (api != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.generatingPlan)),
      );
      api.generatePlan(task.id).then((result) {
        if (!context.mounted) return;
        final ok = result['success'] == true;
        final l10nSnack = AppLocalizations.of(context)!;
        if (ok) {
           ref.read(taskNotifierProvider.notifier).refresh();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? l10n.feedbackSubmitted : l10nSnack.generateFailed(''))),
        );
      }).catchError((e) {
        if (!context.mounted) return;
        final l10nErr = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10nErr.generateFailed(e.toString()))),
        );
      });
    }
  }


  void _phaseAdvance(BuildContext context, String phase) {
    final l10n = AppLocalizations.of(context)!;
    final task = widget.task;
    final ref = widget.ref;
    final api = ref.read(taskApiServiceProvider);
    if (api != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.executingPhase(phase))),
      );
      api.phaseAdvance(task.id, phase: phase).then((result) {
        if (!context.mounted) return;
        final ok = result['success'] == true;
        final l10nSnack = AppLocalizations.of(context)!;
        if (ok) {
           ref.read(taskNotifierProvider.notifier).refresh();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? l10n.feedbackSubmitted : l10nSnack.phaseExecutionFailed(''))),
        );
      }).catchError((e) {
        if (!context.mounted) return;
        final l10nErr = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10nErr.phaseExecutionFailed(e.toString()))),
        );
      });
    }
  }

  void _phaseAdvanceAndStartAgent(BuildContext context, TaskModel task, WidgetRef ref, String backend, String targetPhase) {
    final l10n = AppLocalizations.of(context)!;
    final String currentPhaseForApi = targetPhase == 'done' ? 'test' : 'code';

    final api = ref.read(taskApiServiceProvider);
    if (api != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.executingPhase(targetPhase))),
      );
      api.phaseAdvance(task.id, phase: currentPhaseForApi).then((result) {
        if (!context.mounted) return;
        final ok = result['success'] == true;
        if (ok) {
           ref.read(taskNotifierProvider.notifier).refresh();
           if (targetPhase == 'done') {
             ref.read(taskNotifierProvider.notifier).updateStatus(task.id, TaskStatus.completed);
           }
           _startAgent(context, task, ref, backend, phase: targetPhase);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.phaseSwitchFailed)),
          );
        }
      }).catchError((e) {
        if (!context.mounted) return;
        final l10nErr = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10nErr.phaseSwitchFailed)),
        );
      });
    }
  }
}

class _FeedbackOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _FeedbackOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(20) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withAlpha(60),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.grey,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
