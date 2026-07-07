import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/parse_count.dart';
import '../../core/utils/image_download.dart';
import '../../core/widgets/tappable.dart';

/// 分享浮层 — 生成可截图海报 + 渲染分享渠道。
///
/// HANDOFF §6.7 真路由:shareUrl 用真实 deep link,复制链接走 Clipboard。
/// Phase 5 已接 share_plus 真分享 + gal 真存相册。
///
/// 海报:RepaintBoundary 包裹(可 toImage 截图),内部 5 种 Canvas 图案之一
/// 作为顶部 40% 背景 + 文字内容 + 二维码占位。
///
/// 5 种图案:waves / mountains / grid / circles / ink,均用 KkColors.teal
/// 不同透明度(0.15 / 0.25 / 0.4),不用蓝/紫。
///
/// 零旁白(HANDOFF §3):无引导文案,只海报 + 切换 + 渠道按钮。
/// 计数铁律(HANDOFF §6.10):likes 取外部传入真实值,禁编造。
///
/// 用法:
///   showShareSheet(context, title: '...', shareType: 'project',
///     shareUrl: 'https://kankan.app/project/p1');
Future<void> showShareSheet(
  BuildContext context, {
  required String title,
  required String shareType,
  required String shareUrl,
  String? subtitle,
  String? authorName,
  String? coverPattern,
  String? coverImageUrl,
  int? likes,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: KkColors.bg,
    barrierColor: Colors.black54,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(KkRadius.xl),
      ),
    ),
    builder: (_) => ShareSheet(
      title: title,
      shareType: shareType,
      shareUrl: shareUrl,
      subtitle: subtitle,
      authorName: authorName,
      coverPattern: coverPattern,
      coverImageUrl: coverImageUrl,
      likes: likes,
    ),
  );
}

class ShareSheet extends ConsumerStatefulWidget {
  /// 分享标题(项目/动态标题)
  final String title;

  /// 副标题(可选,作者名 / 摘要)
  final String? subtitle;

  /// 作者名(可选)
  final String? authorName;

  /// 'project' | 'post' | 'topic' | 'profile'
  final String shareType;

  /// 深链 URL(mock:'https://kankan.app/${shareType}/${id}')
  final String shareUrl;

  /// 'waves' | 'mountains' | 'grid' | 'circles' | 'ink' 之一
  /// null 则根据 shareType 默认
  final String? coverPattern;

  /// 真实封面图 URL(项目/动态传作品封面)。非空 → 海报顶部铺真图(每个作品不一样),
  /// 图案切换器隐藏;空(话题/主页无单一封面)→ 退回抽象图案。
  final String? coverImageUrl;

  /// 点赞数(真实,可选)
  final int? likes;

  const ShareSheet({
    super.key,
    required this.title,
    required this.shareType,
    required this.shareUrl,
    this.subtitle,
    this.authorName,
    this.coverPattern,
    this.coverImageUrl,
    this.likes,
  });

  @override
  ConsumerState<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<ShareSheet> {
  /// 当前选中图案
  late String _pattern;

  /// 有真封面图可用(项目/动态);有则海报铺真图、隐藏图案切换器。
  bool get _hasCover =>
      widget.coverImageUrl != null && widget.coverImageUrl!.isNotEmpty;

  /// 海报 RepaintBoundary key(用于 toImage 截图,Phase 5 接 gal 真存相册)
  final GlobalKey _boundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _pattern = widget.coverPattern ?? _defaultPattern(widget.shareType);
  }

