import 'package:dio/dio.dart';

/// Service for pairing-related API calls
class PairingApiService {
  PairingApiService({
    required this.baseUrl,
    this.token,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    if (token != null && token!.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
    _dio.options.headers['Content-Type'] = 'application/json';
    _dio.options.connectTimeout = const Duration(seconds: 5);
    _dio.options.receiveTimeout = const Duration(seconds: 5);
  }

  final String baseUrl;
  final String? token;
  final Dio _dio;

  /// Get current pairing info (IP, port, PIN)
  Future<Map<String, dynamic>> getPairingInfo() async {
    final response = await _dio.get('$baseUrl/api/pair/info');
    return response.data as Map<String, dynamic>;
  }

  /// Reset the PIN code (requires authentication)
  Future<Map<String, dynamic>> resetPIN() async {
    final response = await _dio.post('$baseUrl/api/pair/reset');
    return response.data as Map<String, dynamic>;
  }
}
