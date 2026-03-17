import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/skill_model.dart';
import '../services/skill_api_service.dart';
import '../services/connection_service.dart';

/// Builds SkillApiService from the saved connection info
final skillApiServiceProvider = Provider<SkillApiService?>((ref) {
  final conn = ref.watch(savedConnectionProvider).valueOrNull;
  if (conn == null) return null;
  return SkillApiService(baseUrl: conn.httpUrl, token: conn.token);
});

/// Fetches the list of skills from the proxy
final skillsProvider = FutureProvider<List<SkillModel>>((ref) async {
  final api = ref.watch(skillApiServiceProvider);
  if (api == null) return [];
  return api.getSkills();
});

/// Currently selected skill for the Agent screen
final selectedSkillProvider = StateProvider<SkillModel?>((ref) => null);

/// Fetches configured skill paths from the proxy
final skillPathsProvider = FutureProvider<List<String>>((ref) async {
  final api = ref.watch(skillApiServiceProvider);
  if (api == null) return [];
  return api.getSkillPaths();
});
