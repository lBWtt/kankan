import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/kk_colors.dart';

/// 装饰性封面图 — 5 种 SVG 风格图案,用 CustomPainter 实现。
///
/// 用途:
///   - ProjectCard 封面(Phase 4 接入,替换领域色块 fallback)
///   - ShareSheet 海报背景(同套路,独立可复用)
///   - 搜索结果卡片封面
///
/// 设计(HANDOFF §5 美术铁律):
///   - 全装饰,不用珊瑚橙(珊瑚橙只给 take)
///   - 5 种图案共用 [KkColors.teal](默认)或调用方传入的 [baseColor]
///   - 透明度三档:0.15 / 0.25 / 0.4(背景轻染 0.06)
///   - 不引入 flutter_svg(自绘 + RepaintBoundary 性能更可控)
///   - 每个 Painter 都实现 [shouldRepaint] — 颜色不变就不重绘
class CoverArt extends StatelessWidget {
  /// 图案: `'waves'` | `'mountains'` | `'grid'` | `'circles'` | `'ink'`
  final String pattern;

  final double width;
  final double height;

  /// 底色(默认 [KkColors.teal])。装饰专用,不接 coral。
  final Color? baseColor;

  const CoverArt({
    super.key,
    required this.pattern,
    this.width = double.infinity,
    this.height = 120,
    this.baseColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = baseColor ?? KkColors.teal;
    return SizedBox(
      width: width,
      height: height,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _painterFor(pattern, color),
          size: Size.infinite,
        ),
      ),
    );
  }

  CustomPainter _painterFor(String pattern, Color color) {
    switch (pattern) {
      case 'waves':
        return _WavesPainter(color: color);
      case 'mountains':
        return _MountainsPainter(color: color);
      case 'grid':
        return _GridPainter(color: color);
      case 'circles':
        return _CirclesPainter(color: color);
      case 'ink':
        return _InkPainter(color: color);
      default:
        return _WavesPainter(color: color);
    }
  }
}

// ── helpers ──

/// `withOpacity` 在 Flutter 3.27+ 弃用,用 `withAlpha(int)` 兼容更早版本。
/// 透明度 0.0–1.0 → alpha 0–255。
Color _a(Color c, double opacity) => c.withAlpha((opacity * 255).round());

// ──────────────────────────────────────────────────────────────────
// 1. waves — 波浪线(4 层叠加,从浅到深)
// ──────────────────────────────────────────────────────────────────
class _WavesPainter extends CustomPainter {
  final Color color;
  const _WavesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = _a(color, 0.06));

    final w = size.width;
    final h = size.height;
    final waves = <_WaveSpec>[
      _WaveSpec(yFrac: 0.30, amp: h * 0.06, len: w * 1.4, alpha: 0.15),
      _WaveSpec(yFrac: 0.45, amp: h * 0.08, len: w * 1.2, alpha: 0.25),
      _WaveSpec(yFrac: 0.62, amp: h * 0.05, len: w * 1.6, alpha: 0.25),
      _WaveSpec(yFrac: 0.78, amp: h * 0.10, len: w * 1.0, alpha: 0.40),
    ];
    for (final spec in waves) {
      final path = Path();
      final baseY = h * spec.yFrac;
      path.moveTo(0, baseY);
      for (var x = 0.0; x <= w; x += 2) {
        final t = (x / spec.len) * 2 * pi;
        path.lineTo(x, baseY + sin(t) * spec.amp);
      }
      path.lineTo(w, h);
      path.lineTo(0, h);
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = _a(color, spec.alpha)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavesPainter old) => old.color != color;
}

class _WaveSpec {
  final double yFrac;
  final double amp;
  final double len;
  final double alpha;
  const _WaveSpec({
    required this.yFrac,
    required this.amp,
    required this.len,
    required this.alpha,
  });
}

