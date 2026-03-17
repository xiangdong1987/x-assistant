class SkillModel {
  final String id;
  final String name;
  final String path;
  String? content;

  SkillModel({
    required this.id,
    required this.name,
    required this.path,
    this.content,
  });

  factory SkillModel.fromJson(Map<String, dynamic> json) {
    return SkillModel(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
    );
  }
}
