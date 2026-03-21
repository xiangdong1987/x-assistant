import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

import '../../../services/websocket_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/command_parser.dart';
import '../../../services/chat_history_storage.dart';
import '../../../models/chat_history_model.dart';
import '../../../providers/task_provider.dart';
import '../../../providers/skill_provider.dart';
import '../../widgets/output_panel.dart';
import '../../widgets/status_indicator.dart';
import '../../widgets/voice_button.dart';
import '../../../services/voice_service.dart';

final _logger = Logger(printer: PrettyPrinter(methodCount: 0, noBoxingByDefault: true));

// Message model
class Message {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final MessageStatus status;
  final ResponseAnalysis? analysis;

  Message({
    String? id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.status = MessageStatus.complete,
    this.analysis,
  }) : id = id ?? const Uuid().v4();

  Message copyWith({
    String? content,
    MessageStatus? status,
    ResponseAnalysis? analysis,
  }) {
    return Message(
      id: id,
      content: content ?? this.content,
      isUser: isUser,
      timestamp: timestamp,
      status: status ?? this.status,
      analysis: analysis ?? this.analysis,
    );
  }
}

enum MessageStatus { pending, streaming, complete, error }

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Message> _messages = [];
  final Map<String, String> _pendingCommands = {};
  final FlutterTts _tts = FlutterTts();

  StreamSubscription<Map<String, dynamic>>? _messageSubscription;
  StreamSubscription<ConnectionStatus>? _statusSubscription;
  bool _isProcessing = false;
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  bool _openclawConnected = true;
  String? _openclawError;
  ResponseAnalysis? _lastResponseAnalysis;
  bool _ttsAvailable = false;

  Future<void> _writeLog(String message) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/xassistant_crash_log.txt');
      final timestamp = DateTime.now().toIso8601String();
      await file.writeAsString('[$timestamp] $message\n', mode: FileMode.append);
      _logger.d('Log written to ${file.path}');
    } catch (e) {
      _logger.e('Failed to write log', error: e);
    }
  }

  @override
  void initState() {
    super.initState();
    _logger.d('MainScreen initState called');
    _writeLog('MainScreen initState called');
    // _initTts(); // Will initialize lazily when speaking
    try {
      _setupWebSocketListener();
    } catch (e, stack) {
      _logger.e('Error in _setupWebSocketListener', error: e, stackTrace: stack);
      _writeLog('Error in _setupWebSocketListener: $e\n$stack');
    }
    try {
      _setupStatusListener();
    } catch (e, stack) {
      _logger.e('Error in _setupStatusListener', error: e, stackTrace: stack);
      _writeLog('Error in _setupStatusListener: $e\n$stack');
    }
    // Load chat history from local storage
    _loadChatHistory();
  }

  // Load chat history from local storage
  Future<void> _loadChatHistory() async {
    try {
      final storage = ref.read(chatHistoryStorageProvider);
      final latest = storage.getLatest();
      if (latest != null && latest.messages.isNotEmpty) {
        // Convert stored ChatMessage to local Message
        final messages = latest.messages
            .map((m) => Message(
                  id: m.id,
                  content: m.content,
                  isUser: m.isUser,
                  timestamp: m.timestamp,
                  status: MessageStatus.complete,
                ))
            .toList();

        if (mounted) {
          setState(() {
            _messages.clear();
            _messages.addAll(messages);
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      _logger.e('Error loading chat history', error: e);
    }
  }

  // Save current messages to local storage
  Future<void> _saveToHistory() async {
    if (_messages.isEmpty) return;

    try {
      final storage = ref.read(chatHistoryStorageProvider);
      final chatMessages = _messages
          .map((m) => ChatMessage(
                id: m.id,
                content: m.content,
                isUser: m.isUser,
                timestamp: m.timestamp,
              ))
          .toList();

      final conversation = ChatHistoryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        messages: chatMessages,
        createdAt: chatMessages.first.timestamp,
        updatedAt: DateTime.now(),
        skillId: ref.read(selectedSkillProvider)?.id,
      );

      await storage.save(conversation);
    } catch (e) {
      _logger.e('Error saving chat history', error: e);
    }
  }

  void _setupStatusListener() {
    _logger.d('MainScreen _setupStatusListener started');
    final wsService = ref.read(webSocketServiceProvider);
    _connectionStatus = wsService.currentStatus;
    _statusSubscription = wsService.connectionStatus.listen((status) {
      if (mounted) {
        setState(() => _connectionStatus = status);
        // History is local-only; do not request OpenClaw chat.history on connect.
      }
    });
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(0.5);
      if (mounted) setState(() => _ttsAvailable = true);
    } catch (e) {
      // TTS may be unavailable on some platforms; hide Read button
      if (mounted) setState(() => _ttsAvailable = false);
    }
  }

  void _setupWebSocketListener() {
    _logger.d('MainScreen _setupWebSocketListener started');
    final wsService = ref.read(webSocketServiceProvider);
    _messageSubscription = wsService.messages.listen(_handleWebSocketMessage);
  }

  void _handleWebSocketMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;

    switch (type) {
      case 'ack':
        break;

      case 'stream':
        final payload = message['payload'] as Map<String, dynamic>?;
        if (payload != null) {
          final commandId = payload['command_id'] as String?;
          final content = payload['content'] as String?;

          if (commandId != null && content != null) {
            _handleStreamContent(commandId, content);
          }
        }
        break;

      case 'complete':
        final payload = message['payload'] as Map<String, dynamic>?;
        if (payload != null) {
          final commandId = payload['command_id'] as String?;
          final status = payload['status'] as String?;
          final error = payload['error'] as String?;

          if (commandId != null) {
            _handleCommandComplete(commandId, status, error);
          }
        }
        break;

      case 'error':
        final payload = message['payload'] as Map<String, dynamic>?;
        final errorMsg = payload?['message'] as String? ?? 'Unknown error';
        _showError(errorMsg);
        break;

      case 'openclaw_status':
        final payload = message['payload'] as Map<String, dynamic>?;
        if (payload != null && mounted) {
          setState(() {
            _openclawConnected = payload['connected'] as bool? ?? false;
            _openclawError = payload['error'] as String?;
          });
        }
        break;

      case 'chat_history':
        // History is local-only; ignore OpenClaw chat.history payload for main screen.
        break;
    }
  }

  void _handleStreamContent(String commandId, String content) {
    setState(() {
      String? messageId = _pendingCommands[commandId];
      
      // If server pushed a stream we didn't explicitly request, create a message for it
      if (messageId == null) {
        messageId = const Uuid().v4();
        _pendingCommands[commandId] = messageId;
        _messages.add(Message(
          id: messageId,
          content: '',
          isUser: false,
          timestamp: DateTime.now(),
          status: MessageStatus.streaming,
        ));
      }

      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          content: content,
          status: MessageStatus.streaming,
        );
      }
    });
    _scrollToBottom();
  }

  void _handleCommandComplete(String commandId, String? status, String? error) {
    setState(() {
      final messageId = _pendingCommands.remove(commandId);
      if (messageId != null) {
        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          final content = error != null && error.isNotEmpty
              ? '${_messages[index].content}\n\nError: $error'
              : _messages[index].content;

          // 分析响应内容
          final analysis = ResponseParser.analyzeResponse(content);
          _lastResponseAnalysis = analysis;

          _messages[index] = _messages[index].copyWith(
            status: status == 'error' ? MessageStatus.error : MessageStatus.complete,
            content: content,
            analysis: analysis,
          );
        }
      }
      _isProcessing = false;
    });
    if (mounted && error != null && error.contains('conversation_busy')) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.waitForConversation)),
      );
    }
    // Save chat history after command completes
    _saveToHistory();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _statusSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _tts.stop();
    super.dispose();
  }

  void _sendQuickResponse(String response) {
    _sendMessage(response);
  }

  String? _lastUserMessage;

  void _retryLastCommand() {
    if (_lastUserMessage != null) {
      _sendMessage(_lastUserMessage!);
    }
  }

  void _sendMessage(String text) {
    final wsService = ref.read(webSocketServiceProvider);

    if (wsService.currentStatus != ConnectionStatus.connected) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.notConnectedToServer),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_isProcessing) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.waitForConversation)),
      );
      return;
    }

    _lastUserMessage = text;
    final commandId = const Uuid().v4();
    final responseMessageId = const Uuid().v4();

    setState(() {
      _messages.add(Message(
        content: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));

      _messages.add(Message(
        id: responseMessageId,
        content: '',
        isUser: false,
        timestamp: DateTime.now(),
        status: MessageStatus.pending,
      ));

      _pendingCommands[commandId] = responseMessageId;
      _isProcessing = true;
      _lastResponseAnalysis = null;
    });

    _textController.clear();
    _scrollToBottom();

    wsService.sendCommand(commandId, text, skill: ref.read(selectedSkillProvider)?.id);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _cancelCurrentCommand() {
    final wsService = ref.read(webSocketServiceProvider);
    for (final commandId in _pendingCommands.keys) {
      wsService.cancelCommand(commandId);
    }
    setState(() {
      _isProcessing = false;
    });
  }

  bool _ttsInitialized = false;
  Future<void> _speakMessage(String text) async {
    if (text.isEmpty) return;
    
    if (!_ttsInitialized) {
      await _initTts();
    }
    
    if (!_ttsAvailable) return;
    await _tts.speak(text);
  }

  // Track last voice state to detect turn completion
  String _lastVoiceTranscript = '';
  String _lastVoiceAiText = '';

  void _onVoiceStateChanged(VoiceState? prev, VoiceState next) {
    // Capture transcript as it comes in
    if (next.transcript.isNotEmpty) {
      _lastVoiceTranscript = next.transcript;
    }
    if (next.aiText.isNotEmpty) {
      _lastVoiceAiText = next.aiText;
    }

    // When a turn completes (status goes from thinking/speaking back to ready/idle),
    // flush the turn into the chat message list.
    final wasActive = prev != null &&
        (prev.status == VoiceStatus.thinking ||
            prev.status == VoiceStatus.speaking);
    final isSettling = next.status == VoiceStatus.ready ||
        next.status == VoiceStatus.idle ||
        next.status == VoiceStatus.error;

    if (wasActive && isSettling && _lastVoiceTranscript.isNotEmpty) {
      final userText = _lastVoiceTranscript;
      final aiText = _lastVoiceAiText;
      _lastVoiceTranscript = '';
      _lastVoiceAiText = '';

      setState(() {
        _messages.add(Message(
          content: userText,
          isUser: true,
          timestamp: DateTime.now(),
          status: MessageStatus.complete,
        ));
        if (aiText.isNotEmpty) {
          _messages.add(Message(
            content: aiText,
            isUser: false,
            timestamp: DateTime.now(),
            status: MessageStatus.complete,
          ));
        }
      });
      _scrollToBottom();
      _saveToHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for voice turn completion and push messages into chat
    ref.listen<VoiceState>(voiceServiceProvider, _onVoiceStateChanged);

    return Scaffold(
      appBar: AppBar(
        title: const StatusIndicator(),
        actions: [
          if (_isProcessing)
            IconButton(
              icon: const Icon(Icons.stop_circle, color: Colors.red),
              onPressed: _cancelCurrentCommand,
              tooltip: AppLocalizations.of(context)?.cancelTooltip ?? 'Cancel',
            ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => context.pushNamed('history'),
            tooltip: AppLocalizations.of(context)?.historyTooltip ?? 'History',
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection status banner
          if (_connectionStatus == ConnectionStatus.disconnected ||
              _connectionStatus == ConnectionStatus.error)
            _ConnectionBanner(status: _connectionStatus),

          // OpenClaw backend status (when WS connected but agent backend is not)
          if (_connectionStatus == ConnectionStatus.connected &&
              !_openclawConnected)
            _OpenClawStatusBanner(
              error: _openclawError,
            ),

          // Output panel
          Expanded(
            child: OutputPanel(
              messages: _messages,
              scrollController: _scrollController,
              onSpeak: _ttsAvailable ? _speakMessage : null,
            ),
          ),

          // Quick response buttons (when Claude asks a question)
          if (_lastResponseAnalysis != null && !_isProcessing)
            _QuickResponsePanel(
              analysis: _lastResponseAnalysis!,
              onResponse: _sendQuickResponse,
            ),

          // Divider
          const Divider(height: 1),

          // Input area
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Voice status panel (shown while voice session is active)
                  Consumer(
                    builder: (context, ref, _) {
                      final voiceState = ref.watch(voiceServiceProvider);
                      if (!voiceState.isActive) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: VoiceStatusSheet(),
                      );
                    },
                  ),

                  // Selected skill chip
                  Consumer(
                    builder: (context, ref, _) {
                      final selectedSkill = ref.watch(selectedSkillProvider);
                      if (selectedSkill == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Chip(
                          avatar: const Icon(Icons.auto_awesome, size: 16),
                          label: Text(selectedSkill.name),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () {
                            ref.read(selectedSkillProvider.notifier).state = null;
                          },
                        ),
                      );
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          decoration: InputDecoration(
                            hintText: AppLocalizations.of(context)?.typeCommand ?? 'Type a command...',
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.send),
                              onPressed: _isProcessing
                                  ? null
                                  : () {
                                      if (_textController.text.isNotEmpty) {
                                        _sendMessage(_textController.text);
                                      }
                                    },
                            ),
                          ),
                          enabled: !_isProcessing,
                          onSubmitted: (text) {
                            if (text.isNotEmpty && !_isProcessing) {
                              _sendMessage(text);
                            }
                          },
                        ),
                      ),
                      const VoiceButton(),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Quick actions
                  Builder(
                    builder: (context) {
                      final l10n = AppLocalizations.of(context)!;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _QuickActionChip(
                            label: l10n.fixErrors,
                            onTap: _isProcessing
                                ? null
                                : () => _sendMessage(l10n.fixErrorsCommand),
                          ),
                          _QuickActionChip(
                            label: l10n.runTests,
                            onTap: _isProcessing
                                ? null
                                : () => _sendMessage(l10n.runTestsCommand),
                          ),
                          _QuickActionChip(
                            label: l10n.explainCode,
                            onTap: _isProcessing
                                ? null
                                : () => _sendMessage(l10n.explainCodeCommand),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick response panel - shows when Claude asks a question
class _QuickResponsePanel extends StatelessWidget {
  final ResponseAnalysis analysis;
  final void Function(String) onResponse;

  const _QuickResponsePanel({
    required this.analysis,
    required this.onResponse,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withAlpha(50),
        border: Border(
          top: BorderSide(color: colorScheme.outline.withAlpha(50)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.help_outline,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!.quickResponse,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _buildResponseButtons(context),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildResponseButtons(BuildContext context) {
    final buttons = <Widget>[];

    switch (analysis.type) {
      case ResponseType.question:
      case ResponseType.confirmation:
        final l10n = AppLocalizations.of(context)!;
        buttons.addAll([
          _ResponseButton(
            label: l10n.yes,
            icon: Icons.check,
            color: Colors.green,
            onTap: () => onResponse('yes'),
          ),
          _ResponseButton(
            label: l10n.no,
            icon: Icons.close,
            color: Colors.red,
            onTap: () => onResponse('no'),
          ),
        ]);
        break;

      case ResponseType.options:
        for (int i = 0; i < analysis.options.length && i < 5; i++) {
          final option = analysis.options[i];
          buttons.add(
            _ResponseButton(
              label: '${i + 1}. ${option.length > 20 ? '${option.substring(0, 20)}...' : option}',
              onTap: () => onResponse('${i + 1}'),
            ),
          );
        }
        break;

      case ResponseType.error:
        buttons.add(
          _ResponseButton(
            label: AppLocalizations.of(context)!.retry,
            icon: Icons.refresh,
            onTap: () => onResponse('retry'),
          ),
        );
        break;

      default:
        break;
    }

    return buttons;
  }
}

class _ResponseButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;
  final VoidCallback onTap;

  const _ResponseButton({
    required this.label,
    this.icon,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: icon != null ? Icon(icon, size: 18, color: color) : const SizedBox.shrink(),
      label: Text(label),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  final ConnectionStatus status;

  const _ConnectionBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: status == ConnectionStatus.error
          ? Colors.red.shade100
          : Colors.orange.shade100,
      child: Row(
        children: [
          Icon(
            status == ConnectionStatus.error ? Icons.error : Icons.warning,
            size: 20,
            color: status == ConnectionStatus.error
                ? Colors.red.shade700
                : Colors.orange.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status == ConnectionStatus.error
                  ? (AppLocalizations.of(context)?.connectionError ?? 'Connection error.')
                  : (AppLocalizations.of(context)?.disconnectedFromServer ?? 'Disconnected.'),
              style: TextStyle(
                color: status == ConnectionStatus.error
                    ? Colors.red.shade700
                    : Colors.orange.shade700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => context.goNamed('pairing'),
            child: Text(AppLocalizations.of(context)?.reconnect ?? 'Reconnect'),
          ),
        ],
      ),
    );
  }
}

class _OpenClawStatusBanner extends StatelessWidget {
  final String? error;

  const _OpenClawStatusBanner({this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.amber.shade100,
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 18, color: Colors.amber.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error != null && error!.isNotEmpty
                  ? AppLocalizations.of(context)!.agentBackendError(error!)
                  : AppLocalizations.of(context)!.agentBackendDisconnected,
              style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _QuickActionChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
    );
  }
}
