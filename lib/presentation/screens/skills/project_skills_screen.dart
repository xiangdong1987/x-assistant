import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/project_model.dart';
import '../../../models/skill_model.dart';
import '../../../providers/project_provider.dart';
import '../../../providers/skill_provider.dart';

/// 项目技能页：展示项目列表与技能，替代原「技能」tab 内容。
class ProjectSkillsScreen extends ConsumerWidget {
  const ProjectSkillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsProvider);
    final skillsAsync = ref.watch(skillsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('项目技能'),
        actions: [
          IconButton(
            icon: const Icon(Icons.rocket_launch_outlined),
            onPressed: () => context.push('/capabilities'),
            tooltip: '开发能力',
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => context.pushNamed('skillsAll'),
            tooltip: '全部技能',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(projectsProvider);
              ref.invalidate(skillsProvider);
            },
            tooltip: '刷新',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(projectsProvider);
          ref.invalidate(skillsProvider);
        },
        child: ListView(
          children: [
            // 项目区块
            _ProjectsSection(projectsAsync: projectsAsync),
            const Divider(height: 24, indent: 16, endIndent: 16),
            // 技能区块（按路径分组）
            skillsAsync.when(
              data: (skills) {
                if (skills.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome_outlined,
                              size: 48, color: colorScheme.outline),
                          const SizedBox(height: 12),
                          Text(
                            '暂无技能',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: colorScheme.outline,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '请在设置中添加技能路径',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.outline,
                                ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final grouped = <String, List<SkillModel>>{};
                for (final skill in skills) {
                  grouped.putIfAbsent(skill.path, () => []).add(skill);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        '技能',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    ...grouped.entries.map(
                      (e) => _SkillGroup(path: e.key, skills: e.value),
                    ),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                      const SizedBox(height: 8),
                      Text('加载失败: $e', style: TextStyle(color: colorScheme.error)),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: () {
                          ref.invalidate(skillsProvider);
                        },
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _ProjectsSection extends ConsumerWidget {
  final AsyncValue<List<ProjectModel>> projectsAsync;

  const _ProjectsSection({required this.projectsAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_special_outlined, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    '项目',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () => context.pushNamed('addProject'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        projectsAsync.when(
          data: (projects) {
            if (projects.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  children: [
                    Text(
                      '暂无项目',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.outline,
                          ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => context.pushNamed('addProject'),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加第一个项目'),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: projects
                  .map(
                    (p) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colorScheme.secondaryContainer,
                        child: Icon(Icons.folder_special, color: colorScheme.secondary, size: 20),
                      ),
                      title: Text(p.name),
                      subtitle: Text(
                        p.path,
                        style: TextStyle(color: colorScheme.outline, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () => context.pushNamed('editProject', extra: p),
                            tooltip: '编辑',
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, color: colorScheme.error, size: 20),
                            onPressed: () => _confirmDeleteProject(context, ref, p),
                            tooltip: '删除',
                          ),
                        ],
                      ),
                      onTap: () => context.pushNamed('editProject', extra: p),
                    ),
                  )
                  .toList(),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator())),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              '加载项目失败: $e',
              style: TextStyle(color: colorScheme.error, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  void _confirmDeleteProject(BuildContext context, WidgetRef ref, ProjectModel project) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除项目'),
        content: Text('确定要删除项目 "${project.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              Navigator.pop(context);
              final api = ref.read(projectApiServiceProvider);
              if (api != null) {
                try {
                  await api.deleteProject(project.key);
                  ref.invalidate(projectsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已删除项目: ${project.name}')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('删除失败: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _SkillGroup extends ConsumerWidget {
  final String path;
  final List<SkillModel> skills;

  const _SkillGroup({required this.path, required this.skills});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  path,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        ...skills.map(
          (skill) => ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(Icons.auto_awesome, color: colorScheme.primary, size: 20),
            ),
            title: Text(skill.name),
            subtitle: Text(
              skill.id,
              style: TextStyle(color: colorScheme.outline, fontSize: 12),
            ),
            trailing: FilledButton.tonalIcon(
              onPressed: () {
                ref.read(selectedSkillProvider.notifier).state = skill;
                final shell = StatefulNavigationShell.of(context);
                shell.goBranch(2);
              },
              icon: const Icon(Icons.send, size: 16),
              label: const Text('使用'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: Size.zero,
              ),
            ),
            onTap: () => _showSkillContent(context, ref, skill),
          ),
        ),
        const Divider(indent: 16, endIndent: 16),
      ],
    );
  }

  void _showSkillContent(BuildContext context, WidgetRef ref, SkillModel skill) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scrollController) => _SkillContentSheet(
          skill: skill,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

class _SkillContentSheet extends ConsumerStatefulWidget {
  final SkillModel skill;
  final ScrollController scrollController;

  const _SkillContentSheet({
    required this.skill,
    required this.scrollController,
  });

  @override
  ConsumerState<_SkillContentSheet> createState() => _SkillContentSheetState();
}

class _SkillContentSheetState extends ConsumerState<_SkillContentSheet> {
  String? _content;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      final api = ref.read(skillApiServiceProvider);
      if (api == null) {
        if (mounted) {
          setState(() {
            _error = '未连接到 Proxy';
            _loading = false;
          });
        }
        return;
      }
      final content = await api.getSkillContent(widget.skill.id);
      if (mounted) {
        setState(() {
          _content = content;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: colorScheme.outline.withAlpha(80),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.skill.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () {
                  ref.read(selectedSkillProvider.notifier).state = widget.skill;
                  Navigator.pop(context);
                  final shell = StatefulNavigationShell.of(context);
                  shell.goBranch(2);
                },
                icon: const Icon(Icons.send, size: 16),
                label: const Text('使用'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text('错误: $_error'))
                  : SingleChildScrollView(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        _content ?? '',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                              height: 1.5,
                            ),
                      ),
                    ),
        ),
      ],
    );
  }
}
