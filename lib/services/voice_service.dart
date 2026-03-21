import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'connection_service.dart';

final _logger = Logger(printer: PrettyPrinter(methodCount: 0, noBoxingByDefault: true));

// ─── State ────────────────────────────────────────────────────────────────────

enum VoiceStatus { idle, connecting, ready, listening, thinking, speaking, error }

class VoiceState {
  final VoiceStatus status;
  final String transcript;      // current STT result
  final String aiText;          // accumulated AI response
  final String? errorMessage;

  const VoiceState({
    this.status = VoiceStatus.idle,
    this.transcript = '',
    this.aiText = '',
    this.errorMessage,
  });

  VoiceState copyWith({
    VoiceStatus? status,
    String? transcript,
    String? aiText,
    String? errorMessage,
  }) =>
      VoiceState(
        status: status ?? this.status,
        transcript: transcript ?? this.transcript,
        aiText: aiText ?? this.aiText,
        errorMessage: errorMessage ?? this.errorMessage,
      );

  bool get isActive => status != VoiceStatus.idle && status != VoiceStatus.error;
}

// ─── Service ──────────────────────────────────────────────────────────────────

class VoiceService extends StateNotifier<VoiceState> {
  VoiceService() : super(const VoiceState());

  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  StreamSubscription<Uint8List>? _recordSub;
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  // TTS audio accumulation
  int _ttsSampleRate = 24000;
  final BytesBuilder _ttsBuffer = BytesBuilder();

  /// Start a voice session connected to the proxy server.
  Future<void> start(ConnectionInfo info) async {
    if (state.isActive) return;

    // Check mic permission via the record package (cross-platform, works on macOS).
    // On macOS the OS will show its own dialog on first access — no pre-request needed.
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      state = state.copyWith(
        status: VoiceStatus.error,
        errorMessage: 'Microphone permission denied',
      );
      return;
    }

    state = state.copyWith(status: VoiceStatus.connecting, transcript: '', aiText: '');

