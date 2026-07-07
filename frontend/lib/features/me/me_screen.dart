import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/parse_count.dart';
import '../../core/widgets/cover_art.dart';
import '../../core/widgets/tappable.dart';
import '../../data/api/users_api.dart';
import '../../data/seed/mock_seed.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/post_repository.dart';
import '../../domain/repositories/project_repository.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/project_provider.dart';
import '../../router/routes.dart';
import '../shared/kk_chip.dart';
import '../shared/profile_header.dart';
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
///   8. 最近看过(横向小卡 + 清空)
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
    final mockMe = ref.watch(userByIdProvider('me'));
    final auth = ref.watch(authProvider);
    final projectRepo = ref.watch(projectRepositoryProvider);
    final postRepo = ref.watch(postRepositoryProvider);
    final appState = ref.watch(appStateProvider);

    // 身份覆盖:登录后头像/名字/简介用真后端账号;未登录用 mock 'me' 演示画像。
    // 统计与下方内容(贡献/领域/话题/最近看过)仍是 mock 演示数据——真·个人数据待接
    // /me + /me/projects 等端点(同 feed remote 的已知分叉)。故计数一律从 mockMe 派生,
    // 保持演示画像自洽。
    final me = auth.currentUser ?? mockMe;
    final isLoggedIn = auth.isLoggedIn;

    // 真实统计(禁编造;演示口径取 mock 'me')
    final myProjects = projectRepo.byAuthor('me');
    final myPosts = postRepo.byAuthor('me');
    // 计数策略:登录 + useRemote → GET /me 真计数(loading/error 退化 mock 占位,
    // 避免数字闪烁/突变);未登录/mock 走 mock 'me' 派生(HANDOFF §6.10 真实数组长度)。
    final mockFollowing = (mockMe?.followingIds ?? const <String>[]).length;
    final mockFollower = (mockMe?.followerIds ?? const <String>[]).length;
    var followingCount = mockFollowing;
    var followerCount = mockFollower;
    // 获赞/收藏 mock 口径(未登录/mock 用)。
    var totalLikes = myProjects.fold<int>(0, (s, p) => s + p.likes) +
        myPosts.fold<int>(0, (s, p) => s + p.likes);
    var savedCount = appState.savedProjectIds.length;
    if (isLoggedIn && AppConfig.useRemote) {
      // .value:loading 时 null → 显 mock 占位;data 时真值;error 时 null → mock 兜底。
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

    // 最近看过 → 真实 Project 列表(过滤已删/不存在的 ID)
    final recentProjects = appState.browseHistory
        .map((id) => projectRepo.byId(id))
        .whereType<Project>()
        .toList();

    // 关注/粉丝列表入口:登录 → 真 UUID(follows 屏走 remote 真列表,与真计数对齐);
    // 未登录 → 'me'(mock 演示列表)。
    final followsTargetId =
        (isLoggedIn && auth.currentUser != null) ? auth.currentUser!.id : 'me';

    return ListView(
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
          onTapFollowing: () => context.push(KkRoutes.follows(followsTargetId)),
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
          // 未登录 → 「登录/注册」入口(点进 /login 拿真 JWT);登录后 → 「编辑资料」。
          nameTrailing: Tappable(
            onTap: () => context.push(
              isLoggedIn ? KkRoutes.profileEdit : KkRoutes.login,
            ),
            borderRadius: BorderRadius.circular(KkRadius.sm),
            child: Text(
              isLoggedIn ? '编辑资料' : '登录 / 注册',
              style: KkType.bodySm.copyWith(color: KkColors.teal),
            ),
          ),
        ),
        const SizedBox(height: KkSpacing.xl),
        // 5. 我的贡献卡(整卡 → activity)
        _contributionCard(context),
        const SizedBox(height: KkSpacing.xl),
        // 我发布的(横向小卡,空态零旁白)
        _myPostsSection(context, ref),
        const SizedBox(height: KkSpacing.xl),
        // 6. 我关注的领域
        _followedDomainsSection(context),
        const SizedBox(height: KkSpacing.xl),
        // 7. 我关注的话题
        _followedTopicsSection(context),
        const SizedBox(height: KkSpacing.xl),
        // 8. 最近看过 + 清空
        _recentlyViewedSection(context, ref, recentProjects),
      ],
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

  // 任务 3:清空浏览历史二次确认(与 settings _confirmClearSearches 写法一致)。
  // 零旁白:只列动作「清空最近看过?」+ 清空/取消,不写后果。确定 teal(非 take,
  // 清空是中性操作,coral 只给 take/删除)。
  Future<void> _confirmClearBrowse(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('清空最近看过？'),
        contentTextStyle: KkType.body.copyWith(color: KkColors.t1),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.md,
          vertical: KkSpacing.sm,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: KkType.bodySm.copyWith(color: KkColors.t3)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('清空', style: KkType.bodySm.copyWith(color: KkColors.teal)),
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
  Widget _contributionCard(BuildContext context) {
    // 真实总贡献数 = cells 里所有 level 之和(非 ×N 编造,任务⑯口径)
    final totalContributions =
        mockHeatmapCells.fold<int>(0, (s, c) => s + c.level);
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
              cells: mockHeatmapCells,
              showStats: true,
              showLegend: true,
              bare: true,
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // 我发布的(横向小卡,空态零旁白,查看全部 → 个人主页项目 tab)
  // ──────────────────────────────────────────────────────────────────
  // 项目用 projectRepo.byAuthor('me'),复用「最近看过」小卡视觉(_recentProjectCard)。
  // 真实计数,禁编造。空态:「还没有发布」(零旁白,不写"快去发布"引导)。
  Widget _myPostsSection(BuildContext context, WidgetRef ref) {
    final projectRepo = ref.watch(projectRepositoryProvider);
    final myProjects = projectRepo.byAuthor('me');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('我发布的', style: KkType.h3),
              const Spacer(),
              if (myProjects.isNotEmpty)
                Tappable(
                  onTap: () => context.push(KkRoutes.profile('me')),
                  borderRadius: BorderRadius.circular(KkRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KkSpacing.sm,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '查看全部',
                          style: KkType.bodySm.copyWith(color: KkColors.t3),
                        ),
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
          if (myProjects.isEmpty)
            Text(
              '还没有发布',
              style: KkType.bodySm.copyWith(color: KkColors.t3),
            )
          else
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: KkSpacing.lg),
                itemCount: myProjects.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: KkSpacing.md),
                itemBuilder: (ctx, i) => _recentProjectCard(ctx, myProjects[i]),
              ),
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // 6. 我关注的领域(chip 排 + "+调整")
  // ──────────────────────────────────────────────────────────────────
  Widget _followedDomainsSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('我关注的领域', style: KkType.h3),
          const SizedBox(height: KkSpacing.md),
          // 任务⑩B:领域 chip 统一用 KkChip.solid(mint+teal);
          // "+调整"做成末尾幽灵 chip(KkChip.ghost + add 图标),
          // 跟在领域 chip 行末尾自然收尾,不单独占行。
          Wrap(
            spacing: KkSpacing.sm,
            runSpacing: KkSpacing.sm,
            alignment: WrapAlignment.start,
            children: [
              for (final d in mockFollowedDomains)
                KkChip.solid(label: _domainLabel(d)),
              KkChip.ghost(
                label: '调整',
                icon: Icons.add,
                onTap: () => context.push(KkRoutes.profileEdit),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 7 领域值 → 中文标签(与 profile_edit._domainOptions 同源)。
  String _domainLabel(String value) {
    const map = <String, String>{
      'ai_image': 'AI图',
      'ai_video': 'AI视频',
      'web': '网页',
      'app': 'App',
      'tool': '工具',
      'opensource': '开源',
      'prompt': 'Prompt',
    };
    return map[value] ?? value;
  }

  // ──────────────────────────────────────────────────────────────────
  // 7. 我关注的话题(chip 排 / 空态)
  // ──────────────────────────────────────────────────────────────────
  Widget _followedTopicsSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('我关注的话题', style: KkType.h3),
          const SizedBox(height: KkSpacing.md),
          if (mockFollowedTopics.isEmpty)
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
                for (final t in mockFollowedTopics)
                  KkChip.solid(
                    label: '#$t',
                    onTap: () => context.push(KkRoutes.topic(t)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // 8. 最近看过 + 清空(横向小卡)
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
              Text('最近看过', style: KkType.h3),
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

  /// 最近看过的小卡(130 宽,封面 84 + 标题/赞数)。
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
                    style: KkType.bodySm
                        .copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatCount(project.likes)} 赞',
                    style: KkType.mono.copyWith(fontSize: 10, color: KkColors.t3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 任务⑩B:chip helpers 已抽到共享 KkChip(solid/ghost/plain),
  // 领域/话题用 KkChip.solid,"+调整"用 KkChip.ghost。
}

/// 最近看过小卡的封面(真图优先,断网/坏链回退 CoverArt)。
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
      loadingBuilder: (ctx, child, progress) =>
          progress == null ? child : const CoverArt(pattern: 'waves', height: 84),
      errorBuilder: (_, __, ___) =>
          const CoverArt(pattern: 'waves', height: 84),
    );
  }
}
