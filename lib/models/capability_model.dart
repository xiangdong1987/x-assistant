/// Available dev capability
class CapabilityInfo {
  final String id;
  final String name;
  final String description;
  final String icon;

  const CapabilityInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
  });

  static const List<CapabilityInfo> all = [
    CapabilityInfo(
      id: 'create-task',
      name: '创建任务',
      description: '创建开发任务并生成计划文件',
      icon: '➕',
    ),
    CapabilityInfo(
      id: 'execute-plan',
      name: '自动开发',
      description: '创建任务 → 生成计划 → 执行开发',
      icon: '🚀',
    ),
  ];
}
