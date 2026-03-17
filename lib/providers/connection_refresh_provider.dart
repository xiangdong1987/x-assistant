import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/websocket_service.dart';
import '../services/connection_service.dart';
import 'skill_provider.dart';
import 'project_provider.dart' as project_prov;
import 'capability_provider.dart' as capability_prov;
import 'task_provider.dart';

Timer? _debounceTimer;

/// 连接状态变化时触发的刷新回调
/// 当 WebSocket 连接成功时，自动刷新技能、项目、任务等数据
/// [onRefreshed] 可选，重连成功后回调（如显示 SnackBar）
void setupConnectionRefresh(WidgetRef ref, {void Function(String message)? onRefreshed}) {
  ref.listen<AsyncValue<ConnectionStatus>>(
    connectionStatusProvider,
    (previous, next) {
      final status = next.valueOrNull;
      if (status == ConnectionStatus.connected) {
        // Debounce to avoid cascading invalidations on rapid reconnects
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 500), () {
          _onConnected(ref);
          // 仅重连时提示（初次连接由 pairing/splash 提示）
          final prev = previous?.valueOrNull;
          if (prev != null &&
              prev != ConnectionStatus.connected &&
              prev != ConnectionStatus.connecting) {
            onRefreshed?.call('已重新连接，已同步技能和项目');
          }
        });
      }
    },
  );
}

void _onConnected(WidgetRef ref) {
  // 1. 刷新连接信息（确保 API 服务使用最新连接）
  ref.invalidate(savedConnectionProvider);
  ref.invalidate(connectionInfoProvider);

  // 2. 刷新技能列表和技能路径
  ref.invalidate(skillsProvider);
  ref.invalidate(skillPathsProvider);

  // 3. 刷新项目目录（project_provider 和 capability_provider 各有一个）
  ref.invalidate(project_prov.projectsProvider);
  ref.invalidate(capability_prov.capabilityProjectsProvider);

  // 4. 刷新任务列表
  ref.invalidate(taskNotifierProvider);
}
