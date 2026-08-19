import 'package:flutter/material.dart';
import '../models/control_command.dart';

/// 触控覆盖层 —— 覆盖在远程屏幕上方，捕获用户的触控操作
///
/// 将用户的触摸事件转化为归一化坐标（0.0~1.0）的 ControlCommand
/// 归一化坐标会被被控端还原为实际屏幕像素坐标
///
/// 内部会计算 letterbox 偏移，确保触摸坐标精确映射到远程屏幕画面上
class TouchOverlay extends StatefulWidget {
  final double remoteScreenWidth;
  final double remoteScreenHeight;
  final ValueChanged<ControlCommand> onCommand;
  final Widget child;

  const TouchOverlay({
    super.key,
    required this.remoteScreenWidth,
    required this.remoteScreenHeight,
    required this.onCommand,
    required this.child,
  });

  @override
  State<TouchOverlay> createState() => _TouchOverlayState();
}

class _TouchOverlayState extends State<TouchOverlay> {
  double? _lastX;
  double? _lastY;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final widgetWidth = constraints.maxWidth;
        final widgetHeight = constraints.maxHeight;

        // 计算图像实际渲染区域（BoxFit.contain + AspectRatio letterbox）
        final remoteAR = widget.remoteScreenWidth > 0 && widget.remoteScreenHeight > 0
            ? widget.remoteScreenWidth / widget.remoteScreenHeight
            : 9.0 / 16.0;
        final widgetAR = widgetHeight > 0 ? widgetWidth / widgetHeight : 1.0;

        double imgW, imgH;
        if (remoteAR > widgetAR) {
          // 远程屏幕更宽 → 图像宽度撑满，上下有黑边
          imgW = widgetWidth;
          imgH = widgetWidth / remoteAR;
        } else {
          // 远程屏幕更窄 → 图像高度撑满，左右有黑边
          imgH = widgetHeight;
          imgW = widgetHeight * remoteAR;
        }
        final offsetX = (widgetWidth - imgW) / 2;
        final offsetY = (widgetHeight - imgH) / 2;

        return Listener(
          onPointerDown: (event) {
            final pos = _normalize(event.localPosition, offsetX, offsetY, imgW, imgH);
            _lastX = pos.dx;
            _lastY = pos.dy;
            widget.onCommand(ControlCommand.touchDown(pos.dx, pos.dy));
          },
          onPointerMove: (event) {
            final pos = _normalize(event.localPosition, offsetX, offsetY, imgW, imgH);
            _lastX = pos.dx;
            _lastY = pos.dy;
            widget.onCommand(ControlCommand.touchMove(pos.dx, pos.dy));
          },
          onPointerUp: (event) {
            final pos = _normalize(event.localPosition, offsetX, offsetY, imgW, imgH);
            widget.onCommand(ControlCommand.touchUp(pos.dx, pos.dy));
            _lastX = null;
            _lastY = null;
          },
          child: widget.child,
        );
      },
    );
  }

  /// 将局部坐标转为归一化坐标 (0.0 ~ 1.0)，映射到图像实际渲染区域
  Offset _normalize(Offset local, double offX, double offY, double imgW, double imgH) {
    if (imgW <= 0 || imgH <= 0) return Offset.zero;
    final x = ((local.dx - offX) / imgW).clamp(0.0, 1.0);
    final y = ((local.dy - offY) / imgH).clamp(0.0, 1.0);
    return Offset(x, y);
  }
}
