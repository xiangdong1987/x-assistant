import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import 'connection_service.dart';

const _proxyExecutablePathKey = 'proxy_executable_path';
const _proxyLaunchConfigKey = 'proxy_launch_config';
const _proxyConnectIpKey = 'proxy_connect_ip';
const _proxyConnectPortKey = 'proxy_connect_port';
const _proxyConnectPinKey = 'proxy_connect_pin';
const _bundledProxyName = 'xassistant-proxy';

/// 代理启动参数配置（与 proxy main.go 的 flag 对应）
class ProxyLaunchConfig {
  const ProxyLaunchConfig({
    this.openclaw = false,
    this.openclawToken = '',
    this.openclawUrl = '',
    this.allowLocalNoAuth = false,
    this.skillsPath = '',
    this.workdir = '',
    this.logPath = '',
    this.voiceEnabled = false,
    this.voiceModelsDir = '',
  });

  final bool openclaw;
  final String openclawToken;
  final String openclawUrl;
  final bool allowLocalNoAuth;
  final String skillsPath;
  final String workdir;
  /// 日志文件路径；非空时 proxy 将日志追加写入该文件，便于查看
  final String logPath;
  /// 语音功能开关
  final bool voiceEnabled;
  /// 语音模型目录路径（空则使用 proxy 默认 ./models）
  final String voiceModelsDir;

  Map<String, dynamic> toJson() => {
        'openclaw': openclaw,
        'openclawToken': openclawToken,
        'openclawUrl': openclawUrl,
        'allowLocalNoAuth': allowLocalNoAuth,
        'skillsPath': skillsPath,
        'workdir': workdir,
        'logPath': logPath,
        'voiceEnabled': voiceEnabled,
        'voiceModelsDir': voiceModelsDir,
      };

  factory ProxyLaunchConfig.fromJson(Map<String, dynamic> json) {
    return ProxyLaunchConfig(
      openclaw: json['openclaw'] as bool? ?? false,
      openclawToken: json['openclawToken'] as String? ?? '',
      openclawUrl: json['openclawUrl'] as String? ?? '',
      allowLocalNoAuth: json['allowLocalNoAuth'] as bool? ?? false,
      skillsPath: json['skillsPath'] as String? ?? '',
      workdir: json['workdir'] as String? ?? '',
      logPath: json['logPath'] as String? ?? '',
      voiceEnabled: json['voiceEnabled'] as bool? ?? false,
      voiceModelsDir: json['voiceModelsDir'] as String? ?? '',
    );
  }

  ProxyLaunchConfig copyWith({
    bool? openclaw,
    String? openclawToken,
    String? openclawUrl,
    bool? allowLocalNoAuth,
    String? skillsPath,
    String? workdir,
    String? logPath,
    bool? voiceEnabled,
    String? voiceModelsDir,
  }) {
    return ProxyLaunchConfig(
      openclaw: openclaw ?? this.openclaw,
      openclawToken: openclawToken ?? this.openclawToken,
      openclawUrl: openclawUrl ?? this.openclawUrl,
      allowLocalNoAuth: allowLocalNoAuth ?? this.allowLocalNoAuth,
      skillsPath: skillsPath ?? this.skillsPath,
      workdir: workdir ?? this.workdir,
      logPath: logPath ?? this.logPath,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      voiceModelsDir: voiceModelsDir ?? this.voiceModelsDir,
    );
  }
}

/// 默认代理日志路径（macOS 常用）
String get defaultProxyLogPath {
  if (!Platform.isMacOS) return '';
  final home = Platform.environment['HOME'] ?? '';
  if (home.isEmpty) return '';
  return path.normalize(path.join(home, 'Library', 'Logs', 'xassistant-proxy', 'proxy.log'));
}

