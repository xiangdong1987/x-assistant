import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:logger/logger.dart';

enum ConnectionStatus { disconnected, connecting, connected, reconnecting, error }

final _logger = Logger(
  printer: PrettyPrinter(methodCount: 0, printEmojis: false),
);

class WebSocketService {
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _connectionTimeoutTimer;
  int _reconnectAttempts = 0;
  static const _maxReconnectAttempts = 10;
  static const _connectionTimeout = Duration(seconds: 10);

  String? _wsUrl;
  String? _token;

  final _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<ConnectionStatus> get connectionStatus => _connectionStatusController.stream;
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;
  ConnectionStatus get currentStatus => _currentStatus;

  Future<void> connect(String wsUrl, String token) async {
    _wsUrl = wsUrl;
    _token = token;

    _setStatus(ConnectionStatus.connecting);
    _logger.i('Connecting to WebSocket: $wsUrl');

    try {
      final uri = Uri.parse('$wsUrl?token=$token');
      _channel = WebSocketChannel.connect(uri);

      // Set connection timeout
      _connectionTimeoutTimer?.cancel();
      bool isConnected = false;

      _connectionTimeoutTimer = Timer(_connectionTimeout, () {
        if (!isConnected && _currentStatus == ConnectionStatus.connecting) {
          _logger.w('Connection timeout');
          _channel?.sink.close();
          _setStatus(ConnectionStatus.error);
          _scheduleReconnect();
        }
      });

      // Try to wait for ready, but don't fail if it throws
      try {
        await _channel!.ready.timeout(
          _connectionTimeout,
          onTimeout: () {
            throw TimeoutException('Connection timeout');
          },
        );
      } catch (e) {
        _logger.w('ready check failed, trying direct connection: $e');
        // Some platforms don't support .ready, so we'll try listening directly
      }

      // Start listening - if connection fails, onError will be called
      _listenToMessages();

      // Mark as connected if we got this far
      isConnected = true;
      _connectionTimeoutTimer?.cancel();
      _logger.i('WebSocket connected successfully');
      _setStatus(ConnectionStatus.connected);
      _reconnectAttempts = 0;
      _startHeartbeat();

      // 触发成功连接回调
      onConnected?.call();
    } catch (e) {
      _connectionTimeoutTimer?.cancel();
      _logger.e('WebSocket connection error: $e');
      _setStatus(ConnectionStatus.error);
      _scheduleReconnect();
    }
  }

  // Callback for auth errors (401)
  void Function()? onAuthError;

  // Callback for consecutive failures (likely IP change)
  void Function()? onConsecutiveFailures;

  // Callback for successful connection
  void Function()? onConnected;

  void _listenToMessages() {
    _channel?.stream.listen(
      (data) {
        try {
          final message = jsonDecode(data as String) as Map<String, dynamic>;
          _logger.d('Received: ${message['type']}');

          // Handle pong messages
          if (message['type'] == 'pong') {
            return;
          }

          _messageController.add(message);
        } catch (e) {
          _logger.w('Failed to parse message: $e');
        }
      },
      onError: (error) {
        _logger.e('WebSocket error: $error');

        // Check if it's a 401 auth error
        final errorStr = error.toString();
        if (errorStr.contains('401') || errorStr.contains('Unauthorized')) {
          _logger.w('Auth error detected, token may be expired');
          _setStatus(ConnectionStatus.error);
          onAuthError?.call();
          return;
        }

        _setStatus(ConnectionStatus.error);
        _scheduleReconnect();
      },
      onDone: () {
        _logger.i('WebSocket closed');
        if (_currentStatus == ConnectionStatus.connected) {
          _setStatus(ConnectionStatus.disconnected);
          _scheduleReconnect();
        }
      },
    );
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _sendPing(),
    );
  }

  void _sendPing() {
    send({
      'type': 'ping',
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
    });
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _logger.e('Max reconnect attempts reached');
      _setStatus(ConnectionStatus.error);
      // 触发外部处理（可能是IP变化）
      onConsecutiveFailures?.call();
      return;
    }

    _heartbeatTimer?.cancel();

    final delay = Duration(
      seconds: _calculateBackoff(_reconnectAttempts),
    );
    _reconnectAttempts++;

    _logger.i('Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');
    _setStatus(ConnectionStatus.reconnecting);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_wsUrl != null && _token != null) {
        connect(_wsUrl!, _token!);
      }
    });
  }

  int _calculateBackoff(int attempt) {
    final seconds = 1 << attempt;
    return seconds > 32 ? 32 : seconds;
  }

  void _setStatus(ConnectionStatus status) {
    _logger.i('Status changed: $_currentStatus -> $status');
    _currentStatus = status;
    _connectionStatusController.add(status);
  }

  void send(Map<String, dynamic> message) {
    if (_channel != null && _currentStatus == ConnectionStatus.connected) {
      _channel!.sink.add(jsonEncode(message));
      _logger.d('Sent: ${message['type']}');
    }
  }

  void sendCommand(String commandId, String text, {String? workingDir, String? skill}) {
    send({
      'type': 'command',
      'id': commandId,
      'payload': {
        'text': text,
        if (workingDir != null) 'working_dir': workingDir,
        if (skill != null) 'skill': skill,
      },
    });
  }

  void cancelCommand(String commandId) {
    send({
      'type': 'cancel',
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'payload': {
        'command_id': commandId,
      },
    });
  }

  void sendChatHistory({int limit = 50}) {
    send({
      'type': 'chat_history',
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'payload': {
        'limit': limit,
      },
    });
  }

  void sendChatAbort(String runId) {
    send({
      'type': 'chat_abort',
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'payload': {
        'run_id': runId,
      },
    });
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _connectionTimeoutTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setStatus(ConnectionStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _connectionStatusController.close();
    _messageController.close();
  }
}

// Riverpod provider
final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final service = WebSocketService();
  ref.onDispose(() => service.dispose());
  return service;
});

final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) {
  final service = ref.watch(webSocketServiceProvider);
  // Start with current status, then listen to stream
  return Stream.value(service.currentStatus).asyncExpand(
    (_) => service.connectionStatus,
  );
});
