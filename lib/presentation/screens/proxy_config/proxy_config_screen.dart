import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/proxy_status_provider.dart';
import '../../../providers/skill_provider.dart';
import '../../../services/connection_service.dart';
import '../../../services/proxy_launch_service.dart';
import '../../../services/websocket_service.dart';
import '../../../l10n/app_localizations.dart';

/// 独立代理配置页：状态、路径、启动参数、启动/关闭（仅 macOS 有完整功能）
class ProxyConfigScreen extends ConsumerStatefulWidget {
  const ProxyConfigScreen({super.key});

  @override
  ConsumerState<ProxyConfigScreen> createState() => _ProxyConfigScreenState();
}

class _ProxyConfigScreenState extends ConsumerState<ProxyConfigScreen> {
  final _pathController = TextEditingController();
  final _ipController = TextEditingController(text: '127.0.0.1');
  final _portController = TextEditingController(text: '8443');
  final _pinController = TextEditingController();
  final _openclawTokenController = TextEditingController();
  final _openclawUrlController = TextEditingController();
  final _skillsPathController = TextEditingController();
  final _workdirController = TextEditingController();
  final _logPathController = TextEditingController();
  bool _pathLoaded = false;
  bool _configLoaded = false;
  bool _connectDefaultsLoaded = false;
  bool _openclaw = false;
  bool _allowLocalNoAuth = false;
  bool _configExpanded = true;
  /// 上次点击「启动代理」时使用的完整命令，用于界面展示与复制排查
  String? _lastLaunchCommand;
  /// 当前代理配置生成的完整命令（路径+参数），便于随时查看与复制
  String? _currentConfigCommand;
  static const _deviceIdKey = 'device_id';

  @override
  void dispose() {
    _pathController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _pinController.dispose();
    _openclawTokenController.dispose();
    _openclawUrlController.dispose();
    _skillsPathController.dispose();
    _workdirController.dispose();
    _logPathController.dispose();
    super.dispose();
  }

  Future<void> _loadConnectDefaults(ConnectionInfo? connection) async {
    if (_connectDefaultsLoaded) return;
    if (connection != null) {
      if (mounted) {
        _ipController.text = connection.ip;
        _portController.text = connection.port.toString();
        _pinController.text = connection.pin ?? '';
        _connectDefaultsLoaded = true;
        setState(() {});
      }
      return;
    }
    final service = ref.read(proxyLaunchServiceProvider);
    final defaults = await service.getProxyConnectDefaults();
    if (mounted) {
      _ipController.text = defaults.ip;
      _portController.text = defaults.port.toString();
      _pinController.text = defaults.pin ?? '';
      _connectDefaultsLoaded = true;
      setState(() {});
    }
  }

  Future<void> _loadPath() async {
    if (_pathLoaded) return;
    final service = ref.read(proxyLaunchServiceProvider);
    final saved = await service.proxyExecutablePath;
    if (mounted) {
      _pathController.text = saved?.trim() ?? '';
      _pathLoaded = true;
      setState(() {});
    }
  }

  Future<void> _loadConfig() async {
    if (_configLoaded) return;
    final service = ref.read(proxyLaunchServiceProvider);
    final config = await service.getLaunchConfig();
    if (mounted) {
      _openclaw = config.openclaw;
      _allowLocalNoAuth = config.allowLocalNoAuth;
      _openclawTokenController.text = config.openclawToken;
      _openclawUrlController.text = config.openclawUrl;
      _skillsPathController.text = config.skillsPath;
      _workdirController.text = config.workdir;
      _logPathController.text = config.logPath.isEmpty ? defaultProxyLogPath : config.logPath;
      _configLoaded = true;
      setState(() {});
    }
  }

  ProxyLaunchConfig _currentConfig() {
    return ProxyLaunchConfig(
      openclaw: _openclaw,
      openclawToken: _openclawTokenController.text.trim(),
      openclawUrl: _openclawUrlController.text.trim(),
      allowLocalNoAuth: _allowLocalNoAuth,
      skillsPath: _skillsPathController.text.trim(),
      workdir: _workdirController.text.trim(),
      logPath: _logPathController.text.trim(),
    );
  }

  String get _effectiveLogPath {
    final p = _logPathController.text.trim();
    return p.isNotEmpty ? p : defaultProxyLogPath;
  }