  static String _defaultPattern(String shareType) {
    switch (shareType) {
      case 'project':
        return 'mountains';
      case 'post':
        return 'waves';
      case 'topic':
        return 'grid';
      case 'profile':
        return 'circles';
      default:
        return 'ink';
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _copyLink() async {
    // 在 await 前捕获 messenger,避免 use_build_context_synchronously
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: widget.shareUrl));
    if (!mounted) return;
    messenger?.showSnackBar(
      SnackBar(
        content: const Text('链接已复制'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── 「保存图片」:RepaintBoundary.toImage → PNG → 落盘 ──
  // 海报已用 _boundaryKey 包裹,toImage(pixelRatio: 3) 拿高分辨率截图,
  // toByteData(png) 拿字节,downloadPngBytes 走条件导入(web:dart:html
  // AnchorElement+Blob 浏览器下载;移动端 gal 真存相册)。成功 toast「已保存到相册」。
  // 注:messenger 在 await 前捕获,避免 use_build_context_synchronously。
  Future<void> _saveImage() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    void snack(String msg) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) {
      snack('保存失败');
      return;
    }
    try {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        snack('保存失败');
        return;
      }
      final bytes = byteData.buffer.asUint8List();
      final ok = await downloadPngBytes(
        bytes,
        'kankan-${widget.shareType}-${DateTime.now().millisecondsSinceEpoch}.png',
      );
      snack(ok ? '已保存到相册' : '保存失败');
    } catch (_) {
      snack('保存失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: KkSpacing.xl,
        right: KkSpacing.xl,
        top: KkSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + KkSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dragHandle(),
          _header(),
          const SizedBox(height: KkSpacing.lg),
          // Section 1:海报预览(核心)
          _posterPreview(),
          const SizedBox(height: KkSpacing.lg),
          // Section 2:图案切换(仅无真封面时显示——有真图不需要选抽象图案)
          if (!_hasCover) ...[
            _patternChips(),
            const SizedBox(height: KkSpacing.lg),
          ],
          // Section 3:分享渠道
          _shareChannels(),
          // Section 4:底部留白
          const SizedBox(height: KkSpacing.xxl),
        ],
      ),
    );
  }

  // ── 顶部抓手(48x4 圆角灰条)──
  Widget _dragHandle() {
    return Center(
      child: Container(
        width: 48,
        height: 4,
        margin: const EdgeInsets.only(bottom: KkSpacing.md),
        decoration: BoxDecoration(
          color: KkColors.t4,
          borderRadius: BorderRadius.circular(KkRadius.pill),
        ),
      ),
    );
  }

  // ── 标题「分享」+ 关闭按钮 ──
  Widget _header() {
    return Row(
      children: [
        const Text('分享', style: KkType.h3),
        const Spacer(),
        Tappable(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(Icons.close, size: 22, color: KkColors.t1),
        ),
      ],
    );
  }

