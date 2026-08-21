import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';
import '../models/control_command.dart';

/// 消息类型常量
class MessageType {
  MessageType._();

  // ─── 信令消息 ───
  static const String register = 'register';           // 设备注册
  static const String registered = 'registered';       // 注册成功
  static const String requestConnect = 'request_connect';  // 请求连接
  static const String connectAccepted = 'connect_accepted'; // 连接被接受
  static const String connectRejected = 'connect_rejected'; // 连接被拒绝
  static const String deviceOnline = 'device_online';  // 设备上线通知
  static const String deviceOffline = 'device_offline'; // 设备离线通知
  static const String deviceList = 'device_list';      // 设备列表

  // ─── 控制消息 ───
  static const String screenFrame = 'screen_frame';     // 屏幕帧（Base64）
  static const String screenFrameBinary = 'screen_bin'; // 屏幕帧（二进制标记）
  static const String controlCommand = 'control_cmd';   // 控制命令
  static const String keyCommand = 'key_cmd';           // 按键命令
  static const String wakeUp = 'wake_up';               // 唤醒命令
  static const String startStream = 'start_stream';     // 开始投屏
  static const String stopStream = 'stop_stream';       // 停止投屏
  static const String ping = 'ping';                    // 心跳
  static const String pong = 'pong';                    // 心跳响应

  // ─── 系统消息 ───
  static const String error = 'error';
  static const String disconnect = 'disconnect';
  static const String streamError = 'stream_error';
}

