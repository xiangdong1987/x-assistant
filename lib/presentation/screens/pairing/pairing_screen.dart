import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../services/connection_service.dart';
import '../../../services/websocket_service.dart';
import '../../../providers/task_provider.dart';
import '../../../providers/skill_provider.dart';
import '../../../providers/project_provider.dart' as project_prov;
import '../../../providers/capability_provider.dart' as capability_prov;
import '../../../l10n/app_localizations.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(text: '8443');
  final TextEditingController _pinController = TextEditingController();
  bool _isConnecting = false;
  String? _errorMessage;
  bool _hasScanned = false;

  static const _deviceIdKey = 'device_id';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    try {
      await Permission.camera.request();
    } on MissingPluginException catch (_) {
      // permission_handler 仅在 iOS/Android 注册了 method channel，macOS/桌面端会抛此异常，忽略即可
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, deviceId);
    }
    return deviceId;
  }

  void _onQRCodeScanned(String code) {
    if (_hasScanned || _isConnecting) return;

    final uri = Uri.tryParse(code);
    if (uri != null && uri.scheme == 'claude-voice') {
      final ip = uri.queryParameters['ip'];
      final port = uri.queryParameters['port'] ?? '8443';
      final pin = uri.queryParameters['pin'];

      if (ip != null && pin != null) {
        _hasScanned = true;
        _connect(ip, int.parse(port), pin);
      }
    }
  }

  Future<void> _connect(String ip, int port, String pin) async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      final connectionService = ref.read(connectionServiceProvider);
      final deviceId = await _getOrCreateDeviceId();

      // First check if server is reachable
      final isReachable = await connectionService.checkHealth(ip, port);
      if (!isReachable) {
        throw Exception('Cannot reach server at $ip:$port');
      }

      // Pair with server
      final connectionInfo = await connectionService.pair(
        ip: ip,
        port: port,
        pin: pin,
        deviceName: 'Flutter App',
        deviceId: deviceId,
      );

      // Connect WebSocket
      final wsService = ref.read(webSocketServiceProvider);
      await wsService.connect(connectionInfo.wsUrl, connectionInfo.token);

      if (!mounted) return;

      // 连接成功后刷新技能和项目数据
      ref.invalidate(savedConnectionProvider);
      ref.invalidate(connectionInfoProvider);
      ref.invalidate(skillsProvider);
      ref.invalidate(skillPathsProvider);
      ref.invalidate(project_prov.projectsProvider);
      ref.invalidate(capability_prov.capabilityProjectsProvider);
      ref.invalidate(taskNotifierProvider);

      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.connectionSuccess),
          backgroundColor: Colors.green,
        ),
      );

      context.goNamed('dashboard');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _hasScanned = false;
      });
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.connectionFailed(_errorMessage ?? '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.connectToComputer),
        actions: [
          if (Platform.isMacOS)
            Tooltip(
              message: l10n.startProxyFirst,
              child: TextButton.icon(
                onPressed: () => context.goNamed('settingsTab'),
                icon: const Icon(Icons.dns, size: 20),
                label: Text(l10n.proxyConfigNav),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l10n.manualProxyUrl,
            onPressed: () => _showManualProxyDialog(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: const Icon(Icons.qr_code_scanner), text: l10n.scanQr),
            Tab(icon: const Icon(Icons.keyboard), text: l10n.manual),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildQRScannerTab(context, l10n),
          _buildManualInputTab(context, l10n),
        ],
      ),
    );
  }

  Widget _buildQRScannerTab(BuildContext context, AppLocalizations l10n) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              MobileScanner(
                onDetect: (capture) {
                  final barcode = capture.barcodes.firstOrNull;
                  if (barcode?.rawValue != null) {
                    _onQRCodeScanned(barcode!.rawValue!);
                  }
                },
              ),
              if (_isConnecting)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 16),
                        Text(
                          l10n.connecting,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              if (Platform.isMacOS) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          l10n.macosProxyHint,
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: () => context.goNamed('settingsTab'),
                          icon: const Icon(Icons.settings_ethernet, size: 20),
                          label: Text(l10n.goToProxyConfig),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              Text(
                l10n.scanQrHint,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.runProxyHint,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildManualInputTab(BuildContext context, AppLocalizations l10n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (Platform.isMacOS) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.dns),
                title: Text(l10n.proxyNotStartedTitle),
                subtitle: Text(l10n.proxyNotStartedSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.goNamed('settingsTab'),
              ),
            ),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 8),
          Text(
            l10n.enterConnectionDetails,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.findOnComputer,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 32),

          // IP Address field
          TextField(
            controller: _ipController,
            decoration: InputDecoration(
              labelText: l10n.computerIp,
              hintText: l10n.ipHint,
              prefixIcon: const Icon(Icons.computer),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),

          // Port field
          TextField(
            controller: _portController,
            decoration: InputDecoration(
              labelText: l10n.portLabel,
              hintText: l10n.portHintShort,
              prefixIcon: const Icon(Icons.settings_ethernet),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),

          // PIN field
          TextField(
            controller: _pinController,
            decoration: InputDecoration(
              labelText: l10n.pinCode,
              hintText: l10n.pinHint,
              prefixIcon: const Icon(Icons.pin),
            ),
            keyboardType: TextInputType.number,
            maxLength: 6,
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],

          const SizedBox(height: 24),

          // Connect button
          FilledButton.icon(
            onPressed: _isConnecting
                ? null
                : () {
                    if (_ipController.text.isNotEmpty &&
                        _pinController.text.isNotEmpty) {
                      final port = int.tryParse(_portController.text) ?? 8443;
                      _connect(_ipController.text, port, _pinController.text);
                    }
                  },
            icon: _isConnecting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.link),
            label: Text(_isConnecting ? l10n.connecting : l10n.connect),
          ),
        ],
      ),
    );
  }

  void _showManualProxyDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ipController = TextEditingController(text: '192.168.');
    final portController = TextEditingController(text: '8443');
    final pinController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        final l10nDialog = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l10n.directProxyOverride),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.directProxyOverrideMessage,
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ipController,
                decoration: InputDecoration(labelText: l10nDialog.ipAddress),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: portController,
                decoration: InputDecoration(labelText: l10nDialog.portLabel),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pinController,
                decoration: InputDecoration(
                  labelText: l10nDialog.pinOptional,
                  hintText: l10nDialog.pinCodeReusable('—'),
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            FilledButton(
            onPressed: () async {
              final ip = ipController.text.trim();
              final port = int.tryParse(portController.text.trim());
              final pin = pinController.text.trim();

              if (ip.isNotEmpty && port != null) {
                Navigator.pop(context);
                setState(() => _isConnecting = true);

                try {
                  final connectionService = ref.read(connectionServiceProvider);
                  final deviceId = await _getOrCreateDeviceId();

                  if (pin.isNotEmpty) {
                    // Use PIN to pair (supports multiple uses)
                    final newConnection = await connectionService.pair(
                      ip: ip,
                      port: port,
                      pin: pin,
                      deviceName: 'Flutter App',
                      deviceId: deviceId,
                    );

                    // Connect WebSocket with the new token
                    final wsService = ref.read(webSocketServiceProvider);
                    await wsService.connect(newConnection.wsUrl, newConnection.token);

                    if (context.mounted) {
                      context.goNamed('dashboard');
                    }
                  } else {
                    // Bypass pairing, use override token
                    final overrideToken = 'override-token-$deviceId';
                    final wsService = ref.read(webSocketServiceProvider);
                    await wsService.connect('ws://$ip:$port/ws', overrideToken);

                    await connectionService.updateConnectionSettings(
                      ip,
                      port,
                      defaultToken: overrideToken,
                      defaultDeviceName: 'Manual Override',
                    );

                    if (context.mounted) {
                      context.goNamed('dashboard');
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    final l10nErr = AppLocalizations.of(context)!;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10nErr.connectionFailed(e.toString())), backgroundColor: Colors.red),
                    );
                    setState(() {
                      _errorMessage = e.toString();
                    });
                  }
                } finally {
                  if (mounted) setState(() => _isConnecting = false);
                }
              }
            },
            child: Text(l10n.connectDirectly),
          ),
        ],
      );
      },
    );
  }
}
