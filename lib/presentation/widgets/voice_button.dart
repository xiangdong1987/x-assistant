import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/connection_service.dart';
import '../../services/voice_service.dart';

/// Animated microphone button that controls the server-side voice pipeline.
///
/// - Idle:      grey mic icon
/// - Connecting: spinner
/// - Ready/Listening: pulsing red mic
/// - Thinking:  pulsing blue AI icon
/// - Speaking:  pulsing purple speaker icon
/// - Error:     red warning icon (tap to retry/dismiss)
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
          onCancel: voice.cancel,
        );
      },
    );
  }
}

class _VoiceButtonCore extends StatefulWidget {
  final VoiceState state;
  final VoidCallback onToggle;
  final VoidCallback onCancel;

  const _VoiceButtonCore({
    required this.state,
    required this.onToggle,
    required this.onCancel,
  });

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
      duration: const Duration(milliseconds: 900),
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

    // Connecting: spinner
    if (s.status == VoiceStatus.connecting) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    // Active session: show inline info panel + mic/cancel button
    if (s.isActive) {
      return _ActivePanel(
        state: s,
        pulse: _pulse,
        onStop: widget.onToggle,
        onCancel: widget.onCancel,
      );
    }

    // Idle / error: just the mic button
    return IconButton(
      iconSize: 26,
      tooltip: s.status == VoiceStatus.error ? (s.errorMessage ?? 'Voice error') : 'Start voice',
      onPressed: widget.onToggle,
      icon: Icon(
        s.status == VoiceStatus.error ? Icons.mic_off : Icons.mic_none,
        color: s.status == VoiceStatus.error ? Colors.red : null,
      ),
    );
  }
}

class _ActivePanel extends StatelessWidget {
  final VoiceState state;
  final Animation<double> pulse;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  const _ActivePanel({
    required this.state,
    required this.pulse,
    required this.onStop,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final (icon, color, tip) = switch (state.status) {
      VoiceStatus.listening => (Icons.mic, Colors.red, 'Listening…'),
      VoiceStatus.thinking  => (Icons.auto_awesome, colorScheme.primary, 'Thinking…'),
      VoiceStatus.speaking  => (Icons.volume_up, Colors.purple, 'Speaking…'),
      _                     => (Icons.mic, Colors.grey, 'Ready'),
    };

    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final scale = state.status == VoiceStatus.listening || state.status == VoiceStatus.speaking
            ? 1.0 + pulse.value * 0.2
            : 1.0;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing status icon
            GestureDetector(
              onTap: state.status == VoiceStatus.thinking || state.status == VoiceStatus.speaking
                  ? onCancel
                  : null,
              child: Tooltip(
                message: tip,
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Stop button
            IconButton(
              iconSize: 20,
              tooltip: 'Stop voice',
              onPressed: onStop,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
          ],
        );
      },
    );
  }
}

/// A bottom sheet (or modal) that shows live transcript + AI text during a session.
class VoiceStatusSheet extends ConsumerWidget {
  const VoiceStatusSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(voiceServiceProvider);
    if (!s.isActive) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s.transcript.isNotEmpty) ...[
            Text(
              'You: ${s.transcript}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (s.aiText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              s.aiText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (s.transcript.isEmpty && s.aiText.isEmpty) ...[
            Row(
              children: [
                Icon(Icons.mic, size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  _statusLabel(s.status),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _statusLabel(VoiceStatus status) => switch (status) {
        VoiceStatus.ready      => 'Waiting for speech…',
        VoiceStatus.listening  => 'Listening…',
        VoiceStatus.thinking   => 'Processing…',
        VoiceStatus.speaking   => 'Speaking…',
        _                      => '',
      };
}
