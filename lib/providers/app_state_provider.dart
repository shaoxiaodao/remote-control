import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../models/device_info.dart';
import '../models/session.dart';
import '../models/control_command.dart';
import '../services/websocket_service.dart';
import '../services/platform_channel_service.dart';
import '../utils/device_id_generator.dart';

/// 全局应用状态管理
class AppStateProvider extends ChangeNotifier {
  final WebSocketService _wsService = WebSocketService();
  final PlatformChannelService _platform = PlatformChannelService.instance;

  // ─── 状态 ───
  AppMode _mode = AppMode.idle;
  DeviceInfo? _localDevice;
  RemoteSession? _session;
  List<DeviceInfo> _onlineDevices = [];
  String _statusMessage = '未连接';
  Uint8List? _latestFrame;
  bool _isAccessibilityEnabled = false;
  int _frameSequence = 0;
  Timer? _fpsTimer;
  int _frameCount = 0;

  // ─── 断线重连状态 ───
  AppMode? _previousMode;
  String? _remoteDeviceId;
  Timer? _streamRetryTimer;
  int _streamRetryCount = 0;
  final Set<String> _trustedDevices = {};

  // ─── 流订阅（用于 dispose 时取消） ───
  StreamSubscription? _wsMsgSub;
  StreamSubscription? _wsConnSub;
  StreamSubscription? _frameSub;

  // ─── Getters ───
  AppMode get mode => _mode;
  DeviceInfo? get localDevice => _localDevice;
  RemoteSession? get session => _session;
  List<DeviceInfo> get onlineDevices => _onlineDevices;
  String get statusMessage => _statusMessage;
  Uint8List? get latestFrame => _latestFrame;
  bool get isAccessibilityEnabled => _isAccessibilityEnabled;
  WebSocketService get wsService => _wsService;
  WsConnectionState get connectionState => _wsService.state;

  // ─── 初始化 ───
  Future<void> initialize() async {
    await _initLocalDevice();
    _setupWebSocketListeners();
    _setupPlatformListeners();
    await _checkAccessibility();
  }

  Future<void> _initLocalDevice() async {
    final deviceId = await _platform.getDeviceId();
    final deviceName = await _platform.getDeviceName();
    final screenSize = await _platform.getScreenSize();
    final deviceInfo = DeviceInfoPlugin();

    String platform = 'unknown';
    String osVersion = '';

    if (defaultTargetPlatform == TargetPlatform.android) {
      platform = 'android';
      final info = await deviceInfo.androidInfo;
      osVersion = 'Android ${info.version.release}';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      platform = 'ios';
      final info = await deviceInfo.iosInfo;
      osVersion = info.systemVersion;
    }

    // 生成或读取持久化的设备ID
    final prefs = await SharedPreferences.getInstance();
    String persistentId = prefs.getString('device_id') ?? '';
    if (persistentId.isEmpty) {
      persistentId = generateDeviceId();
      await prefs.setString('device_id', persistentId);
    }

    _localDevice = DeviceInfo(
      deviceId: persistentId,
      deviceName: deviceName,
      platform: platform,
      osVersion: osVersion,
      screenWidth: screenSize['width'] ?? 1080,
      screenHeight: screenSize['height'] ?? 1920,
      lastSeen: DateTime.now(),
      status: DeviceStatus.online,
    );

    notifyListeners();
  }

  // ═══════════════════════════════════════════
  //  WebSocket 连接管理
  // ═══════════════════════════════════════════

  Future<bool> connectToServer() async {
    if (_localDevice == null) return false;

    _statusMessage = '正在连接服务器...';
    notifyListeners();

    final connected = await _wsService.connect(_localDevice!.deviceId);
    if (connected) {
      _statusMessage = '已连接到服务器';
    } else {
      _statusMessage = '连接失败，请检查服务器地址';
    }
    notifyListeners();
    return connected;
  }

