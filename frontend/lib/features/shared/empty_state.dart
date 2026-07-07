import 'package:flutter/material.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';

/// 空状态组件 — HANDOFF §5:无 emoji,用图标 + 文案。
///
/// 6 变体(B3 补 followers/search):
///   - generic   通用("暂无内容")
///   - feed      流空("还没有动态"/"关注的人发的动态在这里")
///   - saved     收藏空("还没收藏"/"收藏的项目在这里")
///   - takeaway  拿走空("还没存过素材"/"存下的素材在这里找回")
///   - followers 关注空("还没关注"/"关注的人在这里")
///   - search    搜索空("没有结果"/"换个词试试")
///
/// 零旁白(HANDOFF §3):只陈述事实,不写"快去发现更多吧"之类引导。
class EmptyState extends StatelessWidget {
  final EmptyStateVariant variant;
  final String? title;
  final String? subtitle;

  const EmptyState({
    super.key,
    required this.variant,
    this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final meta = _meta();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.xxl,
        vertical: KkSpacing.xxxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            meta.icon,
            size: 48,
            color: KkColors.t4,
          ),
          const SizedBox(height: KkSpacing.md),
          Text(
            title ?? meta.title,
            style: KkType.body.copyWith(color: KkColors.t3),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null || meta.subtitle != null) ...[
            const SizedBox(height: KkSpacing.xs),
            Text(
              subtitle ?? meta.subtitle!,
              style: KkType.bodySm.copyWith(color: KkColors.t4),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  _EmptyMeta _meta() {
    switch (variant) {
      case EmptyStateVariant.generic:
        return const _EmptyMeta(
          icon: Icons.inbox_outlined,
          title: '暂无内容',
          subtitle: null,
        );
      case EmptyStateVariant.feed:
        return const _EmptyMeta(
          icon: Icons.dynamic_feed_outlined,
          title: '还没有动态',
          subtitle: '关注的人发的动态在这里',
        );
      case EmptyStateVariant.saved:
        return const _EmptyMeta(
          icon: Icons.bookmark_border_outlined,
          title: '还没收藏',
          subtitle: '收藏的项目在这里',
        );
      case EmptyStateVariant.takeaway:
        return const _EmptyMeta(
          icon: Icons.download_outlined,
          title: '还没存过素材',
          subtitle: '存下的素材在这里找回',
        );
      case EmptyStateVariant.followers:
        return const _EmptyMeta(
          icon: Icons.people_outline,
          title: '还没关注',
          subtitle: '关注的人在这里',
        );
      case EmptyStateVariant.search:
        return const _EmptyMeta(
          icon: Icons.search_off,
          title: '没有结果',
          subtitle: '换个词试试',
        );
    }
  }
}

enum EmptyStateVariant { generic, feed, saved, takeaway, followers, search }

class _EmptyMeta {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _EmptyMeta({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}
