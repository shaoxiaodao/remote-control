/// 设备信息模型
class DeviceInfo {
  final String deviceId;
  final String deviceName;
  final String platform; // 'android' | 'ios'
  final String osVersion;
  final int screenWidth;
  final int screenHeight;
  final DateTime lastSeen;
  final DeviceStatus status;

  DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.osVersion,
    required this.screenWidth,
    required this.screenHeight,
    required this.lastSeen,
    this.status = DeviceStatus.offline,
  });

  DeviceInfo copyWith({
    String? deviceId,
    String? deviceName,
    String? platform,
    String? osVersion,
    int? screenWidth,
    int? screenHeight,
    DateTime? lastSeen,
    DeviceStatus? status,
  }) {
    return DeviceInfo(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      platform: platform ?? this.platform,
      osVersion: osVersion ?? this.osVersion,
      screenWidth: screenWidth ?? this.screenWidth,
      screenHeight: screenHeight ?? this.screenHeight,
      lastSeen: lastSeen ?? this.lastSeen,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'platform': platform,
    'osVersion': osVersion,
    'screenWidth': screenWidth,
    'screenHeight': screenHeight,
    'lastSeen': lastSeen.toIso8601String(),
    'status': status.name,
  };

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
    deviceId: json['deviceId'] as String,
    deviceName: json['deviceName'] as String? ?? 'Unknown',
    platform: json['platform'] as String? ?? 'unknown',
    osVersion: json['osVersion'] as String? ?? '',
    screenWidth: (json['screenWidth'] as num?)?.toInt() ?? 1080,
    screenHeight: (json['screenHeight'] as num?)?.toInt() ?? 1920,
    lastSeen: json['lastSeen'] != null
        ? DateTime.parse(json['lastSeen'] as String)
        : DateTime.now(),
    status: DeviceStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => DeviceStatus.offline,
    ),
  );
}

enum DeviceStatus {
  online,
  offline,
  busy,
  controlling,
  sleep,
}
