import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/project_model.dart';
import '../../../providers/project_provider.dart';

class EditProjectScreen extends ConsumerStatefulWidget {
  final ProjectModel? project;

  const EditProjectScreen({super.key, this.project});

  @override
  ConsumerState<EditProjectScreen> createState() => _EditProjectScreenState();
}

class _EditProjectScreenState extends ConsumerState<EditProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _keyController;
  late TextEditingController _nameController;
  late TextEditingController _pathController;
  late TextEditingController _typeController;
  late TextEditingController _techStackController;
  late TextEditingController _ownerController;
  late TextEditingController _statusController;
  late TextEditingController _descriptionController;
  late TextEditingController _githubUrlController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    _keyController = TextEditingController(text: p?.key ?? '');
    _nameController = TextEditingController(text: p?.name ?? '');
    _pathController = TextEditingController(text: p?.path ?? '');
    _typeController = TextEditingController(text: p?.type ?? 'unknown');
    _techStackController = TextEditingController(text: p?.techStack.join(', ') ?? '');
    _ownerController = TextEditingController(text: p?.owner ?? 'unknown');
    _statusController = TextEditingController(text: p?.status ?? 'active');
    _descriptionController = TextEditingController(text: p?.description ?? '');
    _githubUrlController = TextEditingController(text: p?.githubUrl ?? '');
  }

  @override
  void dispose() {
    _keyController.dispose();
    _nameController.dispose();
    _pathController.dispose();
    _typeController.dispose();
    _techStackController.dispose();
    _ownerController.dispose();
    _statusController.dispose();
    _descriptionController.dispose();
    _githubUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final techStackList = _techStackController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final newProject = ProjectModel(
      key: _keyController.text.trim(),
      name: _nameController.text.trim(),
      path: _pathController.text.trim(),
      type: _typeController.text.trim().isEmpty ? 'unknown' : _typeController.text.trim(),
      techStack: techStackList,
      owner: _ownerController.text.trim().isEmpty ? 'unknown' : _ownerController.text.trim(),
      status: _statusController.text.trim().isEmpty ? 'active' : _statusController.text.trim(),
      description: _descriptionController.text.trim(),
      githubUrl: _githubUrlController.text.trim().isEmpty ? null : _githubUrlController.text.trim(),
    );

    final api = ref.read(projectApiServiceProvider);
    if (api != null) {
      try {
        await api.saveProject(newProject);
        ref.invalidate(projectsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.project == null ? '项目已创建' : '项目已更新'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('保存失败：$e'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未连接到服务端，请先在设置中完成连接'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.project != null;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑项目' : '添加项目'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // 必填信息
            _SectionHeader(
              title: '必填信息',
              subtitle: '项目标识、名称与本地路径为必填项',
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _keyController,
              decoration: const InputDecoration(
                labelText: '项目标识',
                hintText: '例如：my_app',
                helperText: '创建后不可修改，用于唯一识别项目',
                border: OutlineInputBorder(),
              ),
              enabled: !isEdit,
              validator: (v) => v!.trim().isEmpty ? '请输入项目标识' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '项目名称',
                hintText: '例如：我的应用',
                border: OutlineInputBorder(),
              ),
              validator: (v) => v!.trim().isEmpty ? '请输入项目名称' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _pathController,
              decoration: const InputDecoration(
                labelText: '项目路径',
                hintText: '例如：/Users/xxx/workspace/my_app',
                helperText: '本地绝对路径，指向项目根目录',
                border: OutlineInputBorder(),
              ),
              validator: (v) => v!.trim().isEmpty ? '请输入项目路径' : null,
            ),
            const SizedBox(height: 24),

            // 选填信息
            _SectionHeader(
              title: '选填信息',
              subtitle: '类型、技术栈、负责人等可按需填写',
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _typeController,
              decoration: const InputDecoration(
                labelText: '类型（选填）',
                hintText: '例如：backend-service、tool',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _techStackController,
              decoration: const InputDecoration(
                labelText: '技术栈（选填）',
                hintText: '例如：Flutter, Dart, Go（逗号分隔）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _ownerController,
              decoration: const InputDecoration(
                labelText: '负责人（选填）',
                hintText: '例如：张三',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _statusController,
              decoration: const InputDecoration(
                labelText: '状态（选填）',
                hintText: '例如：active、archived',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '描述（选填）',
                hintText: '简要描述项目用途',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _githubUrlController,
              decoration: const InputDecoration(
                labelText: 'GitHub 地址（选填）',
                hintText: '例如：https://github.com/owner/repo',
                prefixIcon: Icon(Icons.code),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 32),

            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? '保存中…' : (isEdit ? '保存修改' : '创建项目')),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
