import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/connection_service.dart';
import '../../services/voice_service.dart';

/// Microphone button that streams speech to the server and fills the text
/// field with the final transcript via [VoiceService].
///
/// States:
///   Idle       → grey mic icon
///   Connecting → spinner
///   Ready      → mic icon (accent color)
///   Listening  → pulsing red mic
///   Error      → red mic_off icon (tap to dismiss)
class VoiceButton extends ConsumerWidget {
  const VoiceButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voiceState = ref.watch(voiceServiceProvider);
    final voice = ref.read(voiceServiceProvider.notifier);
    final connAsync = ref.watch(savedConnectionProvider);

    return connAsync.when(
      loading: () => const SizedBox(width: 48, height: 48),
      error: (_, __) => const SizedBox.shrink(),
      data: (info) {
        if (info == null) return const SizedBox.shrink();
        return _VoiceButtonCore(
          state: voiceState,
          onToggle: () async {
            if (voiceState.isActive) {
              await voice.stop();
            } else {
              await voice.start(info);
            }
          },
        );
      },
    );
  }
}

class _VoiceButtonCore extends StatefulWidget {
  final VoiceState state;
  final VoidCallback onToggle;

  const _VoiceButtonCore({required this.state, required this.onToggle});

  @override
  State<_VoiceButtonCore> createState() => _VoiceButtonCoreState();
}

class _VoiceButtonCoreState extends State<_VoiceButtonCore>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final colorScheme = Theme.of(context).colorScheme;

    if (s.status == VoiceStatus.connecting) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    if (s.status == VoiceStatus.listening) {
      return AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) => IconButton(
          iconSize: 26,
          tooltip: s.transcript.isNotEmpty ? s.transcript : 'Listening…',
          onPressed: widget.onToggle,
          icon: Icon(
            Icons.mic,
            color: Color.lerp(Colors.red, Colors.red.shade200, _pulse.value),
          ),
        ),
      );
    }

    if (s.status == VoiceStatus.ready) {
      return IconButton(
        iconSize: 26,
        tooltip: 'Listening (tap to stop)',
        onPressed: widget.onToggle,
        icon: Icon(Icons.mic, color: colorScheme.primary),
      );
    }

    // Idle or error
    return IconButton(
      iconSize: 26,
      tooltip: s.status == VoiceStatus.error
          ? (s.errorMessage ?? 'Voice error — tap to retry')
          : 'Start voice input',
      onPressed: widget.onToggle,
      icon: Icon(
        s.status == VoiceStatus.error ? Icons.mic_off : Icons.mic_none,
        color: s.status == VoiceStatus.error ? Colors.red : null,
      ),
    );
  }
}

/// Inline partial transcript shown above the input field while listening.
class VoiceStatusSheet extends ConsumerWidget {
  const VoiceStatusSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(voiceServiceProvider);
    if (!s.isActive) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final text = s.transcript.isNotEmpty
        ? s.transcript
        : switch (s.status) {
            VoiceStatus.ready     => '等待说话…',
            VoiceStatus.listening => '正在聆听…',
            _                     => '',
          };

    if (text.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outline.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(Icons.mic, size: 14, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: s.transcript.isNotEmpty
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
