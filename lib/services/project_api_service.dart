import 'package:dio/dio.dart';

import '../models/project_model.dart';

class ProjectApiService {
  final String baseUrl;
  final String token;
  final Dio _dio;

  ProjectApiService({required this.baseUrl, required this.token})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {'Authorization': 'Bearer $token'},
        ));

  /// Fetch all projects
  Future<List<ProjectModel>> getProjects() async {
    final response = await _dio.get('/api/projects');
    final Map<String, dynamic> data = response.data as Map<String, dynamic>;
    final List<dynamic> projectsJson = data['projects'] as List<dynamic>? ?? [];
    return projectsJson
        .map((e) => ProjectModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Create or update a project
  Future<ProjectModel> saveProject(ProjectModel project) async {
    final response = await _dio.post('/api/projects', data: project.toJson());
    final data = response.data as Map<String, dynamic>;
    return ProjectModel.fromJson(data['project'] as Map<String, dynamic>);
  }

  /// Delete a project by key
  Future<void> deleteProject(String key) async {
    await _dio.delete('/api/projects/$key');
  }
}
