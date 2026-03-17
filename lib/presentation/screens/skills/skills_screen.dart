import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/skill_model.dart';
import '../../../providers/skill_provider.dart';

class SkillsScreen extends ConsumerWidget {
  const SkillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skillsAsync = ref.watch(skillsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('技能'),
        actions: [
          IconButton(
            icon: const Icon(Icons.rocket_launch_outlined),
            onPressed: () => context.push('/capabilities'),
            tooltip: '开发能力',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(skillsProvider),
            tooltip: '刷新',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(skillsProvider),
        child: skillsAsync.when(
          data: (skills) {
            if (skills.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_outlined,
                        size: 64, color: colorScheme.outline),
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: () => context.goNamed('settings'),
                      child: const Text('前往设置'),
                    ),
                  ],
                ),
              );
            }

            // Group by path
            final grouped = <String, List<SkillModel>>{};
            for (final skill in skills) {
              grouped.putIfAbsent(skill.path, () => []).add(skill);
            }

            return ListView.builder(
              itemCount: grouped.length,
              itemBuilder: (context, index) {
                final entry = grouped.entries.elementAt(index);
                return _SkillGroup(
                  path: entry.key,
                  skills: entry.value,
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 8),
                Text('加载失败: $e'),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(skillsProvider),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
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
        ...skills.map((skill) => ListTile(
              leading: CircleAvatar(
                backgroundColor: colorScheme.primaryContainer,
                child: Icon(Icons.auto_awesome, color: colorScheme.primary, size: 20),
              ),
              title: Text(skill.name),
              subtitle: Text(skill.id,
                  style: TextStyle(color: colorScheme.outline, fontSize: 12)),
              trailing: FilledButton.tonalIcon(
                onPressed: () {
                  ref.read(selectedSkillProvider.notifier).state = skill;
                  // Navigate to Agent tab (index 2)
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
            )),
        const Divider(indent: 16, endIndent: 16),
      ],
    );
  }

  void _showSkillContent(
      BuildContext context, WidgetRef ref, SkillModel skill) async {
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
        setState(() {
          _error = '未连接到 Proxy';
          _loading = false;
        });
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
        // Handle bar
        Container(
          margin: const EdgeInsets.only(top: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: colorScheme.outline.withAlpha(80),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Title
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
        // Content
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
