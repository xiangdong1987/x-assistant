import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../proxy_config/proxy_config_screen.dart';
import '../../../providers/proxy_status_provider.dart';
import '../../../services/connection_service.dart' show savedConnectionProvider;
import 'settings_screen.dart';

/// 设置 Tab 内容：macOS 且代理未运行时先展示代理配置页（保留底部导航）；否则展示设置页。
class SettingsOrProxyConfigScreen extends ConsumerStatefulWidget {
  const SettingsOrProxyConfigScreen({super.key});

  @override
  ConsumerState<SettingsOrProxyConfigScreen> createState() =>
      _SettingsOrProxyConfigScreenState();
}

class _SettingsOrProxyConfigScreenState
    extends ConsumerState<SettingsOrProxyConfigScreen> {
  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(proxyStatusProvider.notifier).check();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) {
      return const SettingsScreen();
    }
    final connectionAsync = ref.watch(savedConnectionProvider);
    final statusAsync = ref.watch(proxyStatusProvider);
    final connection = connectionAsync.valueOrNull;
    final status = statusAsync.valueOrNull;

    // macOS：无保存连接或代理未运行时，先展示代理配置页
    final showProxyConfig = connection == null ||
        status == ProxyStatus.idle ||
        status == ProxyStatus.checking ||
        status == ProxyStatus.notRunning;

    if (showProxyConfig) {
      return const ProxyConfigScreen();
    }
    return const SettingsScreen();
  }
}
