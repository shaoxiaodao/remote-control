import 'device_info.dart';

/// 远程控制会话模型
class RemoteSession {
  final String sessionId;
  final DeviceInfo localDevice;
  DeviceInfo? remoteDevice;
  SessionState state;
  DateTime startTime;
  int framesReceived;
  int commandsSent;
  double latencyMs; // 当前延迟（毫秒）
  int fps;          // 实际帧率

  RemoteSession({
    required this.sessionId,
    required this.localDevice,
    this.remoteDevice,
    this.state = SessionState.idle,
    DateTime? startTime,
    this.framesReceived = 0,
    this.commandsSent = 0,
    this.latencyMs = 0.0,
    this.fps = 0,
  }) : startTime = startTime ?? DateTime.now();

  Duration get duration => DateTime.now().difference(startTime);

  String get durationString {
    final d = duration;
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void reset() {
    state = SessionState.idle;
    remoteDevice = null;
    framesReceived = 0;
    commandsSent = 0;
    latencyMs = 0.0;
    fps = 0;
  }
}

enum SessionState {
  idle,           // 未连接
  connecting,     // 正在连接到中继服务器
  waitingPeer,    // 等待对方连接
  connected,      // 已连接但尚未开始投屏
  streaming,      // 正在投屏
  controlling,    // 正在控制
  paused,         // 暂停
  disconnected,   // 已断开
  error,          // 出错
}

extension SessionStateExt on SessionState {
  String get displayName {
    switch (this) {
      case SessionState.idle:
        return '未连接';
      case SessionState.connecting:
        return '正在连接...';
      case SessionState.waitingPeer:
        return '等待对方连接...';
      case SessionState.connected:
        return '已连接';
      case SessionState.streaming:
        return '投屏中';
      case SessionState.controlling:
        return '控制中';
      case SessionState.paused:
        return '已暂停';
      case SessionState.disconnected:
        return '已断开';
      case SessionState.error:
        return '连接错误';
    }
  }

  bool get isActive =>
      this == SessionState.connected ||
      this == SessionState.streaming ||
      this == SessionState.controlling;

  bool get canControl =>
      this == SessionState.streaming ||
      this == SessionState.controlling;
}
