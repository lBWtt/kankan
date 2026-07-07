import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/pagination/infinite_scroll.dart';
import '../../core/pagination/page.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/skeletons.dart';
import '../../core/widgets/tappable.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/post_repository.dart';
import '../../domain/repositories/search_repository.dart';
import '../../providers/paginated_posts_provider.dart';
import '../shared/remote_error.dart';
import '../../providers/app_state_provider.dart';
import '../../router/routes.dart';
import '../shared/comment_bottom_sheet.dart';
import '../shared/empty_state.dart';
import '../shared/kk_chip.dart';
import '../shared/post_card.dart';

/// 发现屏 — HANDOFF §1 动态(轻)feed。
///
/// 双流(HANDOFF §6.6 — Web 版重灾区,Flutter 从零做对):
///   - 推荐:全部动态(按时间倒序)
///   - 关注:仅关注的人发的(从 followedUserIds 过滤)
///
/// 切换 tab 不重新请求,本地过滤(Phase 5 接后端再分页)。
/// 评论弹层:点评论图标 → showCommentBottomSheet(统一 CommentThread)。
///
/// 零旁白(HANDOFF §3):无"快来发条动态吧"之类引导。空状态用 EmptyState。
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  /// 加载态:Phase 5 接真后端时,把这个 _loading 切到真 await 网络请求即可。
  /// 现在 mock 数据是同步的,300ms 假延迟让骨架屏有展示机会。
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // KkRootShell 已提供 NoiseBackground + SafeArea(bottom: false),
    // branch 屏只返回内容 Column,不重复包装(避免双重噪点 + 双重 SafeArea)。
    return Column(
      children: [
        _topBar(),
        // loading 时锁住 Tab,避免在骨架屏期间切 feed。
        IgnorePointer(ignoring: _loading, child: _tabBar()),
        Expanded(
          child: ColoredBox(
            // 任务②:列表区 bg2 底,PostCard bgCard "浮"起来
            color: KkColors.bgSubtle,
            child: _loading
                ? _skeletonList()
                : TabBarView(
                    controller: _tabCtrl,
                    children: const [
                      _RecommendFeed(),
                      _FollowingFeed(),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ── 加载态骨架屏:3 个 ProjectCardSkeleton + 1 个 PostCardSkeleton ──
  // PostCardSkeleton 自带 horizontal: KkSpacing.lg 内边距,ProjectCardSkeleton
  // 是 edge-to-edge 的,所以外层包一层 lg 横向 padding 对齐真实 feed 边距。
  Widget _skeletonList() {
    return ListView(
      children: const [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: KkSpacing.lg,
            vertical: KkSpacing.sm,
          ),
          child: ProjectCardSkeleton(),
        ),
        SizedBox(height: KkSpacing.lg),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: KkSpacing.lg),
          child: ProjectCardSkeleton(),
        ),
        SizedBox(height: KkSpacing.lg),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: KkSpacing.lg),
          child: ProjectCardSkeleton(),
        ),
        SizedBox(height: KkSpacing.lg),
        PostCardSkeleton(),
      ],
    );
  }

  // ── 顶栏:标题 + 搜索入口 ──
  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.md,
      ),
      child: Row(
        children: [
          // 任务②:标题后 6×6 teal 品牌点
          Text('发现', style: KkType.h1),
          const SizedBox(width: 7),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: KkColors.teal,
              shape: BoxShape.circle,
            ),
          ),
          const Spacer(),
          Tappable(
            onTap: () => context.push(KkRoutes.search),
            child: const Icon(Icons.search, size: 22, color: KkColors.t1),
          ),
        ],
      ),
    );
  }

  // ── 双流 tab:推荐 / 关注 ──
  Widget _tabBar() {
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
        tabs: const [
          Tab(text: '推荐'),
          Tab(text: '关注'),
        ],
      ),
    );
  }
}

// ── 推荐 feed:全部动态(按时间倒序)──
// P0-1 分页：用 paginatedPostsProvider（游标分页 + 无限滚动 + 去重）。
// mock 模式下 provider 一次性返回全部（hasMore=false），行为与旧版一致。
class _RecommendFeed extends ConsumerStatefulWidget {
  const _RecommendFeed();

  @override
  ConsumerState<_RecommendFeed> createState() => _RecommendFeedState();
}

