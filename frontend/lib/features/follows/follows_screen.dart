import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/pagination/infinite_scroll.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/backend_id.dart';
import '../../core/widgets/skeletons.dart';
import '../../core/widgets/kk_back_button.dart';
import '../../core/widgets/tappable.dart';
import '../../data/api/users_api.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/paginated_follows_provider.dart';
import '../../providers/project_provider.dart';
import '../../router/routes.dart';
import '../shared/avatar.dart';
import '../shared/empty_state.dart';
import '../shared/remote_error.dart';

/// 关注 / 粉丝列表屏 — HANDOFF §6.5 真路由 + §6.10 真实计数。
///
/// 路由:`/u/:userId/follows?type=followers|following`(可深链)。
/// 双 Tab:
///   - 关注 N   我关注的人(remote: GET /users/{id}/following;mock: user.followingIds)
///   - 粉丝 N   关注我的人(remote: GET /users/{id}/followers;mock: user.followerIds)
/// N 取真实长度,无虚构放大公式(Web 版重灾区,Flutter 端从零做对)。
///
/// 数据源策略(与 kankan _ProjectList 同套路):
///   - useRemote + 真后端 id(UUID) → 真接口,游标分页 + 无限滚动(P0-1 收口)。
///     Tab 计数从 remoteUserPublicProvider(后端聚合 follower/following_count,真总数)
///     取,避免分页后 items.length 只显首页数。
///   - mock(短 id 'chen' 或 'me') → 内存 user.followingIds/followerIds,
///     paginated provider 的 mock 分支 Page.last 一次性返回(hasMore=false,
///     InfiniteScroll 自然不触发 loadMore),保留原 300ms 假 loading 骨架。
///
/// 行内布局:TappableAvatar(40px) + 名字/简介 + 关注按钮。
/// 行整体 Tappable → push /u/:rowUserId。关注按钮独立 Tappable → toggleFollow
/// (嵌套 InkWell 内层优先消费手势,不会触发行点击)。关注按钮逻辑不动(Claude 双轨)。
///
/// 零旁白(HANDOFF §3):空状态只一行事实,不写"去发现更多有趣的人"。
/// 珊瑚橙(HANDOFF §5):本屏无 take / 点赞,完全不用 coral。
/// 关注按钮走 teal(未关注) / bgSubtle + bd(已关注)二态,与 post_card 一致。
class FollowsScreen extends ConsumerStatefulWidget {
  final String userId;

  /// 初始 Tab:'following' | 'followers'。
  final String initialTab;

  const FollowsScreen({
    super.key,
    required this.userId,
    this.initialTab = 'following',
  });

  @override
  ConsumerState<FollowsScreen> createState() => _FollowsScreenState();
}

