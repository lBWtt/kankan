import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/tappable.dart';
import '../../domain/models/models.dart';
import 'comment_thread.dart';

/// HANDOFF §6.1 评论弹层 — 从底部滑出的全屏评论 sheet。
///
/// 发现页/看看页点评论入口 → 弹出此 sheet,内嵌 CommentThread(统一组件)。
/// 详情页内联用 CommentThread(showInput: true),不弹 sheet。
///
/// 用法:
///   showCommentBottomSheet(context, hostType: 'post', hostId: 'post_2');
Future<void> showCommentBottomSheet(
  BuildContext context, {
  required String hostType,
  required String hostId,
  required List<Comment> initialComments,
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
    builder: (_) => CommentBottomSheet(
      hostType: hostType,
      hostId: hostId,
      initialComments: initialComments,
    ),
  );
}

class CommentBottomSheet extends ConsumerWidget {
  final String hostType;
  final String hostId;
  final List<Comment> initialComments;

  const CommentBottomSheet({
    super.key,
    required this.hostType,
    required this.hostId,
    required this.initialComments,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final height = MediaQuery.of(context).size.height * 0.85;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          // 顶栏:拖把 + 标题 + 关闭
          _topBar(context),
          const Divider(height: 1, color: KkColors.divider),
          // 评论列表 + 输入框
          Expanded(
            child: CommentThread(
              hostType: hostType,
              hostId: hostId,
              initialComments: initialComments,
              showInput: true,
              showHeader: true,
              // 任务⑨:长按 → 动作 sheet 收进 CommentThread 内部(_showActions),
              // 接通复制/编辑(own)/删除(own)/打开链接。不再外部传 onCommentLongPress。
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.md,
      ),
      child: Row(
        children: [
          // 占位让标题居中
          const SizedBox(width: KkTouch.minTarget),
          const Spacer(),
          Text('心得 ${initialComments.length}', style: KkType.h3),
          const Spacer(),
          Tappable(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(Icons.close, size: 22, color: KkColors.t1),
          ),
        ],
      ),
    );
  }
}
