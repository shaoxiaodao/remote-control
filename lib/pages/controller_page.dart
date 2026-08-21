import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../config/app_config.dart';
import '../models/control_command.dart';
import '../models/session.dart';
import '../widgets/screen_view.dart';
import '../widgets/touch_overlay.dart';

/// 控制端页面 —— 显示远程屏幕并发送控制命令
class ControllerPage extends StatefulWidget {
  const ControllerPage({super.key});

  @override
  State<ControllerPage> createState() => _ControllerPageState();
}

class _ControllerPageState extends State<ControllerPage> {
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _scheduleHideControls();
    // 保持竖屏，使用沉浸式状态栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _showControls) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _scheduleHideControls();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Consumer<AppStateProvider>(
          builder: (context, provider, _) {
            final session = provider.session;
            final frame = provider.latestFrame;

            return Stack(
              children: [
                // ─── 远程屏幕（带触控覆盖）───
                TouchOverlay(
                  remoteScreenWidth: session?.remoteDevice?.screenWidth.toDouble() ?? 1080,
                  remoteScreenHeight: session?.remoteDevice?.screenHeight.toDouble() ?? 1920,
                  onCommand: (cmd) {
                    provider.sendCommand(cmd);
                    _scheduleHideControls();
                  },
                  child: GestureDetector(
                    onTap: _toggleControls,
                    child: ScreenView(
                      frameData: frame,
                      aspectRatio: _getAspectRatio(session),
                    ),
                  ),
                ),

                // ─── 顶部状态栏 ───
                if (_showControls) _buildTopBar(provider, session),

                // ─── 底部控制栏 ───
                if (_showControls) _buildBottomBar(provider),

                // ─── 连接状态提示 ───
                if (session == null ||
                    session.state == SessionState.connecting)
                  _buildConnectingOverlay(),

                if (frame == null &&
                    session != null &&
                    session.state == SessionState.connected)
                  _buildWaitingOverlay(provider),
              ],
            );
          },
        ),
      ),
    );
  }

  double _getAspectRatio(RemoteSession? session) {
    if (session?.remoteDevice != null) {
      final h = session!.remoteDevice!.screenHeight;
      if (h > 0) {
        return session.remoteDevice!.screenWidth / h;
      }
    }
    return 9 / 16;
  }

  Widget _buildTopBar(AppStateProvider provider, RemoteSession? session) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top,
          left: 16,
          right: 16,
          bottom: 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            // 返回按钮
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => _handleBack(),
            ),
            const SizedBox(width: 8),
            // 设备名称
            Expanded(
              child: Text(
                session?.remoteDevice?.deviceName ?? '远程设备',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // 延迟指示
            if (session != null) _buildLatencyIndicator(session),
            const SizedBox(width: 12),
            // FPS
            if (session != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${session.fps} FPS',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLatencyIndicator(RemoteSession session) {
    final latency = session.latencyMs;
    Color color;
    if (latency < 100) {
      color = Colors.green;
    } else if (latency < 300) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${latency.toInt()}ms',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(AppStateProvider provider) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 8,
          top: 8,
          left: 16,
          right: 16,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildActionButton(
              icon: Icons.arrow_back,
              label: '返回',
              onTap: () => provider.sendCommand(
                ControlCommand.keyAction('back'),
              ),
            ),
            _buildActionButton(
              icon: Icons.home,
              label: '主页',
              onTap: () => provider.sendCommand(
                ControlCommand.keyAction('home'),
              ),
            ),
            _buildActionButton(
              icon: Icons.square,
              label: '最近',
              onTap: () => provider.sendCommand(
                ControlCommand.keyAction('recent'),
              ),
            ),
            _buildActionButton(
              icon: Icons.screen_lock_portrait,
              label: '锁屏',
              onTap: () => provider.sendCommand(
                ControlCommand.lockScreen(),
              ),
            ),
            _buildActionButton(
              icon: Icons.brightness_high,
              label: '唤醒',
              onTap: () => provider.wakeRemoteDevice(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppConfig.primaryColor),
            const SizedBox(height: 24),
            Text(
              '正在连接远程设备...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingOverlay(AppStateProvider provider) {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.screen_share,
              size: 64,
              color: AppConfig.primaryColor,
            ),
            const SizedBox(height: 16),
            Text(
              provider.statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '远程设备可能未授权屏幕捕获',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => provider.retryStream(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConfig.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleBack() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConfig.surfaceColor,
        title: const Text(
          '断开连接',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          '确定要断开与远程设备的连接吗？',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AppStateProvider>().disconnectFromDevice();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('断开'),
          ),
        ],
      ),
    );
  }
}
