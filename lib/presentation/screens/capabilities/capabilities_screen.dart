import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/capability_model.dart';
import '../../../models/project_model.dart';
import '../../../providers/capability_provider.dart';
import '../../../providers/project_provider.dart';

class CapabilitiesScreen extends ConsumerStatefulWidget {
  const CapabilitiesScreen({super.key});

  @override
  ConsumerState<CapabilitiesScreen> createState() => _CapabilitiesScreenState();
}

class _CapabilitiesScreenState extends ConsumerState<CapabilitiesScreen> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final projectsAsync = ref.watch(projectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('开发能力'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(projectsProvider),
            tooltip: '刷新',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Text(
            '选择能力执行开发任务',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),

          // Capability cards
          ...CapabilityInfo.all.map((cap) => _CapabilityCard(
                capability: cap,
                onTap: () => _showExecuteDialog(context, cap),
              )),

          const SizedBox(height: 24),

          // Projects section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '已注册项目',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              TextButton.icon(
                onPressed: () => _showAddProjectDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          projectsAsync.when(
            data: (projects) {
              if (projects.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.folder_open_outlined,
                            size: 48, color: colorScheme.outline),
                        const SizedBox(height: 8),
                        Text('暂无项目',
                            style: TextStyle(color: colorScheme.outline)),
                        const SizedBox(height: 4),
                        Text('添加项目以使用开发能力',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: colorScheme.outline)),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: projects
                    .map((p) => _ProjectTile(
                          project: p,
                          onDelete: () => _deleteProject(p.key),
                        ))
                    .toList(),
              );
            },
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('加载失败: $e',
                    style: TextStyle(color: colorScheme.error)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showExecuteDialog(
      BuildContext context, CapabilityInfo cap) async {
    final projectsAsync = ref.read(projectsProvider);
    final projects = projectsAsync.valueOrNull ?? [];

    if (projects.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先添加项目')),
      );
      return;
    }

    final titleController = TextEditingController();
    final descController = TextEditingController();
    String selectedProjectKey = projects.first.key;
    String selectedExecutor = 'claude';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('${cap.icon} ${cap.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cap.description,
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 16),
                
                if (cap.id == 'execute-plan') ...[
                  const Text('选择执行器', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'claude', label: Text('Claude'), icon: Icon(Icons.auto_awesome_outlined, size: 16)),
                      ButtonSegment(value: 'cursor', label: Text('Cursor'), icon: Icon(Icons.code_outlined, size: 16)),
                    ],
                    selected: {selectedExecutor},
                    onSelectionChanged: (val) => setState(() => selectedExecutor = val.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 16),
                ],

                DropdownButtonFormField<String>(
                  value: selectedProjectKey,
                  decoration: const InputDecoration(
                    labelText: '项目',
                    border: OutlineInputBorder(),
                  ),
                  items: projects
                      .map((p) => DropdownMenuItem(
                            value: p.key,
                            child: Text(p.name),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => selectedProjectKey = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '任务标题',
                    hintText: '例如: 优化库存同步API',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: '需求描述',
                    hintText: '详细说明需要实现的功能',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('执行'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      final title = titleController.text.trim();
      if (title.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入任务标题')),
        );
        return;
      }

      final capId = cap.id == 'execute-plan' 
          ? (selectedExecutor == 'cursor' ? 'execute-plan-cursor' : 'execute-plan')
          : cap.id;

      await _executeCapability(
        capId,
        title,
        descController.text.trim().isEmpty ? title : descController.text.trim(),
        selectedProjectKey,
      );
    }
  }

  Future<void> _executeCapability(
    String capability,
    String title,
    String description,
    String projectKey,
  ) async {
    final api = ref.read(capabilityApiServiceProvider);
    if (api == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未连接到代理服务器')),
      );
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在执行...')),
      );

      final result = await api.executeCapability(
        capability: capability,
        title: title,
        description: description,
        projectKey: projectKey,
      );

      if (!mounted) return;

      final taskData = result['task'] as Map<String, dynamic>?;
      final taskId = taskData?['taskId'] as String? ?? '';
      final planPath = taskData?['planPath'] as String? ?? '';

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ 任务已创建: $taskId'),
          duration: const Duration(seconds: 3),
        ),
      );

      if (result.containsKey('openclawRequestId')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🚀 已发送到 Agent: ${result['openclawRequestId']}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ 执行失败: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _showAddProjectDialog(BuildContext context) async {
    final keyController = TextEditingController();
    final nameController = TextEditingController();
    final pathController = TextEditingController();
    final descController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加项目'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyController,
                decoration: const InputDecoration(
                  labelText: '项目键 (Key)',
                  hintText: '例如: my_project',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '项目名称',
                  hintText: '例如: 库存系统',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pathController,
                decoration: const InputDecoration(
                  labelText: '项目路径',
                  hintText: '/path/to/project',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: '描述（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('添加'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final key = keyController.text.trim();
      final name = nameController.text.trim();
      final path = pathController.text.trim();

      if (key.isEmpty || name.isEmpty || path.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请填写项目键、名称和路径')),
        );
        return;
      }

      final api = ref.read(capabilityApiServiceProvider);
      if (api == null) return;

      try {
        await api.upsertProject(ProjectModel(
          key: key,
          name: name,
          path: path,
          status: 'active',
          description: descController.text.trim(),
        ));
        ref.invalidate(projectsProvider);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteProject(String key) async {
    final api = ref.read(capabilityApiServiceProvider);
    if (api == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除项目?'),
        content: Text('确定要删除项目 "$key" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await api.deleteProject(key);
        ref.invalidate(projectsProvider);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }
}

// ─── Capability Card ────────────────────────────────────────────────

class _CapabilityCard extends StatelessWidget {
  final CapabilityInfo capability;
  final VoidCallback onTap;

  const _CapabilityCard({required this.capability, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(capability.icon,
                  style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(capability.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(capability.description,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Project Tile ────────────────────────────────────────────────────

class _ProjectTile extends StatelessWidget {
  final ProjectModel project;
  final VoidCallback onDelete;

  const _ProjectTile({required this.project, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          child: Text(project.name.characters.first,
              style: TextStyle(color: colorScheme.onPrimaryContainer)),
        ),
        title: Text(project.name),
        subtitle: Text(
          project.description ?? project.path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, size: 20, color: colorScheme.error),
          onPressed: onDelete,
        ),
      ),
    );
  }
}
