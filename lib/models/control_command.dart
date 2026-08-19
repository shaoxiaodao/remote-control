import 'dart:convert';

/// 远程控制命令模型
class ControlCommand {
  final ControlCommandType type;
  final double x; // 归一化坐标 0.0 ~ 1.0
  final double y;
  final double? force; // 按压强度（可选）
  final double? scrollDelta; // 滚动量
  final double? scale; // 缩放因子（捏合手势）
  final String? keyAction; // 按键动作（如 back, home）
  final int timestamp;

  const ControlCommand({
    required this.type,
    this.x = 0.0,
    this.y = 0.0,
    this.force,
    this.scrollDelta,
    this.scale,
    this.keyAction,
    int? timestamp,
  }) : timestamp = timestamp ?? 0;

  /// 创建时自动填充时间戳
  factory ControlCommand.touchDown(double x, double y) {
    return ControlCommand(
      type: ControlCommandType.touchDown,
      x: x,
      y: y,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory ControlCommand.touchMove(double x, double y) {
    return ControlCommand(
      type: ControlCommandType.touchMove,
      x: x,
      y: y,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory ControlCommand.touchUp(double x, double y) {
    return ControlCommand(
      type: ControlCommandType.touchUp,
      x: x,
      y: y,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory ControlCommand.scroll(double x, double y, double delta) {
    return ControlCommand(
      type: ControlCommandType.scroll,
      x: x,
      y: y,
      scrollDelta: delta,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory ControlCommand.keyAction(String action) {
    return ControlCommand(
      type: ControlCommandType.keyAction,
      keyAction: action,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory ControlCommand.wakeUp() {
    return ControlCommand(
      type: ControlCommandType.wakeUp,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory ControlCommand.lockScreen() {
    return ControlCommand(
      type: ControlCommandType.lockScreen,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'x': x,
    'y': y,
    if (force != null) 'force': force,
    if (scrollDelta != null) 'scrollDelta': scrollDelta,
    if (scale != null) 'scale': scale,
    if (keyAction != null) 'keyAction': keyAction,
    'timestamp': timestamp,
  };

  factory ControlCommand.fromJson(Map<String, dynamic> json) => ControlCommand(
    type: ControlCommandType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => ControlCommandType.touchDown,
    ),
    x: (json['x'] as num?)?.toDouble() ?? 0.0,
    y: (json['y'] as num?)?.toDouble() ?? 0.0,
    force: (json['force'] as num?)?.toDouble(),
    scrollDelta: (json['scrollDelta'] as num?)?.toDouble(),
    scale: (json['scale'] as num?)?.toDouble(),
    keyAction: json['keyAction'] as String?,
    timestamp: json['timestamp'] as int? ?? 0,
  );

  String encode() => jsonEncode(toJson());
}

enum ControlCommandType {
  touchDown,
  touchMove,
  touchUp,
  scroll,
  keyAction,   // 返回键、Home键等
  wakeUp,      // 唤醒屏幕
  lockScreen,  // 锁屏
  screenshot,  // 截图
  openApp,     // 打开指定App
}
