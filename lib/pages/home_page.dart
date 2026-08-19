import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../config/app_config.dart';
import '../services/websocket_service.dart';
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

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
  }

  Future<void> _initialize() async {
    if (!mounted) return;
    final provider = context.read<AppStateProvider>();
    try {
      await provider.initialize();
      if (!mounted) return;
      await provider.connectToServer();
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
}
