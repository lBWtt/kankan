// 这个文件是干什么的：关注 / 粉丝列表的分页 provider（follows_screen 两 Tab 用）。
// 它对应产品里的什么功能：用户主页「关注 N / 粉丝 N」列表的无限滚动加载更多。
// 如果它出错了：列表加载/追加/刷新失败，或重复加载，或计数与列表体不一致。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/pagination/paginated_notifier.dart';
import '../core/pagination/page.dart';
import '../core/utils/backend_id.dart';
import '../data/api/users_api.dart';
import '../domain/models/models.dart';
import 'app_state_provider.dart';
import 'auth_provider.dart';
import 'project_provider.dart';

// ──────────────────────────────────────────────────────────────────
// 粉丝列表分页 Notifier
// ──────────────────────────────────────────────────────────────────

/// 用户粉丝列表的分页 state。
///
/// useRemote + 真后端 id(UUID)：游标分页 GET /users/{id}/followers。
/// mock（短 id）：一次性返回全部 user.followerIds 解析出的 KkUser 列表（hasMore=false），
/// 与 follows_screen 原 mock 分支同源（userByIdProvider 解析）。
///
/// 订阅：watch followedUserIds.contains(userId) —— 我关注/取关该用户 → 我从 ta 的
/// 粉丝列表加入/退出，provider 重建重拉首页（与原 remoteFollowersProvider 一致）。
class PaginatedFollowersNotifier extends PaginatedNotifier<KkUser> {
  final String userId;
  PaginatedFollowersNotifier(this.userId);

  @override
  int get pageSize => AppConfig.useRemote ? 20 : 999;

  @override
  String idOf(KkUser item) => item.id;

  @override
  PaginatedState<KkUser> build() {
    // 我关注/取关该用户 → 我从 ta 的粉丝列表加入/退出,重拉首页。
    ref.watch(
      appStateProvider.select((s) => s.followedUserIds.contains(userId)),
    );
    return super.build();
  }

  @override
  Future<Page<KkUser>> fetchPage(String? cursor) async {
    if (!AppConfig.useRemote || !looksLikeBackendId(userId)) {
      // mock：一次性全量，hasMore=false（InfiniteScroll 自然不触发 loadMore）。
      // 同源 follows_screen mock 分支：userByIdProvider(userId) 拿宿主用户，
      // 读 followerIds，每个 id 经 userByIdProvider 解析成 KkUser。
      final host = ref.read(userByIdProvider(userId));
      final out = <KkUser>[];
      if (host != null) {
        for (final id in host.followerIds) {
          final u = ref.read(userByIdProvider(id));
          if (u != null) out.add(u);
        }
      }
      return Page.last(out);
    }
    final page = await ref.read(usersApiProvider).followers(
          userId,
          limit: pageSize,
          cursor: cursor,
        );
    return Page<KkUser>(
      items: page.users,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }
}

/// 用户粉丝列表分页 provider（family by userId）。
final paginatedFollowersProvider = NotifierProvider.autoDispose
    .family<PaginatedFollowersNotifier, PaginatedState<KkUser>, String>(
  (userId) => PaginatedFollowersNotifier(userId),
);

// ──────────────────────────────────────────────────────────────────
// 关注列表分页 Notifier
// ──────────────────────────────────────────────────────────────────

/// 用户关注列表的分页 state。语义同 [PaginatedFollowersNotifier]，
/// 数据源 GET /users/{id}/following；mock 同源 user.followingIds。
///
/// 订阅：若 userId 是当前登录用户，watch followedUserIds.length —— 我关注/取关
/// 别人 → 我的 following 列表变，provider 重建重拉。他人 following 列表与本地
/// 状态无关，不订阅（与原 remoteFollowingProvider 一致）。
class PaginatedFollowingNotifier extends PaginatedNotifier<KkUser> {
  final String userId;
  PaginatedFollowingNotifier(this.userId);

  @override
  int get pageSize => AppConfig.useRemote ? 20 : 999;

  @override
  String idOf(KkUser item) => item.id;

  @override
  PaginatedState<KkUser> build() {
    final myId = ref.watch(authProvider).currentUser?.id;
    if (myId != null && myId == userId) {
      // 我关注/取关别人 → 我的 following 列表变,重拉首页。
      ref.watch(
        appStateProvider.select((s) => s.followedUserIds.length),
      );
    }
    return super.build();
  }

  @override
  Future<Page<KkUser>> fetchPage(String? cursor) async {
    if (!AppConfig.useRemote || !looksLikeBackendId(userId)) {
      // mock：一次性全量，hasMore=false。同源 user.followingIds → userByIdProvider 解析。
      final host = ref.read(userByIdProvider(userId));
      final out = <KkUser>[];
      if (host != null) {
        for (final id in host.followingIds) {
          final u = ref.read(userByIdProvider(id));
          if (u != null) out.add(u);
        }
      }
      return Page.last(out);
    }
    final page = await ref.read(usersApiProvider).following(
          userId,
          limit: pageSize,
          cursor: cursor,
        );
    return Page<KkUser>(
      items: page.users,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  }
}

/// 用户关注列表分页 provider（family by userId）。
final paginatedFollowingProvider = NotifierProvider.autoDispose
    .family<PaginatedFollowingNotifier, PaginatedState<KkUser>, String>(
  (userId) => PaginatedFollowingNotifier(userId),
);
