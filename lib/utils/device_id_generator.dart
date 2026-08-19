import 'dart:math';
import '../config/app_config.dart';

/// 生成设备唯一 ID
/// 格式: RC + 9位随机数字，例如 RC123456789
String generateDeviceId() {
  final random = Random.secure();
  final digits = List.generate(
    AppConfig.deviceIdLength,
    (_) => random.nextInt(10).toString(),
  ).join();
  return '${AppConfig.deviceIdPrefix}$digits';
}

/// 格式化设备 ID 为可读形式（添加空格分隔）
/// RC123456789 → RC 123 456 789
String formatDeviceId(String id) {
  if (id.length <= 2) return id;
  final prefix = id.substring(0, 2);
  final digits = id.substring(2);
  final groups = <String>[];
  for (int i = 0; i < digits.length; i += 3) {
    final end = (i + 3 > digits.length) ? digits.length : i + 3;
    groups.add(digits.substring(i, end));
  }
  return '$prefix ${groups.join(' ')}';
}
