import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/capability_model.dart';
import '../models/project_model.dart';
import '../services/capability_api_service.dart';
import '../services/connection_service.dart';

/// Builds CapabilityApiService from saved connection info
final capabilityApiServiceProvider = Provider<CapabilityApiService?>((ref) {
  final conn = ref.watch(savedConnectionProvider).valueOrNull;
  if (conn == null) return null;
  return CapabilityApiService(baseUrl: conn.httpUrl, token: conn.token);
});

/// Fetches all registered projects from the proxy (via capability API)
final capabilityProjectsProvider = FutureProvider<List<ProjectModel>>((ref) async {
  final api = ref.watch(capabilityApiServiceProvider);
  if (api == null) return [];
  return api.getProjects();
});
