import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/connection_fail_tracker.dart';
import '../services/connection_service.dart';
import '../services/websocket_service.dart';

/// 连接诊断状态
enum ConnectionDiagnosisState {
  /// 未知/初始状态
  unknown,
  /// 已连接
  connected,
  /// 正在连接
  connecting,
  /// 网络问题
  networkError,
  /// IP可能已变化
  ipLikelyChanged,
  /// 认证错误
  authError,
}

/// 连接诊断状态数据
class ConnectionDiagnosisStateData {
  final ConnectionDiagnosisState state;
  final String? savedIp;
  final int? savedPort;
  final int failCount;
  final String? message;

  ConnectionDiagnosisStateData({
    required this.state,
    this.savedIp,
    this.savedPort,
    this.failCount = 0,
    this.message,
  });

  ConnectionDiagnosisStateData copyWith({
    ConnectionDiagnosisState? state,
    String? savedIp,
    int? savedPort,
    int? failCount,
    String? message,
  }) {
    return ConnectionDiagnosisStateData(
      state: state ?? this.state,
      savedIp: savedIp ?? this.savedIp,
      savedPort: savedPort ?? this.savedPort,
      failCount: failCount ?? this.failCount,
      message: message ?? this.message,
    );
  }
}

/// 连接诊断 Notifier
class ConnectionDiagnosisNotifier extends StateNotifier<ConnectionDiagnosisStateData> {
  final ConnectionService _connectionService;
  final WebSocketService _webSocketService;
  final ConnectionFailTracker _failTracker;
  StreamSubscription<ConnectionStatus>? _statusSubscription;

  ConnectionDiagnosisNotifier(
    this._connectionService,
    this._webSocketService,
    this._failTracker,
  ) : super(ConnectionDiagnosisStateData(state: ConnectionDiagnosisState.unknown)) {
    _init();
  }

  void _init() {
    // 加载保存的连接信息
    _loadSavedConnection();

    // 监听WebSocket连接状态
    _statusSubscription = _webSocketService.connectionStatus.listen(_onConnectionStatusChanged);

    // 设置 WebSocket 失败回调
    _webSocketService.onConsecutiveFailures = _onConsecutiveFailures;

    // 设置 WebSocket 成功连接回调
    _webSocketService.onConnected = _onConnected;
  }

  void _onConnected() {
    // 连接成功时重置失败计数
    _failTracker.reset();
    state = state.copyWith(
      state: ConnectionDiagnosisState.connected,
      failCount: 0,
      message: '已连接',
    );
    _loadSavedConnection();
  }

  Future<void> _loadSavedConnection() async {
    final connection = await _connectionService.loadSavedConnection();
    if (connection != null) {
      final failCount = await _failTracker.getFailCount();
      state = state.copyWith(
        savedIp: connection.ip,
        savedPort: connection.port,
        failCount: failCount,
      );
    }
  }

  Future<void> _onConnectionStatusChanged(ConnectionStatus status) async {
    switch (status) {
      case ConnectionStatus.connected:
        await _failTracker.reset();
        state = state.copyWith(
          state: ConnectionDiagnosisState.connected,
          failCount: 0,
          message: '已连接',
        );
        await _loadSavedConnection();
        break;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        state = state.copyWith(
          state: ConnectionDiagnosisState.connecting,
          message: '正在连接...',
        );
        break;
      case ConnectionStatus.disconnected:
        final isIpChanged = await _checkIpChange();
        if (isIpChanged) {
          state = state.copyWith(
            state: ConnectionDiagnosisState.ipLikelyChanged,
            message: 'IP可能已变化，请重新配对',
          );
        } else {
          state = state.copyWith(
            state: ConnectionDiagnosisState.networkError,
            message: '网络连接断开',
          );
        }
        break;
      case ConnectionStatus.error:
        final isIpChanged = await _checkIpChange();
        if (isIpChanged) {
          state = state.copyWith(
            state: ConnectionDiagnosisState.ipLikelyChanged,
            message: '连接多次失败，IP可能已变化',
          );
        } else {
          state = state.copyWith(
            state: ConnectionDiagnosisState.networkError,
            message: '连接失败',
          );
        }
        break;
    }
  }

  Future<void> _onConsecutiveFailures() async {
    // 记录失败
    await _failTracker.recordFailure();
    final failCount = await _failTracker.getFailCount();
    state = state.copyWith(failCount: failCount);

    // 检查是否是IP问题
    final isIpChanged = await _checkIpChange();
    if (isIpChanged) {
      state = state.copyWith(
        state: ConnectionDiagnosisState.ipLikelyChanged,
        message: '多次连接失败，IP可能已变化',
      );
    }
  }

  Future<bool> _checkIpChange() async {
    final failCount = await _failTracker.getFailCount();
    if (failCount >= 3) {
      return await _failTracker.isIpLikelyChanged();
    }
    return false;
  }

  /// 刷新连接状态（用于手动触发）
  Future<void> refreshDiagnosis() async {
    await _loadSavedConnection();
    final failCount = await _failTracker.getFailCount();
    state = state.copyWith(failCount: failCount);
  }

  /// 清除连接信息并重置状态
  Future<void> clearConnection() async {
    await _connectionService.disconnect();
    await _failTracker.reset();
    state = ConnectionDiagnosisStateData(
      state: ConnectionDiagnosisState.unknown,
      message: '已清除连接信息',
    );
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _webSocketService.onConsecutiveFailures = null;
    _webSocketService.onConnected = null;
    super.dispose();
  }
}

/// 失败追踪器 Provider
final connectionFailTrackerProvider = Provider<ConnectionFailTracker>((ref) {
  return ConnectionFailTracker();
});

/// 连接诊断 Provider
final connectionDiagnosisProvider =
    StateNotifierProvider<ConnectionDiagnosisNotifier, ConnectionDiagnosisStateData>((ref) {
  final connectionService = ref.watch(connectionServiceProvider);
  final webSocketService = ref.watch(webSocketServiceProvider);
  final failTracker = ref.watch(connectionFailTrackerProvider);

  return ConnectionDiagnosisNotifier(
    connectionService,
    webSocketService,
    failTracker,
  );
});