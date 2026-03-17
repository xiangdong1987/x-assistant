import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _localeKey = 'app_locale';

/// Current app locale. Persisted via SharedPreferences.
/// Values: 'zh' | 'en'. Null means use system locale (defaults to loading then system).
final localeProvider =
    StateNotifierProvider<LocaleNotifier, Locale?>((ref) => LocaleNotifier());

class LocaleNotifier extends StateNotifier<Locale?> {
  LocaleNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_localeKey);
    if (code != null && (code == 'zh' || code == 'en')) {
      state = Locale(code);
    } else {
      state = null; // system
    }
  }

  /// Set app language and persist. [languageCode] should be 'zh' or 'en'.
  Future<void> setLocale(String languageCode) async {
    if (languageCode != 'zh' && languageCode != 'en') return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, languageCode);
    state = Locale(languageCode);
  }

  /// Clear saved locale (use system).
  Future<void> clearLocale() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localeKey);
    state = null;
  }
}
