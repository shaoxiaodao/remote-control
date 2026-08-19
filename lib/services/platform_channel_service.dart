import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// 平台通道服务 —— Flutter 与原生代码之间的桥接层
///
/// Android: MediaProjection 屏幕捕获 + AccessibilityService 触控模拟
/// iOS: ReplayKit Broadcast Extension 屏幕捕获（受限）
class PlatformChannelService {
  PlatformChannelService._();
  static final PlatformChannelService instance = PlatformChannelService._();

  // ─── Method Channels ───
  static const MethodChannel _screenChannel =
      MethodChannel('com.remotecontrol/screen_capture');
  static const MethodChannel _controlChannel =
      MethodChannel('com.remotecontrol/touch_control');
  static const MethodChannel _wakeChannel =
      MethodChannel('com.remotecontrol/wake_lock');
  static const MethodChannel _deviceChannel =
      MethodChannel('com.remotecontrol/device_info');

  // ─── Event Channels ───
  static const EventChannel _frameChannel =
      EventChannel('com.remotecontrol/screen_frames');
  static const EventChannel _statusChannel =
      EventChannel('com.remotecontrol/service_status');

  StreamSubscription? _frameSubscription;
  StreamSubscription? _statusSubscription;

  // ─── 屏幕帧流 ───
  final _frameController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get frameStream => _frameController.stream;

  // ─── 服务状态流 ───
  final _statusController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;

  // ═══════════════════════════════════════════
  //  屏幕捕获
  // ═══════════════════════════════════════════

  /// 请求屏幕捕获权限并开始捕获
  /// 返回是否成功
  Future<bool> startScreenCapture({
    int fps = 15,
    int quality = 50,
    int maxWidth = 720,
  }) async {
    try {
      final result = await _screenChannel.invokeMethod<bool>('startCapture', {
        'fps': fps,
        'quality': quality,
        'maxWidth': maxWidth,
      });
      if (result == true) {
        _startListeningFrames();
      }
      return result ?? false;
    } on PlatformException catch (e) {
      print('Screen capture error: ${e.message}');
      return false;
    }
  }

  /// 停止屏幕捕获
  Future<void> stopScreenCapture() async {
    _stopListeningFrames();
    try {
      await _screenChannel.invokeMethod('stopCapture');
    } on PlatformException catch (e) {
      print('Stop capture error: ${e.message}');
    }
  }

  /// 检查屏幕捕获是否正在运行
  Future<bool> isCapturing() async {
    try {
      return await _screenChannel.invokeMethod<bool>('isCapturing') ?? false;
    } on PlatformException {
      return false;
    }
  }

  void _startListeningFrames() {
    _frameSubscription?.cancel();
    _frameSubscription = _frameChannel.receiveBroadcastStream().listen(
      (data) {
        if (data is Uint8List) {
          _frameController.add(data);
        }
      },
      onError: (e) {
        print('Frame stream error: $e');
      },
    );
  }

  void _stopListeningFrames() {
    _frameSubscription?.cancel();
    _frameSubscription = null;
  }

  // ═══════════════════════════════════════════
  //  触控模拟
  // ═══════════════════════════════════════════