class _RecommendFeedState extends ConsumerState<_RecommendFeed> {
  late final ScrollController _scrollCtrl;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    InfiniteScroll.attach(_scrollCtrl, onLoadMore: () {
      ref.read(paginatedPostsProvider.notifier).loadMore();
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 任务⑬:推荐流顶部「今日话题」横条(话题空则不渲染,零旁白)。
    final topics = ref.watch(searchRepositoryProvider).topTopics(limit: 8);

    final Widget feed;
    final state = ref.watch(paginatedPostsProvider);
    if (state.isLoading) {
      feed = const Center(
        child: Padding(
          padding: EdgeInsets.all(KkSpacing.xxl),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(KkColors.teal),
          ),
        ),
      );
    } else if (state.error != null && state.items.isEmpty) {
      // 首屏加载失败。
      feed = RemoteError(
        message: '动态加载失败',
        onRetry: () async =>
            ref.read(paginatedPostsProvider.notifier).refresh(),
      );
    } else {
      // 过滤「不感兴趣」+ 按时间倒序（mock/remote 通用；remote 后端已倒序，重排幂等）。
      final ni = ref.watch(appStateProvider).notInterestedIds;
      final posts = state.items
          .where((p) => !ni.contains(p.id))
          .toList()
        ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      feed = _refreshableList(context, ref, posts, state);
    }

    if (topics.isEmpty) return feed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TodayTopicStrip(topics: topics),
        Expanded(child: feed),
      ],
    );
  }

  Widget _refreshableList(
    BuildContext context,
    WidgetRef ref,
    List<Post> posts,
    PaginatedState<Post> paginatedState,
  ) {
    final list = posts.isEmpty
        ? ListView(
            children: const [EmptyState(variant: EmptyStateVariant.feed)],
          )
        : ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.only(bottom: KkSpacing.xxl),
            // +1：底部加载指示器（追加加载时显示）。
            itemCount: posts.length + 1,
            itemBuilder: (context, i) {
              if (i == posts.length) {
                return LoadMoreIndicator(
                  enabled: paginatedState.isLoadingMore,
                );
              }
              final post = posts[i];
              return PostCard(
                post: post,
                onTap: () => context.push(KkRoutes.postDetail(post.id)),
                onCommentTap: () => _showComments(context, ref, post),
              );
            },
          );
    return RefreshIndicator(
      color: KkColors.teal,
      onRefresh: () async {
        await ref.read(paginatedPostsProvider.notifier).refresh();
        // mock：同步刷一下 search repo（今日话题）。
        ref.invalidate(searchRepositoryProvider);
      },
      child: list,
    );
  }

  void _showComments(BuildContext context, WidgetRef ref, Post post) {
    final repo = ref.read(postRepositoryProvider);
    final comments = repo.commentsFor(post.id);
    showCommentBottomSheet(
      context,
      hostType: 'post',
      hostId: post.id,
      initialComments: comments,
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 任务⑬:推荐流顶部「今日话题」横条
// ──────────────────────────────────────────────────────────────────
// 发现效率入口:左「今日话题」(t1 加粗)+ 右「话题广场 →」(teal → topicPlaza)
// + 下方一排横向话题 chip(topTopics(limit:8),点 → topic(tag))。
// 话题空 → 整条不渲染(由 _RecommendFeed 调用方守,本组件假定 topics 非空)。
//
// 视觉:bgCard 浮起(列表区 bgSubtle)+ 头部 + 横向 chip + 极浅 divider(参考
// 任务⑦ _RecommendStrip 做法)。铁律:coral 只给 take(此处全 teal/中性);
// 无 emoji(用 # + Icon);零旁白(标题就是"今日话题");触控 ≥44pt(KkChip
// 外层 Tappable 内置 minSize 44)。
class _TodayTopicStrip extends StatelessWidget {
  final List<Topic> topics;

  const _TodayTopicStrip({required this.topics});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: KkColors.bgCard,
      padding: const EdgeInsets.symmetric(vertical: KkSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(context),
          const SizedBox(height: KkSpacing.sm),
          SizedBox(
            // 横列表高度跟齐 Tappable 的 minSize 44
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
              itemCount: topics.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: KkSpacing.sm),
              itemBuilder: (context, i) {
                final t = topics[i];
                // 修 bug:原来直接用 KkChip.solid(onTap:),其内部
                // Material(transparent)>InkWell 在横向 ListView 的 Scrollable
                // 里,InkWell 的 TapGestureRecognizer 与 HorizontalDragGestureRecognizer
                // 竞争,Flutter web(mouse)下鼠标 down→亚像素移动即被判 drag,
                // tap 被 cancel → 点击无反应;且 KkChip 内 InkWell 无 minSize 约束,
                // 实际触控区 ~29px < 44pt 铁律。
                // 修复:外层用项目验证过的 Tappable(translucent 命中 + ConstrainedBox
                // min44 + InkWell),KkChip.solid 不传 onTap(纯视觉,内部不套 InkWell)。
                // Tappable 在横向 ListView item 里宽度 unbounded 但 Center 不撑满
                // (不同于 Wrap 的 bounded→expand 阶梯 bug),触控区稳 44pt,点击稳。
                // 不改 KkChip 本身 — 保护 me 页 Wrap 场景仍走 InkWell 自适应布局。
                return Tappable(
                  onTap: () => context.push(KkRoutes.topic(t.tag)),
                  borderRadius: BorderRadius.circular(KkRadius.pill),
                  child: KkChip.solid(label: '#${t.tag}'),
                );
              },
            ),
          ),
          // 极浅 divider 分隔横条与 feed
          const Divider(
            color: KkColors.divider,
            height: 1,
            thickness: 0.5,
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Row(
        children: [
          Text(
            '今日话题',
            style: KkType.body.copyWith(
              color: KkColors.t1,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Tappable(
            onTap: () => context.push(KkRoutes.topicPlaza),
            child: Container(
              // padding 撑到 ~44pt 热区
              padding: const EdgeInsets.symmetric(
                horizontal: KkSpacing.sm,
                vertical: KkSpacing.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '话题广场',
                    style: KkType.bodySm.copyWith(
                      fontSize: 12,
                      color: KkColors.teal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: KkColors.teal,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 关注 feed:仅关注的人发的 ──
class _FollowingFeed extends ConsumerWidget {
  const _FollowingFeed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final repo = ref.watch(postRepositoryProvider);
    final followed = appState.followedUserIds;

    // 关注流 = 关注的人发的动态(按时间倒序)。
    // 首次启动 app_state.followedUserIds 为空(用户还没主动关注过),
    // 给 fallback:展示 mock 里"我(me)"默认关注的人(lin/chen/wang),
    // 让关注流不是恒空(否则首次进 app 关注流空,体验差)。
    // 用户主动关注/取关后,followed 非空,走真实过滤。
    final effectiveFollowed = followed.isEmpty
        ? const <String>{'chen', 'lin', 'wang'}
        : followed;

    // 任务⑫:同样过滤「不感兴趣」(负反馈闭环对称推荐流)。
    final ni = appState.notInterestedIds;
    final posts = repo
        .all()
        .where((p) =>
            effectiveFollowed.contains(p.authorId) && !ni.contains(p.id))
        .toList()
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));

    if (posts.isEmpty) {
      return RefreshIndicator(
        color: KkColors.teal,
        onRefresh: () async {
          ref.invalidate(postRepositoryProvider);
          await Future<void>.delayed(const Duration(milliseconds: 400));
        },
        child: ListView(
          children: const [EmptyState(variant: EmptyStateVariant.feed)],
        ),
      );
    }

    return RefreshIndicator(
      color: KkColors.teal,
      onRefresh: () async {
        ref.invalidate(postRepositoryProvider);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: KkSpacing.xxl),
        itemCount: posts.length,
        itemBuilder: (context, i) {
          final post = posts[i];
          return PostCard(
            post: post,
            onTap: () => context.push(KkRoutes.postDetail(post.id)),
            onCommentTap: () => _showComments(context, ref, post),
          );
        },
      ),
    );
  }

  void _showComments(BuildContext context, WidgetRef ref, Post post) {
    final repo = ref.read(postRepositoryProvider);
    final comments = repo.commentsFor(post.id);
    showCommentBottomSheet(
      context,
      hostType: 'post',
      hostId: post.id,
      initialComments: comments,
    );
  }
}