  // ── Section 1:海报预览 ──
  Widget _posterPreview() {
    return Center(
      child: RepaintBoundary(
        key: _boundaryKey,
        child: Container(
          width: 280,
          height: 360,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: KkColors.bgCard,
            borderRadius: BorderRadius.circular(KkRadius.lg),
            border: Border.all(color: KkColors.bd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部背景(占海报上半 40% = 144 高):有真封面铺真图(每个作品不一样),
              // 加载中/坏链回退抽象图案;无封面(话题/主页)用抽象图案。
              SizedBox(
                height: 144,
                width: double.infinity,
                child: _hasCover
                    ? Image.network(
                        widget.coverImageUrl!,
                        fit: BoxFit.cover,
                        loadingBuilder: (ctx, child, progress) =>
                            progress == null ? child : _patternBg(),
                        errorBuilder: (_, __, ___) => _patternBg(),
                      )
                    : _patternBg(),
              ),
              // 内容区
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(KkSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题(最多 2 行,溢出省略)
                      Text(
                        widget.title,
                        style: KkType.h2,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: KkSpacing.xs),
                        Text(
                          widget.subtitle!,
                          style: KkType.bodySm.copyWith(color: KkColors.t3),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const Spacer(),
                      // 底部:作者 + 品牌 + 点赞数 + 二维码
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(child: _posterBottom()),
                          const SizedBox(width: KkSpacing.md),
                          // 任务⑧:真二维码(QrImageView 编码 widget.shareUrl)。
                          // 深模块(t1 #16130F) + 白底 + 内边距构成 quiet zone,
                          // 保证海报图案背景上仍可扫。包白色圆角小盒(KkRadius.sm)
                          // 进一步隔离彩色/图案背景,对比度优先于配色(SPEC §6)。
                          _posterQr(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _posterBottom() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.authorName != null)
          Text(
            widget.authorName!,
            style: KkType.bodySm.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 2),
        Text(
          '看看 Kankan',
          style: KkType.bodySm.copyWith(
            color: KkColors.teal,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (widget.likes != null) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              const Icon(
                Icons.favorite_border,
                size: 11,
                color: KkColors.t3,
              ),
              const SizedBox(width: 3),
              Text(
                formatCount(widget.likes!),
                style: KkType.mono.copyWith(fontSize: 11, color: KkColors.t3),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ── 海报二维码(真·可扫描)──
  // 任务⑧:替换 _QrPlaceholderPainter(画得像但编码不了真实 URL)。
  // 包白色圆角小盒:海报该区域紧邻图案背景 + 品牌色文字,白盒隔离保证
  // 深模块 + 白底 + 足够 quiet zone,任何扫描器都能读出 shareUrl。
  // 不套用 teal/coral 到模块(对比度优先于配色,SPEC §6 任务⑧铁律)。
  Widget _posterQr() {
    return Container(
      width: 64,
      height: 64,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(KkRadius.sm),
      ),
      child: QrImageView(
        data: widget.shareUrl,
        size: 56,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF16130F),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF16130F),
        ),
        errorCorrectionLevel: QrErrorCorrectLevel.M,
      ),
    );
  }

  /// 抽象图案背景(无真封面 / 真封面加载中或坏链时用)。
  Widget _patternBg() => CustomPaint(
        painter: _patternPainter(_pattern),
        size: Size.infinite,
      );

  CustomPainter _patternPainter(String pattern) {
    switch (pattern) {
      case 'waves':
        return const _WavesPainter(currentPattern: 'waves');
      case 'mountains':
        return const _MountainsPainter(currentPattern: 'mountains');
      case 'grid':
        return const _GridPainter(currentPattern: 'grid');
      case 'circles':
        return const _CirclesPainter(currentPattern: 'circles');
      case 'ink':
      default:
        return const _InkPainter(currentPattern: 'ink');
    }
  }

  // ── Section 2:图案切换(横向 chip 行)──
  Widget _patternChips() {
    const patterns = <(String, String)>[
      ('waves', '波浪'),
      ('mountains', '山峦'),
      ('grid', '网格'),
      ('circles', '同心'),
      ('ink', '水墨'),
    ];
    return SizedBox(
      height: KkTouch.minTarget,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: patterns.length,
        separatorBuilder: (_, __) => const SizedBox(width: KkSpacing.sm),
        itemBuilder: (_, i) {
          final (key, label) = patterns[i];
          final selected = _pattern == key;
          return Tappable(
            onTap: () => setState(() => _pattern = key),
            borderRadius: BorderRadius.circular(KkRadius.pill),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: KkSpacing.md,
                vertical: KkSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: selected ? KkColors.teal : KkColors.bgCard,
                borderRadius: BorderRadius.circular(KkRadius.pill),
                border: selected ? null : Border.all(color: KkColors.bd),
              ),
              child: Center(
                child: Text(
                  label,
                  style: KkType.bodySm.copyWith(
                    color: selected ? Colors.white : KkColors.t2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Section 3:分享渠道(横排 4 个圆形按钮)──
  Widget _shareChannels() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        // Phase 5：系统分享面板（微信/微博/QQ 等由系统 sheet 列出）。
        _channelButton(
          icon: Icons.share_outlined,
          label: '分享',
          onTap: _shareSystem,
        ),
        _channelButton(
          icon: Icons.link,
          label: '复制链接',
          onTap: _copyLink,
        ),
        _channelButton(
          icon: Icons.download_outlined,
          label: '保存图片',
          onTap: _saveImage,
        ),
      ],
    );
  }

  /// Phase 5：调用系统分享面板分享深链 + 标题。
  /// share_plus 的 Share.share 会调起 iOS/Android 系统 share sheet，
  /// 用户可选微信/微博/QQ/拷贝等；web 上退化为 Web Share API 或拷贝提示。
  Future<void> _shareSystem() async {
    try {
      await Share.share(
        '${widget.title}\n${widget.shareUrl}',
        subject: widget.title,
      );
    } catch (_) {
      _showSnack('分享失败');
    }
  }

  Widget _channelButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Tappable(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: KkColors.bgSubtle,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 22, color: KkColors.t1),
          ),
          const SizedBox(height: KkSpacing.xs),
          Text(
            label,
            style: KkType.bodySm.copyWith(fontSize: 12, color: KkColors.t2),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────
// 5 种 Canvas 图案 painter(均用 KkColors.teal 不同透明度)
// 不用蓝/紫,只用 teal.withOpacity(0.15 / 0.25 / 0.4)
// ───────────────────────────────────────────────────────────────────

/// 1. 波浪:三条 sin 曲线,从下到上透明度递增(0.15 / 0.25 / 0.4)
class _WavesPainter extends CustomPainter {
  final String currentPattern;

  const _WavesPainter({this.currentPattern = 'waves'});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    // 从下到上:透明度递增(底 0.15 / 中 0.25 / 顶 0.4)
    final waves = <(double, double)>[
      (h * 0.85, 0.15),
      (h * 0.65, 0.25),
      (h * 0.45, 0.4),
    ];
    for (final (baseY, opacity) in waves) {
      final paint = Paint()
        ..color = KkColors.teal.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(0, baseY);
      const amplitude = 8.0;
      // 两个完整周期 across width
      for (var x = 0.0; x <= w; x += 2) {
        final dy = math.sin((x / w) * 4 * math.pi) * amplitude;
        path.lineTo(x, baseY + dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavesPainter old) =>
      old.currentPattern != currentPattern;
}

/// 2. 山峦:三层山形(三角形叠加),远山浅近山深
class _MountainsPainter extends CustomPainter {
  final String currentPattern;

  const _MountainsPainter({this.currentPattern = 'mountains'});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    // 远 → 近,透明度递增(远 0.15 / 中 0.25 / 近 0.4)
    _fillTriangle(
      canvas,
      [Offset(0, h), Offset(w * 0.4, h * 0.35), Offset(w * 0.85, h)],
      0.15,
    );
    _fillTriangle(
      canvas,
      [Offset(w * 0.15, h), Offset(w * 0.55, h * 0.55), Offset(w * 1.05, h)],
      0.25,
    );
    _fillTriangle(
      canvas,
      [Offset(-w * 0.1, h), Offset(w * 0.5, h * 0.78), Offset(w * 1.1, h)],
      0.4,
    );
  }

  void _fillTriangle(Canvas canvas, List<Offset> pts, double opacity) {
    final paint = Paint()..color = KkColors.teal.withOpacity(opacity);
    final path = Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MountainsPainter old) =>
      old.currentPattern != currentPattern;
}

/// 3. 网格:6x6 点阵网格,每个点 4x4 圆形
class _GridPainter extends CustomPainter {
  final String currentPattern;

  const _GridPainter({this.currentPattern = 'grid'});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    const rows = 6;
    const cols = 6;
    final dx = w / (cols + 1);
    final dy = h / (rows + 1);
    final paint = Paint()..color = KkColors.teal.withOpacity(0.25);
    for (var r = 1; r <= rows; r++) {
      for (var c = 1; c <= cols; c++) {
        canvas.drawCircle(Offset(c * dx, r * dy), 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.currentPattern != currentPattern;
}

/// 4. 同心:5 个同心圆,从内到外透明度递减
class _CirclesPainter extends CustomPainter {
  final String currentPattern;

  const _CirclesPainter({this.currentPattern = 'circles'});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final maxR = math.min(w, h) * 0.45;
    // 从内到外透明度递减:inner 0.4 → outer 0.15
    const opacities = [0.4, 0.32, 0.25, 0.2, 0.15];
    for (var i = 0; i < 5; i++) {
      final r = maxR * (i + 1) / 5;
      final paint = Paint()
        ..color = KkColors.teal.withOpacity(opacities[i])
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CirclesPainter old) =>
      old.currentPattern != currentPattern;
}

/// 5. 水墨:晕染效果(4 个 drawCircle + maskFilter blur)
class _InkPainter extends CustomPainter {
  final String currentPattern;

  const _InkPainter({this.currentPattern = 'ink'});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = KkColors.teal.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    // 3-4 个圆心,模拟水墨晕染层次
    canvas.drawCircle(Offset(w * 0.3, h * 0.4), 30, paint);
    canvas.drawCircle(Offset(w * 0.6, h * 0.5), 24, paint);
    canvas.drawCircle(Offset(w * 0.45, h * 0.7), 20, paint);
    canvas.drawCircle(Offset(w * 0.75, h * 0.3), 18, paint);
  }

  @override
  bool shouldRepaint(covariant _InkPainter old) =>
      old.currentPattern != currentPattern;
}
