import 'package:flutter/material.dart';

import '../theme/kk_colors.dart';
import '../theme/tokens.dart';

/// Phase 1 占位屏。
///
/// 用途:验证 5 Tab 切换 + 暖纸底 + 衬线标题能显示中文。
/// Phase 2 起各 feature screen 替换为真实实现,此组件保留作 dev-only 占位。
///
/// 不含 emoji(HANDOFF §5:全面禁止 emoji,空状态/提示也不许用)。
class PlaceholderScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData? icon;

  const PlaceholderScreen({
    super.key,
    required this.title,
    this.subtitle = '',
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KkSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 48, color: KkColors.t3),
              const SizedBox(height: KkSpacing.lg),
            ],
            // 衬线标题(验证中文字体:放字体前回退系统衬线,放字体后 Noto Serif SC)
            Text(title, style: KkType.h1, textAlign: TextAlign.center),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: KkSpacing.sm),
              Text(subtitle, style: KkType.bodySm, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
