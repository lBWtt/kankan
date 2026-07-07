import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_state_provider.dart';

/// 暖纸噪点底 — HANDOFF §5:暖纸噪点底 #FBF9F4。
///
/// Web 版用 SVG feTurbulence;Flutter 版用 CustomPainter 画确定性散点
/// (基于 seed 的伪随机,RepaintBoundary 包裹只画一次)。
///
/// 用法:NoiseBackground(child: ...)。底层是 Scaffold 的 KkColors.bg,
/// 上层叠这层噪点,再上层是内容。噪点在内容之下。

/// 噪点画笔(确定性,基于 seed)
class NoisePainter extends CustomPainter {
  final int seed;
  final int dotCount;
  final Color color;

  const NoisePainter({
    this.seed = 20251201,
    this.dotCount = 1800,
    this.color = const Color(0x14000000), // ~8% 黑
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rng = Random(seed);
    final paint = Paint()..color = color;
    for (var i = 0; i < dotCount; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      // 0.4–1.0 px 的微小圆点
      final r = 0.4 + rng.nextDouble() * 0.6;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant NoisePainter old) =>
      old.seed != seed || old.dotCount != dotCount || old.color != color;
}

/// 全屏噪点底包装。RepaintBoundary 隔离重绘(滚动时噪点不重画)。
class NoiseBackground extends ConsumerWidget {
  final Widget child;
  final int seed;

  const NoiseBackground({
    super.key,
    required this.child,
    this.seed = 20251201,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 暖纸底纹真生效:settings 关掉 → 不画噪点(纯 bg 底)。
    final paper = ref.watch(
      appStateProvider.select((s) => s.paperTexture),
    );
    if (!paper) return child;
    return RepaintBoundary(
      child: CustomPaint(
        painter: NoisePainter(seed: seed),
        child: child,
      ),
    );
  }
}
