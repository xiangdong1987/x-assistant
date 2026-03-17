import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project_model.dart';
import '../services/project_api_service.dart';
import '../services/connection_service.dart';

/// Builds ProjectApiService from the saved connection info
final projectApiServiceProvider = Provider<ProjectApiService?>((ref) {
  final conn = ref.watch(savedConnectionProvider).valueOrNull;
  if (conn == null) return null;
  return ProjectApiService(baseUrl: conn.httpUrl, token: conn.token);
});

/// Fetches the list of projects from the proxy
final projectsProvider = FutureProvider<List<ProjectModel>>((ref) async {
  final api = ref.watch(projectApiServiceProvider);
  if (api == null) return [];
  return api.getProjects();
});
