import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/backend_id.dart';
import '../../core/widgets/kk_back_button.dart';
import '../../core/widgets/tappable.dart';
import '../../data/api/users_api.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/post_repository.dart';
import '../../domain/repositories/project_repository.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/project_provider.dart';
import '../../providers/remote_post_provider.dart';
import '../../providers/remote_project_provider.dart';
import '../../router/routes.dart';
import '../shared/empty_state.dart';
import '../shared/list_state_views.dart';
import '../shared/post_card.dart';
import '../shared/profile_header.dart';
import '../shared/project_card.dart';
import '../shared/remote_error.dart';
import '../shared/report_sheet.dart';

/// 个人主页屏 — HANDOFF §6.5 真路由 + 三 Tab + 关注/拉黑/举报。
///
/// 三 Tab:
///   - 动态  PostRepository.byAuthor(userId)
///   - 项目  ProjectRepository.byAuthor(userId)
///   - 收藏  该用户收藏的项目(自己:appState.savedProjectIds;
///           他人:mock 假设几个,真实场景后端查)
///
/// 顶栏:
///   - 头像(点击大图,Phase 4)/ 名字 / 简介 / 关注/粉丝/获赞(真实)
///   - 关注按钮(他人)或编辑资料按钮(自己,Phase 4 跳 profile-edit)
///   - 更多按钮(拉黑/举报 action sheet)
///
/// 计数铁律(HANDOFF §6.10):所有数字取真实数组长度。
/// 零旁白(HANDOFF §3):空状态用 EmptyState。
class ProfileScreen extends ConsumerStatefulWidget {
  final String userId;

  /// 初始 Tab（0=动态 1=项目 2=收藏）。从「我发布的→查看全部」进来传 1，直接看作品。
  final int initialTabIndex;

