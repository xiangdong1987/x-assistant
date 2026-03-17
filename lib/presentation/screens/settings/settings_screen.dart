import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/connection_service.dart';
import '../../../services/websocket_service.dart';
import '../../../services/notification_service.dart';
import '../../../providers/skill_provider.dart';
import '../../../providers/project_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../providers/proxy_status_provider.dart';
import '../../../services/proxy_launch_service.dart';
import '../../../services/pairing_api_service.dart';
import '../../../providers/connection_diagnosis_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../l10n/app_localizations.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.showProxyPrompt = false});

  final bool showProxyPrompt;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _proxyPromptShown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.showProxyPrompt && !_proxyPromptShown && mounted) {
      _proxyPromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.goNamed('proxyConfig');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: ListView(
        children: [
          // Connection section
          _SectionHeader(title: l10n.connection),
          Consumer(
            builder: (context, ref, child) {
              final savedConnectionAsync = ref.watch(savedConnectionProvider);

              return savedConnectionAsync.when(
                data: (connection) {
                  if (connection == null) {
                    return Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.qr_code),
                          title: Text(l10n.pairNewDevice),
                          onTap: () => context.pushNamed('pairing'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.settings_ethernet),
                          title: Text(l10n.setManualProxy),
                          subtitle: Text(l10n.bypassPairingHint),
                          onTap: () {
                            _showEditConnectionDialog(
                              context,
                              ref,
                              ConnectionInfo(
                                ip: '192.168.',
                                port: 8443,
                                token: '',
                                deviceName: 'Manual Override',
                                pairedAt: DateTime.now(),
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.computer),
                        title: Text(l10n.connectedDevice),
                        subtitle: Text(l10n.deviceInfo(connection.deviceName, connection.ip, connection.port.toString())),
                        trailing: const Icon(Icons.edit, color: Colors.blue),
                        onTap: () {
                          _showEditConnectionDialog(context, ref, connection);
                        },
                      ),
                      // Connection diagnosis info
                      Consumer(
                        builder: (context, ref, child) {
                          final diagnosis = ref.watch(connectionDiagnosisProvider);

                          // Show warning if IP likely changed
                          if (diagnosis.state == ConnectionDiagnosisState.ipLikelyChanged) {
                            return ListTile(
                              leading: const Icon(Icons.warning, color: Colors.orange),
                              title: Text(l10n.connectionMayHaveIssue),
                              subtitle: Text(diagnosis.message ?? l10n.stateIpChanged),
                              trailing: TextButton(
                                onPressed: () => _showConnectionDiagnosticDialog(context, ref),
                                child: Text(l10n.diagnose),
                              ),
                            );
                          }

                          // Show connection status for other states
                          if (diagnosis.state == ConnectionDiagnosisState.networkError ||
                              diagnosis.state == ConnectionDiagnosisState.connecting) {
                            return ListTile(
                              leading: Icon(
                                diagnosis.state == ConnectionDiagnosisState.connecting
                                    ? Icons.sync
                                    : Icons.wifi_off,
                                color: Colors.grey,
                              ),
                              title: Text(diagnosis.message ?? l10n.checkingConnection),
                              trailing: diagnosis.state == ConnectionDiagnosisState.networkError
                                  ? TextButton(
                                      onPressed: () => _showConnectionDiagnosticDialog(context, ref),
                                      child: Text(l10n.diagnose),
                                    )
                                  : null,
                            );
                          }

                          // Show diagnosis entry for connected users
                          return ListTile(
                            leading: const Icon(Icons.health_and_safety, size: 20),
                            title: Text(l10n.connectionDiagnosis),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _showConnectionDiagnosticDialog(context, ref),
                          );
                        },
                      ),
                      // PIN Code display
                      if (connection.pin != null)
                        ListTile(
                          leading: const Icon(Icons.pin),
                          title: Text(l10n.pinCode),
                          subtitle: Text(l10n.pinCodeReusable(connection.pin!)),
                          trailing: IconButton(
                            icon: const Icon(Icons.refresh, color: Colors.blue),
                            tooltip: l10n.resetPinTooltip,
                            onPressed: () {
                              _showResetPINDialog(context, ref, connection);
                            },
                          ),
                        ),
                      ListTile(
                        leading: const Icon(Icons.link_off),
                        title: Text(l10n.disconnect),
                        onTap: () {
                          _showDisconnectDialog(context, ref);
                        },
                      ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => ListTile(
                  leading: const Icon(Icons.error, color: Colors.red),
                  title: Text(l10n.errorLoadingConnection),
                  subtitle: Text(e.toString()),
                ),
              );
            },
          ),

          const Divider(),

          // 代理配置入口（macOS）：跳转独立代理配置页进行启动/关闭与管理
          if (Platform.isMacOS)
            ListTile(
              leading: const Icon(Icons.dns),
              title: Text(l10n.proxyConfig),
              subtitle: Text(l10n.proxyConfigSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.pushNamed('proxyConfig'),
            ),

          const Divider(),

          // Skill paths section
          _SectionHeader(title: l10n.openclawSkills),
          Consumer(
            builder: (context, ref, child) {
              final pathsAsync = ref.watch(skillPathsProvider);
              return pathsAsync.when(
                data: (paths) {
                  return Column(
                    children: [
                      ...paths.map((p) => ListTile(
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(p, overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () async {
                                final updated = List<String>.from(paths)..remove(p);
                                final api = ref.read(skillApiServiceProvider);
                                if (api != null) {
                                  await api.setSkillPaths(updated);
                                  ref.invalidate(skillPathsProvider);
                                  ref.invalidate(skillsProvider);
                                }
                              },
                            ),
                          )),
                      ListTile(
                        leading: const Icon(Icons.add),
                        title: Text(l10n.addSkillPath),
                        onTap: () => _showAddPathDialog(context, ref, paths),
                      ),
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => ListTile(
                  leading: const Icon(Icons.error, color: Colors.red),
                  title: Text(l10n.cannotLoadSkillPaths),
                  subtitle: Text(e.toString()),
                ),
              );
            },
          ),

          const Divider(),

          // X助手 项目管理 section
          _SectionHeader(title: l10n.xAssistantProjects),
          Consumer(
            builder: (context, ref, child) {
              final projectsAsync = ref.watch(projectsProvider);
              return Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.folder_special),
                    title: Text(l10n.manageProjects),
                    subtitle: projectsAsync.when(
                      data: (projects) => Text(
                        projects.isEmpty
                            ? l10n.projectsSubtitle
                            : l10n.projectsCount(projects.length),
                      ),
                      loading: () => Text(l10n.loading),
                      error: (_, __) => Text(l10n.projectsSubtitle),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.pushNamed('projects'),
                  ),
                ],
              );
            },
          ),

          const Divider(),

          // Voice section
          _SectionHeader(title: l10n.voice),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up),
            title: Text(l10n.textToSpeech),
            subtitle: Text(l10n.readAloud),
            value: true, // TODO: Connect to actual setting
            onChanged: (value) {
              // TODO: Update setting
            },
          ),
          ListTile(
            leading: const Icon(Icons.speed),
            title: Text(l10n.speechRate),
            subtitle: Text(l10n.normal),
            onTap: () {
              // TODO: Show speech rate options
            },
          ),

          const Divider(),

          // Notifications section
          _SectionHeader(title: l10n.notifications),
          Consumer(
            builder: (context, ref, child) {
              final service = ref.watch(notificationServiceProvider);
              return SwitchListTile(
                secondary: const Icon(Icons.notifications_active),
                title: Text(l10n.systemNotification),
                subtitle: Text(l10n.systemNotificationSubtitle),
                value: service.isSystemNotificationEnabled,
                onChanged: (value) {
                  service.setSystemNotificationEnabled(value);
                },
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: Text(l10n.viewMessages),
            subtitle: Text(l10n.viewNotificationHistory),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushNamed('notifications'),
          ),

          const Divider(),

          // Language section
          _SectionHeader(title: l10n.language),
          Consumer(
            builder: (context, ref, _) {
              final locale = ref.watch(localeProvider);
              final current = locale == const Locale('zh')
                  ? l10n.languageChinese
                  : (locale == const Locale('en') ? l10n.languageEnglish : l10n.system);
              return ListTile(
                leading: const Icon(Icons.language),
                title: Text(l10n.language),
                subtitle: Text(current),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showLanguageDialog(context, ref),
              );
            },
          ),

          const Divider(),

          // Appearance section
          _SectionHeader(title: l10n.appearance),
          ListTile(
            leading: const Icon(Icons.palette),
            title: Text(l10n.theme),
            subtitle: Text(l10n.system),
            onTap: () {
              // TODO: Show theme options
            },
          ),

          const Divider(),

          // About section
          _SectionHeader(title: l10n.about),
          ListTile(
            leading: const Icon(Icons.info),
            title: Text(l10n.version),
            subtitle: Text(l10n.versionPlaceholder),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(l10n.github),
            subtitle: const Text('https://github.com/xiangdong1987/xassistant'),
            onTap: () async {
              final url = Uri.parse('https://github.com/xiangdong1987/xassistant');
              if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('无法打开链接')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.language),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l10n.languageChinese),
              onTap: () async {
                await ref.read(localeProvider.notifier).setLocale('zh');
                if (context.mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text(l10n.languageEnglish),
              onTap: () async {
                await ref.read(localeProvider.notifier).setLocale('en');
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPathDialog(
      BuildContext context, WidgetRef ref, List<String> currentPaths) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.addSkillPath),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: l10n.pathHint,
            labelText: l10n.path,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final path = controller.text.trim();
              if (path.isNotEmpty) {
                final updated = [...currentPaths, path];
                final api = ref.read(skillApiServiceProvider);
                if (api != null) {
                  await api.setSkillPaths(updated);
                  ref.invalidate(skillPathsProvider);
                  ref.invalidate(skillsProvider);
                }
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: Text(l10n.add),
          ),
        ],
      ),
    );
  }

  void _showDisconnectDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.disconnectConfirmTitle),
        content: Text(l10n.disconnectConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(connectionServiceProvider).disconnect();
              if (context.mounted) {
                ref.invalidate(savedConnectionProvider);
                context.goNamed('pairing');
              }
            },
            child: Text(l10n.disconnect),
          ),
        ],
      ),
    );
  }

  void _showResetPINDialog(BuildContext context, WidgetRef ref, ConnectionInfo connection) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.resetPinTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.resetPinMessage,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.currentPin(connection.pin!),
              style: Theme.of(context).textTheme.titleMedium,
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
              try {
                final api = PairingApiService(
                  baseUrl: connection.httpUrl,
                  token: connection.token,
                );

                final result = await api.resetPIN();
                final newPin = result['pin'] as String?;

                if (context.mounted && newPin != null) {
                  Navigator.pop(context);

                  // Update connection with new PIN
                  final connectionService = ref.read(connectionServiceProvider);
                  final updatedConnection = ConnectionInfo(
                    ip: connection.ip,
                    port: connection.port,
                    token: connection.token,
                    deviceName: connection.deviceName,
                    pairedAt: DateTime.now(),
                    pin: newPin,
                  );

                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString(
                    'connection_info',
                    jsonEncode(updatedConnection.toJson()),
                  );

                  ref.invalidate(savedConnectionProvider);

                  final l10n = AppLocalizations.of(context)!;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.pinResetSuccess(newPin)),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  final l10n = AppLocalizations.of(context)!;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.resetFailed(e.toString())),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: Text(l10n.confirmReset),
          ),
        ],
      ),
    );
  }

  void _showEditConnectionDialog(
      BuildContext context, WidgetRef ref, ConnectionInfo connection) {
    final l10n = AppLocalizations.of(context)!;
    final ipController = TextEditingController(text: connection.ip);
    final portController = TextEditingController(text: connection.port.toString());
    final pinController = TextEditingController(); // Empty by default, user can enter new PIN or leave blank to use saved

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.editConnection),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ipController,
              decoration: InputDecoration(labelText: l10n.ipAddress),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: portController,
              decoration: InputDecoration(labelText: l10n.port),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              decoration: InputDecoration(
                labelText: l10n.pinCode,
                hintText: connection.pin != null ? l10n.pinUseSavedHint : l10n.pinEnterHint,
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
            ),
            if (connection.pin != null) ...[
              const SizedBox(height: 8),
              Text(
                l10n.leaveEmptyUseSavedPin,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final newIp = ipController.text.trim();
              final newPort = int.tryParse(portController.text.trim());
              final pin = pinController.text.trim();

              if (newIp.isNotEmpty && newPort != null) {
                final nav = Navigator.of(context);
                try {
                  final connectionService = ref.read(connectionServiceProvider);

                  // Use saved PIN if user didn't enter a new one
                  final pinToUse = pin.isNotEmpty ? pin : (connection.pin ?? '');

                  if (pinToUse.isEmpty) {
                    // No PIN at all, just update IP/Port without re-pairing
                    await connectionService.updateConnectionSettings(
                      newIp,
                      newPort,
                      defaultToken: connection.token,
                      defaultDeviceName: connection.deviceName,
                    );
                    ref.invalidate(savedConnectionProvider);
                    nav.pop();
                  } else {
                    // Generate or get device ID
                    final prefs = await SharedPreferences.getInstance();
                    String? deviceId = prefs.getString('device_id');
                    if (deviceId == null) {
                      deviceId = Uuid().v4();
                      await prefs.setString('device_id', deviceId);
                    }

                    // Perform actual pairing to get a valid token (PIN supports multiple uses)
                    final newConnection = await connectionService.pair(
                      ip: newIp,
                      port: newPort,
                      pin: pinToUse,
                      deviceName: connection.deviceName,
                      deviceId: deviceId!,
                    );

                    ref.invalidate(savedConnectionProvider);

                    // Reconnect immediately using the new valid token
                    final wsService = ref.read(webSocketServiceProvider);
                    wsService.disconnect();
                    wsService.connect(newConnection.wsUrl, newConnection.token);

                    nav.pop();
                  }
                } catch (e) {
                  if (context.mounted) {
                    final l10n = AppLocalizations.of(context)!;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.pairFailed(e.toString()))),
                    );
                  }
                }
              } else {
                final l10n = AppLocalizations.of(context)!;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.pleaseFillAllFields)),
                );
              }
            },
            child: Text(l10n.connect),
          ),
        ],
      ),
    );
  }

  /// 显示连接诊断对话框
  void _showConnectionDiagnosticDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, child) {
          final diagnosis = ref.watch(connectionDiagnosisProvider);

          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  diagnosis.state == ConnectionDiagnosisState.ipLikelyChanged
                      ? Icons.warning
                      : Icons.health_and_safety,
                  color: diagnosis.state == ConnectionDiagnosisState.ipLikelyChanged
                      ? Colors.orange
                      : Colors.blue,
                ),
                const SizedBox(width: 8),
                Text(l10n.connectionDiagnosis),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DiagnosticItem(
                  icon: Icons.info_outline,
                  label: l10n.diagnosisCurrentState,
                  value: _getStateText(diagnosis.state, l10n),
                ),
                const SizedBox(height: 12),

                if (diagnosis.savedIp != null) ...[
                  _DiagnosticItem(
                    icon: Icons.computer,
                    label: l10n.diagnosisSavedIp,
                    value: '${diagnosis.savedIp}:${diagnosis.savedPort}',
                  ),
                  const SizedBox(height: 12),
                ],

                _DiagnosticItem(
                  icon: Icons.error_outline,
                  label: l10n.diagnosisFailCount,
                  value: l10n.diagnosisFailCountValue(diagnosis.failCount),
                ),

                // 提示信息
                if (diagnosis.message != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lightbulb_outline, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            diagnosis.message!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.close),
              ),
              if (diagnosis.state == ConnectionDiagnosisState.ipLikelyChanged ||
                  diagnosis.state == ConnectionDiagnosisState.networkError)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    context.pushNamed('pairing');
                  },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(l10n.rePair),
                ),
              if (diagnosis.state == ConnectionDiagnosisState.connected)
                TextButton(
                  onPressed: () async {
                    await ref.read(connectionDiagnosisProvider.notifier).refreshDiagnosis();
                  },
                  child: Text(l10n.refresh),
                ),
            ],
          );
        },
      ),
    );
  }

  String _getStateText(ConnectionDiagnosisState state, AppLocalizations l10n) {
    switch (state) {
      case ConnectionDiagnosisState.unknown:
        return l10n.stateUnknown;
      case ConnectionDiagnosisState.connected:
        return l10n.stateConnected;
      case ConnectionDiagnosisState.connecting:
        return l10n.stateConnecting;
      case ConnectionDiagnosisState.networkError:
        return l10n.stateNetworkError;
      case ConnectionDiagnosisState.ipLikelyChanged:
        return l10n.stateIpChanged;
      case ConnectionDiagnosisState.authError:
        return l10n.stateAuthError;
    }
  }
}

