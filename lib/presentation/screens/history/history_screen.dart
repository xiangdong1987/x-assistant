import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/task_provider.dart';
import '../../../services/chat_history_storage.dart';
import '../../../models/chat_history_model.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<ChatHistoryItem> _conversations = [];

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    try {
      final storage = ref.read(chatHistoryStorageProvider);
      final items = storage.getAll();
      if (mounted) {
        setState(() {
          _conversations = items;
        });
      }
    } catch (e) {
      debugPrint('Error loading chat history: $e');
    }
  }

  Future<void> _deleteConversation(ChatHistoryItem item) async {
    try {
      final storage = ref.read(chatHistoryStorageProvider);
      await storage.delete(item.id);
      if (mounted) {
        setState(() {
          _conversations.removeWhere((c) => c.id == item.id);
        });
      }
    } catch (e) {
      debugPrint('Error deleting chat history item: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final conversations = _conversations;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.commandHistory),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed:
                conversations.isEmpty ? null : () => _showClearConfirmation(context),
            tooltip: l10n.clearHistory,
          ),
        ],
      ),
      body: conversations.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.history, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(l10n.noCommandHistory),
                ],
              ),
            )
          : ListView.builder(
              itemCount: conversations.length,
              itemBuilder: (context, index) {
                final item = conversations[index];
                return _ConversationListTile(
                  conversation: item,
                  onTap: () {
                    context.pushNamed('agent', extra: item.id);
                  },
                  onDelete: () => _deleteConversation(item),
                );
              },
            ),
    );
  }

  void _showClearConfirmation(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final storage = ref.read(chatHistoryStorageProvider);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.clearHistory),
        content: Text(l10n.clearHistoryConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              await storage.clearAll();

              try {
                final api = ref.read(taskApiServiceProvider);
                if (api != null) {
                  await api.clearChatHistory();
                }
              } catch (e) {
                debugPrint(
                    'Warning: failed to clear backend history: $e');
              }

              if (mounted) {
                setState(() {
                  _conversations = [];
                });
                Navigator.of(dialogContext).pop();
              }
            },
            child: Text(l10n.clear, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _ConversationListTile extends StatelessWidget {
  final dynamic conversation;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ConversationListTile({
    required this.conversation,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = conversation.title ?? l10n.untitledConversation;
    final messageCount = conversation.messageCount;
    final updatedAt = conversation.updatedAt;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          Icons.chat,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.messageCount(messageCount)),
          Text(
            _formatTimestamp(context, updatedAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
        tooltip: l10n.delete,
      ),
      isThreeLine: true,
      onTap: onTap,
    );
  }

  String _formatTimestamp(BuildContext context, DateTime timestamp) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) {
      return l10n.justNow;
    } else if (diff.inHours < 1) {
      return l10n.minutesAgo(diff.inMinutes);
    } else if (diff.inDays < 1) {
      return l10n.hoursAgo(diff.inHours);
    } else if (diff.inDays < 7) {
      return l10n.daysAgo(diff.inDays);
    } else {
      return '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
    }
  }
}