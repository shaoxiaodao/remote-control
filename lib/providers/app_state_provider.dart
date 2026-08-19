import 'dart:async';
import 'dart:convert';
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
    _statusMessage = '已断开远程连接';
    notifyListeners();
  }

  // ═══════════════════════════════════════════
  //  被控模式（作为被控端）
  // ═══════════════════════════════════════════

  /// 进入被控等待模式
  Future<void> enterControlledMode() async {
    _mode = AppMode.controlled;
    _statusMessage = '等待远程控制连接...';

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
          break;
        case WsConnectionState.connecting:
          _statusMessage = '正在连接...';
          break;
        case WsConnectionState.disconnected:
          _statusMessage = '连接已断开';
          _mode = AppMode.idle;
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

      case MessageType.error:
        _statusMessage = '服务器错误: ${message['message'] ?? ''}';
        break;
    }
    notifyListeners();
  }

  void _onConnectionRequest(Map<String, dynamic> message) {
    // 在 UI 层会弹出对话框
    // 这里仅存储请求者信息
    final fromId = message['fromId'] as String?;
    if (fromId != null) {
      _statusMessage = '收到来自 $fromId 的连接请求';
    }
  }

  void _onConnectionAccepted(Map<String, dynamic> message) {
    if (_session != null) {
      _session!.state = SessionState.connected;
      _statusMessage = '连接已建立，开始投屏...';
      // 请求对方开始投屏
      final fromId = message['fromId'] as String?;
      if (fromId != null) {
        _wsService.startStream(fromId);
      }
    }
  }

  void _onScreenFrame(Map<String, dynamic> message) {
    final frame = message['frame'] as String?;
    if (frame != null) {
      try {
        _latestFrame = base64Decode(frame);
        _session?.framesReceived++;
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
    _session?.reset();
    _mode = AppMode.idle;
    _latestFrame = null;
    _statusMessage = '远程设备已断开';
  }

  Future<void> _checkAccessibility() async {
    _isAccessibilityEnabled =
        await _platform.isAccessibilityServiceEnabled();
    notifyListeners();
  }

  Future<void> refreshAccessibility() async {
    await _checkAccessibility();
  }

  @override
  void dispose() {
    _wsMsgSub?.cancel();
    _wsConnSub?.cancel();
    _frameSub?.cancel();
    _wsService.dispose();
    _fpsTimer?.cancel();
    // 注意：不调用 _platform.dispose()，因为它是单例
    super.dispose();
  }
}

enum AppMode {
  idle,        // 空闲（未处于任何会话）
  controlling, // 控制端模式
  controlled,  // 被控端模式
}
