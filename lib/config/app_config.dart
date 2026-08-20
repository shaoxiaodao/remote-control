import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局应用配置
///
/// 服务器地址支持三种方式（优先级从高到低）：
/// 1. App 内设置页面（运行时修改，存储在 SharedPreferences）
/// 2. 环境变量 RC_SERVER_HOST / RC_SERVER_PORT
/// 3. 下面的默认值
class AppConfig {
  AppConfig._();

  // ─── 服务器默认值（可被运行时覆盖） ───
  static const String defaultHost = 'maintaining-platinum-solution-madrid.trycloudflare.com';
  static const int defaultPort = 443;
  static const bool defaultUseSSL = true;

  // ─── 运行时配置（通过 SharedPreferences 持久化） ───
  static String _runtimeHost = '';
  static int _runtimePort = defaultPort;
  static bool _runtimeUseSSL = defaultUseSSL;
  static bool _initialized = false;

  static String get relayServerHost => _runtimeHost.isNotEmpty
      ? _runtimeHost
      : const String.fromEnvironment('RC_SERVER_HOST', defaultValue: defaultHost);

  static int get relayServerPort => _runtimeHost.isNotEmpty
      ? _runtimePort
      : int.tryParse(const String.fromEnvironment('RC_SERVER_PORT', defaultValue: '')) ?? defaultPort;

  static bool get useSSL => _runtimeUseSSL;

  static String get wsUrl {
    final scheme = useSSL ? 'wss' : 'ws';
    return '$scheme://$relayServerHost:$relayServerPort';
  }

  static bool get isConfigured => relayServerHost.isNotEmpty;

  /// App 启动时调用，从 SharedPreferences 读取上次配置
  static Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _runtimeHost = prefs.getString('server_host') ?? defaultHost;
    _runtimePort = prefs.getInt('server_port') ?? defaultPort;
    _runtimeUseSSL = prefs.getBool('server_use_ssl') ?? defaultUseSSL;
    _initialized = true;
  }

  /// 保存服务器配置（设置页面调用）
  static Future<void> saveServerConfig(String host, int port, {bool ssl = false}) async {
    final prefs = await SharedPreferences.getInstance();
    _runtimeHost = host;
    _runtimePort = port;
    _runtimeUseSSL = ssl;
    await prefs.setString('server_host', host);
    await prefs.setInt('server_port', port);
    await prefs.setBool('server_use_ssl', ssl);
  }

  /// 清除服务器配置（重置为默认）
  static Future<void> clearServerConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _runtimeHost = '';
    _runtimePort = defaultPort;
    _runtimeUseSSL = defaultUseSSL;
    await prefs.remove('server_host');
    await prefs.remove('server_port');
    await prefs.remove('server_use_ssl');
  }

  // ─── 视频/图像配置 ───
  static const int screenCaptureFps = 15;
  static const int jpegQuality = 50;
  static const int maxFrameWidth = 720;
  static const int maxFrameSizeBytes = 200 * 1024;

  // ─── 网络配置（保活优化） ───
  static const Duration wsReconnectDelay = Duration(seconds: 3); // 指数退避基数
  static const Duration wsHeartbeatInterval = Duration(seconds: 10); // 心跳间隔
  static const Duration heartbeatTimeout = Duration(seconds: 30); // 心跳超时（30s 无响应则强制重连）
  static const Duration wsConnectionTimeout = Duration(seconds: 15);
  // 重连次数：无上限（手机可能锁屏数小时，必须持续尝试重连）

  // ─── UI 配置 ───
  static const Color primaryColor = Color(0xFF2196F3);
  static const Color accentColor = Color(0xFF03DAC6);
  static const Color errorColor = Color(0xFFCF6679);
  static const Color backgroundColor = Color(0xFF121212);
  static const Color surfaceColor = Color(0xFF1E1E1E);

  // ─── 设备 ID 前缀 ───
  static const String deviceIdPrefix = 'RC';
  static const int deviceIdLength = 9;
}
