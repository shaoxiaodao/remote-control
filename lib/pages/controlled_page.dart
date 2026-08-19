import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../config/app_config.dart';
import '../models/session.dart';
import '../services/websocket_service.dart';
import '../services/platform_channel_service.dart';
import '../utils/device_id_generator.dart';

/// 被控端页面 —— 显示本机信息、等待连接请求、管理被控会话
class ControlledPage extends StatefulWidget {
  const ControlledPage({super.key});

  @override
  State<ControlledPage> createState() => _ControlledPageState();
}

class _ControlledPageState extends State<ControlledPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  StreamSubscription? _messageSub;
  bool _showingDialog = false; // 防止多个对话框堆叠
  bool _enteredControlledMode = false; // 防止重复进入

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enterControlledMode();
    });
  }

  Future<void> _enterControlledMode() async {
    if (_enteredControlledMode) return;
    _enteredControlledMode = true;

    final provider = context.read<AppStateProvider>();
    await provider.enterControlledMode();

    // 监听连接请求（含错误处理）
    _messageSub = provider.wsService.messageStream.listen(
      (message) {
        final type = message['type'] as String?;
        if (type == MessageType.requestConnect) {
          final fromId = message['fromId'] as String?;
          if (fromId != null && mounted && !_showingDialog) {
            _showingDialog = true;
            _showConnectionRequestDialog(fromId, message['fromName'] as String? ?? '未知设备');
          }
        }
      },
      onError: (_) {
        // WebSocket 错误不中断监听
      },
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _messageSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppConfig.surfaceColor,
        elevation: 0,
        title: const Text('被控模式'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _exitControlledMode(),
        ),
      ),
      body: Consumer<AppStateProvider>(
        builder: (context, provider, _) {
          final session = provider.session;
          final isControlling = session != null &&
              (session.state == SessionState.streaming ||
               session.state == SessionState.controlling ||
               session.state == SessionState.connected);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                // 状态图标（脉冲动画）
                _buildStatusIndicator(provider, isControlling),
                const SizedBox(height: 32),

                // 设备ID卡片
                _buildDeviceIdCard(provider),
                const SizedBox(height: 24),

                // 连接状态
                if (isControlling)
                  _buildActiveSessionCard(provider, session!)
                else
                  _buildWaitingCard(provider),

                const SizedBox(height: 24),

                // 权限提示
                _buildPermissionCard(provider),

                const SizedBox(height: 24),

                // 退出按钮
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => _exitControlledMode(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '退出被控模式',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusIndicator(AppStateProvider provider, bool isControlling) {
    return Center(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Transform.scale(
            scale: isControlling ? 1.0 : 0.9 + _pulseController.value * 0.1,
            child: child,
          );
        },
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isControlling
                ? const RadialGradient(colors: [
                    AppConfig.primaryColor,
                    Color(0xFF1565C0),
                  ])
                : const RadialGradient(colors: [
                    AppConfig.accentColor,
                    Color(0xFF00695C),
                  ]),
            boxShadow: [
              BoxShadow(
                color: (isControlling
                        ? AppConfig.primaryColor
                        : AppConfig.accentColor)
                    .withOpacity(0.4),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Icon(
            isControlling ? Icons.screen_share : Icons.shield,
            size: 56,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceIdCard(AppStateProvider provider) {
    final device = provider.localDevice;
    if (device == null) return const SizedBox();

    return Card(
      color: AppConfig.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              '分享此 ID 给控制端',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              formatDeviceId(device.deviceId),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingCard(AppStateProvider provider) {
    return Card(
      color: AppConfig.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '等待连接中',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              provider.statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSessionCard(
      AppStateProvider provider, RemoteSession session) {
    return Card(
      color: AppConfig.primaryColor.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppConfig.primaryColor.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppConfig.primaryColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '正在被控制',
                  style: TextStyle(
                    color: AppConfig.primaryColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (session.remoteDevice != null)
              Text(
                '控制方: ${session.remoteDevice!.deviceName}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '已持续 ${session.durationString}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStatChip('FPS', '${session.fps}'),
                const SizedBox(width: 12),
                _buildStatChip('延迟', '${session.latencyMs.toInt()}ms'),
                const SizedBox(width: 12),
                _buildStatChip('帧数', '${session.framesReceived}'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  provider.disconnectFromDevice();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('断开连接'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionCard(AppStateProvider provider) {
    return Card(
      color: AppConfig.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '权限检查',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 12),
            _buildPermissionRow(
              '无障碍服务',
              provider.isAccessibilityEnabled,
              onTap: provider.isAccessibilityEnabled
                  ? null
                  : () async {
                      await PlatformChannelService.instance
                          .openAccessibilitySettings();
                      // 用户手动开启后回来刷新
                      await Future.delayed(const Duration(seconds: 1));
                      await provider.refreshAccessibility();
                    },
            ),
            const Divider(color: Colors.white12, height: 16),
            _buildPermissionRow(
              '服务器连接',
              provider.connectionState == WsConnectionState.connected,
              onTap: provider.connectionState == WsConnectionState.connected
                  ? null
                  : () => provider.connectToServer(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionRow(
    String label,
    bool enabled, {
    VoidCallback? onTap,
  }) {
    return Row(
      children: [
        Icon(
          enabled ? Icons.check_circle : Icons.warning,
          color: enabled ? Colors.green : Colors.orange,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 14,
            ),
          ),
        ),
        if (!enabled && onTap != null)
          TextButton(
            onPressed: onTap,
            child: const Text('去设置'),
          ),
      ],
    );
  }

  void _showConnectionRequestDialog(
      String fromId, String fromName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConfig.surfaceColor,
        title: Row(
          children: [
            const Icon(Icons.person_add, color: AppConfig.primaryColor),
            const SizedBox(width: 8),
            const Text(
              '连接请求',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '设备 "$fromName" 请求远程控制你的设备',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              'ID: $fromId',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AppStateProvider>().rejectConnection(fromId);
            },
            child: const Text('拒绝'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AppStateProvider>().acceptConnection(fromId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConfig.primaryColor,
            ),
            child: const Text('接受'),
          ),
        ],
      ),
    ).then((_) {
      _showingDialog = false;
    });
  }

  void _exitControlledMode() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConfig.surfaceColor,
        title: const Text(
          '退出被控模式',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          '退出后将停止接受远程控制',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<AppStateProvider>().exitControlledMode();
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }
}
