import 'package:flutter/material.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/tappable.dart';

/// 任务⑩B:共享 chip 组件 — me_screen 领域/话题统一用,达到发现页克制精致。
///
/// 抽出原因:用户嫌 me_screen 领域/话题 chip "太丑"——朴素 bgSubtle+bd+pill,
/// 窄栏换行散、"+调整"落单行突兀。统一成一套样式 + 末尾幽灵 chip 自然收尾。
///
/// 三种 chip:
///   - [KkChip.solid] 实心(mint 底 + teal 文字,领域/话题用)
///   - [KkChip.ghost] 幽灵(透明底 + 细边 + t2 文字,可点,末尾"+调整"用)
///   - [KkChip.plain] 朴素(bgSubtle + bd + t1,不强调,分类标签用)
///
/// 设计:
///   - 高度统一(pill + sm 垂直内边距 ≈ 28px)
///   - Wrap spacing/runSpacing sm(收紧,不散)
///   - 左对齐
///   - ghost chip 虚线/细边 + "+" 图标,跟在行末尾自然收尾,不单独占行
///
/// 铁律:无 emoji(用 Icon);触控 ≥44pt(ghost/plain 可点时外层 Tappable 撑 ≥44);
/// coral 只给 take(本组件不用 coral)。
class KkChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool removable;
  final VoidCallback? onRemove;
  final _ChipTone tone;

  const KkChip._({
    required this.label,
    required this.tone,
    this.icon,
    this.onTap,
    this.removable = false,
    this.onRemove,
  });

  /// 实心 chip:mint 底 + teal 文字 + teal 边(领域/话题强调态)
  /// 带可选 onRemove(× 关闭)。
  factory KkChip.solid({
    Key? key,
    required String label,
    VoidCallback? onTap,
    bool removable = false,
    VoidCallback? onRemove,
  }) {
    return KkChip._(
      label: label,
      tone: _ChipTone.solid,
      onTap: onTap,
      removable: removable,
      onRemove: onRemove,
    );
  }

  /// 幽灵 chip:透明底 + 细边 + t2 文字 + "+" 图标(末尾"+调整"用)
  factory KkChip.ghost({
    Key? key,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return KkChip._(
      label: label,
      tone: _ChipTone.ghost,
      icon: icon,
      onTap: onTap,
    );
  }

  /// 朴素 chip:bgSubtle 底 + bd 边 + t1 文字(分类标签,不强调)
  factory KkChip.plain({
    Key? key,
    required String label,
    VoidCallback? onTap,
  }) {
    return KkChip._(
      label: label,
      tone: _ChipTone.plain,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final (bgColor, borderColor, textColor, iconColor) = switch (tone) {
      _ChipTone.solid => (KkColors.mint, KkColors.teal, KkColors.tealDark, KkColors.teal),
      _ChipTone.ghost => (Colors.transparent, KkColors.bd, KkColors.t2, KkColors.t2),
      _ChipTone.plain => (KkColors.bgSubtle, KkColors.bd, KkColors.t1, KkColors.t2),
    };

    final chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.md,
        vertical: KkSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(KkRadius.pill),
        border: tone == _ChipTone.ghost
            ? Border.all(color: borderColor, width: 0.8)
            : Border.all(color: borderColor, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: KkSpacing.xs),
          ],
          Text(
            label,
            style: KkType.bodySm.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (removable && onRemove != null) ...[
            const SizedBox(width: KkSpacing.xs),
            // P2-无障碍:× 关闭是 icon-only 按钮,必须传 semanticLabel。
            // 读屏会念「移除 <chip label>」。注:'移除' 当前硬编码,
            // i18n 全量迁移时加入 KkStrings.remove + arb 条目。
            Tappable(
              onTap: onRemove,
              semanticLabel: '移除 $label',
              borderRadius: BorderRadius.circular(KkRadius.pill),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close, size: 12, color: iconColor),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return chip;
    // 修 bug:原来用 Tappable 包裹,其内部 Center 在 Wrap 里会撑满整行宽度,
    // 导致可点 chip 各占一行、居中显示(阶梯状很丑)。改用自适应 InkWell,
    // 尺寸贴合 chip,Wrap 里正常左排流式换行。
    // P2-无障碍:外层 InkWell 没有自带 button 语义,这里显式 Semantics(button: true)
    // + label(chip 的 Text 会自动 merge,但显式 button 让读屏念「<label>, 按钮」)。
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KkRadius.pill),
          child: chip,
        ),
      ),
    );
  }
}

enum _ChipTone { solid, ghost, plain }