/// 代理程序路径的读取与保存、启动参数配置、以及通过 Process 启动代理（仅 macOS）
class ProxyLaunchService {
  Future<String?> get proxyExecutablePath async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_proxyExecutablePathKey);
  }

  Future<void> setProxyExecutablePath(String pathToSet) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_proxyExecutablePathKey, pathToSet.trim());
  }

  Future<ProxyLaunchConfig> getLaunchConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_proxyLaunchConfigKey);
    if (raw == null) return const ProxyLaunchConfig();
    try {
      return ProxyLaunchConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const ProxyLaunchConfig();
    }
  }

  Future<void> setLaunchConfig(ProxyLaunchConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_proxyLaunchConfigKey, jsonEncode(config.toJson()));
  }

  /// 连接默认值（IP、端口、PIN），用于无保存连接时启动代理与启动后自动配对连接。
  Future<({String ip, int port, String? pin})> getProxyConnectDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString(_proxyConnectIpKey)?.trim() ?? '127.0.0.1';
    final port = int.tryParse(prefs.getString(_proxyConnectPortKey) ?? '') ?? 8443;
    final pin = prefs.getString(_proxyConnectPinKey)?.trim();
    return (ip: ip, port: port, pin: pin != null && pin.isNotEmpty ? pin : null);
  }

  Future<void> setProxyConnectDefaults({required String ip, required int port, String? pin}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_proxyConnectIpKey, ip.trim());
    await prefs.setString(_proxyConnectPortKey, port.toString());
    if (pin != null && pin.isNotEmpty) {
      await prefs.setString(_proxyConnectPinKey, pin.trim());
    } else {
      await prefs.remove(_proxyConnectPinKey);
    }
  }

  /// 返回与 Flutter macOS .app 打包在一起的代理可执行文件路径（若存在）。
  static String? get bundledProxyPath {
    if (!Platform.isMacOS) return null;
    try {
      final exe = Platform.resolvedExecutable;
      final resourcesDir = path.normalize(path.join(path.dirname(exe), '..', 'Resources'));
      final candidate = path.join(resourcesDir, _bundledProxyName);
      if (File(candidate).existsSync()) return candidate;
    } catch (_) {}
    return null;
  }

  /// Debug 构建时优先使用项目内的 proxy/xassistant-proxy（未签名、与终端可启动的一致），避免 app 内 spawn .app 内二进制失败。
  static String? get devProxyPath {
    if (!Platform.isMacOS) return null;
    try {
      final exe = Platform.resolvedExecutable;
      if (!exe.contains('Build/Products/Debug')) return null;
      final projectRoot = path.normalize(path.join(path.dirname(exe), '..', '..', '..', '..', '..', '..', '..', '..'));
      final candidate = path.join(projectRoot, 'proxy', _bundledProxyName);
      if (File(candidate).existsSync()) return candidate;
    } catch (_) {}
    return null;
  }

  /// 根据路径、连接信息与启动配置生成完整命令行（不执行），便于界面展示与复制到终端。
  static String buildLaunchCommandString({
    required String executablePath,
    required int port,
    String? pin,
    required ProxyLaunchConfig config,
    required String defaultLogPath,
  }) {
    final args = <String>['-port', port.toString(), '-host', '0.0.0.0'];
    if (pin != null && pin.length == 6) args.addAll(['-pin', pin]);
    if (config.openclaw) {
      args.add('-openclaw');
      if (config.openclawToken.isNotEmpty) args.addAll(['-openclaw-token', config.openclawToken]);
      if (config.openclawUrl.isNotEmpty) args.addAll(['-openclaw-url', config.openclawUrl]);
    }
    if (config.allowLocalNoAuth) args.add('-allow-local-no-auth');
    if (config.skillsPath.isNotEmpty) args.addAll(['-skills-path', config.skillsPath]);
    if (config.workdir.isNotEmpty) args.addAll(['-workdir', config.workdir]);
    final logPath = config.logPath.trim().isNotEmpty ? config.logPath.trim() : defaultLogPath;
    if (logPath.isNotEmpty) args.addAll(['-log', logPath]);
    if (config.voiceEnabled) {
      args.add('-voice');
      if (config.voiceModelsDir.isNotEmpty) args.addAll(['-voice-models-dir', config.voiceModelsDir]);
    }
    return [executablePath, ...args].join(' ');
  }

  /// 实际用于启动的路径：用户配置 > Debug 时项目内 proxy > 打包内代理。Debug 无沙盒时可执行项目内未签名 proxy，与终端一致易成功。
  Future<String?> get effectiveProxyPath async {
    final saved = (await proxyExecutablePath)?.trim();
    if (saved != null && saved.isNotEmpty) return saved;
    final dev = devProxyPath;
    if (dev != null) return dev;
    return bundledProxyPath;
  }

  /// 启动代理的返回：error 为 null 表示成功；command 为本次使用的完整命令行（便于排查）。
  static const _logTag = '[ProxyLaunch]';

  /// 使用已配置的路径、启动参数与连接信息启动代理进程（仅 macOS）。
  /// 返回 (error, command)：error 为 null 表示成功；command 为完整命令，便于在界面显示或复制到终端排查。
  Future<({String? error, String command})> startProxy(ConnectionInfo? connection) async {
    if (!Platform.isMacOS) return (error: '仅支持 macOS', command: '');
    final pathToUse = (await effectiveProxyPath)?.trim();
    if (pathToUse == null || pathToUse.isEmpty) return (error: '未配置代理路径且未找到打包的代理', command: '');

    final file = File(pathToUse);
    if (!file.existsSync()) return (error: '代理程序不存在: $pathToUse', command: '');

    final config = await getLaunchConfig();
    final port = connection?.port ?? 8443;
    final args = <String>[
      '-port',
      port.toString(),
      '-host',
      '0.0.0.0',
    ];
    if (connection?.pin != null && connection!.pin!.length == 6) {
      args.addAll(['-pin', connection.pin!]);
    }
    if (config.openclaw) {
      args.add('-openclaw');
      if (config.openclawToken.isNotEmpty) {
        args.addAll(['-openclaw-token', config.openclawToken]);
      }
      if (config.openclawUrl.isNotEmpty) {
        args.addAll(['-openclaw-url', config.openclawUrl]);
      }
    }
    if (config.allowLocalNoAuth) {
      args.add('-allow-local-no-auth');
    }
    if (config.skillsPath.isNotEmpty) {
      args.addAll(['-skills-path', config.skillsPath]);
    }
    if (config.workdir.isNotEmpty) {
      args.addAll(['-workdir', config.workdir]);
    }
    final logPath = config.logPath.trim().isNotEmpty ? config.logPath.trim() : defaultProxyLogPath;
    if (logPath.isNotEmpty) {
      args.addAll(['-log', logPath]);
    }
    if (config.voiceEnabled) {
      args.add('-voice');
      if (config.voiceModelsDir.isNotEmpty) {
        args.addAll(['-voice-models-dir', config.voiceModelsDir]);
      }
    }

    final workDir = config.workdir.trim().isNotEmpty
        ? config.workdir.trim()
        : path.dirname(pathToUse);
    final cmdLine = [pathToUse, ...args].join(' ');

    // 打印到 stdout（若从终端 flutter run 可见）；同时通过返回值在界面展示
    print('$_logTag executable: $pathToUse');
    print('$_logTag args: $args');
    print('$_logTag workingDirectory: $workDir');
    print('$_logTag 完整命令: $cmdLine');

    try {
      await Process.start(
        pathToUse,
        args,
        mode: ProcessStartMode.detached,
        workingDirectory: workDir,
      );
      print('$_logTag Process.start 已调用');
      return (error: null, command: cmdLine);
    } catch (e, st) {
      print('$_logTag 启动异常: $e');
      print('$_logTag $st');
      return (error: '启动失败: $e', command: cmdLine);
    }
  }

  /// 通过 POST /api/shutdown 关闭已运行的代理（需已保存连接且带 token）。
  Future<bool> stopProxy(ConnectionInfo connection) async {
    try {
      final client = HttpClient();
      final req = await client.postUrl(Uri.parse('${connection.httpUrl}/api/shutdown'));
      req.headers.set('Authorization', 'Bearer ${connection.token}');
      req.headers.set('Content-Type', 'application/json');
      final resp = await req.close();
      await resp.drain();
      client.close();
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
