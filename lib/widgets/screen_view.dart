import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 远程屏幕显示组件
///
/// 接收 Base64 解码后的 JPEG 帧数据，渲染为实时画面
class ScreenView extends StatelessWidget {
  final Uint8List? frameData;
  final double? aspectRatio;
  final BoxFit fit;
  final Widget? overlay;

  const ScreenView({
    super.key,
    this.frameData,
    this.aspectRatio,
    this.fit = BoxFit.contain,
    this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: aspectRatio ?? (9 / 16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 屏幕帧
              if (frameData != null && frameData!.isNotEmpty)
                Image.memory(
                  frameData!,
                  fit: fit,
                  gaplessPlayback: true, // 防止闪烁
                )
              else
                _buildPlaceholder(),

              // 覆盖层（触控、UI 控件等）
              if (overlay != null) overlay!,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.smartphone,
            size: 80,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '等待画面...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
