import 'package:hive/hive.dart';

part 'chat_history_model.g.dart';

@HiveType(typeId: 10)
class ChatHistoryItem extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  List<ChatMessage> messages;

  @HiveField(2)
  final DateTime createdAt;

  @HiveField(3)
  DateTime updatedAt;

  @HiveField(4)
  String? skillId;

  ChatHistoryItem({
    required this.id,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
    this.skillId,
  });

  ChatHistoryItem copyWith({
    List<ChatMessage>? messages,
    DateTime? updatedAt,
    String? skillId,
  }) {
    return ChatHistoryItem(
      id: id,
      messages: messages ?? this.messages,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      skillId: skillId ?? this.skillId,
    );
  }

  /// 获取第一条用户消息作为会话标题
  String? get title {
    for (final msg in messages) {
      if (msg.isUser && msg.content.isNotEmpty) {
        return msg.content.length > 50
            ? '${msg.content.substring(0, 50)}...'
            : msg.content;
      }
    }
    return null;
  }

  /// 获取消息数量
  int get messageCount => messages.length;
}

@HiveType(typeId: 11)
class ChatMessage extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String content;

  @HiveField(2)
  final bool isUser;

  @HiveField(3)
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
  });
}