import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/app_state_provider.dart';
import '../config/app_config.dart';
import '../services/websocket_service.dart';
import '../services/platform_channel_service.dart';
import '../utils/device_id_generator.dart';
import 'controller_page.dart';
import 'controlled_page.dart';
import 'settings_page.dart';

/// 主页 —— 显示设备ID、模式选择、连接状态
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _platform = PlatformChannelService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 从设置页返回时刷新无障碍状态
      final provider = context.read<AppStateProvider>();
      provider.refreshAccessibility();
    }
  }

  Future<void> _initialize() async {
    if (!mounted) return;
    final provider = context.read<AppStateProvider>();
    try {
      await provider.initialize();
      if (!mounted) return;
      await provider.connectToServer();
      // 启动状态监听（无障碍服务开关变化时自动刷新）
      _platform.startStatusListener();
      // 初始化完成后弹出权限引导
      if (!mounted) return;
      await _showPermissionSetup();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('初始化失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      body: SafeArea(
        child: Consumer<AppStateProvider>(
          builder: (context, provider, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),
                  _buildHeader(),
                  const SizedBox(height: 32),
                  if (!AppConfig.isConfigured) ...[
                    _buildServerConfigPrompt(),
                    const SizedBox(height: 24),
                  ],
                  _buildDeviceIdCard(provider),
                  const SizedBox(height: 24),
                  _buildConnectionStatus(provider),
                  const SizedBox(height: 32),
                  _buildModeButtons(provider),
                  const SizedBox(height: 24),
                  if (provider.onlineDevices.isNotEmpty)
                    _buildOnlineDevices(provider),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white54, size: 24),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
          ],
        ),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppConfig.primaryColor, AppConfig.accentColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.screen_share, size: 40, color: Colors.white),
        ),
        const SizedBox(height: 16),
        const Text(
          '远程控制',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '手机远程投屏与控制',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildServerConfigPrompt() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsPage()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.orange.withOpacity(0.15),
              Colors.red.withOpacity(0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.dns, color: Colors.orange, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '请先配置服务器',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '点击此处设置中继服务器地址',
                    style: TextStyle(
                      color: Colors.orange.withOpacity(0.7),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.orange, size: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceIdCard(AppStateProvider provider) {
    final device = provider.localDevice;
    if (device == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Card(
      color: AppConfig.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.phone_android, color: AppConfig.primaryColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  device.deviceName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppConfig.primaryColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    device.osVersion,
                    style: const TextStyle(
                      color: AppConfig.primaryColor,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '你的设备ID',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatDeviceId(device.deviceId),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  color: AppConfig.primaryColor,
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: device.deviceId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('设备ID已复制'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatus(AppStateProvider provider) {
    final isConnected =
        provider.connectionState == WsConnectionState.connected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isConnected
            ? Colors.green.withOpacity(0.1)
            : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected
              ? Colors.green.withOpacity(0.3)
              : Colors.red.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isConnected ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              provider.statusMessage,
              style: TextStyle(
                color: isConnected ? Colors.green : Colors.red,
                fontSize: 14,
              ),
            ),
          ),
          if (!isConnected)
            TextButton(
              onPressed: () {
                provider.wsService.resetReconnectCounter();
                provider.connectToServer();
              },
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }

  Widget _buildModeButtons(AppStateProvider provider) {
    return Column(
      children: [
        // 远程控制（作为控制端）
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: provider.connectionState == WsConnectionState.connected
                ? () => _showConnectDialog(provider)
                : null,
            icon: const Icon(Icons.computer, size: 24),
            label: const Text(
              '远程控制',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConfig.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 4,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 被远程控制（作为被控端）
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton.icon(
            onPressed: provider.connectionState == WsConnectionState.connected
                ? () => _enterControlledMode(provider)
                : null,
            icon: const Icon(Icons.shield, size: 24),
            label: const Text(
              '允许被控制',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppConfig.accentColor,
              side: const BorderSide(color: AppConfig.accentColor, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOnlineDevices(AppStateProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '在线设备 (${provider.onlineDevices.length})',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ...provider.onlineDevices.map((device) => Card(
              color: AppConfig.surfaceColor,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppConfig.primaryColor.withOpacity(0.15),
                  child: Icon(
                    device.platform == 'ios'
                        ? Icons.phone_iphone
                        : Icons.phone_android,
                    color: AppConfig.primaryColor,
                  ),
                ),
                title: Text(
                  device.deviceName,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  formatDeviceId(device.deviceId),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: AppConfig.primaryColor,
                ),
                onTap: () {
                  provider.connectToDevice(device.deviceId);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ControllerPage(),
                    ),
                  );
                },
              ),
            )),
      ],
    );
  }

  void _showConnectDialog(AppStateProvider provider) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConfig.surfaceColor,
        title: const Text(
          '连接到远程设备',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '输入远程设备的ID来建立连接',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                letterSpacing: 2,
              ),
              decoration: InputDecoration(
                hintText: 'RC 123 456 789',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final input = controller.text.replaceAll(' ', '');
              if (input.isNotEmpty) {
                Navigator.pop(ctx);
                provider.connectToDevice(input);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ControllerPage(),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConfig.primaryColor,
            ),
            child: const Text('连接'),
          ),
        ],
      ),
    ).then((_) {
      controller.dispose();
    });
  }

  void _enterControlledMode(AppStateProvider provider) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ControlledPage(),
      ),
    );
  }

  /// 权限引导弹窗 —— 应用启动后自动弹出
  /// 依次引导用户授予：通知权限、无障碍服务、修改系统设置
  Future<void> _showPermissionSetup() async {
    // ─── 步骤 1：通知权限（Android 13+）───
    final notifStatus = await Permission.notification.status;
    if (!notifStatus.isGranted && mounted) {
      final granted = await _showPermissionStep(
        icon: Icons.notifications_active,
        iconColor: Colors.blue,
        title: '通知权限',
        description: '远程控制需要显示常驻通知以保持后台服务运行，防止被系统回收。',
        buttonText: '授予通知权限',
        onGrant: () async {
          final status = await Permission.notification.request();
          return status.isGranted;
        },
      );
      if (granted != true) return; // 用户关闭了弹窗
    }

    // ─── 步骤 2：无障碍服务 ───
    final accessibilityEnabled = await _platform.isAccessibilityServiceEnabled();
    if (!accessibilityEnabled && mounted) {
      final granted = await _showPermissionStep(
        icon: Icons.accessibility_new,
        iconColor: Colors.green,
        title: '无障碍服务',
        description: '开启无障碍服务后，远程设备可以模拟触控操作（点击、滑动、滚动）和系统按键（返回、主页、最近任务）。',
        buttonText: '前往开启',
        onGrant: () async {
          await _platform.openAccessibilitySettings();
          // 用户会在系统设置中操作，返回后通过 didChangeAppLifecycleState 刷新
          return true;
        },
      );
      if (granted != true) return;
    }

    // ─── 步骤 3：修改系统设置 ───
    final canWrite = await _platform.canWriteSettings();
    if (!canWrite && mounted) {
      await _showPermissionStep(
        icon: Icons.settings_suggest,
        iconColor: Colors.orange,
        title: '修改系统设置',
        description: '允许修改系统设置后，远程设备可以控制屏幕亮度、屏幕超时等系统级选项。',
        buttonText: '前往授权',
        onGrant: () async {
          await _platform.requestWriteSettings();
          return true;
        },
      );
    }
  }

  /// 单步权限引导弹窗
  /// 返回 true 表示用户点击了按钮，null/false 表示用户关闭了弹窗
  Future<bool?> _showPermissionStep({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required String buttonText,
    required Future<bool> Function() onGrant,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConfig.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          description,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 14,
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              '稍后再说',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              await onGrant();
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: iconColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }
}
