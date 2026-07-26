import 'package:flutter/material.dart';

/// 暖纸底包装（原 NoiseBackground——噪点已删，退化为纯容器）。
class NoiseBackground extends StatelessWidget {
  final Widget child;
  final int seed;

  const NoiseBackground({
    super.key,
    required this.child,
    this.seed = 20251201,
  });

  @override
  Widget build(BuildContext context) {
    // ── [ZCode] 暖纸底纹开关已从设置移除（噪点不可见），直接返回 child ──
    return child;
  }
}