  /// 检查 AccessibilityService 是否可用（Android only）
  Future<bool> isAccessibilityServiceEnabled() async {
    try {
      return await _controlChannel
              .invokeMethod<bool>('isAccessibilityEnabled') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// 打开无障碍设置页（Android only）
  Future<void> openAccessibilitySettings() async {
    try {
      await _controlChannel.invokeMethod('openAccessibilitySettings');
    } on PlatformException catch (e) {
      print('Open accessibility settings error: ${e.message}');
    }
  }

  /// 检查是否有修改系统设置的权限（Android only）
  Future<bool> canWriteSettings() async {
    try {
      return await _controlChannel.invokeMethod<bool>('canWriteSettings') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 打开"修改系统设置"权限页面（Android only）
  Future<void> requestWriteSettings() async {
    try {
      await _controlChannel.invokeMethod('requestWriteSettings');
    } on PlatformException catch (e) {
      print('Request write settings error: ${e.message}');
    }
  }

  /// 模拟触控按下
  Future<void> simulateTouchDown(double x, double y,
      {int screenWidth = 0, int screenHeight = 0}) async {
    try {
      await _controlChannel.invokeMethod('touchDown', {
        'x': x,
        'y': y,
        'screenWidth': screenWidth,
        'screenHeight': screenHeight,
      });
    } on PlatformException catch (e) {
      print('Touch down error: ${e.message}');
    }
  }

  /// 模拟触控移动
  Future<void> simulateTouchMove(double x, double y) async {
    try {
      await _controlChannel.invokeMethod('touchMove', {
        'x': x,
        'y': y,
      });
    } on PlatformException catch (e) {
      print('Touch move error: ${e.message}');
    }
  }

  /// 模拟触控抬起
  Future<void> simulateTouchUp(double x, double y) async {
    try {
      await _controlChannel.invokeMethod('touchUp', {
        'x': x,
        'y': y,
      });
    } on PlatformException catch (e) {
      print('Touch up error: ${e.message}');
    }
  }

  /// 模拟滚动
  Future<void> simulateScroll(double x, double y, double delta) async {
    try {
      await _controlChannel.invokeMethod('scroll', {
        'x': x,
        'y': y,
        'delta': delta,
      });
    } on PlatformException catch (e) {
      print('Scroll error: ${e.message}');
    }
  }

  /// 模拟按键（back, home, recent）
  Future<void> simulateKeyAction(String action) async {
    try {
      await _controlChannel.invokeMethod('keyAction', {
        'action': action,
      });
    } on PlatformException catch (e) {
      print('Key action error: ${e.message}');
    }
  }

  // ═══════════════════════════════════════════
  //  唤醒 / 锁屏
  // ═══════════════════════════════════════════

  /// 唤醒设备屏幕
  Future<void> wakeUpScreen() async {
    try {
      await _wakeChannel.invokeMethod('wakeUp');
    } on PlatformException catch (e) {
      print('Wake up error: ${e.message}');
    }
  }

  /// 锁定屏幕
  Future<void> lockScreen() async {
    try {
      await _wakeChannel.invokeMethod('lockScreen');
    } on PlatformException catch (e) {
      print('Lock screen error: ${e.message}');
    }
  }

  /// 保持屏幕常亮
  Future<void> keepScreenOn(bool on) async {
    try {
      await _wakeChannel.invokeMethod('keepScreenOn', {'on': on});
    } on PlatformException catch (e) {
      print('Keep screen on error: ${e.message}');
    }
  }

  /// 启动前台服务（Android only, 用于保活）
  Future<void> startForegroundService() async {
    try {
      await _wakeChannel.invokeMethod('startForegroundService');
    } on PlatformException catch (e) {
      print('Foreground service error: ${e.message}');
    }
  }

  // ═══════════════════════════════════════════
  //  设备信息
  // ═══════════════════════════════════════════

  /// 获取设备唯一 ID（持久化）
  Future<String> getDeviceId() async {
    try {
      return await _deviceChannel.invokeMethod<String>('getDeviceId') ??
          'unknown';
    } on PlatformException {
      return 'unknown';
    }
  }

  /// 获取设备名称
  Future<String> getDeviceName() async {
    try {
      return await _deviceChannel.invokeMethod<String>('getDeviceName') ??
          'Unknown Device';
    } on PlatformException {
      return 'Unknown Device';
    }
  }

  /// 获取屏幕尺寸
  Future<Map<String, int>> getScreenSize() async {
    try {
      final result =
          await _deviceChannel.invokeMethod<Map>('getScreenSize');
      if (result != null) {
        return {
          'width': result['width'] as int? ?? 1080,
          'height': result['height'] as int? ?? 1920,
        };
      }
    } on PlatformException {
      // fallback
    }
    return {'width': 1080, 'height': 1920};
  }

  // ═══════════════════════════════════════════
  //  服务状态监听
  // ═══════════════════════════════════════════

  void startStatusListener() {
    _statusSubscription?.cancel();
    _statusSubscription = _statusChannel.receiveBroadcastStream().listen(
      (data) {
        if (data is Map) {
          _statusController.add(Map<String, dynamic>.from(data));
        }
      },
      onError: (e) {
        print('Status stream error: $e');
      },
    );
  }

  void dispose() {
    _frameSubscription?.cancel();
    _statusSubscription?.cancel();
    _frameController.close();
    _statusController.close();
  }
}