  void disconnectFromServer() {
    _stopStreaming();
    _wsService.disconnect();
    _statusMessage = '已断开连接';
    _mode = AppMode.idle;
    _onlineDevices.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════
  //  控制模式（作为控制端）
  // ═══════════════════════════════════════════

  /// 请求连接到远程设备
  void connectToDevice(String targetDeviceId) {
    if (_localDevice == null) return;
    _mode = AppMode.controlling;
    _session = RemoteSession(
      sessionId: const Uuid().v4(),
      localDevice: _localDevice!,
      state: SessionState.connecting,
    );
    _statusMessage = '正在请求连接...';
    _wsService.requestConnect(targetDeviceId);
    notifyListeners();
  }

  /// 发送控制命令
  void sendCommand(ControlCommand command) {
    if (_session?.remoteDevice == null) return;
    _wsService.sendControlCommand(
      _session!.remoteDevice!.deviceId,
      command,
    );
    _session!.commandsSent++;
    notifyListeners();
  }

  /// 请求远程设备唤醒
  void wakeRemoteDevice() {
    if (_session?.remoteDevice == null) return;
    _wsService.sendMessage({
      'type': MessageType.wakeUp,
      'targetId': _session!.remoteDevice!.deviceId,
    });
  }

  /// 断开与远程设备的连接
  void disconnectFromDevice() {
    if (_session?.remoteDevice != null) {
      _wsService.stopStream(_session!.remoteDevice!.deviceId);
      _wsService.sendMessage({
        'type': MessageType.disconnect,
        'targetId': _session!.remoteDevice!.deviceId,
      });
    }
    _session?.reset();
    _mode = AppMode.idle;
    _latestFrame = null;
    _previousMode = null;
    _remoteDeviceId = null;
    _streamRetryTimer?.cancel();
    _streamRetryCount = 0;
    _statusMessage = '已断开远程连接';
    notifyListeners();
  }

  // ═══════════════════════════════════════════
  //  被控模式（作为被控端）
  // ═══════════════════════════════════════════

  /// 进入被控等待模式
  Future<void> enterControlledMode() async {
    _mode = AppMode.controlled;
    _previousMode = null; // 新进入被控，不需要重连
    _statusMessage = '等待远程控制连接...';

    // 加载可信设备列表
    await _loadTrustedDevices();

    // 启动前台服务保活
    await _platform.startForegroundService();
    // 保持屏幕常亮
    await _platform.keepScreenOn(true);

    notifyListeners();
  }

  /// 退出被控模式
  Future<void> exitControlledMode() async {
    _stopStreaming();
    await _platform.keepScreenOn(false);
    await _platform.stopScreenCapture();
    _mode = AppMode.idle;
    _previousMode = null;
    _remoteDeviceId = null;
    _statusMessage = '已退出被控模式';
    notifyListeners();
  }

  /// 接受远程连接请求
  void acceptConnection(String controllerId) {
    if (_localDevice == null) return;
    _wsService.sendMessage({
      'type': MessageType.connectAccepted,
      'targetId': controllerId,
    });

    // 从在线设备列表中查找控制端设备
    final controllers = _onlineDevices.where((d) => d.deviceId == controllerId).toList();
    final remoteDevice = controllers.isNotEmpty
        ? controllers.first
        : DeviceInfo(
            deviceId: controllerId,
            deviceName: 'Unknown',
            platform: 'unknown',
            osVersion: '',
            screenWidth: 1080,
            screenHeight: 1920,
            lastSeen: DateTime.now(),
          );

    _session = RemoteSession(
      sessionId: const Uuid().v4(),
      localDevice: _localDevice!,
      remoteDevice: remoteDevice,
      state: SessionState.connected,
    );
    _statusMessage = '远程连接已建立';
    notifyListeners();
  }

  /// 拒绝远程连接请求
  void rejectConnection(String controllerId) {
    _wsService.sendMessage({
      'type': MessageType.connectRejected,
      'targetId': controllerId,
      'reason': '用户拒绝',
    });
    _statusMessage = '已拒绝连接请求';
    notifyListeners();
  }

  // ═══════════════════════════════════════════
  //  屏幕投屏
  // ═══════════════════════════════════════════

  Future<void> _startStreaming(String targetId) async {
    // 如果已经在投屏，先停止旧的捕获（处理重复 start_stream）
    if (_session?.state == SessionState.streaming) {
      await _platform.stopScreenCapture();
    }

    final success = await _platform.startScreenCapture(
      fps: AppConfig.screenCaptureFps,
      quality: AppConfig.jpegQuality,
      maxWidth: AppConfig.maxFrameWidth,
    );

    if (success) {
      _session?.state = SessionState.streaming;
      _statusMessage = '正在投屏...';
      _startFpsCounter();
      notifyListeners();
    } else {
      _statusMessage = '屏幕捕获启动失败';
      // 通知控制端投屏失败
      if (_session?.remoteDevice != null) {
        _wsService.sendMessage({
          'type': MessageType.streamError,
          'targetId': _session!.remoteDevice!.deviceId,
          'reason': 'screen_capture_failed',
        });
      }
      notifyListeners();
    }
  }

  void _stopStreaming() {
    _platform.stopScreenCapture();
    _fpsTimer?.cancel();
    _frameCount = 0;
    if (_session != null) {
      _session!.state = SessionState.connected;
      _session!.fps = 0;
    }
  }

  void _startFpsCounter() {
    _fpsTimer?.cancel();
    _frameCount = 0;
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_session != null) {
        _session!.fps = _frameCount;
        _frameCount = 0;
        notifyListeners();
      }
    });
  }

  // ═══════════════════════════════════════════
  //  WebSocket 消息处理
  // ═══════════════════════════════════════════

  void _setupWebSocketListeners() {
    _wsMsgSub = _wsService.messageStream.listen(_handleMessage);
    _wsConnSub = _wsService.connectionStateStream.listen((state) {
      switch (state) {
        case WsConnectionState.connected:
          _statusMessage = '已连接到服务器';
          // 断线重连：恢复之前的模式并重新建立连接
          _attemptAutoReconnect();
          break;
        case WsConnectionState.connecting:
          _statusMessage = '正在连接...';
          break;
        case WsConnectionState.disconnected:
          _statusMessage = '连接已断开，正在重连...';
          // 保存当前模式用于断线重连（不重置！）
          if (_mode != AppMode.idle) {
            _previousMode = _mode;
            if (_session?.remoteDevice != null) {
              _remoteDeviceId = _session!.remoteDevice!.deviceId;
            }
            // 被控端：停止投屏等待重连
            if (_mode == AppMode.controlled) {
              _platform.stopScreenCapture();
            }
          }
          break;
        case WsConnectionState.error:
          _statusMessage = '连接错误';
          break;
      }
      notifyListeners();
    });
  }

  void _setupPlatformListeners() {
    // 监听来自原生的屏幕帧
    _frameSub = _platform.frameStream.listen((frame) {
      _frameCount++;
      // 将帧发送给远程的控制端
      if (_mode == AppMode.controlled && _session?.remoteDevice != null) {
        _frameSequence++;
        final base64 = base64Encode(frame);
        _wsService.sendScreenFrame(
          _session!.remoteDevice!.deviceId,
          base64,
          _frameSequence,
        );
      }
    });
  }

  void _handleMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;
    switch (type) {
      case MessageType.registered:
        _statusMessage = '设备已注册，等待连接';
        break;

      case MessageType.deviceList:
        final devices = (message['devices'] as List?)
                ?.map((d) => DeviceInfo.fromJson(d as Map<String, dynamic>))
                .where((d) => d.deviceId != _localDevice?.deviceId)
                .toList() ??
            [];
        _onlineDevices = devices;
        break;

      case MessageType.deviceOnline:
        final device = DeviceInfo.fromJson(
            message['device'] as Map<String, dynamic>);
        if (device.deviceId != _localDevice?.deviceId) {
          _onlineDevices.removeWhere(
              (d) => d.deviceId == device.deviceId);
          _onlineDevices.add(device);
        }
        break;

      case MessageType.deviceOffline:
        final deviceId = message['deviceId'] as String?;
        if (deviceId != null) {
          _onlineDevices.removeWhere((d) => d.deviceId == deviceId);
        }
        break;

      case MessageType.requestConnect:
        // 有人请求连接本设备（被控端收到）
        _onConnectionRequest(message);
        break;

      case MessageType.connectAccepted:
        // 对方接受了连接（控制端收到）
        _onConnectionAccepted(message);
        break;

      case MessageType.connectRejected:
        _statusMessage = '连接被拒绝: ${message['reason'] ?? ''}';
        _mode = AppMode.idle;
        _previousMode = null;
        break;

      case MessageType.startStream:
        // 控制端请求开始投屏（被控端收到）
        _startStreaming(message['fromId'] as String? ?? '').catchError((_) {});
        break;

      case MessageType.stopStream:
        _stopStreaming();
        break;

      case MessageType.screenFrame:
        // 收到屏幕帧（控制端收到）
        _onScreenFrame(message);
        break;

      case MessageType.controlCommand:
        // 收到控制命令（被控端收到）
        _onControlCommand(message);
        break;

      case MessageType.wakeUp:
        // 收到唤醒命令（被控端收到）
        _platform.wakeUpScreen();
        break;

      case MessageType.disconnect:
        // 远程设备断开
        _onRemoteDisconnect(message);
        break;

      case MessageType.pong:
        // 计算延迟
        final sentTs = message['timestamp'] as int? ?? 0;
        if (sentTs > 0 && _session != null) {
          _session!.latencyMs =
              (DateTime.now().millisecondsSinceEpoch - sentTs).toDouble();
        }
        break;

      case MessageType.streamError:
        _statusMessage = '投屏失败: ${message['reason'] ?? '未知错误'}';
        _streamRetryTimer?.cancel();
        break;

      case MessageType.error:
        _statusMessage = '服务器错误: ${message['message'] ?? ''}';
        break;
    }
    notifyListeners();
  }

  void _onConnectionRequest(Map<String, dynamic> message) {
    final fromId = message['fromId'] as String?;
    if (fromId != null) {
      // 自动接受可信设备的连接请求
      if (_trustedDevices.contains(fromId)) {
        _statusMessage = '自动接受可信设备连接...';
        acceptConnection(fromId);
        return;
      }
      _statusMessage = '收到来自 $fromId 的连接请求';

      // 首次连接的设备自动加入可信列表（不再需要反复确认）
      _trustedDevices.add(fromId);
      _saveTrustedDevices();
    }
  }

  void _onConnectionAccepted(Map<String, dynamic> message) {
    final fromId = message['fromId'] as String?;

    // 如果 session 为 null（断线重连后），重新创建
    if (_session == null && _localDevice != null) {
      _session = RemoteSession(
        sessionId: const Uuid().v4(),
        localDevice: _localDevice!,
        state: SessionState.connecting,
      );
    }

    if (_session != null) {
      _session!.state = SessionState.connected;
      _latestFrame = null;
      _statusMessage = '连接已建立，开始投屏...';

      if (fromId != null) {
        _wsService.startStream(fromId);
        _remoteDeviceId = fromId;

        // 启动投屏重试计时器（如果 10 秒没收到帧，自动重试）
        _streamRetryCount = 0;
        _startStreamRetryTimer(fromId);
      }
    }
  }

  void _onScreenFrame(Map<String, dynamic> message) {
    final frame = message['frame'] as String?;
    if (frame != null) {
      try {
        _latestFrame = base64Decode(frame);
        _session?.framesReceived++;
        // 收到帧说明投屏正常，取消重试计时器
        _streamRetryTimer?.cancel();
        _streamRetryTimer = null;
        // 计算帧延迟
        final timestamp = message['timestamp'] as int? ?? 0;
        if (timestamp > 0 && _session != null) {
          _session!.latencyMs =
              (DateTime.now().millisecondsSinceEpoch - timestamp).toDouble();
        }
      } catch (_) {
        // 忽略格式错误的帧，不中断流
      }
    }
  }

  void _onControlCommand(Map<String, dynamic> message) {
    final cmdJson = message['command'] as Map<String, dynamic>?;
    if (cmdJson == null) return;

    final cmd = ControlCommand.fromJson(cmdJson);
    final screenSize = _localDevice != null
        ? (_localDevice!.screenWidth, _localDevice!.screenHeight)
        : (1080, 1920);

    switch (cmd.type) {
      case ControlCommandType.touchDown:
        _platform.simulateTouchDown(
          cmd.x * screenSize.$1,
          cmd.y * screenSize.$2,
          screenWidth: screenSize.$1,
          screenHeight: screenSize.$2,
        );
        break;
      case ControlCommandType.touchMove:
        _platform.simulateTouchMove(
          cmd.x * screenSize.$1,
          cmd.y * screenSize.$2,
        );
        break;
      case ControlCommandType.touchUp:
        _platform.simulateTouchUp(
          cmd.x * screenSize.$1,
          cmd.y * screenSize.$2,
        );
        break;
      case ControlCommandType.scroll:
        _platform.simulateScroll(
          cmd.x * screenSize.$1,
          cmd.y * screenSize.$2,
          cmd.scrollDelta ?? 0,
        );
        break;
      case ControlCommandType.keyAction:
        _platform.simulateKeyAction(cmd.keyAction ?? 'back');
        break;
      case ControlCommandType.wakeUp:
        _platform.wakeUpScreen();
        break;
      case ControlCommandType.lockScreen:
        _platform.lockScreen();
        break;
      default:
        break;
    }
  }

  void _onRemoteDisconnect(Map<String, dynamic> message) {
    final reason = message['reason'] as String? ?? '设备已离线';
    // 保存状态用于自动重连
    _previousMode = _mode;
    _remoteDeviceId = _session?.remoteDevice?.deviceId;
    _session?.reset();
    _latestFrame = null;
    _streamRetryTimer?.cancel();
    _statusMessage = '远程设备已断开，等待重连...';
  }

  Future<void> _checkAccessibility() async {
    _isAccessibilityEnabled =
        await _platform.isAccessibilityServiceEnabled();
    notifyListeners();
  }

  Future<void> refreshAccessibility() async {
    await _checkAccessibility();
  }

  // ═══════════════════════════════════════════
  //  断线自动重连
  // ═══════════════════════════════════════════

  /// WebSocket 重连成功后，自动恢复之前的会话
  void _attemptAutoReconnect() {
    if (_previousMode == AppMode.controlling && _remoteDeviceId != null) {
      // 控制端：自动重新连接到之前的被控设备
      final targetId = _remoteDeviceId!;
      _previousMode = null;

      // 确认目标设备仍在线
      if (_onlineDevices.any((d) => d.deviceId == targetId)) {
        _statusMessage = '正在自动重连...';
        _mode = AppMode.controlling;
        _session = RemoteSession(
          sessionId: const Uuid().v4(),
          localDevice: _localDevice!,
          state: SessionState.connecting,
        );
        _wsService.requestConnect(targetId);
        notifyListeners();
      }
    } else if (_previousMode == AppMode.controlled) {
      // 被控端：恢复被控模式，等待控制端重新连接
      _previousMode = null;
      _mode = AppMode.controlled;
      _statusMessage = '已重连，等待控制端连接...';
      notifyListeners();
    }
  }

  /// 投屏重试计时器：如果 N 秒没收到帧，自动重新请求投屏
  void _startStreamRetryTimer(String targetId) {
    _streamRetryTimer?.cancel();
    _streamRetryTimer = Timer(const Duration(seconds: 10), () {
      // 如果还没有收到帧且仍在连接状态，重试
      if (_latestFrame == null &&
          _session != null &&
          _session!.state == SessionState.connected &&
          _mode == AppMode.controlling) {
        if (_streamRetryCount < 5) {
          _streamRetryCount++;
          _statusMessage = '等待屏幕画面，正在重试($_streamRetryCount/5)...';
          _wsService.startStream(targetId);
          _startStreamRetryTimer(targetId); // 继续重试
          notifyListeners();
        } else {
          _statusMessage = '无法获取远程屏幕，请检查对方是否已授权';
          notifyListeners();
        }
      }
    });
  }

  /// 手动重试投屏（UI 调用）
  void retryStream() {
    if (_session?.remoteDevice != null && _mode == AppMode.controlling) {
      _latestFrame = null;
      _session!.state = SessionState.connected;
      _streamRetryCount = 0;
      _wsService.startStream(_session!.remoteDevice!.deviceId);
      _startStreamRetryTimer(_session!.remoteDevice!.deviceId);
      _statusMessage = '重新请求屏幕画面...';
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════
  //  可信设备管理
  // ═══════════════════════════════════════════

  Future<void> _loadTrustedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final devices = prefs.getStringList('trusted_devices') ?? [];
    _trustedDevices.clear();
    _trustedDevices.addAll(devices);
  }

  Future<void> _saveTrustedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('trusted_devices', _trustedDevices.toList());
  }

  @override
  void dispose() {
    _wsMsgSub?.cancel();
    _wsConnSub?.cancel();
    _frameSub?.cancel();
    _wsService.dispose();
    _fpsTimer?.cancel();
    _streamRetryTimer?.cancel();
    super.dispose();
  }
}

enum AppMode {
  idle,        // 空闲（未处于任何会话）
  controlling, // 控制端模式
  controlled,  // 被控端模式
}
