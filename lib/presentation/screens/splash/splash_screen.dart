import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/connection_service.dart';
import '../../../services/websocket_service.dart';
import '../../../providers/task_provider.dart';
import '../../../providers/skill_provider.dart';
import '../../../providers/project_provider.dart' as project_prov;
import '../../../providers/capability_provider.dart' as capability_prov;

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _checkConnectionAndNavigate();
  }

  Future<void> _checkConnectionAndNavigate() async {
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    setState(() => _status = 'Checking connection...');

    try {
      final connectionService = ref.read(connectionServiceProvider);
      final savedConnection = await connectionService.loadSavedConnection();

      if (savedConnection != null) {
        setState(() => _status = 'Connecting to ${savedConnection.ip}...');

        // Check if server is still reachable
        final isReachable = await connectionService.checkHealth(
          savedConnection.ip,
          savedConnection.port,
        );

        if (isReachable) {
          // Set up auth error handler
          final wsService = ref.read(webSocketServiceProvider);
          wsService.onAuthError = () async {
            if (savedConnection.pin != null) {
              setState(() => _status = 'Token expired, re-pairing...');
              final success = await _rePairAndConnect(savedConnection);
              if (!success && mounted) {
                context.goNamed('pairing');
              }
            } else {
              await connectionService.disconnect();
              if (mounted) {
                context.goNamed('pairing');
              }
            }
          };

          // Try initial connection
          await wsService.connect(savedConnection.wsUrl, savedConnection.token);

          // Wait a moment to see if connection succeeds
          await Future.delayed(const Duration(milliseconds: 800));

          if (!mounted) return;

          if (wsService.currentStatus == ConnectionStatus.connected) {
            _refreshAll(ref);
            context.goNamed('dashboard');
            return;
          } else if (wsService.currentStatus == ConnectionStatus.error) {
            // If it failed and we have a PIN, try re-pairing immediately
            if (savedConnection.pin != null) {
              setState(() => _status = 'Connection failed, attempting re-pair...');
              final success = await _rePairAndConnect(savedConnection);
              if (success && mounted) {
                context.goNamed('dashboard');
                return;
              }
            }
            
            setState(() => _status = 'Connection failed, please pair again');
            await connectionService.disconnect();
            await Future.delayed(const Duration(seconds: 1));
            if (mounted) {
              context.goNamed('pairing');
            }
            return;
          }

          // Still connecting (maybe slow), go anyway and UI will show status
          _refreshAll(ref);
          context.goNamed('dashboard');
          return;
        } else {
          // Server not reachable
          if (!mounted) return;
          // On macOS: 进入设置 Tab（保留底部导航），该 Tab 内会先展示代理配置页
          if (Platform.isMacOS) {
            context.goNamed('settingsTab');
            return;
          }
          context.goNamed('pairing');
          return;
        }
      }
    } catch (e) {
      final connectionService = ref.read(connectionServiceProvider);
      await connectionService.disconnect();
    }

    if (!mounted) return;
    context.goNamed('pairing');
  }

  Future<bool> _rePairAndConnect(ConnectionInfo info) async {
    try {
      final connectionService = ref.read(connectionServiceProvider);
      final wsService = ref.read(webSocketServiceProvider);
      
      // Get device ID
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('device_id') ?? 'unknown-device';

      // Re-pair using stored PIN
      final newInfo = await connectionService.pair(
        ip: info.ip,
        port: info.port,
        pin: info.pin!,
        deviceName: info.deviceName,
        deviceId: deviceId,
      );

      // Try connecting with new token
      await wsService.connect(newInfo.wsUrl, newInfo.token);
      
      // Wait for success
      await Future.delayed(const Duration(milliseconds: 1000));
      if (wsService.currentStatus == ConnectionStatus.connected) {
        _refreshAll(ref);
        return true;
      }
    } catch (e) {
      debugPrint('Re-pairing failed: $e');
    }
    return false;
  }

  void _refreshAll(WidgetRef ref) {
    ref.invalidate(savedConnectionProvider);
    ref.invalidate(connectionInfoProvider);
    ref.invalidate(skillsProvider);
    ref.invalidate(skillPathsProvider);
    ref.invalidate(project_prov.projectsProvider);
    ref.invalidate(capability_prov.capabilityProjectsProvider);
    ref.invalidate(taskNotifierProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App icon
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.smart_toy,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'xassistant',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'AI Assistant for xassistant',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _status,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