  const ProfileScreen({
    super.key,
    required this.userId,
    this.initialTabIndex = 0,
  });

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userByIdProvider(widget.userId));
    final auth = ref.watch(authProvider);
    // 「是不是我自己」：userId=='me'（mock 场景）或等于当前登录账号的 UUID。
    // 修 bug：me_screen「查看全部」跳的是我的 UUID，之前只判 =='me' → 误判成看别人的主页
    // （显示「关注」按钮、第三人称视角）。补上 UUID 比对，自己的主页正确进自视角。
    final projectRepo = ref.watch(projectRepositoryProvider);
    final postRepo = ref.watch(postRepositoryProvider);
    final appState = ref.watch(appStateProvider);

    final projects = projectRepo.byAuthor(widget.userId);
    final posts = postRepo.byAuthor(widget.userId);
    // 远程用户(UUID + useRemote)→ 读 GET /users/{id} 真计数 + 真昵称/头像/简介。
    // mock 用户(短 id 'chen')保持 mock 派生。loading/error 退化 mock 占位(无闪烁)。
    final isRemoteUser =
        AppConfig.useRemote && looksLikeBackendId(widget.userId);
    int following = (user?.followingIds ?? const <String>[]).length;
    int followers = (user?.followerIds ?? const <String>[]).length;
    KkUser? displayUser = user;
    if (isRemoteUser) {
      final pub = ref.watch(remoteUserPublicProvider(widget.userId)).value;
      if (pub != null) {
        following = pub.followingCount;
        followers = pub.followerCount;
        // 用真资料覆盖(mock 没有这位远程用户的 name/avatar/bio)。
        displayUser = KkUser(
          id: pub.id,
          name: pub.nickname.isNotEmpty ? pub.nickname : widget.userId,
          avatar: pub.avatarUrl,
          bio: pub.bio,
        );
      }
    }
    final currentUser = auth.currentUser;
    final isMe = currentUser != null &&
        (widget.userId == 'me' ||
            widget.userId == currentUser.id ||
            displayUser?.id == currentUser.id ||
            (displayUser?.name.trim().isNotEmpty == true &&
                displayUser!.name.trim() == currentUser.name.trim()));
    var totalLikes = projects.fold<int>(0, (s, p) => s + p.likes) +
        posts.fold<int>(0, (s, p) => s + p.likes);
    // Tab 计数:mock 用 byAuthor 长度;远程用户 mock 列表为空,改用真列表长度
    // (家族 provider 同参数与 Tab 内共享缓存,不多打一次网络)。loading 退化 0。
    var postCount = posts.length;
    var projectCount = projects.length;
    if (isRemoteUser) {
      final rp = ref.watch(userPostsProvider(widget.userId)).value;
      final rj = ref.watch(userProjectsProvider(widget.userId)).value;
      if (rp != null) {
        postCount = rp.length;
        totalLikes += rp.fold<int>(0, (s, p) => s + p.likes);
      }
      if (rj != null) {
        projectCount = rj.length;
        totalLikes += rj.fold<int>(0, (s, p) => s + p.likes);
      }
    }
    final isFollowing = appState.followedUserIds.contains(widget.userId);

    return Scaffold(
      backgroundColor: KkColors.bg,
      // 任务⑩A:头部对齐 me_screen 视觉语言(渐变 banner + 大头像 + inline 统计)。
      // 不用 AppBar(会盖住 banner 渐变),返回/更多按钮浮在 banner 右上角。
      body: Column(
        children: [
          // 头部:ProfileHeader(banner + 大头像 + 名字 + banner 右上槽 +
          // inline 统计行 关注/粉丝/获赞 + 右侧关注/编辑按钮)
          ProfileHeader(
            user: displayUser,
            userId: widget.userId,
            followingCount: following,
            followerCount: followers,
            totalLikes: totalLikes,
            onTapFollowing: () => context.push(KkRoutes.follows(widget.userId)),
            onTapFollowers: () => context
                .push('${KkRoutes.follows(widget.userId)}?type=followers'),
            // 返回键放左上角（符合直觉，与「更多」分开左右）。
            // 和动态详情等页面共用同一个返回组件与触控规格。
            bannerLeading: const KkBackButton(color: Colors.white),
            bannerActions: [
              // 更多(自己=编辑/退出；他人=拉黑/举报 sheet)
              BannerIconButton(
                icon: Icons.more_horiz,
                onTap: () => _showMoreSheet(context, isMe),
              ),
            ],
            // 右侧操作槽:自己 → 编辑资料;他人 → 关注/已关注
            actionSlot: isMe ? _editButton() : _followButton(isFollowing),
          ),
          const SizedBox(height: KkSpacing.sm),
          _contributionStrip(projectCount, postCount, totalLikes),
          const SizedBox(height: KkSpacing.sm),
          // Tab 栏
          _tabBar(projectCount, postCount),
          // Tab 内容
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _PostsTab(userId: widget.userId),
                _ProjectsTab(userId: widget.userId),
                _SavedTab(userId: widget.userId, isMe: isMe),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 任务⑩A:旧 _profileCard / _countBlock 已删,头部复用共享 ProfileHeader
  // (渐变 banner + 大头像 + inline 统计 + 右侧关注/编辑按钮)。

  Widget _contributionStrip(int projectCount, int postCount, int totalLikes) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      padding: const EdgeInsets.all(KkSpacing.md),
      decoration: BoxDecoration(
        color: KkColors.bgCard,
        borderRadius: BorderRadius.circular(KkRadius.md),
        border: Border.all(color: KkColors.bd),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_graph_outlined, size: 18, color: KkColors.teal),
          const SizedBox(width: KkSpacing.sm),
          Text('TA 的贡献',
              style: KkType.body.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            '$projectCount 作品 · $postCount 动态 · $totalLikes 获赞',
            style: KkType.bodySm.copyWith(color: KkColors.t3),
          ),
        ],
      ),
    );
  }

  Widget _followButton(bool isFollowing) {
    return Tappable(
      onTap: () =>
          ref.read(appStateProvider.notifier).toggleFollow(widget.userId),
      borderRadius: BorderRadius.circular(KkRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.xl,
          vertical: KkSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isFollowing ? KkColors.bgSubtle : KkColors.teal,
          borderRadius: BorderRadius.circular(KkRadius.pill),
          border: isFollowing ? Border.all(color: KkColors.bd) : null,
        ),
        child: Text(
          isFollowing ? '已关注' : '关注',
          style: TextStyle(
            color: isFollowing ? KkColors.t2 : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: 'NotoSerifSC',
          ),
        ),
      ),
    );
  }

  Widget _editButton() {
    return Tappable(
      onTap: () => context.push(KkRoutes.profileEdit),
      borderRadius: BorderRadius.circular(KkRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.xl,
          vertical: KkSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: KkColors.bgSubtle,
          borderRadius: BorderRadius.circular(KkRadius.pill),
          border: Border.all(color: KkColors.bd),
        ),
        child: Text(
          '编辑资料',
          style: TextStyle(
            color: KkColors.t2,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: 'NotoSerifSC',
          ),
        ),
      ),
    );
  }

  Widget _tabBar(int projectCount, int postCount) {
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
          Tab(text: '动态 $postCount'),
          Tab(text: '项目 $projectCount'),
          const Tab(text: '收藏'),
        ],
      ),
    );
  }

  /// 更多操作 sheet(拉黑 / 举报)
  /// HANDOFF §3 零旁白:不写"举报后会怎样",只列动作。
  void _showMoreSheet(BuildContext context, bool isMe) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KkColors.bgCard,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMe) ...[
              _sheetItem(
                icon: Icons.edit_outlined,
                label: '编辑资料',
                onTap: () {
                  Navigator.pop(context);
                  context.push(KkRoutes.profileEdit);
                },
              ),
              const Divider(height: 1, color: KkColors.divider, indent: 56),
              // HANDOFF §5:珊瑚橙只给 take。破坏性操作用 t1 深色 + 字重,
              // 不用珊瑚橙(避免视觉与 take 混淆)。
              _sheetItem(
                icon: Icons.logout_outlined,
                label: '退出登录',
                color: KkColors.t1,
                weight: FontWeight.w600,
                // 修死按钮:原来只 pop(点了没反应)。无真 session,MVP 给二次确认 + 反馈。
                onTap: () async {
                  Navigator.pop(context); // 关 sheet
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (dctx) => AlertDialog(
                      title: const Text('退出登录'),
                      content: const Text('确定要退出登录吗？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dctx, false),
                          child: const Text('取消',
                              style: TextStyle(color: KkColors.t3)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dctx, true),
                          child: const Text('确定',
                              style: TextStyle(color: KkColors.teal)),
                        ),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    // 修 bug：原来只弹 toast、没真登出（令牌还在，写操作照常）。
                    // 与 settings 的登出一致，真调 logout() 清令牌+登录态。
                    ref.read(authProvider.notifier).logout();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已退出登录'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: KkColors.t1,
                      ),
                    );
                  }
                },
              ),
            ] else ...[
              _sheetItem(
                icon: Icons.person_remove_outlined,
                label: '拉黑',
                color: KkColors.t1,
                weight: FontWeight.w600,
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('已拉黑'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: KkColors.t1,
                    ),
                  );
                },
              ),
              const Divider(height: 1, color: KkColors.divider, indent: 56),
              _sheetItem(
                icon: Icons.flag_outlined,
                label: '举报',
                color: KkColors.t1,
                weight: FontWeight.w600,
                onTap: () {
                  Navigator.pop(context);
                  showReportSheet(
                    context,
                    targetType: 'user',
                    targetId: widget.userId,
                  );
                },
              ),
            ],
            const Divider(height: 1, color: KkColors.divider),
            _sheetItem(
              icon: Icons.close,
              label: '取消',
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetItem({
    required IconData icon,
    required String label,
    Color? color,
    FontWeight? weight,
    VoidCallback? onTap,
  }) {
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.md,
          vertical: KkSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color ?? KkColors.t2),
            const SizedBox(width: KkSpacing.md),
            Text(
              label,
              style: KkType.body.copyWith(
                color: color ?? KkColors.t1,
                fontWeight: weight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 动态 Tab
// ──────────────────────────────────────────────────────────────────

class _PostsTab extends ConsumerWidget {
  final String userId;
  const _PostsTab({required this.userId});

  bool get _isRemote => AppConfig.useRemote && looksLikeBackendId(userId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 远程用户(UUID)→ GET /users/{id}/posts 三态;mock 用户→ byAuthor。
    if (_isRemote) {
      return ref.watch(userPostsProvider(userId)).when(
            loading: () => const PostListSkeleton(),
            error: (e, _) => RemoteError(
              message: '动态加载失败',
              error: e,
              onRetry: () async => ref.invalidate(userPostsProvider(userId)),
            ),
            data: (posts) => _list(context, posts),
          );
    }
    final posts = ref.watch(postRepositoryProvider).byAuthor(userId)
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return _list(context, posts);
  }

  Widget _list(BuildContext context, List<Post> posts) {
    if (posts.isEmpty) {
      return ListView(
        children: const [EmptyState(variant: EmptyStateVariant.feed)],
      );
    }
    return ListView.builder(
      itemCount: posts.length,
      itemBuilder: (context, i) => PostCard(
        post: posts[i],
        onTap: () => context.push(KkRoutes.postDetail(posts[i].id)),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 项目 Tab
// ──────────────────────────────────────────────────────────────────

class _ProjectsTab extends ConsumerWidget {
  final String userId;
  const _ProjectsTab({required this.userId});

  bool get _isRemote => AppConfig.useRemote && looksLikeBackendId(userId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 远程用户(UUID)→ GET /users/{id}/projects（仅 published）三态;mock→ byAuthor。
    if (_isRemote) {
      return ref.watch(userProjectsProvider(userId)).when(
            loading: () => const ProjectListSkeleton(),
            error: (e, _) => RemoteError(
              message: '作品加载失败',
              error: e,
              onRetry: () async => ref.invalidate(userProjectsProvider(userId)),
            ),
            data: (projects) => _list(projects),
          );
    }
    final projects = ref.watch(projectRepositoryProvider).byAuthor(userId)
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return _list(projects);
  }

  Widget _list(List<Project> projects) {
    if (projects.isEmpty) {
      return ListView(
        children: const [EmptyState(variant: EmptyStateVariant.generic)],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          KkSpacing.lg, KkSpacing.sm, KkSpacing.lg, KkSpacing.xxl),
      itemCount: projects.length,
      separatorBuilder: (_, __) => const SizedBox(height: KkSpacing.md),
      itemBuilder: (context, i) =>
          ProjectCard(project: projects[i], showAuthor: false),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 收藏 Tab
// ──────────────────────────────────────────────────────────────────

class _SavedTab extends ConsumerWidget {
  final String userId;
  final bool isMe;
  const _SavedTab({required this.userId, required this.isMe});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(projectRepositoryProvider);
    final appState = ref.watch(appStateProvider);

    // 他人收藏对外不可见(后端无「查他人 favorites」端点,隐私)——远程他人一律空态。
    // 自己的收藏 = 后端 UUID 收藏完整卡片(remoteFavoritesProvider) + mock 短 id 演示收藏。
    // 远程收藏卡按 savedProjectIds 过滤(乐观取消收藏即时隐藏,同 library 屏)。
    final remoteFavsAsync = ref.watch(remoteFavoritesProvider);
    final remoteFavs = isMe
        ? (remoteFavsAsync.value ?? const <Project>[])
            .where((p) => appState.savedProjectIds.contains(p.id))
        : const <Project>[];
    final saved = isMe
        ? <Project>[
            ...remoteFavs,
            ...repo.all().where((p) => appState.savedProjectIds.contains(p.id)),
          ]
        : const <Project>[];

    if (isMe &&
        AppConfig.useRemote &&
        remoteFavsAsync.isLoading &&
        appState.savedProjectIds.isNotEmpty) {
      return const ProjectListSkeleton();
    }
    if (isMe &&
        AppConfig.useRemote &&
        remoteFavsAsync.error != null &&
        saved.isEmpty) {
      return RemoteError(
        message: '收藏加载失败',
        error: remoteFavsAsync.error,
        onRetry: () async => ref.invalidate(remoteFavoritesProvider),
      );
    }
    if (saved.isEmpty) {
      return ListView(
        children: const [EmptyState(variant: EmptyStateVariant.saved)],
      );
    }
    return ListView.builder(
      itemCount: saved.length,
      itemBuilder: (context, i) =>
          ProjectCard(project: saved[i], compact: true),
    );
  }
}
