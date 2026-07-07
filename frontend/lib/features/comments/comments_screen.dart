import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/backend_id.dart';
import '../../core/widgets/kk_back_button.dart';
import '../../core/widgets/tappable.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/post_repository.dart';
import '../shared/comment_thread.dart';
import '../shared/empty_state.dart';

/// 全屏评论壳 — HANDOFF §6.1 CommentThread 的全屏容器。
///
/// 用途:
///   - 详情页「心得 N」标题旁的「查看全部」入口
///   - 动态卡评论图标点击(Phase 3 接线)
///
/// 与 detail / post_detail 内联 CommentThread 的区别:此页给评论独立的全屏空间,
/// AppBar 标题展示「心得 N」(N 真实计数),并提供热/新排序。
///
/// 路由:/comments/:type/:id
///   - type ∈ {'project','post'}
///   - id   = hostId(project.id / post.id)
///
/// 计数铁律(HANDOFF §6.10):N = comments.length,真实数组长度。
/// 零旁白(HANDOFF §3):标题只「心得 N」,空状态只「暂无心得」。
/// 珊瑚橙(HANDOFF §5):本屏不出现(like 情感色在 CommentThread 内部,非本文件)。
enum _SortMode { hot, recent }

class CommentsScreen extends ConsumerStatefulWidget {
  final String hostType;
  final String hostId;

  const CommentsScreen({
    super.key,
    required this.hostType,
    required this.hostId,
  });

  @override
  ConsumerState<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends ConsumerState<CommentsScreen> {
  _SortMode _sortMode = _SortMode.hot;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(postRepositoryProvider);
    // repo.commentsFor 已按 hostId 过滤;再按 hostType 收窄(project / post 共享 ID
    // 空间极小,但仍按 HANDOFF §6.1 严格区分)。
    final comments = repo
        .commentsFor(widget.hostId)
        .where((c) => c.hostType == widget.hostType)
        .toList();

    final sorted = _sort(comments);

    // P0-1 收口:remote 模式下 commentsFor 返回空(mock 数据不含远程宿主评论),
    // 空状态交给 CommentThread 的 paginated provider 判定(loading → 空 + isLoading,
    // data 空 → _emptyHint)。mock 模式保留原瞬时空状态(无 loading 闪烁)。
    final isRemote =
        AppConfig.useRemote && looksLikeBackendId(widget.hostId);

    return Scaffold(
      backgroundColor: KkColors.bg,
      appBar: AppBar(
        backgroundColor: KkColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const KkBackButton(),
        titleSpacing: 0,
        // P0-1 收口:remote 模式 sorted(mock commentsFor)恒空 → 不显数字避免误导;
        // mock 模式显真实 mock 评论数。remote 的真实总数需后端 total 字段(暂未提供),
        // 列表体用 paginated provider 分页加载。
        title: Text(
          isRemote ? '心得' : '心得 ${sorted.length}',
          style: KkType.h3,
        ),
        actions: [
          if (sorted.isNotEmpty)
            Tappable(
              onTap: _toggleSort,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KkSpacing.lg,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _sortMode == _SortMode.hot
                          ? Icons.local_fire_department_outlined
                          : Icons.schedule_outlined,
                      size: 16,
                      color: KkColors.t2,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _sortMode == _SortMode.hot ? '热' : '新',
                      style: KkType.bodySm.copyWith(
                        color: KkColors.t2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: (!isRemote && sorted.isEmpty)
          ? const Center(
              child: EmptyState(
                variant: EmptyStateVariant.generic,
                title: '暂无心得',
              ),
            )
          : SafeArea(
              top: false,
              // P0-1 收口:全屏评论页给 CommentThread 自己的滚动容器
              // (inlineInScroll: false → ListView.builder + InfiniteScroll +
              // LoadMoreIndicator),支持游标分页无限滚动。原 SingleChildScrollView
              // 包装移除(避免与 CommentThread 内部 ListView 嵌套滚动)。
              child: CommentThread(
                hostType: widget.hostType,
                hostId: widget.hostId,
                initialComments: sorted,
                showInput: true,
                showHeader: false,
                inlineInScroll: false,
                // 任务⑨:长按 → 动作 sheet 收进 CommentThread 内部(_showActions),
                // 接通复制/编辑(own)/删除(own)/打开链接。不再外部传 onCommentLongPress。
              ),
            ),
    );
  }

  void _toggleSort() {
    setState(() {
      _sortMode =
          _sortMode == _SortMode.hot ? _SortMode.recent : _SortMode.hot;
    });
  }

  List<Comment> _sort(List<Comment> src) {
    final list = List<Comment>.of(src);
    switch (_sortMode) {
      case _SortMode.hot:
        // 按点赞数(含回复折算:likes + replies 总点赞)降序,同分按时间新→旧
        list.sort((a, b) {
          final aScore = a.likes + a.replies.fold<int>(0, (s, r) => s + r.likes);
          final bScore = b.likes + b.replies.fold<int>(0, (s, r) => s + r.likes);
          if (aScore != bScore) return bScore.compareTo(aScore);
          return b.createdAtMs.compareTo(a.createdAtMs);
        });
        break;
      case _SortMode.recent:
        list.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
        break;
    }
    return list;
  }
}
