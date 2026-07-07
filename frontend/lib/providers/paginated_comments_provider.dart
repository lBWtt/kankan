// 这个文件是干什么的：评论列表的分页 provider（CommentThread 远程模式用）。
// 它对应产品里的什么功能：项目 / 动态详情评论区无限滚动加载更多顶级评论。
// 如果它出错了：评论加载/追加/刷新失败，或重复加载，或点赞态错。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/pagination/paginated_notifier.dart';
import '../core/pagination/page.dart';
import '../core/utils/backend_id.dart';
import '../data/api/comments_api.dart';
import '../data/seed/mock_seed.dart' as seed;
import '../domain/models/models.dart';
import 'app_state_provider.dart';

/// 把 (hostType, hostId) 复合参数序列化成 family key。
///
/// 用 ':' 分隔（hostType 是固定枚举值 'project' / 'post'，不含 ':'；hostId 是
/// UUID 或 mock 短 id，也不含 ':'），保证双向解析无歧义。当前仅做正向序列化，
/// 不需要反解析（Notifier 不需要拆 key）。
String commentThreadKey(String hostType, String hostId) => '$hostType:$hostId';

/// 评论列表的分页 state。
///
/// useRemote + 真后端宿主 id(UUID)：游标分页 GET /comments?host_type=&host_id=。
/// 后端返回的「我已赞」评论 id 集合（[CommentList.likedIds]）并入 app_state.likedItemIds
/// （与 paginated_posts_provider 同套路），让 _CommentTile 的 isLiked 走 app_state
/// 统一读取。
///
/// mock（短 hostId）：一次性返回全部 commentsFor(hostId)（hasMore=false），与
/// CommentThread 原 mock 分支同源（widget.initialComments 也是 commentsFor）。
///
/// 评论是树形（replies 嵌套），分页只对顶层评论分页，replies 跟随父评论一次返回
/// （后端通常不对 replies 分页，无需特殊处理）。
class PaginatedCommentsNotifier extends PaginatedNotifier<Comment> {
  /// '$hostType:$hostId' 形式的 family key。
  final String key;
  PaginatedCommentsNotifier(this.key);

  @override
  int get pageSize => AppConfig.useRemote ? 30 : 999;

  @override
  String idOf(Comment item) => item.id;

  /// 从 key 拆出 (hostType, hostId)。
  /// hostType 是固定枚举值 'project'/'post' 不含 ':'，split(':', 2) 取首段 + 余段
  /// （hostId 即使含 ':' 也安全，目前不会）。每次 fetchPage 调用时解析（build 可能
  /// 多次运行,不用 late final 避免二次赋值抛 LateInitializationError）。
  ({String hostType, String hostId}) _parseKey() {
    final idx = key.indexOf(':');
    if (idx <= 0) return (hostType: 'project', hostId: key);
    return (
      hostType: key.substring(0, idx),
      hostId: key.substring(idx + 1),
    );
  }

  @override
  Future<Page<Comment>> fetchPage(String? cursor) async {
    final parts = _parseKey();
    final hostType = parts.hostType;
    final hostId = parts.hostId;
    if (!AppConfig.useRemote || !looksLikeBackendId(hostId)) {
      // mock：一次性全量，hasMore=false。用 mock_seed 顶层 commentsFor（唯一真源，
      // 按 hostId 过滤 mockComments；ProjectRepository 无 commentsFor 方法，见其类注释）。
      final comments = seed.commentsFor(hostId);
      return Page.last(comments);
    }
    final res = await ref.read(commentsApiProvider).list(
          hostType,
          hostId,
          limit: pageSize,
          cursor: cursor,
        );
    // 后端「我已赞」并进 app_state（点亮心，与 paginated_posts_provider 同套路）。
    if (res.likedIds.isNotEmpty) {
      ref.read(appStateProvider.notifier).mergeLikedIds(res.likedIds);
    }
    return Page<Comment>(
      items: res.comments,
      nextCursor: res.nextCursor,
      hasMore: res.hasMore,
    );
  }
}

/// 评论列表分页 provider（family by `'$hostType:$hostId'` key）。
///
/// 用法：`ref.watch(paginatedCommentsProvider(commentThreadKey('post', post.id)))`。
/// CommentThread 远程模式 watch 本 provider；mock 模式不 watch（保持 widget.initialComments）。
final paginatedCommentsProvider = NotifierProvider.autoDispose
    .family<PaginatedCommentsNotifier, PaginatedState<Comment>, String>(
  (key) => PaginatedCommentsNotifier(key),
);