/// 诊断信息项组件
class _DiagnosticItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DiagnosticItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}

/// 代理状态与启动区块（仅 macOS）
class _ProxySection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ProxySection> createState() => _ProxySectionState();
}

class _ProxySectionState extends ConsumerState<_ProxySection> {
  final _pathController = TextEditingController();
  final _openclawTokenController = TextEditingController();
  final _openclawUrlController = TextEditingController();
  final _skillsPathController = TextEditingController();
  final _workdirController = TextEditingController();
  bool _pathLoaded = false;
  bool _configLoaded = false;
  bool _openclaw = false;
  bool _allowLocalNoAuth = false;

  @override
  void dispose() {
    _pathController.dispose();
    _openclawTokenController.dispose();
    _openclawUrlController.dispose();
    _skillsPathController.dispose();
    _workdirController.dispose();
    super.dispose();
  }

  Future<void> _loadPath() async {
    if (_pathLoaded) return;
    final service = ref.read(proxyLaunchServiceProvider);
    final path = await service.effectiveProxyPath;
    if (mounted) {
      _pathController.text = path ?? '';
      _pathLoaded = true;
      setState(() {});
    }
  }

  Future<void> _loadLaunchConfig() async {
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
      _configLoaded = true;
      setState(() {});
    }
  }

  ProxyLaunchConfig _currentLaunchConfig() {
    return ProxyLaunchConfig(
      openclaw: _openclaw,
      openclawToken: _openclawTokenController.text.trim(),
      openclawUrl: _openclawUrlController.text.trim(),
      allowLocalNoAuth: _allowLocalNoAuth,
      skillsPath: _skillsPathController.text.trim(),
      workdir: _workdirController.text.trim(),
    );
  }

  /// 启动代理后轮询检测状态，检测到运行则刷新 UI 并触发 WebSocket 重连
  Future<void> _refreshAfterProxyStart(BuildContext context, ConnectionInfo connection) async {
    const maxAttempts = 5;
    const interval = Duration(milliseconds: 1500);
    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(interval);
      if (!context.mounted) return;
      await ref.read(proxyStatusProvider.notifier).check();
      await Future.delayed(const Duration(milliseconds: 300));
      if (!context.mounted) return;
      final status = ref.read(proxyStatusProvider).valueOrNull;
      if (status == ProxyStatus.running) {
        ref.invalidate(savedConnectionProvider);
        ref.read(webSocketServiceProvider).connect(connection.wsUrl, connection.token);
        if (context.mounted) {
          final l10nSnack = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10nSnack.proxyStartSuccessSnack), backgroundColor: Colors.green),
          );
        }
        return;
      }
    }
    if (context.mounted) {
      final l10nSnack = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10nSnack.proxyStartWaitSnack)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: l10n.proxySection),
        Consumer(
          builder: (context, ref, _) {
            final connectionAsync = ref.watch(savedConnectionProvider);
            final statusAsync = ref.watch(proxyStatusProvider);

            return connectionAsync.when(
              data: (connection) {
                if (connection == null) {
                  return ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(l10n.pleasePairOrConfigThenDetect),
                  );
                }
                // 有连接：展示状态与操作
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      leading: Icon(
                        statusAsync.when(
                          data: (s) => s == ProxyStatus.running
                              ? Icons.check_circle
                              : s == ProxyStatus.notRunning
                                  ? Icons.cancel
                                  : Icons.help_outline,
                          loading: () => Icons.hourglass_empty,
                          error: (_, __) => Icons.error_outline,
                        ),
                        color: statusAsync.when(
                          data: (s) => s == ProxyStatus.running
                              ? Colors.green
                              : s == ProxyStatus.notRunning
                                  ? Colors.orange
                                  : null,
                          loading: () => null,
                          error: (_, __) => Colors.red,
                        ),
                      ),
                      title: Text(
                        statusAsync.when(
                          data: (s) {
                            switch (s) {
                              case ProxyStatus.idle:
                                return l10n.proxyStatusNotDetectedShort;
                              case ProxyStatus.checking:
                                return l10n.proxyCheckingShort;
                              case ProxyStatus.running:
                                return l10n.proxyRunningShort;
                              case ProxyStatus.notRunning:
                                return l10n.proxyNotRunningShort;
                            }
                          },
                          loading: () => l10n.proxyCheckingShort,
                          error: (e, _) => l10n.detectFailed,
                        ),
                      ),
                      trailing: statusAsync.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : TextButton(
                              onPressed: () {
                                ref.read(proxyStatusProvider.notifier).check();
                              },
                              child: Text(l10n.detectLabel),
                            ),
                    ),
                    // 代理启动参数：有连接时始终显示，便于修改下次启动参数
                    _ProxyLaunchConfigForm(
                      openclaw: _openclaw,
                      allowLocalNoAuth: _allowLocalNoAuth,
                      openclawTokenController: _openclawTokenController,
                      openclawUrlController: _openclawUrlController,
                      skillsPathController: _skillsPathController,
                      workdirController: _workdirController,
                      onOpenclawChanged: (v) => setState(() => _openclaw = v),
                      onAllowLocalNoAuthChanged: (v) => setState(() => _allowLocalNoAuth = v),
                      onSaveConfig: () async {
                        await ref.read(proxyLaunchServiceProvider).setLaunchConfig(_currentLaunchConfig());
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(AppLocalizations.of(context)!.launchParamsSavedSnack)),
                          );
                        }
                      },
                    ),
                    if (statusAsync.valueOrNull == ProxyStatus.notRunning) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: TextField(
                          controller: _pathController,
                          decoration: InputDecoration(
                            labelText: l10n.proxyPathLabelShort,
                            hintText: l10n.proxyPathHintLong,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Row(
                          children: [
                            FilledButton.icon(
                              onPressed: () async {
                                final service = ref.read(proxyLaunchServiceProvider);
                                final path = _pathController.text.trim();
                                await service.setProxyExecutablePath(path);
                                await service.setLaunchConfig(_currentLaunchConfig());
                                final result = await service.startProxy(connection);
                                if (!context.mounted) return;
                                if (result.error == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(AppLocalizations.of(context)!.startProxyPleaseWaitSnack)),
                                  );
                                  _refreshAfterProxyStart(context, connection);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(AppLocalizations.of(context)!.startFailed(result.error ?? '')), backgroundColor: Colors.red),
                                  );
                                }
                              },
                              icon: const Icon(Icons.play_arrow, size: 20),
                              label: Text(l10n.startProxyLabel),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
              loading: () => ListTile(
                leading: const Icon(Icons.hourglass_empty),
                title: Text(l10n.loadingConnectionTitle),
              ),
              error: (e, _) => ListTile(
                leading: const Icon(Icons.error_outline, color: Colors.red),
                title: Text(l10n.loadFailedWithError(e)),
              ),
            );
          },
        ),
        // 进入页面后加载已保存的代理路径与启动参数（仅一次）
        Builder(
          builder: (context) {
            if (!_pathLoaded) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _loadPath());
            }
            if (!_configLoaded) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _loadLaunchConfig());
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}