  Future<void> _refreshAfterStart(BuildContext context, ConnectionInfo connection) async {
    for (var i = 0; i < 5; i++) {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!context.mounted) return;
      await ref.read(proxyStatusProvider.notifier).check();
      await Future.delayed(const Duration(milliseconds: 300));
      if (!context.mounted) return;
      if (ref.read(proxyStatusProvider).valueOrNull == ProxyStatus.running) {
        ref.invalidate(savedConnectionProvider);
        ref.read(webSocketServiceProvider).connect(connection.wsUrl, connection.token);
        ref.invalidate(skillsProvider);
        ref.invalidate(skillPathsProvider);
        if (context.mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.proxyStartSuccess), backgroundColor: Colors.green),
          );
        }
        return;
      }
    }
    if (context.mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.proxyStartWaitCheck)),
      );
    }
  }

  /// 启动后自动轮询检测代理状态（使用指定 ip/port），更新 UI 为「代理已运行」。
  Future<void> _autoDetectAfterStart(BuildContext context, ProxyStatusNotifier notifier, String ip, int port) async {
    for (var i = 0; i < 8; i++) {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!context.mounted) return;
      await notifier.check(ip: ip, port: port);
      if (ref.read(proxyStatusProvider).valueOrNull == ProxyStatus.running) return;
    }
  }

  /// 无保存连接时：代理启动后使用表单中的 IP/端口/PIN 发起配对并连接。
  Future<void> _pairAndConnectAfterStart(BuildContext context, String ip, int port, String pin) async {
    for (var i = 0; i < 8; i++) {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!context.mounted) return;
      await ref.read(proxyStatusProvider.notifier).check();
      await Future.delayed(const Duration(milliseconds: 300));
      if (ref.read(proxyStatusProvider).valueOrNull != ProxyStatus.running) continue;
      try {
        final prefs = await SharedPreferences.getInstance();
        String? deviceId = prefs.getString(_deviceIdKey);
        if (deviceId == null) {
          deviceId = const Uuid().v4();
          await prefs.setString(_deviceIdKey, deviceId);
        }
        final conn = await ref.read(connectionServiceProvider).pair(
          ip: ip,
          port: port,
          pin: pin,
          deviceName: 'macOS',
          deviceId: deviceId,
        );
        ref.invalidate(savedConnectionProvider);
        ref.read(webSocketServiceProvider).connect(conn.wsUrl, conn.token);
        ref.invalidate(skillsProvider);
        ref.invalidate(skillPathsProvider);
        if (context.mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.autoPairedConnected), backgroundColor: Colors.green),
          );
        }
        return;
      } catch (_) {
        if (i >= 6 && context.mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.autoConnectFailed)),
          );
        }
      }
    }
  }

  Widget _buildConnectInfoCard(ConnectionInfo? connection) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(l10n.proxyConnectionInfo, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            if (connection != null) ...[
              Text('${l10n.ipLabel}: ${connection.ip}', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text('${l10n.portLabel}: ${connection.port}', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text('PIN: ${connection.pin ?? l10n.pinDash}', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(l10n.afterStartUseInfo, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ] else ...[
              TextField(
                controller: _ipController,
                decoration: InputDecoration(labelText: l10n.ipLabel, hintText: l10n.ipPortHint, border: const OutlineInputBorder(), isDense: true),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _portController,
                decoration: InputDecoration(labelText: l10n.portLabel, hintText: l10n.portHintShort, border: const OutlineInputBorder(), isDense: true),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pinController,
                decoration: InputDecoration(
                  labelText: l10n.pinOptional,
                  hintText: l10n.pinOptionalHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!Platform.isMacOS) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.proxyConfigTitle)),
        body: Center(child: Text(l10n.proxyConfigMacOnly)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.goNamed('dashboard');
            }
          },
        ),
        title: Text(l10n.proxyConfigTitle),
        actions: [
          TextButton.icon(
            onPressed: () => context.pushNamed('settings'),
            icon: const Icon(Icons.settings, size: 20),
            label: Text(l10n.systemSettings),
          ),
        ],
      ),
      body: Consumer(
        builder: (context, ref, _) {
          final connectionAsync = ref.watch(savedConnectionProvider);
          final statusAsync = ref.watch(proxyStatusProvider);

          return connectionAsync.when(
            data: (connection) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _loadPath();
                _loadConfig();
                _loadConnectDefaults(connection);
              });

              final status = statusAsync.valueOrNull;
              final isRunning = status == ProxyStatus.running;
              final canStartProxy = !isRunning;
              final canStopProxy = isRunning && connection != null;
              final l10nData = AppLocalizations.of(context)!;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (connection == null) ...[
                    Card(
                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(l10nData.pleaseStartProxyFirst, style: Theme.of(context).textTheme.titleSmall),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10nData.noSavedConnectionHint,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _buildConnectInfoCard(connection),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: Icon(
                        isRunning ? Icons.check_circle : Icons.cancel,
                        color: isRunning ? Colors.green : Colors.orange,
                      ),
                      title: Text(isRunning ? l10nData.proxyRunning : (status == ProxyStatus.checking ? l10nData.proxyChecking : l10nData.proxyNotRunning)),
                      trailing: statusAsync.isLoading
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : TextButton(
                              onPressed: () {
                                final notifier = ref.read(proxyStatusProvider.notifier);
                                if (connection != null) {
                                  notifier.check();
                                } else {
                                  final ip = _ipController.text.trim().isEmpty ? '127.0.0.1' : _ipController.text.trim();
                                  final port = int.tryParse(_portController.text.trim()) ?? 8443;
                                  notifier.check(ip: ip, port: port);
                                }
                              },
                              child: Text(l10nData.detect),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pathController,
                    decoration: InputDecoration(
                      labelText: l10nData.proxyPathLabel,
                      hintText: l10nData.proxyPathHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Debug 下会优先使用项目内 proxy/xassistant-proxy（与终端可启动的一致），应用内启动更易成功。请先执行 ./macos/scripts/build_proxy.sh 生成。Release/沙盒下使用 .app 内代理。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  _buildCurrentConfigCommandCard(context, ref, connection),
                  const SizedBox(height: 16),
                  _buildConfigSection(),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: canStartProxy
                            ? () async {
                                final service = ref.read(proxyLaunchServiceProvider);
                                final path = _pathController.text.trim();
                                await service.setProxyExecutablePath(path);
                                await service.setLaunchConfig(_currentConfig());
                                final ip = _ipController.text.trim().isEmpty ? '127.0.0.1' : _ipController.text.trim();
                                final port = int.tryParse(_portController.text.trim()) ?? 8443;
                                final pin = _pinController.text.trim();
                                final connectionToUse = connection ??
                                    (pin.length == 6
                                        ? ConnectionInfo(ip: ip, port: port, token: '', deviceName: '', pairedAt: DateTime.now(), pin: pin)
                                        : null);
                                final result = await service.startProxy(connectionToUse);
                                if (!mounted) return;
                                setState(() => _lastLaunchCommand = result.command.isNotEmpty ? result.command : null);
                                if (result.error == null) {
                                  final notifier = ref.read(proxyStatusProvider.notifier);
                                  final l10nSnack = AppLocalizations.of(context)!;
                                  if (connection != null) {
                                    await service.setProxyConnectDefaults(ip: connection.ip, port: connection.port, pin: connection.pin);
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10nSnack.startingProxy)));
                                    _refreshAfterStart(context, connection);
                                    _autoDetectAfterStart(context, notifier, connection.ip, connection.port);
                                  } else if (pin.length == 6) {
                                    await service.setProxyConnectDefaults(ip: ip, port: port, pin: pin);
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10nSnack.startingProxyConnect)));
                                    _pairAndConnectAfterStart(context, ip, port, pin);
                                    _autoDetectAfterStart(context, notifier, ip, port);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(l10nSnack.proxyStartChecking)),
                                    );
                                    _autoDetectAfterStart(context, notifier, ip, port);
                                  }
                                } else {
                                  final l10nErr = AppLocalizations.of(context)!;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(l10nErr.startFailed(result.error!)), backgroundColor: Colors.red),
                                  );
                                }
                              }
                            : null,
                        icon: const Icon(Icons.play_arrow, size: 20),
                        label: Text(l10nData.startProxy),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: canStopProxy
                            ? () async {
                                final service = ref.read(proxyLaunchServiceProvider);
                                final ok = await service.stopProxy(connection!);
                                if (!mounted) return;
                                if (ok) {
                                  await ref.read(proxyStatusProvider.notifier).check(ip: connection!.ip, port: connection!.port);
                                  if (!mounted) return;
                                  final l10nStop = AppLocalizations.of(context)!;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(l10nStop.proxyStopped), backgroundColor: Colors.orange),
                                  );
                                } else {
                                  final l10nStopFail = AppLocalizations.of(context)!;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(l10nStopFail.stopFailed)),
                                  );
                                }
                              }
                            : null,
                        icon: const Icon(Icons.stop, size: 20),
                        label: Text(l10nData.stopProxy),
                      ),
                    ],
                  ),
                  if (_lastLaunchCommand != null && _lastLaunchCommand!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.terminal, size: 20, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(l10nData.launchCommand, style: Theme.of(context).textTheme.titleSmall),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: _lastLaunchCommand!));
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10nData.copiedToClipboard)));
                                  },
                                  icon: const Icon(Icons.copy, size: 18),
                                  label: Text(l10nData.copy),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              _lastLaunchCommand!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  if (connection == null)
                    Center(
                      child: FilledButton.icon(
                        onPressed: () => context.goNamed('pairing'),
                        icon: const Icon(Icons.qr_code),
                        label: Text(l10nData.goToPair),
                      ),
                    ),
                  if (connection == null) const SizedBox(height: 12),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: () => context.goNamed('dashboard'),
                      icon: const Icon(Icons.apps),
                      label: Text(l10nData.enterApp),
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) {
              final l10nErr = AppLocalizations.of(context)!;
              return Center(child: Text(l10nErr.loadFailed(e.toString())));
            },
          );
        },
      ),
    );
  }

  Future<void> _updateCurrentConfigCommand(BuildContext context, WidgetRef ref, ConnectionInfo? connection) async {
    final service = ref.read(proxyLaunchServiceProvider);
    final path = _pathController.text.trim().isNotEmpty
        ? _pathController.text.trim()
        : await service.effectiveProxyPath;
    final port = connection?.port ?? 8443;
    final pin = connection?.pin;
    final l10n = AppLocalizations.of(context)!;
    final cmd = (path != null && path.isNotEmpty)
        ? ProxyLaunchService.buildLaunchCommandString(
            executablePath: path,
            port: port,
            pin: pin,
            config: _currentConfig(),
            defaultLogPath: defaultProxyLogPath,
          )
        : l10n.proxyPathNotSet;
    if (mounted && _currentConfigCommand != cmd) {
      setState(() => _currentConfigCommand = cmd);
    }
  }

  Widget _buildCurrentConfigCommandCard(BuildContext context, WidgetRef ref, ConnectionInfo? connection) {
    final l10n = AppLocalizations.of(context)!;
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateCurrentConfigCommand(context, ref, connection));
    final cmd = _currentConfigCommand ?? l10n.loading;
    final canCopy = cmd.isNotEmpty && cmd != l10n.proxyPathNotSet && cmd != l10n.loading;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.terminal, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(l10n.launchCommand, style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (canCopy)
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _currentConfigCommand!));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.copiedToClipboard)));
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(l10n.copy),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              cmd,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigSection() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _configExpanded = !_configExpanded),
          child: Row(
            children: [
              Icon(_configExpanded ? Icons.expand_less : Icons.expand_more),
              const SizedBox(width: 4),
              Text(l10n.proxyLaunchParams, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
        ),
        if (_configExpanded) ...[
          const SizedBox(height: 12),
          SwitchListTile(
            value: _openclaw,
            onChanged: (v) => setState(() => _openclaw = v),
            title: Text(l10n.enableOpenClaw),
            contentPadding: EdgeInsets.zero,
          ),
          TextField(
            controller: _openclawTokenController,
            decoration: InputDecoration(labelText: l10n.openClawToken, border: const OutlineInputBorder(), isDense: true),
            obscureText: true,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _openclawUrlController,
            decoration: InputDecoration(labelText: l10n.openClawUrlOptional, border: const OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _allowLocalNoAuth,
            onChanged: (v) => setState(() => _allowLocalNoAuth = v),
            title: Text(l10n.allowLocalNoAuth),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _skillsPathController,
                  decoration: InputDecoration(labelText: l10n.skillsPath, border: const OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    final path = await FilePicker.platform.getDirectoryPath();
                    if (path != null && mounted) {
                      _skillsPathController.text = path;
                      setState(() {});
                    }
                  },
                  icon: const Icon(Icons.folder_open, size: 20),
                  label: Text(l10n.selectDirectory),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _workdirController,
                  decoration: InputDecoration(labelText: l10n.workdirOptional, border: const OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    final path = await FilePicker.platform.getDirectoryPath();
                    if (path != null && mounted) {
                      _workdirController.text = path;
                      setState(() {});
                    }
                  },
                  icon: const Icon(Icons.folder_open, size: 20),
                  label: Text(l10n.selectDirectory),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _logPathController,
                  decoration: InputDecoration(
                    labelText: l10n.logPathLabel,
                    hintText: l10n.logPathHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    final dir = await FilePicker.platform.getDirectoryPath();
                    if (dir != null && mounted) {
                      _logPathController.text = '$dir/proxy.log';
                      setState(() {});
                    }
                  },
                  icon: const Icon(Icons.folder_open, size: 20),
                  label: Text(l10n.selectDirectory),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: () async {
                  await ref.read(proxyLaunchServiceProvider).setLaunchConfig(_currentConfig());
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.launchParamsSaved)));
                  }
                },
                icon: const Icon(Icons.save, size: 18),
                label: Text(l10n.saveLaunchParams),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final path = _effectiveLogPath;
                  if (path.isEmpty) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.noLogPath)));
                    }
                    return;
                  }
                  final file = File(path);
                  if (!await file.exists()) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.logNotGenerated(path))));
                    }
                    return;
                  }
                  if (Platform.isMacOS) {
                    await Process.run('open', [path]);
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.logOpened)));
                  }
                },
                icon: const Icon(Icons.description, size: 18),
                label: Text(l10n.viewLog),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
