import 'package:dio/dio.dart';

import '../models/skill_model.dart';

class SkillApiService {
  final String baseUrl;
  final String token;
  final Dio _dio;

  SkillApiService({required this.baseUrl, required this.token})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {'Authorization': 'Bearer $token'},
        ));

  /// Fetch configured skill paths
  Future<List<String>> getSkillPaths() async {
    final response = await _dio.get('/api/config/skill-paths');
    final data = response.data as Map<String, dynamic>;
    return List<String>.from(data['paths'] ?? []);
  }

  /// Update configured skill paths
  Future<void> setSkillPaths(List<String> paths) async {
    await _dio.post('/api/config/skill-paths', data: {'paths': paths});
  }

  /// Fetch all discovered skills
  Future<List<SkillModel>> getSkills() async {
    final response = await _dio.get('/api/skills');
    final List<dynamic> data = response.data as List<dynamic>;
    return data
        .map((e) => SkillModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetch a skill's markdown content
  Future<String> getSkillContent(String id) async {
    final response = await _dio.get('/api/skills/$id/content');
    return response.data as String;
  }

  /// Execute a skill by calling /api/skills/execute and returning the HANDOFF JSON
  Future<Map<String, dynamic>> executeSkill(String skill, String command, List<String> args) async {
    final response = await _dio.post('/api/skills/execute', data: {
      'skill': skill,
      'command': command,
      'args': args,
    });
    return response.data as Map<String, dynamic>;
  }

  /// Fetch today's agenda by executing the openclaw-agenda skill
  Future<List<dynamic>> getAgenda(String from, String to) async {
    final result = await executeSkill('openclaw-agenda', 'agenda', ['--from=$from', '--to=$to']);
    if (result['ok'] == true) {
      return result['data']['agenda'] as List<dynamic>;
    }
    return [];
  }

  /// Create a new schedule item
  Future<bool> createScheduleItem(Map<String, String> fields) async {
    final args = fields.entries.map((e) => '--${e.key}=${e.value}').toList();
    final result = await executeSkill('openclaw-sync-schedule', 'create', args);
    return result['ok'] == true;
  }

  /// Update a schedule item by ID
  Future<bool> updateScheduleItem(String id, Map<String, String> fields) async {
    final args = ['--id=$id', ...fields.entries.map((e) => '--${e.key}=${e.value}')];
    final result = await executeSkill('openclaw-sync-schedule', 'update', args);
    return result['ok'] == true;
  }

  /// Delete a schedule item by ID
  Future<bool> deleteScheduleItem(String id) async {
    final result = await executeSkill('openclaw-sync-schedule', 'delete', ['--id=$id']);
    return result['ok'] == true;
  }
}