/// WebSocket 信令与数据中继服务
///
/// 保活策略（针对长时间锁屏场景优化）：
/// 1. 指数退避重连：3s → 6s → 12s → 24s → 48s → 60s（上限），永不放弃
/// 2. 心跳超时检测：如果 N 秒没收到 pong，强制断开并重连
/// 3. 随机抖动：避免多个设备同时重连导致服务器雪崩
/// 4. 无限重试：手机锁屏可能数小时，必须持续尝试
class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _streamSub; // 当前连接的流订阅，防止重复
  Timer? _heartbeatTimer;
  Timer? _heartbeatTimeoutTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _intentionalDisconnect = false;
  final _random = Random();

  // ─── 事件流 ───
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _binaryController = StreamController<Uint8List>.broadcast();
  final _connectionStateController = StreamController<WsConnectionState>.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<Uint8List> get binaryStream => _binaryController.stream;
  Stream<WsConnectionState> get connectionStateStream => _connectionStateController.stream;

  WsConnectionState _state = WsConnectionState.disconnected;
  WsConnectionState get state => _state;

  String? _deviceId;
  String? get deviceId => _deviceId;

  /// 连接到中继服务器
  Future<bool> connect(String deviceId, {String? serverUrl}) async {
    _deviceId = deviceId;
    _intentionalDisconnect = false;
    _cleanupChannel();

    final url = serverUrl ?? AppConfig.wsUrl;
    if (url.isEmpty || !url.contains('://')) {
      _state = WsConnectionState.error;
      _connectionStateController.add(_state);
      return false;
    }

    _state = WsConnectionState.connecting;
    _connectionStateController.add(_state);

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('$url/ws'),
      );

      await _channel!.ready.timeout(AppConfig.wsConnectionTimeout);

      _state = WsConnectionState.connected;
      _connectionStateController.add(_state);
      _reconnectAttempts = 0;

      // 注册设备
      sendMessage({
        'type': MessageType.register,
        'deviceId': deviceId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // 监听消息（先取消旧订阅，防止重复）
      _streamSub = _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
      );

      // 启动心跳和超时检测
      _startHeartbeat();
      _startHeartbeatTimeout();
      return true;
    } catch (e) {
      _state = WsConnectionState.error;
      _connectionStateController.add(_state);
      _scheduleReconnect();
      return false;
    }
  }

  /// 断开连接
  void disconnect() {
    _intentionalDisconnect = true;
    _heartbeatTimer?.cancel();
    _heartbeatTimeoutTimer?.cancel();
    _reconnectTimer?.cancel();
    _streamSub?.cancel();
    _streamSub = null;
    _channel?.sink.close();
    _channel = null;
    _state = WsConnectionState.disconnected;
    _connectionStateController.add(_state);
  }

  /// 清理旧连接资源（内部使用）
  void _cleanupChannel() {
    _streamSub?.cancel();
    _streamSub = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimeoutTimer?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  /// 重置重连计数器（用户手动重试时调用）
  void resetReconnectCounter() {
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
  }

  /// 发送 JSON 消息
  void sendMessage(Map<String, dynamic> message) {
    if (_state != WsConnectionState.connected) return;
    try {
      _channel?.sink.add(jsonEncode(message));
    } catch (e) {
      // ignore send errors
    }
  }

  /// 发送二进制数据（屏幕帧）
  void sendBinary(Uint8List data) {
    if (_state != WsConnectionState.connected) return;
    try {
      _channel?.sink.add(data);
    } catch (e) {
      // ignore send errors
    }
  }

  /// 发送控制命令
  void sendControlCommand(String targetDeviceId, ControlCommand command) {
    sendMessage({
      'type': MessageType.controlCommand,
      'targetId': targetDeviceId,
      'command': command.toJson(),
    });
  }

  /// 发送屏幕帧（Base64 编码的 JPEG）
  void sendScreenFrame(String targetDeviceId, String base64Frame, int seq) {
    sendMessage({
      'type': MessageType.screenFrame,
      'targetId': targetDeviceId,
      'frame': base64Frame,
      'seq': seq,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 请求连接到目标设备
  void requestConnect(String targetDeviceId) {
    sendMessage({
      'type': MessageType.requestConnect,
      'targetId': targetDeviceId,
    });
  }

  /// 开始投屏
  void startStream(String targetDeviceId) {
    sendMessage({
      'type': MessageType.startStream,
      'targetId': targetDeviceId,
    });
  }

  /// 停止投屏
  void stopStream(String targetDeviceId) {
    sendMessage({
      'type': MessageType.stopStream,
      'targetId': targetDeviceId,
    });
  }

  // ─── 内部方法 ───

  void _onData(dynamic data) {
    if (data is String) {
      try {
        final message = jsonDecode(data) as Map<String, dynamic>;
        // 收到 pong 时重置心跳超时计时器
        if (message['type'] == MessageType.pong) {
          _startHeartbeatTimeout();
        }
        _messageController.add(message);
      } catch (e) {
        // ignore parse errors
      }
    } else if (data is Uint8List) {
      _binaryController.add(data);
    }
  }

  void _onError(dynamic error) {
    _state = WsConnectionState.error;
    _connectionStateController.add(_state);
    if (!_intentionalDisconnect) {
      _scheduleReconnect();
    }
  }

  void _onDone() {
    if (!_intentionalDisconnect) {
      _state = WsConnectionState.disconnected;
      _connectionStateController.add(_state);
      _scheduleReconnect();
    }
  }

  /// 启动心跳：每 10 秒发送一次 ping
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(AppConfig.wsHeartbeatInterval, (_) {
      sendMessage({
        'type': MessageType.ping,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  /// 心跳超时检测
  ///
  /// 如果超过 [AppConfig.heartbeatTimeout] 没收到任何数据，
  /// 说明连接可能已断（Doze 模式下 TCP 连接可能被系统静默关闭），
  /// 此时主动断开并重连，而不是傻等。
  void _startHeartbeatTimeout() {
    _heartbeatTimeoutTimer?.cancel();
    _heartbeatTimeoutTimer = Timer(AppConfig.heartbeatTimeout, () {
      if (_state == WsConnectionState.connected && !_intentionalDisconnect) {
        // 超时了，强制断开并重连
        _cleanupChannel();
        _state = WsConnectionState.disconnected;
        _connectionStateController.add(_state);
        _scheduleReconnect();
      }
    });
  }

  /// 指数退避重连
  ///
  /// 策略：
  /// - 基础延迟：3 秒
  /// - 指数增长：3s, 6s, 12s, 24s, 48s, 60s (上限)
  /// - 随机抖动：±20%，避免多个设备同时重连
  /// - 永不放弃：无限重试直到连接成功或用户手动断开
  ///
  /// 这样即使手机锁屏 8 小时后解锁，也能在几十秒内重新连上服务器。
  void _scheduleReconnect() {
    if (_intentionalDisconnect) return;

    _heartbeatTimer?.cancel();
    _heartbeatTimeoutTimer?.cancel();
    _reconnectTimer?.cancel();

    // 指数退避：baseDelay * 2^attempts，上限 60 秒
    final baseDelayMs = AppConfig.wsReconnectDelay.inMilliseconds;
    final expDelay = baseDelayMs * pow(2, min(_reconnectAttempts, 5)).toInt();
    final cappedDelay = expDelay.clamp(baseDelayMs, 60000); // 上限 60s

    // 添加 ±20% 随机抖动
    final jitter = (cappedDelay * 0.2 * (_random.nextDouble() * 2 - 1)).toInt();
    final finalDelay = Duration(milliseconds: cappedDelay + jitter);

    _reconnectTimer = Timer(finalDelay, () {
      _reconnectAttempts++;
      if (_deviceId != null) {
        connect(_deviceId!);
      }
    });
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _binaryController.close();
    _connectionStateController.close();
  }
}

enum WsConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}
