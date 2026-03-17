import 'package:dio/dio.dart';

import '../models/capability_model.dart';
import '../models/project_model.dart';

class CapabilityApiService {
  final String baseUrl;
  final String token;
  final Dio _dio;

  CapabilityApiService({required this.baseUrl, required this.token})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Authorization': 'Bearer $token'},
        ));

  /// Fetch all registered projects
  Future<List<ProjectModel>> getProjects() async {
    final response = await _dio.get('/api/projects');
    final data = response.data as Map<String, dynamic>;
    final projects = data['projects'] as List<dynamic>? ?? [];
    return projects
        .map((e) => ProjectModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Add or update a project
  Future<void> upsertProject(ProjectModel project) async {
    await _dio.post('/api/projects', data: project.toJson());
  }

  /// Delete a project
  Future<void> deleteProject(String key) async {
    await _dio.delete('/api/projects/$key');
  }

  /// Execute a capability (create-task, execute-plan, execute-plan-cursor)
  Future<Map<String, dynamic>> executeCapability({
    required String capability,
    required String title,
    required String description,
    required String projectKey,
    String? priority,
  }) async {
    final response = await _dio.post('/api/capabilities/execute', data: {
      'capability': capability,
      'title': title,
      'description': description,
      'projectKey': projectKey,
      if (priority != null) 'priority': priority,
    });
    return response.data as Map<String, dynamic>;
  }
}
