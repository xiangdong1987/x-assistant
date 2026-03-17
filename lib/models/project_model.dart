class ProjectModel {
  final String key;
  final String name;
  final String path;
  final String type;
  final List<String> techStack;
  final String owner;
  final String status;
  final String description;
  final String? githubUrl;

  ProjectModel({
    required this.key,
    required this.name,
    required this.path,
    this.type = 'unknown',
    this.techStack = const [],
    this.owner = 'unknown',
    this.status = 'active',
    this.description = '',
    this.githubUrl,
  });

  factory ProjectModel.fromJson(Map<String, dynamic> json) {
    return ProjectModel(
      key: json['key'] as String? ?? '',
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      type: json['type'] as String? ?? 'unknown',
      techStack: (json['techStack'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      owner: json['owner'] as String? ?? 'unknown',
      status: json['status'] as String? ?? 'active',
      description: json['description'] as String? ?? '',
      githubUrl: json['githubUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'name': name,
      'path': path,
      'type': type,
      'techStack': techStack,
      'owner': owner,
      'status': status,
      'description': description,
      if (githubUrl != null && githubUrl!.isNotEmpty) 'githubUrl': githubUrl,
    };
  }
}