/// 代理启动参数表单（OpenClaw、技能路径等）
class _ProxyLaunchConfigForm extends StatefulWidget {
  const _ProxyLaunchConfigForm({
    required this.openclaw,
    required this.allowLocalNoAuth,
    required this.openclawTokenController,
    required this.openclawUrlController,
    required this.skillsPathController,
    required this.workdirController,
    required this.onOpenclawChanged,
    required this.onAllowLocalNoAuthChanged,
    required this.onSaveConfig,
  });

  final bool openclaw;
  final bool allowLocalNoAuth;
  final TextEditingController openclawTokenController;
  final TextEditingController openclawUrlController;
  final TextEditingController skillsPathController;
  final TextEditingController workdirController;
  final ValueChanged<bool> onOpenclawChanged;
  final ValueChanged<bool> onAllowLocalNoAuthChanged;
  final VoidCallback onSaveConfig;

  @override
  State<_ProxyLaunchConfigForm> createState() => _ProxyLaunchConfigFormState();
}

class _ProxyLaunchConfigFormState extends State<_ProxyLaunchConfigForm> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                const SizedBox(width: 4),
                Text(
                  l10n.proxyLaunchParamsTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 12),
            SwitchListTile(
              value: widget.openclaw,
              onChanged: widget.onOpenclawChanged,
              title: Text(l10n.enableOpenClawTitle),
              subtitle: Text(l10n.enableOpenClawSubtitle),
              contentPadding: EdgeInsets.zero,
            ),
            TextField(
              controller: widget.openclawTokenController,
              decoration: InputDecoration(
                labelText: l10n.openClawTokenLabel,
                hintText: l10n.openClawTokenHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: widget.openclawUrlController,
              decoration: InputDecoration(
                labelText: l10n.openClawUrlLabel,
                hintText: l10n.openClawUrlHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: widget.allowLocalNoAuth,
              onChanged: widget.onAllowLocalNoAuthChanged,
              title: Text(l10n.allowLocalNoAuthTitle),
              subtitle: Text(l10n.allowLocalNoAuthSubtitle),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.skillsPathController,
                    decoration: InputDecoration(
                      labelText: l10n.skillsPathLabel,
                      hintText: l10n.skillsPathHint,
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
                      final path = await FilePicker.platform.getDirectoryPath();
                      if (path != null && context.mounted) {
                        widget.skillsPathController.text = path;
                        setState(() {});
                      }
                    },
                    icon: const Icon(Icons.folder_open, size: 20),
                    label: Text(l10n.selectDirectoryLabel),
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
                    controller: widget.workdirController,
                    decoration: InputDecoration(
                      labelText: l10n.workdirLabel,
                      hintText: l10n.workdirHint,
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
                      final path = await FilePicker.platform.getDirectoryPath();
                      if (path != null && context.mounted) {
                        widget.workdirController.text = path;
                        setState(() {});
                      }
                    },
                    icon: const Icon(Icons.folder_open, size: 20),
                    label: Text(l10n.selectDirectoryLabel),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: widget.onSaveConfig,
              icon: const Icon(Icons.save, size: 18),
              label: Text(l10n.saveLaunchParamsLabel),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