// ──────────────────────────────────────────────────────────────────
// 2. mountains — 山峦(3 层,从远到近渐深)
// ──────────────────────────────────────────────────────────────────
class _MountainsPainter extends CustomPainter {
  final Color color;
  const _MountainsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = _a(color, 0.06));

    final h = size.height;
    _drawLayer(canvas, size, baseY: h * 0.55, peakY: h * 0.25, alpha: 0.15);
    _drawLayer(canvas, size, baseY: h * 0.75, peakY: h * 0.40, alpha: 0.25);
    _drawLayer(canvas, size, baseY: h * 0.95, peakY: h * 0.55, alpha: 0.40);
  }

  void _drawLayer(
    Canvas canvas,
    Size size, {
    required double baseY,
    required double peakY,
    required double alpha,
  }) {
    final w = size.width;
    final path = Path();
    path.moveTo(0, baseY);
    // 三座山峰,中间最高
    final p1 = Offset(w * 0.20, peakY + (baseY - peakY) * 0.18);
    final p2 = Offset(w * 0.50, peakY);
    final p3 = Offset(w * 0.78, peakY + (baseY - peakY) * 0.22);
    path.lineTo(p1.dx - w * 0.12, baseY);
    path.lineTo(p1.dx, p1.dy);
    path.lineTo((p1.dx + p2.dx) / 2, baseY - (baseY - peakY) * 0.10);
    path.lineTo(p2.dx, p2.dy);
    path.lineTo((p2.dx + p3.dx) / 2, baseY - (baseY - peakY) * 0.10);
    path.lineTo(p3.dx, p3.dy);
    path.lineTo(w, baseY);
    path.lineTo(w, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = _a(color, alpha)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _MountainsPainter old) => old.color != color;
}

// ──────────────────────────────────────────────────────────────────
// 3. grid — 点阵(规则点 + 确定性散布的 accent 点)
// ──────────────────────────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  final Color color;
  const _GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = _a(color, 0.06));

    final w = size.width;
    final h = size.height;
    const step = 14.0;
    const dotR = 1.6;
    final cols = (w / step).floor();
    final rows = (h / step).floor();
    final xOff = (w - cols * step) / 2 + step / 2;
    final yOff = (h - rows * step) / 2 + step / 2;
    final basePaint = Paint()..color = _a(color, 0.25);
    final accentPaint = Paint()..color = _a(color, 0.40);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final x = xOff + c * step;
        final y = yOff + r * step;
        // 确定性散布的 accent 点(无 rng,稳定不闪)
        final accented = ((r * 7 + c * 13) % 6) == 0;
        canvas.drawCircle(
          Offset(x, y),
          dotR,
          accented ? accentPaint : basePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.color != color;
}

// ──────────────────────────────────────────────────────────────────
// 4. circles — 同心圆(5 圈从外到内渐浓 + 中心实心点)
// ──────────────────────────────────────────────────────────────────
class _CirclesPainter extends CustomPainter {
  final Color color;
  const _CirclesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = _a(color, 0.06));

    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final maxR = max(size.width, size.height) * 0.65;
    final rings = <_Ring>[
      _Ring(frac: 1.00, alpha: 0.15),
      _Ring(frac: 0.78, alpha: 0.20),
      _Ring(frac: 0.58, alpha: 0.25),
      _Ring(frac: 0.40, alpha: 0.30),
      _Ring(frac: 0.22, alpha: 0.40),
    ];
    for (final ring in rings) {
      canvas.drawCircle(
        Offset(cx, cy),
        maxR * ring.frac,
        Paint()
          ..color = _a(color, ring.alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
    // 中心实心点
    canvas.drawCircle(Offset(cx, cy), 2.4, Paint()..color = _a(color, 0.40));
  }

  @override
  bool shouldRepaint(covariant _CirclesPainter old) => old.color != color;
}

class _Ring {
  final double frac;
  final double alpha;
  const _Ring({required this.frac, required this.alpha});
}

// ──────────────────────────────────────────────────────────────────
// 5. ink — 水墨晕染(4 个 RadialGradient 墨晕叠加)
// ──────────────────────────────────────────────────────────────────
class _InkPainter extends CustomPainter {
  final Color color;
  const _InkPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = _a(color, 0.06));

    final w = size.width;
    final h = size.height;
    final m = min(w, h);
    _drawInk(canvas, Offset(w * 0.50, h * 0.50), m * 0.50, 0.40);
    _drawInk(canvas, Offset(w * 0.25, h * 0.35), m * 0.32, 0.25);
    _drawInk(canvas, Offset(w * 0.78, h * 0.65), m * 0.35, 0.25);
    _drawInk(canvas, Offset(w * 0.65, h * 0.22), m * 0.18, 0.15);
  }

  void _drawInk(Canvas canvas, Offset center, double radius, double alpha) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final shader = RadialGradient(
      colors: [_a(color, alpha), _a(color, 0.0)],
      stops: const [0.0, 1.0],
    ).createShader(rect);
    canvas.drawCircle(center, radius, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _InkPainter old) => old.color != color;
}
