import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

class ConnectionInfo {
  final String ip;
  final int port;
  final String token;
  final String deviceName;
  final DateTime pairedAt;
  final String? pin;

  ConnectionInfo({
    required this.ip,
    required this.port,
    required this.token,
    required this.deviceName,
    required this.pairedAt,
    this.pin,
  });

  String get wsUrl => 'ws://$ip:$port/ws';
  String get httpUrl => 'http://$ip:$port';

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'port': port,
    'token': token,
    'deviceName': deviceName,
    'pairedAt': pairedAt.toIso8601String(),
    'pin': pin,
  };

  factory ConnectionInfo.fromJson(Map<String, dynamic> json) => ConnectionInfo(
    ip: json['ip'] as String,
    port: json['port'] as int,
    token: json['token'] as String,
    deviceName: json['deviceName'] as String,
    pairedAt: DateTime.parse(json['pairedAt'] as String),
    pin: json['pin'] as String?,
  );
}

class ConnectionService {
  static const _storageKey = 'connection_info';
  final _dio = Dio();

  ConnectionInfo? _currentConnection;
  ConnectionInfo? get currentConnection => _currentConnection;

  /// Load saved connection info from storage
  Future<ConnectionInfo?> loadSavedConnection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_storageKey);
      if (data != null) {
        _currentConnection = ConnectionInfo.fromJson(jsonDecode(data));
        return _currentConnection;
      }
    } catch (e) {
      // Ignore errors, return null
    }
    return null;
  }

  /// Pair with a proxy server using PIN
  Future<ConnectionInfo> pair({
    required String ip,
    required int port,
    required String pin,
    required String deviceName,
    required String deviceId,
  }) async {
    final url = 'http://$ip:$port/api/pair';

    try {
      final response = await _dio.post(
        url,
        data: {
          'pin': pin,
          'device_name': deviceName,
          'device_id': deviceId,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      final data = response.data as Map<String, dynamic>;

      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Pairing failed');
      }

      final connectionInfo = ConnectionInfo(
        ip: ip,
        port: port,
        token: data['token'] as String,
        deviceName: deviceName,
        pairedAt: DateTime.now(),
        pin: pin,
      );

      // Save to storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(connectionInfo.toJson()),
      );

      _currentConnection = connectionInfo;
      return connectionInfo;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('Invalid PIN code');
      }
      throw Exception('Connection failed: ${e.message}');
    }
  }

  /// Update the current connection's IP and port, optionally with a new PIN
  /// If PIN is provided and different from current, re-pair with the server
  /// If PIN is not provided, keep existing token and connection
  Future<void> updateConnectionSettings(String ip, int port, {String? pin, String? defaultToken, String? defaultDeviceName}) async {
    final deviceName = _currentConnection?.deviceName ?? defaultDeviceName ?? 'Manual Override';
    final pairedAt = _currentConnection?.pairedAt ?? DateTime.now();
    final existingPin = _currentConnection?.pin;

    // If PIN is provided, re-pair to get a new token (supports multiple uses of PIN)
    String token;
    if (pin != null && pin.isNotEmpty) {
      try {
        final connectionService = ConnectionService();
        final prefs = await SharedPreferences.getInstance();
        String? deviceId = prefs.getString('device_id');
        if (deviceId == null) {
          deviceId = Uuid().v4();
          await prefs.setString('device_id', deviceId);
        }

        final newConnection = await connectionService.pair(
          ip: ip,
          port: port,
          pin: pin,
          deviceName: deviceName,
          deviceId: deviceId!,
        );
        token = newConnection.token;
      } catch (e) {
        // If pairing fails, fall back to existing token
        token = _currentConnection?.token ?? defaultToken ?? 'override-token-${DateTime.now().millisecondsSinceEpoch}';
      }
    } else {
      // No PIN provided, keep existing token
      token = _currentConnection?.token ?? defaultToken ?? 'override-token-${DateTime.now().millisecondsSinceEpoch}';
    }

    final updatedConnection = ConnectionInfo(
      ip: ip,
      port: port,
      token: token,
      deviceName: deviceName,
      pairedAt: pairedAt,
      pin: existingPin ?? pin, // Save PIN for future use
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(updatedConnection.toJson()),
    );

    _currentConnection = updatedConnection;
  }

  /// Check if proxy server is reachable
  Future<bool> checkHealth(String ip, int port) async {
    try {
      final response = await _dio.get(
        'http://$ip:$port/api/health',
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      return response.data['status'] == 'ok';
    } catch (e) {
      return false;
    }
  }

  /// Clear saved connection
  Future<void> disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    _currentConnection = null;
  }
}

// Riverpod providers
final connectionServiceProvider = Provider<ConnectionService>((ref) {
  return ConnectionService();
});

final savedConnectionProvider = FutureProvider<ConnectionInfo?>((ref) async {
  final service = ref.watch(connectionServiceProvider);
  return service.loadSavedConnection();
});
