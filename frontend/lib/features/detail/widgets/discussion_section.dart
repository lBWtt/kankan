import 'package:flutter/material.dart';

import '../../../core/theme/kk_colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/tappable.dart';
import '../../../domain/models/models.dart';

/// 心得讨论区 — HANDOFF §2.3 页面顺序固定:...→ 心得讨论 → 相关项目 → 底栏。
///
/// Phase 2 简化:展示评论列表(只读)+ 底部评论入口占位。
/// Phase 3 接 CommentThread 统一组件(HANDOFF §6.1)。
class DiscussionSection extends StatelessWidget {
  final String hostId;
  final List<Comment> comments;
  final int commentCount;
  final VoidCallback? onAddComment;

  /// “查看全部”入口(→ 全屏评论页)。null 时不显示。
  final VoidCallback? onViewAll;

  const DiscussionSection({
    super.key,
    required this.hostId,
    required this.comments,
    required this.commentCount,
    this.onAddComment,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题(零旁白:只显示数字,不写"快来发表你的看法")
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KkSpacing.lg,
            vertical: KkSpacing.md,
          ),
          child: Row(
            children: [
              Text('心得 $commentCount', style: KkType.h3),
              const Spacer(),
              if (onViewAll != null && comments.isNotEmpty)
                Tappable(
                  onTap: onViewAll,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '查看全部',
                        style: KkType.bodySm.copyWith(color: KkColors.teal),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 16, color: KkColors.teal),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // 评论列表(空 → 空状态,无 emoji,HANDOFF §5)
        if (comments.isEmpty)
          Padding(
            padding: const EdgeInsets.all(KkSpacing.xl),
            child: Text(
              '暂无心得',
              style: KkType.bodySm,
              textAlign: TextAlign.center,
            ),
          )
        else
          for (final c in comments) _CommentTile(comment: c),

        // 底部评论入口(占位,Phase 3 接 CommentThread)
        if (onAddComment != null)
          Padding(
            padding: const EdgeInsets.all(KkSpacing.lg),
            child: Tappable(
              onTap: onAddComment,
              borderRadius: BorderRadius.circular(KkRadius.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: KkSpacing.md,
                  horizontal: KkSpacing.lg,
                ),
                decoration: BoxDecoration(
                  color: KkColors.bgSubtle,
                  borderRadius: BorderRadius.circular(KkRadius.pill),
                  border: Border.all(color: KkColors.bd),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 16, color: KkColors.t3),
                    SizedBox(width: KkSpacing.sm),
                    Text('写心得', style: KkType.bodySm),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Comment comment;

  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头像占位(首字母)
          _Avatar(userId: comment.authorId),
          const SizedBox(width: KkSpacing.md),
          // 内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      comment.authorId,
                      style: KkType.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: KkColors.t1,
                      ),
                    ),
                    const SizedBox(width: KkSpacing.sm),
                    Text(
                      _timeAgo(comment.createdAtMs),
                      style: KkType.mono.copyWith(fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(comment.content, style: KkType.body),
                if (comment.replies.isNotEmpty) ...[
                  const SizedBox(height: KkSpacing.sm),
                  // 楼中楼(简化)
                  Container(
                    padding: const EdgeInsets.all(KkSpacing.sm),
                    decoration: BoxDecoration(
                      color: KkColors.bgSubtle,
                      borderRadius: BorderRadius.circular(KkRadius.sm),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final r in comment.replies) ...[
                          Text(
                            r.content,
                            style: KkType.bodySm,
                          ),
                          if (r != comment.replies.last)
                            const SizedBox(height: KkSpacing.sm),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(int ms) {
    final diff = DateTime.now().millisecondsSinceEpoch - ms;
    if (diff < 0) return '刚刚';
    final min = diff ~/ 60000;
    if (min < 60) return '$min分钟前';
    final hr = min ~/ 60;
    if (hr < 24) return '$hr小时前';
    final day = hr ~/ 24;
    return '$day天前';
  }
}

class _Avatar extends StatelessWidget {
  final String userId;

  const _Avatar({required this.userId});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        color: KkColors.mint,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        userId.isNotEmpty ? userId[0].toUpperCase() : '?',
        style: const TextStyle(
          color: KkColors.teal,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          fontFamily: 'JetBrainsMono',
        ),
      ),
    );
  }
}
