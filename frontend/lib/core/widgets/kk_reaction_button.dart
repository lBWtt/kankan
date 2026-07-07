import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'tappable.dart';

/// 反应型图标按钮 — 点赞 / 收藏共用。
///
/// 任务 C:点亮瞬间图标做一次轻 scale 弹(1 → 1.3 → 1),+ HapticFeedback。
/// 只在「点亮」(isLit: false → true)时弹;取消点赞不弹(避免误导)。
/// 触感两向都给(点亮 + 取消都 lightImpact)。
///
/// 用 AnimationController 手控(forward().thenReverse()),保证「一次性触发」,
/// 不随 rebuild 反复评估(flutter_animate 链式每次 build 都评估,不适合此场景)。
///
/// 替换原散落的 _IconStat(点赞行)/ _Stat(点赞行)/ 单独 Tappable(收藏 icon)。
/// **不替换**评论数 / 拿走数等非 toggle 场景(那些仍用 _IconStat / _Stat)。
///
/// 铁律:coral 只给 take(本组件非 take,色由调用方传——点赞用 KkColors.like,
/// 收藏用 KkColors.teal);无 emoji(用 Icon);触控 ≥44pt(Tappable 内置)。
class KkReactionButton extends StatefulWidget {
  /// 当前态图标(已点亮=填充 favorite / 未点亮=favorite_border,由调用方按 isLit 选)。
  final IconData icon;

  /// 数字(可选)。null 或空串 → 只显图标(收藏按钮用)。
  final String? value;

  /// 图标 + 文字色(已点亮=KkColors.like / KkColors.teal;未点亮=t3)。
  final Color color;

  /// 是否已点亮。false → true 时触发一次 scale 弹。
  final bool isLit;

  /// 点击回调(调用方负责 toggleLike / toggleSave)。
  final VoidCallback onTap;

  /// 图标尺寸(默认 18;post_card / post_detail 用 16,project_card 用 14)。
  final double iconSize;

  /// 内边距(默认与 _IconStat 一致:vertical md, horizontal sm)。
  final EdgeInsetsGeometry padding;

  /// P2-无障碍:可选语义标签。Icon-only 反应按钮必须传(读屏需要文字念);
  /// 含 value 时 Flutter 会自动读数字,但仍需一个动作名作为标签前缀。
  /// null 时不包 Semantics(向后兼容现有调用点)。
  final String? semanticLabel;

  const KkReactionButton({
    super.key,
    required this.icon,
    required this.color,
    required this.isLit,
    required this.onTap,
    this.value,
    this.iconSize = 18,
    this.padding = const EdgeInsets.symmetric(
      vertical: KkSpacing.md,
      horizontal: KkSpacing.sm,
    ),
    this.semanticLabel,
  });

  @override
  State<KkReactionButton> createState() => _KkReactionButtonState();
}

class _KkReactionButtonState extends State<KkReactionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      reverseDuration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(covariant KkReactionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只在 false → true 时触发(点亮才弹,取消不弹)。
    if (!oldWidget.isLit && widget.isLit) {
      _ctrl.forward().then((_) {
        if (mounted) _ctrl.reverse();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    // 触感两向都给(点亮 + 取消都轻触)。
    HapticFeedback.lightImpact();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final showValue = widget.value != null && widget.value!.isNotEmpty;
    return Tappable(
      onTap: _handleTap,
      // P2-无障碍:透传到 Tappable 的 Semantics(icon-only 按钮需要语义标签,
      // 读屏会念「<label>, 按钮」)。null 时 Tappable 不包 Semantics,向后兼容。
      semanticLabel: widget.semanticLabel,
      child: Padding(
        padding: widget.padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _scale,
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: widget.color,
              ),
            ),
            if (showValue) ...[
              const SizedBox(width: 4),
              Text(
                widget.value!,
                style: KkType.mono.copyWith(
                  fontSize: widget.iconSize <= 14 ? 11 : 12,
                  color: widget.color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
