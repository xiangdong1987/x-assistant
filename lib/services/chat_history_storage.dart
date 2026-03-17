import 'package:hive_flutter/hive_flutter.dart';

import '../models/chat_history_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Storage provider (singleton)
final chatHistoryStorageProvider = Provider<ChatHistoryStorage>((ref) {
  return ChatHistoryStorage();
});

class ChatHistoryStorage {
  static const String _boxName = 'chat_history';
  Box<ChatHistoryItem>? _box;

  /// Initialize asynchronously (registers adapters and opens box)
  Future<void> init() async {
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(ChatHistoryItemAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(ChatMessageAdapter());
    }

    _box = await Hive.openBox<ChatHistoryItem>(_boxName);
  }

  /// Initialize synchronously when box is already opened (called from main.dart)
  void initSync() {
    _box = Hive.box<ChatHistoryItem>(_boxName);
  }

  Box<ChatHistoryItem> get box {
    if (_box == null) {
      throw StateError('ChatHistoryStorage not initialized. Call init() first.');
    }
    return _box!;
  }

  /// Get all conversations sorted by updated time (newest first)
  List<ChatHistoryItem> getAll() {
    return box.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Get conversation by ID
  ChatHistoryItem? getById(String id) {
    return box.get(id);
  }

  /// Get the most recent conversation
  ChatHistoryItem? getLatest() {
    final all = getAll();
    return all.isNotEmpty ? all.first : null;
  }

  /// Save or update a conversation
  Future<void> save(ChatHistoryItem conversation) async {
    await box.put(conversation.id, conversation);
  }

  /// Save conversation and return the ID
  Future<String> saveConversation(ChatHistoryItem conversation) async {
    await box.put(conversation.id, conversation);
    return conversation.id;
  }

  /// Delete a conversation by ID
  Future<void> delete(String id) async {
    await box.delete(id);
  }

  /// Clear all conversations
  Future<void> clearAll() async {
    await box.clear();
  }

  /// Get total conversation count
  int get count => box.length;

  /// Get conversations within a date range
  List<ChatHistoryItem> getByDateRange(DateTime start, DateTime end) {
    return getAll().where((c) {
      return c.createdAt.isAfter(start) && c.createdAt.isBefore(end);
    }).toList();
  }

  /// Get today's conversations
  List<ChatHistoryItem> getTodayConversations() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return getByDateRange(startOfDay, endOfDay);
  }
}