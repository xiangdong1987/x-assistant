import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/websocket_service.dart';

class StatusIndicator extends ConsumerStatefulWidget {
  const StatusIndicator({super.key});

  @override
  ConsumerState<StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends ConsumerState<StatusIndicator> {
  ConnectionStatus _status = ConnectionStatus.disconnected;
  StreamSubscription<ConnectionStatus>? _subscription;

  @override
  void initState() {
    super.initState();
    _initStatus();
  }

  void _initStatus() {
    final wsService = ref.read(webSocketServiceProvider);
    _status = wsService.currentStatus;
    _subscription = wsService.connectionStatus.listen((status) {
      if (mounted) {
        setState(() => _status = status);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _StatusContent(status: _status);
  }
}

class _StatusContent extends StatelessWidget {
  final ConnectionStatus status;

  const _StatusContent({required this.status});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusDot(status: status),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'xassistant',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              _statusText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _statusColor,
                  ),
            ),
          ],
        ),
      ],
    );
  }

  String get _statusText {
    switch (status) {
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.connecting:
        return 'Connecting...';
      case ConnectionStatus.disconnected:
        return 'Disconnected';
      case ConnectionStatus.reconnecting:
        return 'Reconnecting...';
      case ConnectionStatus.error:
        return 'Connection Error';
    }
  }

  Color get _statusColor {
    switch (status) {
      case ConnectionStatus.connected:
        return Colors.green;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        return Colors.orange;
      case ConnectionStatus.disconnected:
        return Colors.grey;
      case ConnectionStatus.error:
        return Colors.red;
    }
  }
}

class _StatusDot extends StatefulWidget {
  final ConnectionStatus status;

  const _StatusDot({required this.status});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _animation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _updateAnimation();
  }

  @override
  void didUpdateWidget(_StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAnimation();
  }

  void _updateAnimation() {
    if (widget.status == ConnectionStatus.connecting ||
        widget.status == ConnectionStatus.reconnecting) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _color {
    switch (widget.status) {
      case ConnectionStatus.connected:
        return Colors.green;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        return Colors.orange;
      case ConnectionStatus.disconnected:
        return Colors.grey;
      case ConnectionStatus.error:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final isAnimating = widget.status == ConnectionStatus.connecting ||
            widget.status == ConnectionStatus.reconnecting;
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isAnimating ? _color.withAlpha((255 * _animation.value).toInt()) : _color,
            boxShadow: widget.status == ConnectionStatus.connected
                ? [
                    BoxShadow(
                      color: _color.withAlpha(102),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}
