// 这个文件是干什么的：动态流的分页 provider（发现页推荐流用）。
// 它对应产品里的什么功能：发现页无限滚动加载更多动态。
// 如果它出错了：流加载/追加/刷新失败，或重复加载。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/pagination/paginated_notifier.dart';
import '../core/pagination/page.dart';
import '../data/api/posts_api.dart';
import '../domain/models/models.dart';
import '../domain/repositories/post_repository.dart';
import 'app_state_provider.dart';

/// 发现页推荐流的分页 state。
///
/// useRemote：游标分页 GET /posts。
/// mock：一次性返回全部 mock 动态（hasMore=false）——mock 数据量小，无需真分页。
/// autoDispose：离开发现页释放，回来重新加载（新鲜数据）。
class PaginatedPostsNotifier extends PaginatedNotifier<Post> {
  @override
  int get pageSize => AppConfig.useRemote ? 20 : 999;

  @override
  String idOf(Post item) => item.id;

  @override
  Future<Page<Post>> fetchPage(String? cursor) async {
    if (!AppConfig.useRemote) {
      // mock：全部一次性返回，hasMore=false。
      // 用 postRepository（含发动态后 addPost 的内存态）而非 mock_seed 直读，
      // 这样 compose 发的动态在 refresh 后能看到。
      final all = ref.read(postRepositoryProvider).all();
      return Page.last(all);
    }
    final res = await ref.read(postsApiProvider).listPaged(
          limit: pageSize,
          cursor: cursor,
        );
    // 把后端「我已赞」并进 app_state（点亮心）。
    if (res.likedIds.isNotEmpty) {
      ref.read(appStateProvider.notifier).mergeLikedIds(res.likedIds);
    }
    return Page<Post>(
      items: res.posts,
      nextCursor: res.nextCursor,
      hasMore: res.hasMore,
    );
  }
}

/// 发现页推荐流分页 provider。
final paginatedPostsProvider =
    NotifierProvider.autoDispose<PaginatedPostsNotifier, PaginatedState<Post>>(
  () => PaginatedPostsNotifier(),
);
