import 'package:shared_preferences/shared_preferences.dart';

/// 连接失败追踪器
/// 用于检测是否可能是IP变化导致的连接失败
class ConnectionFailTracker {
  static const _storageKey = 'connection_fail_count';
  static const _lastFailTimeKey = 'connection_last_fail_time';
  static const _failThreshold = 3; // 连续失败3次视为IP可能变化
  static const _resetMinutes = 5; // 5分钟内的失败才累积计算

  /// 记录连接失败
  Future<void> recordFailure() async {
    final prefs = await SharedPreferences.getInstance();
    final lastFailStr = prefs.getString(_lastFailTimeKey);

    if (lastFailStr != null) {
      final lastFail = DateTime.tryParse(lastFailStr);
      if (lastFail != null) {
        // 检查是否超过重置时间
        if (DateTime.now().difference(lastFail).inMinutes >= _resetMinutes) {
          // 超过5分钟，重置计数
          await prefs.setInt(_storageKey, 1);
        } else {
          // 5分钟内失败，累加计数
          final count = prefs.getInt(_storageKey) ?? 0;
          await prefs.setInt(_storageKey, count + 1);
        }
      } else {
        // 无法解析时间，重置
        await prefs.setInt(_storageKey, 1);
      }
    } else {
      // 首次失败
      await prefs.setInt(_storageKey, 1);
    }

    await prefs.setString(_lastFailTimeKey, DateTime.now().toIso8601String());
  }

  /// 检查是否可能IP已变化（连续多次失败）
  Future<bool> isIpLikelyChanged() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_storageKey) ?? 0;

    // 如果连续失败超过阈值，且最近一次失败在5分钟内
    if (count >= _failThreshold) {
      final lastFail = prefs.getString(_lastFailTimeKey);
      if (lastFail != null) {
        final failTime = DateTime.tryParse(lastFail);
        if (failTime != null &&
            DateTime.now().difference(failTime).inMinutes < _resetMinutes) {
          return true;
        }
      }
    }
    return false;
  }

  /// 获取当前失败计数
  Future<int> getFailCount() async {
    final prefs = await SharedPreferences.getInstance();
    final lastFailStr = prefs.getString(_lastFailTimeKey);

    if (lastFailStr != null) {
      final lastFail = DateTime.tryParse(lastFailStr);
      if (lastFail != null &&
          DateTime.now().difference(lastFail).inMinutes >= _resetMinutes) {
        // 超过5分钟，计数已过期
        return 0;
      }
    }
    return prefs.getInt(_storageKey) ?? 0;
  }

  /// 重置失败计数（连接成功时调用）
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    await prefs.remove(_lastFailTimeKey);
  }

  /// 获取最后失败时间
  Future<DateTime?> getLastFailTime() async {
    final prefs = await SharedPreferences.getInstance();
    final lastFailStr = prefs.getString(_lastFailTimeKey);
    if (lastFailStr != null) {
      return DateTime.tryParse(lastFailStr);
    }
    return null;
  }
}