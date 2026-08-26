import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/pagination/infinite_scroll.dart';
import '../../core/pagination/page.dart';
import '../../core/prefs.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/skeletons.dart';
import '../../core/widgets/tappable.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/post_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/search_provider.dart';
import '../../providers/paginated_posts_provider.dart';
import '../../providers/remote_post_provider.dart';
import '../../providers/remote_project_provider.dart';
import '../shared/remote_error.dart';
import '../../providers/app_state_provider.dart';
import '../../router/routes.dart';
import '../shared/comment_bottom_sheet.dart';
import '../shared/empty_state.dart';
import '../shared/kk_chip.dart';
import '../shared/list_state_views.dart';
import '../shared/post_card.dart';
import '../shared/project_card.dart';

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
  final int initialTabIndex;

  const DiscoverScreen({super.key, this.initialTabIndex = 0});

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
    _tabCtrl = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    if (AppConfig.useRemote) {
      // 远端有真实加载态（paginatedPostsProvider isLoading），不摆 300ms 假骨架。
      _loading = false;
    } else {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() => _loading = false);
      });
    }
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
                    // 恢复横滑切 Tab（默认 physics）：用户反馈完全禁掉太不方便。
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

  // 推荐排序种子：每次下拉刷新变一次 → 整批重排，逛起来有新鲜感（与「看看/推荐」
  // recommend_masonry 一致，不是固定时间倒序榜单）。
  int _seed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;

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
    // 统一走 topTopicsProvider：mock 读内存、remote 读 /topics；加载中/失败 → 空 → 不渲染。
    // 「今日话题」= 取高热池 top-30，按当天日期滚动窗口取 8 个 → 每天换一批、但仍是真实高热话题
    // （后端只按 heat 定序，冷启动内容少时 top-8 天天一样，会「固定死」；这里按日轮换消除固定感）。
    final pool = ref.watch(topTopicsProvider(30)).asData?.value ?? const <Topic>[];
    final topics = _todayTopics(pool, 8);

    final Widget feed;
    final state = ref.watch(paginatedPostsProvider);
    if (state.isLoading) {
      feed = const PostListSkeleton();
    } else if (state.error != null && state.items.isEmpty) {
      // 首屏加载失败。error 透传 → 失败页显示真实原因（网络/HTTP码/业务码）。
      feed = RemoteError(
        message: '动态加载失败',
        error: state.error,
        onRetry: () async =>
            ref.read(paginatedPostsProvider.notifier).refresh(),
      );
    } else {
      // 过滤「不感兴趣」+ 自己发的（自己的动态归「关注」和个人主页，不塞进推荐）。
      // 排序 = 每次下拉刷新换一批（不是固定时间倒序）：随机抖动占主导（rng*100），
      // 点赞/评论只做很轻加权——否则高赞永远压顶、看着「刷新没换」。_seed 每次刷新变→整批重排。
      final ni = ref.watch(appStateProvider).notInterestedIds;
      final myId = ref.watch(authProvider).currentUser?.id;
      final posts = state.items
          .where((p) => !ni.contains(p.id) && p.authorId != myId)
          .toList();
      final rng = Random(_seed);
      final score = <String, double>{
        for (final p in posts)
          p.id: rng.nextDouble() * 100.0 + p.likes * 0.1 + p.commentCount * 0.3,
      };
      posts.sort((a, b) => score[b.id]!.compareTo(score[a.id]!));
      feed = _refreshableList(context, ref, posts, state);
    }

    // 「今日话题」当天被手动关掉则隐藏（次日自动再现）。
    final today = _todayStr();
    final topicDismissKey =
        '${ref.watch(authProvider).currentUser?.id ?? 'guest'}::${PrefsKeys.kvTopicDismissDate}';
    final dismissed =
        ref.watch(prefsProvider).getString(topicDismissKey) == today;
    if (topics.isEmpty || dismissed) return feed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TodayTopicStrip(
          topics: topics,
          onClose: () {
            final offset = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
            ref.read(prefsProvider).setString(topicDismissKey, today);
            setState(() {}); // 立即收起（prefs 写入不触发 rebuild）
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !_scrollCtrl.hasClients) return;
              _scrollCtrl.jumpTo(offset.clamp(
                _scrollCtrl.position.minScrollExtent,
                _scrollCtrl.position.maxScrollExtent,
              ));
            });
          },
        ),
        Expanded(child: feed),
      ],
    );
  }

  /// 「今日话题」按天轮换：从高热池里以当天日期为种子滑动出 [take] 个。
  /// 同一天内稳定（不会每次 rebuild 抖动），跨天自动换一批 → 消除「固定死」。
  /// 池不够 take 时原样返回（零旁白：不足就少显示几个，不编造）。
  List<Topic> _todayTopics(List<Topic> pool, int take) {
    if (pool.length <= take) return pool;
    final now = DateTime.now();
    final epochDay =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch ~/
            Duration.millisecondsPerDay;
    final start = (epochDay * take) % pool.length;
    return [for (var i = 0; i < take; i++) pool[(start + i) % pool.length]];
  }

  /// 本地日期串 yyyy-mm-dd（用于「今日话题」按天记忆关闭态）。
  String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Widget _refreshableList(
    BuildContext context,
    WidgetRef ref,
    List<Post> posts,
    PaginatedState<Post> paginatedState,
  ) {
    final list = posts.isEmpty
        ? ListView(
            key: const PageStorageKey('discover-recommend-empty'),
            controller: _scrollCtrl,
            children: const [EmptyState(variant: EmptyStateVariant.feed)],
          )
        : ListView.builder(
            key: const PageStorageKey('discover-recommend-list'),
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
        // 下拉刷新：换种子 → 整批重排（这就是「刷新换内容」）；同时重拉后端拿新增。
        setState(
            () => _seed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff);
        await ref.read(paginatedPostsProvider.notifier).refresh();
        // 刷新今日话题横条（mock 走内存聚合、remote 重拉 /topics）。
        ref.invalidate(topTopicsProvider);
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

  /// 点右上角 ✕ 关闭（当天不再显示，次日再现）。
  final VoidCallback onClose;

  const _TodayTopicStrip({required this.topics, required this.onClose});

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
              separatorBuilder: (_, __) => const SizedBox(width: KkSpacing.sm),
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
          // 关闭 ✕（当天收起，次日自动再现）
          Tappable(
            onTap: onClose,
            borderRadius: BorderRadius.circular(KkRadius.pill),
            child: const Padding(
              padding: EdgeInsets.all(KkSpacing.sm),
              child: Icon(Icons.close, size: 16, color: KkColors.t3),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 关注 feed:仅关注的人发的 ──
class _FollowingFeed extends ConsumerStatefulWidget {
  const _FollowingFeed();

  @override
  ConsumerState<_FollowingFeed> createState() => _FollowingFeedState();
}

class _FollowingFeedState extends ConsumerState<_FollowingFeed> {
  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final repo = ref.watch(postRepositoryProvider);
    final auth = ref.watch(authProvider);
    final remoteState = ref.watch(paginatedPostsProvider);
    final projectsAsync = ref.watch(remoteProjectsProvider);
    final followed = appState.followedUserIds;
    final myId = auth.currentUser?.id;

    // 关注流 = 关注的人发的动态(按时间倒序)。
    // 首次启动 app_state.followedUserIds 为空(用户还没主动关注过),
    // 给 fallback:展示 mock 里"我(me)"默认关注的人(lin/chen/wang),
    // 让关注流不是恒空(否则首次进 app 关注流空,体验差)。
    // 用户主动关注/取关后,followed 非空,走真实过滤。
    final effectiveFollowed = followed;

    // 任务⑫:同样过滤「不感兴趣」(负反馈闭环对称推荐流)。
    final ni = appState.notInterestedIds;
    final source = AppConfig.useRemote ? remoteState.items : repo.all();
    // 关注流 = 关注的人 + 我自己 发的动态。
    // 修 bug：马甲内容持续灌入，全局分页流首页全是最新马甲动态，自己早先发的动态
    // 被挤出首页 → 在这里过滤 authorId==myId 永远命中不到。用 userPostsProvider
    // 直接把「我的动态」补齐（不受分页首页限制），再与关注者动态去重合并。
    final myPosts = (AppConfig.useRemote && myId != null)
        ? (ref.watch(userPostsProvider(myId)).asData?.value ?? const <Post>[])
        : const <Post>[];
    final seenPostIds = <String>{};
    final posts = <Post>[];
    for (final p in [...myPosts, ...source]) {
      if (!(p.authorId == myId || effectiveFollowed.contains(p.authorId))) {
        continue;
      }
      if (ni.contains(p.id)) continue;
      if (!seenPostIds.add(p.id)) continue;
      posts.add(p);
    }
    posts.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    final projects = (projectsAsync.asData?.value ?? const <Project>[])
        .where((p) =>
            (p.authorId == myId || effectiveFollowed.contains(p.authorId)) &&
            !ni.contains(p.id))
        .toList();
    final items = <({int time, Post? post, Project? project})>[
      for (final post in posts)
        (time: post.createdAtMs, post: post, project: null),
      for (final project in projects)
        (time: project.createdAtMs, post: null, project: project),
    ]..sort((a, b) => b.time.compareTo(a.time));

    if (AppConfig.useRemote &&
        (remoteState.isLoading || projectsAsync.isLoading) &&
        items.isEmpty) {
      return const PostListSkeleton();
    }

    final followError = remoteState.error ?? projectsAsync.error;
    if (AppConfig.useRemote && followError != null && items.isEmpty) {
      return RemoteError(
        message: '关注页加载失败',
        error: followError,
        onRetry: () async {
          await ref.read(paginatedPostsProvider.notifier).refresh();
          ref.invalidate(remoteProjectsProvider);
          if (myId != null) ref.invalidate(userPostsProvider(myId));
        },
      );
    }

    if (items.isEmpty) {
      return RefreshIndicator(
        color: KkColors.teal,
        onRefresh: () async {
          if (AppConfig.useRemote) {
            await ref.read(paginatedPostsProvider.notifier).refresh();
            ref.invalidate(remoteProjectsProvider);
            if (myId != null) ref.invalidate(userPostsProvider(myId));
          } else {
            ref.invalidate(postRepositoryProvider);
            await Future<void>.delayed(const Duration(milliseconds: 400));
          }
        },
        child: ListView(
          children: const [EmptyState(variant: EmptyStateVariant.feed)],
        ),
      );
    }

    return RefreshIndicator(
      color: KkColors.teal,
      onRefresh: () async {
        if (AppConfig.useRemote) {
          await ref.read(paginatedPostsProvider.notifier).refresh();
          ref.invalidate(remoteProjectsProvider);
          if (myId != null) ref.invalidate(userPostsProvider(myId));
        } else {
          ref.invalidate(postRepositoryProvider);
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: KkSpacing.xxl),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          final post = item.post;
          if (post != null) {
            return PostCard(
              post: post,
              onTap: () => context.push(KkRoutes.postDetail(post.id)),
              onCommentTap: () => _showComments(context, ref, post),
            );
          }
          return ProjectCard(project: item.project!);
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