class _FollowsScreenState extends ConsumerState<FollowsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  // mock 分支:300ms 假 loading 骨架(与 discover/kankan/library mock 一致)。
  // remote 分支用 PaginatedState.isLoading,不用这个旗。
  bool _mockLoading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 2,
      vsync: this,
      // 'followers' → 第二个 Tab(index 1);其他默认 'following'(index 0)。
      initialIndex: widget.initialTab == 'followers' ? 1 : 0,
    );
    // mock 分支才需要假 loading;remote 分支 PaginatedState.isLoading 兜底,跳过。
    if (!_isRemote) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() => _mockLoading = false);
      });
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  bool get _isRemote =>
      AppConfig.useRemote && looksLikeBackendId(widget.userId);

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userByIdProvider(widget.userId));
    // Tab 计数:
    //   - remote:remoteUserPublicProvider 拉的 follower_count/following_count
    //     (后端聚合真总数,不随分页首页数变化)。
    //   - mock:user.followerIds/followingIds 真实数组长度。
    // 两种都避免「分页后 Tab 计数只显首页数」的回归。
    final isRemote = _isRemote;
    final userPublicAsync =
        isRemote ? ref.watch(remoteUserPublicProvider(widget.userId)) : null;
    final followingCount = isRemote
        ? (userPublicAsync?.value?.followingCount ??
            user?.followingIds.length ??
            0)
        : (user?.followingIds.length ?? 0);
    final followerCount = isRemote
        ? (userPublicAsync?.value?.followerCount ??
            user?.followerIds.length ??
            0)
        : (user?.followerIds.length ?? 0);

    // Tab 内容:两 Tab 都用 _PaginatedFollowList(mock/remote 统一)。
    // remote 模式:游标分页 + 无限滚动;
    // mock 模式:Page.last 一次性返回,InfiniteScroll 不触发。
    final followingTab = _PaginatedFollowList(
      userId: widget.userId,
      followers: false,
      emptyTitle: '还没有关注的人',
      emptyVariant: EmptyStateVariant.followers,
    );
    final followersTab = _PaginatedFollowList(
      userId: widget.userId,
      followers: true,
      emptyTitle: '还没有粉丝',
      emptyVariant: EmptyStateVariant.followers,
    );

    return Scaffold(
      backgroundColor: KkColors.bg,
      appBar: AppBar(
        backgroundColor: KkColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const KkBackButton(),
        titleSpacing: 0,
        // 标题保持极简:只显示用户名(如"陈小匠")。当前 Tab 已表明"关注/粉丝"语义。
        title: Text(
          user?.name ?? widget.userId,
          style: KkType.h3,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          // mock loading 时锁 TabBar 避免误触;remote 分支 _mockLoading 永远 true
          // (initState 跳过假 loading),但 remote 用 PaginatedState.isLoading,不锁。
          IgnorePointer(
            ignoring: !isRemote && _mockLoading,
            child: _tabBar(followingCount, followerCount),
          ),
          Expanded(
            child: isRemote
                ? TabBarView(
                    controller: _tabCtrl,
                    children: [followingTab, followersTab],
                  )
                : _mockLoading
                    ? const _SkeletonFollowList()
                    : TabBarView(
                        controller: _tabCtrl,
                        children: [followingTab, followersTab],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _tabBar(int followingCount, int followerCount) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: KkColors.divider)),
      ),
      child: TabBar(
        controller: _tabCtrl,
        labelColor: KkColors.t1,
        unselectedLabelColor: KkColors.t3,
        labelStyle: KkType.body.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: KkType.body,
        indicatorSize: TabBarIndicatorSize.label,
        indicatorColor: KkColors.teal,
        indicatorWeight: 2,
        tabs: [
          Tab(text: '关注 $followingCount'),
          Tab(text: '粉丝 $followerCount'),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 骨架行 — 镜像 _FollowRow(40 头像 + 名字/简介 + 关注按钮)
// HANDOFF §5:不用 coral;只用 KkColors.*(bgCard/bgSubtle)+ 骨架 shimmer
// ──────────────────────────────────────────────────────────────────

class _SkeletonFollowRow extends StatelessWidget {
  const _SkeletonFollowRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.md,
      ),
      color: KkColors.bgCard,
      child: Row(
        children: [
          // 头像(40 圆)
          const SkeletonBox(
            width: 40,
            height: 40,
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          const SizedBox(width: KkSpacing.md),
          // 名字 16 + 简介 12
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                SkeletonLine(width: 120, height: 16),
                SizedBox(height: 4),
                SkeletonLine(width: 80, height: 12),
              ],
            ),
          ),
          const SizedBox(width: KkSpacing.md),
          // 关注按钮(56×28 圆角 pill)
          const SkeletonBox(
            width: 56,
            height: 28,
            borderRadius: BorderRadius.all(Radius.circular(KkRadius.pill)),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 分页列表(P0-1 收口:PaginatedState 三态 + 无限滚动)
//
// 替代原 _RemoteFollowList(AsyncValue) + _FollowList(mock userIds)双轨:
//   - mock:paginatedXxxProvider 的 mock 分支 Page.last 一次性返回(hasMore=false),
//     InfiniteScroll 不触发 loadMore,行为与原 _FollowList 一致。
//   - remote:游标分页 + 无限滚动 + 去重 + 防重入(PaginatedNotifier 基类提供)。
// ──────────────────────────────────────────────────────────────────

class _PaginatedFollowList extends ConsumerStatefulWidget {
  final String userId;

  /// true = followers(粉丝),false = following(关注)。
  final bool followers;
  final String emptyTitle;
  final EmptyStateVariant emptyVariant;

  const _PaginatedFollowList({
    required this.userId,
    required this.followers,
    required this.emptyTitle,
    required this.emptyVariant,
  });

  @override
  ConsumerState<_PaginatedFollowList> createState() =>
      _PaginatedFollowListState();
}

class _PaginatedFollowListState extends ConsumerState<_PaginatedFollowList> {
  late final ScrollController _scrollCtrl;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    InfiniteScroll.attach(_scrollCtrl, onLoadMore: () {
      // hasMore=false 时 Notifier.loadMore no-op(mock + remote 末页)。
      if (widget.followers) {
        ref
            .read(paginatedFollowersProvider(widget.userId).notifier)
            .loadMore();
      } else {
        ref
            .read(paginatedFollowingProvider(widget.userId).notifier)
            .loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.followers
        ? ref.watch(paginatedFollowersProvider(widget.userId))
        : ref.watch(paginatedFollowingProvider(widget.userId));

    if (state.isLoading) {
      return const _SkeletonFollowList();
    }
    if (state.error != null && state.items.isEmpty) {
      // 首屏加载失败:RemoteError 重试 → refresh。
      return RemoteError(
        message: '加载失败',
        onRetry: () async {
          if (widget.followers) {
            await ref
                .read(paginatedFollowersProvider(widget.userId).notifier)
                .refresh();
          } else {
            await ref
                .read(paginatedFollowingProvider(widget.userId).notifier)
                .refresh();
          }
        },
      );
    }
    if (state.items.isEmpty) {
      // 零旁白:空状态只一行事实(followers variant:people_outline + 「还没关注」)。
      return ListView(
        children: [
          EmptyState(
            variant: widget.emptyVariant,
            title: widget.emptyTitle,
          ),
        ],
      );
    }

    // KkUser 已在 UsersApi._parseUsers 里 cacheRemoteUser(或 mock userByIdProvider),
    // _FollowRow watch userByIdProvider 能查到。传 id 复用 mock/remote 同款行。
    final users = state.items;
    final list = ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.only(bottom: KkSpacing.xxl),
      // +1:底部加载指示器(追加加载时显示)。
      itemCount: users.length + 1,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: KkColors.divider, indent: 72),
      itemBuilder: (context, i) {
        if (i == users.length) {
          return LoadMoreIndicator(enabled: state.isLoadingMore);
        }
        return _FollowRow(userId: users[i].id);
      },
    );
    return RefreshIndicator(
      color: KkColors.teal,
      onRefresh: () async {
        if (widget.followers) {
          await ref
              .read(paginatedFollowersProvider(widget.userId).notifier)
              .refresh();
        } else {
          await ref
              .read(paginatedFollowingProvider(widget.userId).notifier)
              .refresh();
        }
      },
      child: list,
    );
  }
}

/// 5 行骨架(mock 假 loading 与 remote 真 loading 共用)。
class _SkeletonFollowList extends StatelessWidget {
  const _SkeletonFollowList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: KkSpacing.xxl),
      itemCount: 5,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: KkColors.divider, indent: 72),
      itemBuilder: (_, __) => const _SkeletonFollowRow(),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 行
// ──────────────────────────────────────────────────────────────────

class _FollowRow extends ConsumerWidget {
  final String userId;

  const _FollowRow({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userByIdProvider(userId));

    return Tappable(
      // 行整体可点 → push 该用户 profile(HANDOFF §6.5 真路由,可深链)。
      onTap: () => context.push(KkRoutes.profile(userId)),
      borderRadius: BorderRadius.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.lg,
          vertical: KkSpacing.md,
        ),
        color: KkColors.bgCard,
        child: Row(
          children: [
            // 头像点击也跳同一目的地,与行点击语义一致。
            TappableAvatar(
              userId: userId,
              user: user,
              size: 40,
              onTap: () => context.push(KkRoutes.profile(userId)),
            ),
            const SizedBox(width: KkSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user?.name ?? userId,
                    style: KkType.body.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (user?.bio != null && user!.bio!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      user.bio!,
                      style: KkType.bodySm.copyWith(color: KkColors.t3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: KkSpacing.md),
            // 嵌套 Tappable:内层 InkWell 优先消费手势,行点击不触发。
            // 自视(userId == 'me')下按钮依然工作 — 你能取关别人。
            _FollowButton(userId: userId),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 关注按钮 — 视觉样式复刻 post_card 的 _FollowButton
// (不 import 私有 widget,按 spec 要求就地复制)
//
// HANDOFF §5:不用珊瑚橙,teal(未关注)/ bgSubtle + bd(已关注)二态。
// ──────────────────────────────────────────────────────────────────

class _FollowButton extends ConsumerWidget {
  final String userId;

  const _FollowButton({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following =
        ref.watch(appStateProvider).followedUserIds.contains(userId);
    return Tappable(
      onTap: () =>
          ref.read(appStateProvider.notifier).toggleFollow(userId),
      borderRadius: BorderRadius.circular(KkRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: KkSpacing.xs,
          horizontal: KkSpacing.md,
        ),
        decoration: BoxDecoration(
          color: following ? KkColors.bgSubtle : KkColors.teal,
          borderRadius: BorderRadius.circular(KkRadius.pill),
          border: following ? Border.all(color: KkColors.bd) : null,
        ),
        child: Text(
          following ? '已关注' : '关注',
          style: TextStyle(
            color: following ? KkColors.t2 : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'NotoSerifSC',
          ),
        ),
      ),
    );
  }
}
