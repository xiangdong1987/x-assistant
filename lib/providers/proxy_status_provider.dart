import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/connection_service.dart';
import '../services/proxy_launch_service.dart';

final proxyLaunchServiceProvider = Provider<ProxyLaunchService>((ref) {
  return ProxyLaunchService();
});

/// 代理存活状态
enum ProxyStatus {
  /// 未检测（无保存连接或尚未检测）
  idle,
  /// 检测中
  checking,
  /// 代理已运行
  running,
  /// 代理未运行或不可达
  notRunning,
}

/// 代理状态 Provider：根据已保存连接请求 GET /api/health 判断代理是否在运行
final proxyStatusProvider =
    StateNotifierProvider<ProxyStatusNotifier, AsyncValue<ProxyStatus>>((ref) {
  final connectionService = ref.watch(connectionServiceProvider);
  return ProxyStatusNotifier(connectionService);
});

class ProxyStatusNotifier extends StateNotifier<AsyncValue<ProxyStatus>> {
  ProxyStatusNotifier(this._connectionService)
      : super(const AsyncValue.data(ProxyStatus.idle));

  final ConnectionService _connectionService;

  /// 执行一次检测。有 [ip]/[port] 时用其检测；否则用已保存连接；无连接且未传地址时为 idle。
  Future<void> check({String? ip, int? port}) async {
    String? checkIp = ip;
    int? checkPort = port;
    if ((checkIp == null || checkPort == null)) {
      final connection = await _connectionService.loadSavedConnection();
      if (connection == null) {
        state = const AsyncValue.data(ProxyStatus.idle);
        return;
      }
      checkIp = connection.ip;
      checkPort = connection.port;
    }
    state = const AsyncValue.loading();
    try {
      final ok = await _connectionService.checkHealth(checkIp!, checkPort!);
      state = AsyncValue.data(ok ? ProxyStatus.running : ProxyStatus.notRunning);
    } catch (_) {
      state = const AsyncValue.data(ProxyStatus.notRunning);
    }
  }

  /// 重置为 idle（例如清除连接后）
  void reset() {
    state = const AsyncValue.data(ProxyStatus.idle);
  }
}
