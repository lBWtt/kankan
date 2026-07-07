import 'package:flutter/material.dart';

import '../theme/kk_colors.dart';
import '../theme/tokens.dart';

/// 骨架屏 — shimmer 横向滑动 2 秒循环。
///
/// 用法:加载态直接返回 `ProjectCardSkeleton()` / `PostCardSkeleton()` /
/// `DetailSkeleton()`。单行/单块用 [SkeletonLine] / [SkeletonBox]。
///
/// 设计(HANDOFF §5):
///   - 底色 [KkColors.bgSubtle](暖纸浅灰)
///   - shimmer 高光 `Colors.white.withAlpha(102)`(~0.4)
///   - 不用蓝/紫系(HANDOFF §5),不用 coral(珊瑚橙只给 take)
///   - 复合骨架(ProjectCard/PostCard/Detail)共用单个 [AnimationController]
///     ——所有 placeholder 同步闪烁,避免视疲劳
///   - 单行/单块骨架自带 [_Shimmer]——可独立使用
class SkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const SkeletonLine({
    super.key,
    this.width = double.infinity,
    this.height = 12,
    this.borderRadius = const BorderRadius.all(Radius.circular(KkRadius.sm)),
  });

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: KkColors.bgSubtle,
          borderRadius: borderRadius,
        ),
      ),
    );
  }
}

class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: KkColors.bgSubtle,
          borderRadius:
              borderRadius ?? const BorderRadius.all(Radius.circular(KkRadius.sm)),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// ProjectCard 镜像 — 顶部封面 120 + 标题/副标题/meta 三行
// 布局参考 lib/features/shared/project_card.dart (full 模式)
// ──────────────────────────────────────────────────────────────────
class ProjectCardSkeleton extends StatelessWidget {
  const ProjectCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Container(
        decoration: BoxDecoration(
          color: KkColors.bgCard,
          borderRadius: BorderRadius.circular(KkRadius.lg),
          border: Border.all(color: KkColors.bd),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部封面区
            Container(height: 120, color: KkColors.bgSubtle),
            Padding(
              padding: const EdgeInsets.all(KkSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _fracLine(0.80, 16), // 标题
                  const SizedBox(height: KkSpacing.sm),
                  _fracLine(0.60, 12), // 副标题
                  const SizedBox(height: KkSpacing.md),
                  _fracLine(0.40, 12), // meta 行
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// PostCard 镜像 — 头像 + 名字/时间 + 正文 ×2 + actions ×3
// 布局参考 lib/features/shared/post_card.dart
// ──────────────────────────────────────────────────────────────────
class PostCardSkeleton extends StatelessWidget {
  const PostCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Container(
        decoration: const BoxDecoration(
          color: KkColors.bgCard,
          border: Border(bottom: BorderSide(color: KkColors.divider)),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.lg,
          vertical: KkSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 作者行:头像 + 名字/时间
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: KkColors.bgSubtle,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: KkSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _fracLine(0.50, 12), // 名字
                      const SizedBox(height: 4),
                      _fracLine(0.30, 10), // 时间
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: KkSpacing.md),
            // 正文 ×2
            _fracLine(1.0, 14),
            const SizedBox(height: 4),
            _fracLine(0.80, 14),
            const SizedBox(height: KkSpacing.md),
            // actions 行:3 个图标占位
            Row(
              children: [
                _iconStatPlaceholder(),
                const SizedBox(width: KkSpacing.lg),
                _iconStatPlaceholder(),
                const SizedBox(width: KkSpacing.lg),
                _iconStatPlaceholder(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconStatPlaceholder() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: KkColors.bgSubtle,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: KkSpacing.xs),
          Container(
            width: 20,
            height: 10,
            color: KkColors.bgSubtle,
          ),
        ],
      );
}

// ──────────────────────────────────────────────────────────────────
// 详情页镜像 — 封面 200 + 标题 + 作者 + 成果方块 + 动作 ×3
// 布局参考 lib/features/detail/detail_screen.dart
// ──────────────────────────────────────────────────────────────────
class DetailSkeleton extends StatelessWidget {
  const DetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部封面
          Container(height: 200, color: KkColors.bgSubtle),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KkSpacing.lg,
              vertical: KkSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题
                _fracLine(0.70, 24),
                const SizedBox(height: KkSpacing.lg),
                // 作者行
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: KkColors.bgSubtle,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: KkSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _fracLine(0.30, 14),
                          const SizedBox(height: 4),
                          _fracLine(0.20, 10),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KkSpacing.lg),
                // 成果区方块
                Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: KkColors.bgSubtle,
                    borderRadius: BorderRadius.circular(KkRadius.md),
                  ),
                ),
                const SizedBox(height: KkSpacing.md),
                // 动作按钮行:3 个 40x40 圆角方块
                Row(
                  children: [
                    _actionBtnPlaceholder(),
                    const SizedBox(width: KkSpacing.md),
                    _actionBtnPlaceholder(),
                    const SizedBox(width: KkSpacing.md),
                    _actionBtnPlaceholder(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtnPlaceholder() => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: KkColors.bgSubtle,
          borderRadius: BorderRadius.circular(KkRadius.md),
        ),
      );
}

// ──────────────────────────────────────────────────────────────────
// 内部:shimmer 容器 — 横向滑动 2 秒循环
// ──────────────────────────────────────────────────────────────────
// 实现:Stack[child + Positioned.fill(DecoratedBox with sliding gradient)]。
// 高光带宽度 = canvas width,从 off-screen 左 → off-screen 右扫过。
// 高光颜色 = Colors.white.withAlpha(102)(~0.4),底色透明 → 自然叠加在 child 上。
class _Shimmer extends StatefulWidget {
  final Widget child;
  const _Shimmer({required this.child});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    // -1 → 2:高光从 off-screen 左扫到 off-screen 右,无缝循环
    _anim = Tween<double>(begin: -1.0, end: 2.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return Stack(
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(_anim.value, 0),
                      end: Alignment(_anim.value + 1, 0),
                      colors: const [
                        Color(0x00FFFFFF),
                        Color(0x66FFFFFF), // white 0.4
                        Color(0x00FFFFFF),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

// ── helpers ──

/// 按父容器宽度百分比的左对齐 placeholder 条。
Widget _fracLine(double widthFactor, double height) =>
    FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: KkColors.bgSubtle,
          borderRadius: BorderRadius.circular(KkRadius.sm),
        ),
      ),
    );
