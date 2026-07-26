import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/domain_meta.dart';
import '../../core/utils/parse_count.dart';
import '../../core/utils/time_ago.dart';
import '../../core/widgets/cover_art.dart';
import '../../core/widgets/tappable.dart';
import '../../data/api/activity_api.dart';
import '../../data/api/users_api.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/post_repository.dart';
import '../../domain/repositories/project_repository.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/project_provider.dart';
import '../../providers/remote_post_provider.dart';
import '../../providers/remote_project_provider.dart';
import '../../providers/search_provider.dart';
import '../../router/routes.dart';
import '../shared/avatar.dart';
import '../shared/kk_chip.dart';
import '../shared/list_state_views.dart';
import '../shared/profile_header.dart';
import '../shared/kk_image.dart';
import '../shared/remote_error.dart';
import 'widgets/contribution_heatmap.dart';

/// 我的屏 — 任务③整屏重构为"个人主页"式布局。
///
/// 从上到下 7 块(签到卡不做,相机/封面上传不做):
///   1. 渐变 banner(160px,暖色柔和渐变)+ 右上通知/设置图标
///   2. 大头像(72×72,压在 banner 底沿)+ 名字 + 编辑资料链接
///   3. inline 四联统计(关注/粉丝/获赞/收藏,纯文字无边框)
///   4. (签到卡跳过)
///   5. 我的贡献卡(白卡 + ContributionHeatmap bare 嵌入,整卡 → activity)
///   6. 我关注的领域(chip 排 + "+调整")
///   7. 我关注的话题(chip 排 / 空态)
///   8. 最近看过的项目(横向小卡 + 清空)
///
/// 真实计数(HANDOFF §6.10 禁 ×200):
///   - 关注 = me.followingIds.length
///   - 粉丝 = me.followerIds.length
///   - 获赞 = myProjects.likes + myPosts.likes
///   - 收藏 = appState.savedProjectIds.length
///   - 贡献活跃 = mockHeatmapCells 里 level>0 的格子数
///
/// 零旁白(HANDOFF §3):无"完善资料"之类引导。
/// 铁律:coral 只给 take / 无 emoji / 触控 ≥44pt / 禁 artifactType 分支。
class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    try {
      return Scaffold(
        backgroundColor: KkColors.bg,
        body: _buildContent(context, ref),
      );
    } catch (error, stack) {
      debugPrint('MeScreen build failed: $error\n$stack');
      return Scaffold(
        backgroundColor: KkColors.bg,
        body: _buildErrorFallback(context, error),
      );
    }
  }

  Widget _buildErrorFallback(BuildContext context, Object error) {
    return ListView(
      key: const PageStorageKey<String>('me-error-root-v1'),
      padding: const EdgeInsets.fromLTRB(
        KkSpacing.lg,
        KkSpacing.xl,
        KkSpacing.lg,
        KkSpacing.xxxl,
      ),
      children: [
        Text('我的', style: KkType.h1),
        const SizedBox(height: KkSpacing.xl),
        Container(
          padding: const EdgeInsets.all(KkSpacing.lg),
          decoration: BoxDecoration(
            color: KkColors.bgCard,
            border: Border.all(color: KkColors.bd),
            borderRadius: BorderRadius.circular(KkRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('页面加载失败', style: KkType.h3),
              const SizedBox(height: KkSpacing.sm),
              Text(
                '请重试，或从设置反馈这个问题。',
                style: KkType.bodySm.copyWith(color: KkColors.t2),
              ),
              const SizedBox(height: KkSpacing.md),
              Text(
                error.toString(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: KkType.mono.copyWith(color: KkColors.t3, fontSize: 11),
              ),
              const SizedBox(height: KkSpacing.md),
              TextButton(
                onPressed: () => context.go(KkRoutes.me),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref) {
    return _buildContentBody(context, ref);
  }

  Widget _buildContentBody(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final projectRepo = ref.watch(projectRepositoryProvider);
    final appState = ref.watch(appStateProvider);

    final isLoggedIn = auth.isLoggedIn;
    // 身份:登录后用真后端账号;未登录 → 「未登录」占位身份(不再回落到 mock「看看君」
    // 演示画像——避免退出登录后仍显示一个假名字/假简介)。
    final me = auth.currentUser ??
        const KkUser(id: 'guest', name: '未登录', bio: '登录后同步你的关注与贡献');

    // 计数(禁编造假数据):未登录一律 0;登录 + useRemote → GET /me 真计数
    // (loading/error 时先显 0 占位,拿到真值再覆盖)。收藏在未登录时取本地会话收藏数
    // (游客浏览时的真实本地收藏),登录后由后端真值覆盖。
    var followingCount = 0;
    var followerCount = 0;
    var totalLikes = 0;
    var savedCount = isLoggedIn ? 0 : appState.savedProjectIds.length;
    if (isLoggedIn && AppConfig.useRemote) {
      // .value:loading/error 时 null → 保持 0 占位;data 时真值覆盖。
      final real = ref.watch(myCountsProvider).value;
      if (real != null) {
        followingCount = real.following;
        followerCount = real.follower;
        totalLikes = real.receivedLikes; // 我的内容获赞总数（后端聚合）
        savedCount = real.favorites; // 我的收藏数（后端聚合）
      }
    }
    // 免打扰生效:DND 开 → effectiveUnreadCount 归零 → 通知铃红点消失。
    final unreadCount = appState.effectiveUnreadCount;

    // 最近看过的项目 → 真实 Project 列表(过滤已删/不存在的 ID)
    final recentProjects = <Project>[];
    for (final id in appState.browseHistory.take(12)) {
      final local = projectRepo.byId(id);
      final remote =
          AppConfig.useRemote ? ref.watch(projectByIdProvider(id)).value : null;
      final project = local ?? remote;
      if (project != null) recentProjects.add(project);
    }

    // 关注/粉丝列表入口:登录 → 真 UUID(follows 屏走 remote 真列表,与真计数对齐);
    // 未登录 → 'me'(mock 演示列表)。
    final followsTargetId =
        (isLoggedIn && auth.currentUser != null) ? auth.currentUser!.id : 'me';

    if (!isLoggedIn) {
      return ListView(
        padding: const EdgeInsets.only(bottom: KkSpacing.xxxl),
        children: [
          _guestHeader(context, savedCount, recentProjects.length),
          if (recentProjects.isNotEmpty) ...[
            const SizedBox(height: KkSpacing.xl),
            _recentlyViewedSection(context, ref, recentProjects),
          ],
          const SizedBox(height: KkSpacing.xl),
          _guestBenefits(),
        ],
      );
    }

    return RefreshIndicator(
      color: KkColors.teal,
      onRefresh: () async {
        // 下拉刷新：删项目 / 点赞动态后不会自动更新——这里重拉「我的」相关 provider。
        final selfId = ref.read(authProvider).currentUser?.id;
        ref.invalidate(myProjectsProvider);
        if (selfId != null) ref.invalidate(userPostsProvider(selfId));
        ref.invalidate(myActivityProvider);
        ref.invalidate(myCountsProvider);
        try {
          await ref.read(myProjectsProvider.future);
          if (selfId != null) await ref.read(userPostsProvider(selfId).future);
        } catch (_) {}
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: KkSpacing.xxxl),
        children: [
          // 1+2+3. 渐变 banner + 大头像 + 名字 + inline 四联统计
          // 任务⑩A:复用共享 ProfileHeader(me 传 fourthStat=收藏,profile 传 actionSlot=关注/编辑)
          ProfileHeader(
            user: me,
            userId: 'me',
            followingCount: followingCount,
            followerCount: followerCount,
            totalLikes: totalLikes,
            onTapFollowing: () =>
                context.push(KkRoutes.follows(followsTargetId)),
            onTapFollowers: () =>
                context.push(KkRoutes.follows(followsTargetId)),
            fourthStatLabel: '收藏',
            fourthStatValue: savedCount,
            onTapFourthStat: () => context.go(KkRoutes.library),
            // 换背景:image_picker 选图 → 存 app_state(会话内有效,web 是 blob URL)。
            bannerImageUrl: appState.bannerImageUrl,
            onChangeBanner: () => _pickBanner(ref),
            bannerActions: [
              BannerIconButton(
                icon: Icons.notifications_outlined,
                onTap: () => context.push(KkRoutes.notifications),
                hasDot: unreadCount > 0,
              ),
              BannerIconButton(
                icon: Icons.settings_outlined,
                onTap: () => context.push(KkRoutes.settings),
              ),
            ],
          ),
          // 编辑资料/登录：从原来挤在名字旁边（与头像/名字不在一条线、显乱）移到头部下方，
          // 独立成一条整齐的按钮，对齐清楚、也更好点。
          _editProfileButton(context, isLoggedIn),
          const SizedBox(height: KkSpacing.xl),
          // 贡献卡保留为个人页稳定入口；没有贡献接口时诚实展示 0，不隐藏功能。
          _contributionCard(context, ref),
          const SizedBox(height: KkSpacing.xl),
          // 我发布的(横向小卡,空态零旁白)
          _myContentSection(context, ref),
          const SizedBox(height: KkSpacing.xl),
          // 「我关注的领域」已移除（用户决策：领域退到后台；用户只关注「话题 + 人」）。
          // 关注的话题——用户的主关注维度。
          _followedTopicsSection(context, ref),
          const SizedBox(height: KkSpacing.xl),
          // 8. 最近看过的项目 + 清空
          _recentlyViewedSection(context, ref, recentProjects),
        ],
      ),
    );
  }

  Widget _guestHeader(
    BuildContext context,
    int savedCount,
    int recentCount,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KkSpacing.lg,
        KkSpacing.md,
        KkSpacing.lg,
        0,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('我的', style: KkType.h2),
              const Spacer(),
              BannerIconButton(
                icon: Icons.settings_outlined,
                onTap: () => context.push(KkRoutes.settings),
              ),
            ],
          ),
          const SizedBox(height: KkSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(KkSpacing.xl),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF1E2), Color(0xFFF0F8F4)],
              ),
              borderRadius: BorderRadius.circular(KkRadius.xl),
              border: Border.all(color: KkColors.bd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const KkAvatar(
                      userId: 'guest',
                      user: KkUser(id: 'guest', name: '未登录'),
                      size: 64,
                    ),
                    const SizedBox(width: KkSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('登录看看', style: KkType.h2),
                          const SizedBox(height: 4),
                          Text(
                            '同步收藏、关注和你的创作',
                            style: KkType.bodySm.copyWith(color: KkColors.t3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KkSpacing.lg),
                Tappable(
                  onTap: () => context.push(KkRoutes.login),
                  borderRadius: BorderRadius.circular(KkRadius.pill),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: KkColors.teal,
                      borderRadius: BorderRadius.circular(KkRadius.pill),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '登录 / 注册',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: KkSpacing.md),
          Row(
            children: [
              Expanded(
                child: _guestQuickAction(
                  context,
                  icon: Icons.bookmark_outline,
                  label: '本地收藏',
                  value: '$savedCount',
                  onTap: () => context.go(KkRoutes.library),
                ),
              ),
              const SizedBox(width: KkSpacing.md),
              Expanded(
                child: _guestQuickAction(
                  context,
                  icon: Icons.history,
                  label: '最近看过的项目',
                  value: '$recentCount',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _guestQuickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KkRadius.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.md,
          vertical: KkSpacing.md,
        ),
        decoration: BoxDecoration(
          color: KkColors.bgCard,
          borderRadius: BorderRadius.circular(KkRadius.lg),
          border: Border.all(color: KkColors.bd),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: KkColors.teal),
            const SizedBox(width: KkSpacing.sm),
            Expanded(child: Text(label, style: KkType.bodySm)),
            Text(value, style: KkType.mono.copyWith(color: KkColors.t2)),
          ],
        ),
      ),
    );
  }

  Widget _guestBenefits() {
    const items = [
      (Icons.auto_awesome_outlined, '发布作品与动态'),
      (Icons.tune_outlined, '关注话题与创作者'),
      (Icons.insights_outlined, '查看互动与贡献'),
    ];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      padding: const EdgeInsets.all(KkSpacing.lg),
      decoration: BoxDecoration(
        color: KkColors.bgCard,
        borderRadius: BorderRadius.circular(KkRadius.lg),
        border: Border.all(color: KkColors.bd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('登录后可使用', style: KkType.h3),
          const SizedBox(height: KkSpacing.md),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              const Divider(height: KkSpacing.lg, color: KkColors.divider),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: KkColors.mint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(items[i].$1, size: 18, color: KkColors.teal),
                ),
                const SizedBox(width: KkSpacing.md),
                Text(items[i].$2, style: KkType.body),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 换背景图:image_picker 选一张 → 存 app_state(会话内有效)。
  /// web 端 file.path 是 blob URL,Image.network 可直接显示;移动端是文件路径。
  Future<void> _pickBanner(WidgetRef ref) async {
    try {
      final file = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (file != null) {
        ref.read(appStateProvider.notifier).setBannerImage(file.path);
      }
    } catch (_) {
      // 用户取消 / 权限拒绝,静默
    }
  }

  // 任务 3:清空最近看过的项目二次确认(与 settings _confirmClearSearches 写法一致)。
  // 零旁白:只列动作「清空最近看过的项目?」+ 清空/取消,不写后果。确定 teal(非 take,
  // 清空是中性操作,coral 只给 take/删除)。
  Future<void> _confirmClearBrowse(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('清空最近看过的项目？'),
        contentTextStyle: KkType.body.copyWith(color: KkColors.t1),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.md,
          vertical: KkSpacing.sm,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                Text('取消', style: KkType.bodySm.copyWith(color: KkColors.t3)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child:
                Text('清空', style: KkType.bodySm.copyWith(color: KkColors.teal)),
          ),
        ],
      ),
    );
    if (ok == true) {
      ref.read(appStateProvider.notifier).clearBrowseHistory();
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('已清空'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // 5. 我的贡献 卡片(白卡 + bare 热力图嵌入,整卡 → activity)
  // ──────────────────────────────────────────────────────────────────
  Widget _contributionCard(BuildContext context, WidgetRef ref) {
    final cells = ref.watch(myActivityProvider).asData?.value.cells ??
        const <HeatmapCell>[];
    // 总贡献数 = cells 里所有 level 之和(非 ×N 编造,任务⑯口径)
    final totalContributions = cells.fold<int>(0, (s, c) => s + c.level);
    return Tappable(
      onTap: () => context.push(KkRoutes.activity),
      borderRadius: BorderRadius.circular(KkRadius.lg),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
        padding: const EdgeInsets.all(KkSpacing.lg),
        decoration: BoxDecoration(
          color: KkColors.bgCard,
          borderRadius: BorderRadius.circular(KkRadius.lg),
          boxShadow: KkElevation.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('我的贡献', style: KkType.h3),
                const Spacer(),
                Text(
                  '近 26 周 · 共 $totalContributions 次贡献',
                  style: KkType.mono.copyWith(color: KkColors.t3, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: KkSpacing.md),
            // 任务⑯:升级后 heatmap(showStats:true 显 3 统计盒),
            // bare 模式嵌入本卡(避免双层 bgCard/边框)
            ContributionHeatmap(
              cells: cells,
              showStats: true,
              showLegend: true,
              bare: true,
            ),
          ],
        ),
      ),
    );
  }

  // ── [ZCode] 我发布的：作品 + 动态两排，各自横向小卡滑 ──
  // ── [Claude 原始] _myPostsSection 只有项目一排 ──
  Widget _myContentSection(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final bool remote =
        auth.isLoggedIn && AppConfig.useRemote && auth.currentUser != null;
    final String selfId = remote ? auth.currentUser!.id : 'me';
    final myProjectsAsync = ref.watch(myProjectsProvider);
    final myPostsAsync = ref.watch(userPostsProvider(selfId));

    // 作品（项目）
    final List<Project> myProjects = remote
        ? (myProjectsAsync.value ?? const <Project>[])
        : ref.watch(projectRepositoryProvider).byAuthor('me');
    // 动态
    final List<Post> myPosts = remote
        ? (myPostsAsync.value ?? const <Post>[])
        : ref.watch(postRepositoryProvider).byAuthor('me');
    final projectsLoading = remote && myProjectsAsync.isLoading;
    final postsLoading = remote && myPostsAsync.isLoading;
    final projectsError = remote ? myProjectsAsync.error : null;
    final postsError = remote ? myPostsAsync.error : null;
    if ((projectsLoading || postsLoading) &&
        myProjects.isEmpty &&
        myPosts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: KkSpacing.lg),
        child: CompactListSkeleton(itemCount: 4),
      );
    }
    final firstError = projectsError ?? postsError;
    if (firstError != null && myProjects.isEmpty && myPosts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
        child: RemoteError(
          message: '我的发布加载失败',
          error: firstError,
          onRetry: () async {
            ref.invalidate(myProjectsProvider);
            ref.invalidate(userPostsProvider(selfId));
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(KkSpacing.lg),
        decoration: BoxDecoration(
          color: KkColors.bgCard,
          borderRadius: BorderRadius.circular(KkRadius.lg),
          border: Border.all(color: KkColors.bd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('我的发布', style: KkType.h3),
            const SizedBox(height: KkSpacing.lg),
            _sectionRow(
              icon: Icons.work_outline,
              title: '作品',
              count: myProjects.length,
              onViewAll: myProjects.isNotEmpty
                  ? () =>
                      context.push('${KkRoutes.profile(selfId)}?tab=projects')
                  : null,
              child: myProjects.isEmpty
                  ? _compactContentEmpty(
                      icon: Icons.work_outline,
                      label: '还没有作品',
                      action: '去发布',
                      onTap: () => context.push(KkRoutes.publish),
                    )
                  : _horizontalCardList(
                      items: myProjects,
                      card: (p) => _recentProjectCard(context, p),
                    ),
            ),
            const SizedBox(height: KkSpacing.xl),
            _sectionRow(
              icon: Icons.chat_outlined,
              title: '动态',
              count: myPosts.length,
              onViewAll: myPosts.length > 3
                  ? () => context.push(KkRoutes.profile(selfId))
                  : null,
              child: myPosts.isEmpty
                  ? _compactContentEmpty(
                      icon: Icons.chat_outlined,
                      label: '还没有动态',
                      action: '发动态',
                      onTap: () => context.push(KkRoutes.compose),
                    )
                  : Column(
                      children: [
                        for (final p in myPosts.take(3))
                          _recentPostRow(context, p),
                        if (myPosts.length > 3)
                          Tappable(
                            onTap: () => context.push(KkRoutes.profile(selfId)),
                            borderRadius: BorderRadius.circular(KkRadius.sm),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: KkSpacing.sm),
                              child: Text(
                                '查看全部 ${myPosts.length} 条动态',
                                style: KkType.bodySm
                                    .copyWith(color: KkColors.teal),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // 编辑资料 / 登录：头部下方的整齐一条按钮（原来挤在名字旁边，与头像/名字不在一条线）。
  Widget _editProfileButton(BuildContext context, bool isLoggedIn) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          KkSpacing.lg, KkSpacing.md, KkSpacing.lg, 0),
      child: Tappable(
        onTap: () =>
            context.push(isLoggedIn ? KkRoutes.profileEdit : KkRoutes.login),
        borderRadius: BorderRadius.circular(KkRadius.md),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: KkColors.bgCard,
            borderRadius: BorderRadius.circular(KkRadius.md),
            border: Border.all(color: KkColors.bd),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isLoggedIn ? Icons.edit_outlined : Icons.login,
                  size: 15, color: KkColors.t1),
              const SizedBox(width: 6),
              Text(
                isLoggedIn ? '编辑资料' : '登录 / 注册',
                style: KkType.bodySm
                    .copyWith(color: KkColors.t1, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 我的动态：紧凑一行（正文 2 行 + 时间/赞/评论 + 可选缩略图），点进详情。
  // 取代原来堆叠整张 PostCard（又高又丑、几条就要一直下拉）。
  Widget _recentPostRow(BuildContext context, Post p) {
    final imgs = p.media.where((m) => m.type == 'image').toList();
    final thumb = imgs.isNotEmpty ? imgs.first.url : null;
    return Tappable(
      onTap: () => context.push(KkRoutes.postDetail(p.id)),
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Container(
        margin: const EdgeInsets.only(bottom: KkSpacing.sm),
        padding: const EdgeInsets.all(KkSpacing.md),
        decoration: BoxDecoration(
          color: KkColors.bgSubtle,
          borderRadius: BorderRadius.circular(KkRadius.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        KkType.bodySm.copyWith(color: KkColors.t1, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(timeAgo(p.createdAtMs),
                          style: KkType.bodySm
                              .copyWith(color: KkColors.t3, fontSize: 11)),
                      const SizedBox(width: KkSpacing.md),
                      const Icon(Icons.favorite_border,
                          size: 12, color: KkColors.t3),
                      const SizedBox(width: 3),
                      Text(formatCount(p.likes),
                          style: KkType.mono
                              .copyWith(fontSize: 11, color: KkColors.t3)),
                      const SizedBox(width: KkSpacing.md),
                      const Icon(Icons.chat_bubble_outline,
                          size: 12, color: KkColors.t3),
                      const SizedBox(width: 3),
                      Text(formatCount(p.commentCount),
                          style: KkType.mono
                              .copyWith(fontSize: 11, color: KkColors.t3)),
                    ],
                  ),
                ],
              ),
            ),
            if (thumb != null) ...[
              const SizedBox(width: KkSpacing.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(KkRadius.sm),
                child: KkImage(
                  url: thumb,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  placeholder: (_) => const CoverArt(pattern: 'grid'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _compactContentEmpty({
    required IconData icon,
    required String label,
    required String action,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(KkSpacing.md),
      decoration: BoxDecoration(
        color: KkColors.bgCard,
        borderRadius: BorderRadius.circular(KkRadius.lg),
        border: Border.all(color: KkColors.bd),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: KkColors.mint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: KkColors.teal),
          ),
          const SizedBox(width: KkSpacing.md),
          Expanded(
            child: Text(label, style: KkType.body.copyWith(color: KkColors.t3)),
          ),
          TextButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    );
  }

  Widget _sectionRow({
    IconData? icon,
    required String title,
    required int count,
    required Widget child,
    VoidCallback? onViewAll,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: KkColors.t2),
              const SizedBox(width: KkSpacing.sm),
            ],
            Text(title, style: KkType.h3),
            const Spacer(),
            if (onViewAll != null)
              Tappable(
                onTap: onViewAll,
                borderRadius: BorderRadius.circular(KkRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: KkSpacing.sm, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('查看全部',
                          style: KkType.bodySm.copyWith(color: KkColors.t3)),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right,
                          size: 16, color: KkColors.t3),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: KkSpacing.md),
        child,
      ],
    );
  }

  Widget _horizontalCardList<T>({
    required List<T> items,
    required Widget Function(T) card,
  }) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: KkSpacing.lg),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: KkSpacing.md),
        itemBuilder: (ctx, i) => card(items[i]),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // 6. 我关注的领域(chip 排 + "+调整")
  // ──────────────────────────────────────────────────────────────────
  // ──────────────────────────────────────────────────────────────────
  // 我关注的话题(chip 排 / 空态)
  // ──────────────────────────────────────────────────────────────────
  Widget _followedTopicsSection(BuildContext context, WidgetRef ref) {
    // 未登录 → 空(不显示 mock 演示话题)。
    final topicsAsync = ref.watch(followedTopicsProvider);
    final topics = topicsAsync.asData?.value ?? const <Topic>[];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('我关注的话题', style: KkType.h3),
          const SizedBox(height: KkSpacing.md),
          if (topicsAsync.isLoading)
            const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (topics.isEmpty)
            Text(
              '# 还没有关注的话题',
              style: KkType.bodySm.copyWith(color: KkColors.t3),
            )
          else
            // 任务⑩B:话题 chip 与领域 chip 同款(KkChip.solid,可点跳话题页)。
            Wrap(
              spacing: KkSpacing.sm,
              runSpacing: KkSpacing.sm,
              alignment: WrapAlignment.start,
              children: [
                for (final t in topics)
                  KkChip.solid(
                    label: '#${t.tag}',
                    onTap: () => context.push(KkRoutes.topic(t.tag)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // 8. 最近看过的项目 + 清空(横向小卡)
  // ──────────────────────────────────────────────────────────────────
  Widget _recentlyViewedSection(
      BuildContext context, WidgetRef ref, List<Project> recent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('最近看过的项目', style: KkType.h3),
              const Spacer(),
              if (recent.isNotEmpty)
                Tappable(
                  // 任务 3:清空浏览历史加二次确认(与删帖/登出/清搜索一致)。
                  onTap: () => _confirmClearBrowse(context, ref),
                  borderRadius: BorderRadius.circular(KkRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KkSpacing.sm,
                      vertical: 4,
                    ),
                    child: Text(
                      '清空',
                      style: KkType.bodySm.copyWith(color: KkColors.t3),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: KkSpacing.md),
          if (recent.isEmpty)
            Text(
              '还没有看过',
              style: KkType.bodySm.copyWith(color: KkColors.t3),
            )
          else
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: KkSpacing.lg),
                itemCount: recent.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: KkSpacing.md),
                itemBuilder: (ctx, i) => _recentProjectCard(ctx, recent[i]),
              ),
            ),
        ],
      ),
    );
  }

  /// 最近看过的项目小卡(130 宽,封面 84 + 标题/赞数)。
  Widget _recentProjectCard(BuildContext context, Project project) {
    return Tappable(
      onTap: () => context.push(KkRoutes.detail(project.id)),
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Container(
        width: 130,
        decoration: BoxDecoration(
          color: KkColors.bgCard,
          borderRadius: BorderRadius.circular(KkRadius.md),
          border: Border.all(color: KkColors.bd),
          boxShadow: KkElevation.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 84,
              width: double.infinity,
              child: _RecentCover(project: project),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KkSpacing.sm,
                vertical: KkSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    project.title,
                    style: KkType.bodySm.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatCount(project.likes)} 赞',
                    style:
                        KkType.mono.copyWith(fontSize: 10, color: KkColors.t3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 任务⑩B:chip helpers 已抽到共享 KkChip(solid/ghost/plain)。
}

/// 最近看过的项目小卡封面(真图优先,断网/坏链回退 CoverArt)。
/// 与 project_card._Cover 同套路:Image.network + loadingBuilder + errorBuilder。
class _RecentCover extends StatelessWidget {
  final Project project;
  const _RecentCover({required this.project});

  @override
  Widget build(BuildContext context) {
    final media = project.resultData.media;
    String? coverUrl;
    if (media.isNotEmpty) {
      final first = media.first;
      if (first.type == 'image') {
        coverUrl = first.url;
      } else if (first.type == 'video' && first.poster != null) {
        coverUrl = first.poster;
      }
    }
    if (coverUrl == null) {
      return const CoverArt(pattern: 'waves', height: 84);
    }
    return Image.network(
      coverUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: 84,
      loadingBuilder: (ctx, child, progress) => progress == null
          ? child
          : const CoverArt(pattern: 'waves', height: 84),
      errorBuilder: (_, __, ___) =>
          const CoverArt(pattern: 'waves', height: 84),
    );
  }
}

// ── [ZCode] 领域编辑轻量 Sheet：只调领域，不动其它资料 ──
class _DomainEditSheet extends StatefulWidget {
  final List<String> current;
  final Future<bool> Function(List<String> selected) onSaved;
  const _DomainEditSheet({required this.current, required this.onSaved});

  @override
  State<_DomainEditSheet> createState() => _DomainEditSheetState();
}

class _DomainEditSheetState extends State<_DomainEditSheet> {
  late Set<String> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.current};
  }

  void _toggle(String v) {
    setState(() {
      if (_selected.contains(v))
        _selected.remove(v);
      else
        _selected.add(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(KkSpacing.xl, KkSpacing.lg, KkSpacing.xl,
          MediaQuery.of(context).viewInsets.bottom + KkSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
              child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: KkSpacing.lg),
                  decoration: BoxDecoration(
                      color: KkColors.t4,
                      borderRadius: BorderRadius.circular(KkRadius.pill)))),
          Text('调整关注领域', style: KkType.h3),
          const SizedBox(height: KkSpacing.lg),
          for (final group in kDomainGroupOptions) ...[
            Text(group.title,
                style: KkType.bodySm.copyWith(color: KkColors.t3)),
            const SizedBox(height: KkSpacing.sm),
            Wrap(spacing: KkSpacing.sm, runSpacing: KkSpacing.sm, children: [
              for (final value in group.values)
                GestureDetector(
                  onTap: () => _toggle(value),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: KkSpacing.md, vertical: KkSpacing.sm),
                    decoration: BoxDecoration(
                      color: _selected.contains(value)
                          ? KkColors.teal
                          : KkColors.bgSubtle,
                      borderRadius: BorderRadius.circular(KkRadius.pill),
                      border: Border.all(
                          color: _selected.contains(value)
                              ? KkColors.teal
                              : KkColors.bd),
                    ),
                    child: Text(domainLabel(value),
                        style: KkType.bodySm.copyWith(
                          color: _selected.contains(value)
                              ? Colors.white
                              : KkColors.t2,
                          fontWeight: _selected.contains(value)
                              ? FontWeight.w600
                              : FontWeight.normal,
                        )),
                  ),
                ),
            ]),
            const SizedBox(height: KkSpacing.lg),
          ],
          const SizedBox(height: KkSpacing.xl),
          Tappable(
            onTap: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    final saved = await widget.onSaved(_selected.toList());
                    if (!mounted) return;
                    if (saved) {
                      Navigator.pop(context);
                    } else {
                      setState(() => _saving = false);
                    }
                  },
            disabled: _saving,
            borderRadius: BorderRadius.circular(KkRadius.pill),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: KkSpacing.md),
              decoration: BoxDecoration(
                  color: KkColors.teal,
                  borderRadius: BorderRadius.circular(KkRadius.pill)),
              alignment: Alignment.center,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('保存',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'NotoSerifSC')),
            ),
          ),
          const SizedBox(height: KkSpacing.md),
        ],
      ),
    );
  }
}