    try {
      final uri = Uri.parse('ws://${info.ip}:${info.port}/voice/ws?token=${info.token}');
      _ws = IOWebSocketChannel.connect(uri);

      _wsSub = _ws!.stream.listen(
        _onMessage,
        onError: (e) {
          _logger.e('[Voice] WebSocket error: $e');
          _handleError('Connection error: $e');
        },
        onDone: () {
          _logger.i('[Voice] WebSocket closed');
          if (state.isActive) _handleError('Connection closed');
        },
      );

      // Send voice_start
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
      _logger.e('[Voice] Connect error: $e');
      _handleError('Failed to connect: $e');
    }
  }

  /// Stop the voice session.
  Future<void> stop() async {
    _sendJson({'type': 'voice_stop', 'payload': {}});
    await _cleanup();
    state = const VoiceState();
  }

  /// Cancel current AI/TTS turn without closing the session.
  void cancel() {
    _sendJson({'type': 'voice_cancel', 'payload': {}});
    state = state.copyWith(status: VoiceStatus.ready);
  }

  // ── Message handling ───────────────────────────────────────────────────────

  void _onMessage(dynamic raw) {
    if (raw is List<int> || raw is Uint8List) {
      // Binary frame = TTS PCM16 audio
      _ttsBuffer.add(raw is Uint8List ? raw : Uint8List.fromList(raw as List<int>));
      return;
    }

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
        _logger.i('[Voice] ready, capabilities=${payload['capabilities']}');
        _startMic();

      case 'voice_vad_start':
        state = state.copyWith(status: VoiceStatus.listening);

      case 'voice_vad_end':
        // Keep listening status until transcript final
        break;

      case 'voice_transcript':
        final text = payload['text'] as String? ?? '';
        final isFinal = payload['is_final'] as bool? ?? false;
        state = state.copyWith(transcript: text);
        if (isFinal) {
          state = state.copyWith(status: VoiceStatus.thinking, aiText: '');
          _stopMic(); // mute mic while AI is thinking/speaking
        }

      case 'voice_ai_start':
        state = state.copyWith(status: VoiceStatus.thinking);

      case 'voice_ai_stream':
        final content = payload['content'] as String? ?? '';
        state = state.copyWith(aiText: state.aiText + content);

      case 'voice_tts_start':
        _ttsSampleRate = (payload['sample_rate'] as num?)?.toInt() ?? 24000;
        _ttsBuffer.clear();
        state = state.copyWith(status: VoiceStatus.speaking);

      case 'voice_tts_end':
        _playTtsBuffer();

      case 'voice_ai_complete':
        final err = payload['error'] as String?;
        if (err != null && err.isNotEmpty) {
          _logger.w('[Voice] AI complete with error: $err');
        }
        // Restart mic after the turn unless TTS is still playing
        if (state.status != VoiceStatus.speaking) {
          _startMic();
          state = state.copyWith(status: VoiceStatus.ready);
        }

      case 'voice_error':
        final message = payload['message'] as String? ?? 'Unknown error';
        _logger.w('[Voice] Server error: $message');
        state = state.copyWith(status: VoiceStatus.error, errorMessage: message);
    }
  }

  // ── Microphone ────────────────────────────────────────────────────────────

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
        if (_ws != null && state.isActive) {
          _ws!.sink.add(chunk);
        }
      });
      _logger.d('[Voice] Mic started');
    } catch (e) {
      _logger.e('[Voice] Mic error: $e');
    }
  }

  Future<void> _stopMic() async {
    await _recordSub?.cancel();
    _recordSub = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    _logger.d('[Voice] Mic stopped');
  }

  // ── TTS playback ──────────────────────────────────────────────────────────

  Future<void> _playTtsBuffer() async {
    final pcmData = _ttsBuffer.takeBytes();
    if (pcmData.isEmpty) {
      _afterTtsComplete();
      return;
    }

    try {
      final wavData = _buildWav(pcmData, _ttsSampleRate);
      final dir = await getTemporaryDirectory();
      await dir.create(recursive: true);
      final file = File('${dir.path}/voice_tts_${DateTime.now().millisecondsSinceEpoch}.wav');
      await file.writeAsBytes(wavData);

      _player.onPlayerComplete.listen((_) => _afterTtsComplete());
      await _player.play(DeviceFileSource(file.path));
      _logger.d('[Voice] TTS playing: ${pcmData.length} bytes PCM, ${_ttsSampleRate}Hz');
    } catch (e) {
      _logger.e('[Voice] TTS playback error: $e');
      _afterTtsComplete();
    }
  }

  void _afterTtsComplete() {
    if (state.isActive) {
      _startMic();
      state = state.copyWith(status: VoiceStatus.ready);
    }
  }

  /// Build a WAV file from raw PCM16 LE mono data.
  Uint8List _buildWav(Uint8List pcm, int sampleRate) {
    const numChannels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    const blockAlign = numChannels * bitsPerSample ~/ 8;
    final dataSize = pcm.length;
    final fileSize = 36 + dataSize;

    final buf = ByteData(44 + dataSize);
    int o = 0;

    // RIFF chunk
    buf.buffer.asUint8List(o, 4).setAll(0, [82, 73, 70, 70]); o += 4; // "RIFF"
    buf.setUint32(o, fileSize, Endian.little); o += 4;
    buf.buffer.asUint8List(o, 4).setAll(0, [87, 65, 86, 69]); o += 4; // "WAVE"

    // fmt sub-chunk
    buf.buffer.asUint8List(o, 4).setAll(0, [102, 109, 116, 32]); o += 4; // "fmt "
    buf.setUint32(o, 16, Endian.little); o += 4;
    buf.setUint16(o, 1, Endian.little); o += 2;  // PCM
    buf.setUint16(o, numChannels, Endian.little); o += 2;
    buf.setUint32(o, sampleRate, Endian.little); o += 4;
    buf.setUint32(o, byteRate, Endian.little); o += 4;
    buf.setUint16(o, blockAlign, Endian.little); o += 2;
    buf.setUint16(o, bitsPerSample, Endian.little); o += 2;

    // data sub-chunk
    buf.buffer.asUint8List(o, 4).setAll(0, [100, 97, 116, 97]); o += 4; // "data"
    buf.setUint32(o, dataSize, Endian.little); o += 4;

    buf.buffer.asUint8List(44).setAll(0, pcm);
    return buf.buffer.asUint8List();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _sendJson(Map<String, dynamic> msg) {
    try {
      _ws?.sink.add(jsonEncode(msg));
    } catch (e) {
      _logger.w('[Voice] send error: $e');
    }
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
    _ttsBuffer.clear();
  }

  @override
  Future<void> dispose() async {
    await _cleanup();
    await _recorder.dispose();
    await _player.dispose();
    super.dispose();
  }
}

// ─── Providers ───────────────────────────────────────────────────────────────

final voiceServiceProvider = StateNotifierProvider<VoiceService, VoiceState>((ref) {
  return VoiceService();
});
