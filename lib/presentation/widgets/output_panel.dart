import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../l10n/app_localizations.dart';
import '../screens/main/main_screen.dart';
import 'code_element_builder.dart';

class OutputPanel extends StatelessWidget {
  final List<Message> messages;
  final ScrollController? scrollController;
  final Future<void> Function(String)? onSpeak;

  const OutputPanel({
    super.key,
    required this.messages,
    this.scrollController,
    this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Type a message below to start',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return _MessageBubble(
          message: message,
          onSpeak: onSpeak,
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final Future<void> Function(String)? onSpeak;

  const _MessageBubble({
    required this.message,
    this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final isStreaming = message.status == MessageStatus.streaming;
    final isPending = message.status == MessageStatus.pending;
    final isError = message.status == MessageStatus.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isUser) ...[
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.smart_toy,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'xassistant',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (isStreaming) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ],
              if (isUser) ...[
                Text(
                  'You',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 12,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(
                    Icons.person,
                    size: 16,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Text(
                _formatTime(message.timestamp),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Message content
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isUser
                  ? colorScheme.primaryContainer
                  : isError
                      ? Colors.red.shade50
                      : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isUser ? 16 : 4),
                topRight: Radius.circular(isUser ? 4 : 16),
                bottomLeft: const Radius.circular(16),
                bottomRight: const Radius.circular(16),
              ),
              border: isError
                  ? Border.all(color: Colors.red.shade200)
                  : null,
            ),
            child: _buildContent(context, colorScheme, isUser, isPending),
          ),

          // Action buttons for Claude messages
          if (!isUser && !isPending && message.content.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionButton(
                  icon: Icons.copy,
                  label: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: message.content));
                    final l10n = AppLocalizations.of(context)!;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.copiedToClipboardShort),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                if (onSpeak != null) ...[
                  const SizedBox(width: 8),
                  _ActionButton(
                    icon: Icons.volume_up,
                    label: 'Read',
                    onPressed: () => onSpeak!(message.content),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ColorScheme colorScheme,
    bool isUser,
    bool isPending,
  ) {
    if (isPending) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Thinking...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      );
    }

    if (message.content.isEmpty) {
      return Text(
        'No response',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
      );
    }

    final textColor = isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurface;

    return MarkdownBody(
      data: message.content,
      selectable: true,
      builders: {
        'code': CodeElementBuilder(context),
      },
      styleSheet: MarkdownStyleSheet(
        p: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: textColor,
              height: 1.5,
            ),
        listBullet: TextStyle(color: textColor),
        h1: Theme.of(context).textTheme.titleLarge?.copyWith(color: textColor, fontWeight: FontWeight.bold),
        h2: Theme.of(context).textTheme.titleMedium?.copyWith(color: textColor, fontWeight: FontWeight.bold),
        h3: Theme.of(context).textTheme.titleSmall?.copyWith(color: textColor, fontWeight: FontWeight.bold),
        code: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              backgroundColor: Colors.transparent, // background handled by builder
            ),
        codeblockDecoration: BoxDecoration(
          color: Colors.transparent, // background handled by builder
        ),
        blockquoteDecoration: BoxDecoration(
          color: colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(4),
          border: Border(left: BorderSide(color: colorScheme.primary, width: 4)),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
