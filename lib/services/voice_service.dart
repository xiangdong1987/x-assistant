import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'connection_service.dart';

final _logger = Logger(printer: PrettyPrinter(methodCount: 0, noBoxingByDefault: true));

// ─── State ────────────────────────────────────────────────────────────────────

enum VoiceStatus { idle, connecting, ready, listening, error }

class VoiceState {
  final VoiceStatus status;
  final String transcript;           // live partial transcript for display
  final String? lastFinalTranscript; // set when a final transcript arrives
  final String? errorMessage;

  const VoiceState({
    this.status = VoiceStatus.idle,
    this.transcript = '',
    this.lastFinalTranscript,
    this.errorMessage,
  });

  VoiceState copyWith({
    VoiceStatus? status,
    String? transcript,
    Object? lastFinalTranscript = _sentinel,
    String? errorMessage,
  }) =>
      VoiceState(
        status: status ?? this.status,
        transcript: transcript ?? this.transcript,
        lastFinalTranscript: lastFinalTranscript == _sentinel
            ? this.lastFinalTranscript
            : lastFinalTranscript as String?,
        errorMessage: errorMessage ?? this.errorMessage,
      );

  bool get isActive => status != VoiceStatus.idle && status != VoiceStatus.error;
}

// Sentinel so copyWith can distinguish "not passed" from "explicitly null"
const _sentinel = Object();

// ─── Service ──────────────────────────────────────────────────────────────────

class VoiceService extends StateNotifier<VoiceState> {
  VoiceService() : super(const VoiceState());

  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  StreamSubscription<Uint8List>? _recordSub;
  final AudioRecorder _recorder = AudioRecorder();

  /// Connect to the voice WebSocket and start dictation.
  Future<void> start(ConnectionInfo info) async {
    if (state.isActive) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      state = state.copyWith(
        status: VoiceStatus.error,
        errorMessage: 'Microphone permission denied',
      );
      return;
    }

    state = state.copyWith(
      status: VoiceStatus.connecting,
      transcript: '',
      lastFinalTranscript: null,
    );

    try {
      final uri = Uri.parse('ws://${info.ip}:${info.port}/voice/ws?token=${info.token}');
      _ws = IOWebSocketChannel.connect(uri);

      _wsSub = _ws!.stream.listen(
        _onMessage,
        onError: (e) => _handleError('Connection error: $e'),
        onDone: () { if (state.isActive) _handleError('Connection closed'); },
      );

      _sendJson({
        'type': 'voice_start',
        'payload': {
          'session_id': 'app_${DateTime.now().millisecondsSinceEpoch}',
          'sample_rate': 16000,
          'language': 'zh-en',
          'speaker_id': 0,
        },
      });
    } catch (e) {
      _handleError('Failed to connect: $e');
    }
  }

  /// Stop dictation and close the session.
  Future<void> stop() async {
    _sendJson({'type': 'voice_stop', 'payload': {}});
    await _cleanup();
    state = const VoiceState();
  }

  // ── Message handling ───────────────────────────────────────────────────────

  void _onMessage(dynamic raw) {
    // Ignore binary frames (no TTS in this mode)
    if (raw is! String) return;

    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = msg['type'] as String? ?? '';
    final payload = msg['payload'] as Map<String, dynamic>? ?? {};

    switch (type) {
      case 'voice_ready':
        state = state.copyWith(status: VoiceStatus.ready);
        _startMic();

      case 'voice_vad_start':
        state = state.copyWith(status: VoiceStatus.listening, transcript: '');

      case 'voice_vad_end':
        state = state.copyWith(status: VoiceStatus.ready);

      case 'voice_transcript':
        final text = payload['text'] as String? ?? '';
        final isFinal = payload['is_final'] as bool? ?? false;
        if (isFinal) {
          _logger.i('[Voice] final transcript: $text');
          state = state.copyWith(
            status: VoiceStatus.ready,
            transcript: '',
            lastFinalTranscript: text,
          );
        } else {
          state = state.copyWith(transcript: text);
        }

      case 'voice_error':
        final message = payload['message'] as String? ?? 'Unknown error';
        _logger.w('[Voice] Server error: $message');
        state = state.copyWith(status: VoiceStatus.error, errorMessage: message);
    }
  }

  // ── Microphone ─────────────────────────────────────────────────────────────

  Future<void> _startMic() async {
    if (await _recorder.isRecording()) return;
    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _recordSub = stream.listen((chunk) {
        if (_ws != null && state.isActive) _ws!.sink.add(chunk);
      });
    } catch (e) {
      _logger.e('[Voice] Mic error: $e');
    }
  }

  Future<void> _stopMic() async {
    await _recordSub?.cancel();
    _recordSub = null;
    if (await _recorder.isRecording()) await _recorder.stop();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _sendJson(Map<String, dynamic> msg) {
    try { _ws?.sink.add(jsonEncode(msg)); } catch (_) {}
  }

  void _handleError(String message) {
    _cleanup();
    state = state.copyWith(status: VoiceStatus.error, errorMessage: message);
  }

  Future<void> _cleanup() async {
    await _stopMic();
    await _wsSub?.cancel();
    _wsSub = null;
    await _ws?.sink.close();
    _ws = null;
  }

  @override
  Future<void> dispose() async {
    await _cleanup();
    await _recorder.dispose();
    super.dispose();
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final voiceServiceProvider = StateNotifierProvider<VoiceService, VoiceState>((ref) {
  return VoiceService();
});
