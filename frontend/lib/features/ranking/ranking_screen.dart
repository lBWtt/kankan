import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/parse_count.dart';
import '../../core/utils/time_ago.dart';
import '../../core/config/app_config.dart';
import '../../core/widgets/skeletons.dart';
import '../../core/widgets/kk_back_button.dart';
import '../../core/widgets/tappable.dart';
import '../../data/api/rankings_api.dart';
import '../../data/seed/mock_seed.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/post_repository.dart';
import '../../domain/repositories/project_repository.dart';
import '../../providers/project_provider.dart';
import '../../router/routes.dart';
import '../shared/avatar.dart';
import '../shared/empty_state.dart';
import '../shared/post_card.dart';
import '../shared/project_card.dart';
import '../shared/remote_error.dart';

/// 榜单屏 — Phase 3 Tier 3。
///
/// 三 Tab(与 kankan 屏风格一致):
///   - 项目榜  projectRepository.sorted('hot') 按 likes 降序(真实计数)
///   - 动态榜  postRepository.all() 按 likes 降序
///   - 作者榜  mockAuthorRanking 启动时聚合(总获赞 = 项目 likes + 动态 likes)
///
/// 领奖台(作者榜 Top3):2nd 左 / 1st 中(最高,teal 强调 + amber 皇冠)/ 3rd 右。
/// 入场动画 stagger:中间先出,左右依次,用 flutter_animate。
///
/// 名次升降(rankChange):
///   - +N 上升  teal + arrow_upward
///   - -N 下降  coral(警示用法,HANDOFF §5 仅此一处)+ arrow_downward
///   - 0  持平  t3 + remove
///
/// 计数铁律(HANDOFF §6.10):所有数字取真实值,禁止编造放大公式。
/// 零旁白(HANDOFF §3):无"快来发第一个"引导。
/// 珊瑚橙铁律:本屏仅 rankChange 下降箭头用 coral(警示),其余禁用 coral。
class RankingScreen extends ConsumerStatefulWidget {
  const RankingScreen({super.key});

  @override
  ConsumerState<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends ConsumerState<RankingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  // Phase 5-c:300ms 假 loading,骨架屏占位(与 discover/kankan/library/follows/activity 一致)
  bool _loading = true;

  // 任务⑥:榜单「X 分钟前更新」时间戳——模块级捕获首次进屏时间。
  // 点击顶部 refresh 按钮 → setState 刷成 now → 文案回「刚刚更新」(零旁白不加 toast)。
  // 说明条随当前 Tab 变「排名依据」副标题(如实描述现有排序口径)。
  late int _lastUpdateMs;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _lastUpdateMs = DateTime.now().millisecondsSinceEpoch;
    // Tab 切换 → setState 重建说明条(排名依据副标题随 Tab 变)
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) setState(() {});
    });
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
    return Scaffold(
      backgroundColor: KkColors.bg,
      appBar: AppBar(
        backgroundColor: KkColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const KkBackButton(),
        titleSpacing: 0,
        // HANDOFF §5 标题用 KkType.h1(NotoSerifSC 衬线)
        title: const Text('榜单', style: KkType.h1),
        actions: [
          // 刷新按钮(任务⑥:接通——点击刷 _lastUpdateMs = now → 文案回「刚刚更新」)
          // 零旁白不加 toast,只靠说明条时间戳反馈。
          Tappable(
            onTap: () {
              setState(() {
                _lastUpdateMs = DateTime.now().millisecondsSinceEpoch;
              });
            },
            child: const Icon(Icons.refresh, size: 22, color: KkColors.t1),
          ),
          const SizedBox(width: KkSpacing.sm),
        ],
      ),
      body: Column(
        children: [
          // loading 时锁 TabBar,避免误触切换(触控热区不变,仅 ignoring)
          IgnorePointer(
            ignoring: _loading,
            child: _tabBar(),
          ),
          // 任务⑥:说明条——左「排名依据」副标题(t3,如实描述现有排序口径)
          // + 右「X 分钟前更新」(timeAgo(_lastUpdateMs),t3 mono 11)。
          // 随当前 Tab 变副标题;随 _lastUpdateMs 变时间戳(refresh 后回「刚刚更新」)。
          if (!_loading) _basisAndFreshnessBar(),
          Expanded(
            child: _loading
                ? _skeletonContent()
                : TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _ProjectRankingList(),
                      _PostRankingList(),
                      _AuthorRanking(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Phase 5-c:加载态骨架 — 领奖台 + 名次行(3 Tab 通用)
  //   ① 领奖台:3 个不同高度 SkeletonBox(2nd 80 / 1st 110 / 3rd 60)
  //   ② 名次行:4 行(rank 16 + avatar 40 + name 14 + stats 11 + chip 36×20)
  // padding 与真实 _ProjectRankingList/_PostRankingList 一致(fromLTRB lg/md/lg/xxl)
  // HANDOFF §5:不用 coral;只用 KkColors.*(bgCard/bgSubtle)+ 骨架 shimmer
  // ──────────────────────────────────────────────────────────────────
  Widget _skeletonContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        KkSpacing.lg, KkSpacing.md, KkSpacing.lg, KkSpacing.xxl,
      ),
      children: [
        // 领奖台骨架:2nd / 1st / 3rd 视觉顺序,高度递减
        Padding(
          padding: const EdgeInsets.symmetric(vertical: KkSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _skeletonPodiumSlot(80)),
              const SizedBox(width: KkSpacing.xs),
              Expanded(child: _skeletonPodiumSlot(110)),
              const SizedBox(width: KkSpacing.xs),
              Expanded(child: _skeletonPodiumSlot(60)),
            ],
          ),
        ),
        const SizedBox(height: KkSpacing.md),
        // 名次行骨架(4 行,镜像 _AuthorRankRow 布局)
        for (var i = 0; i < 4; i++) ...[
          _skeletonRankRow(),
          const SizedBox(height: KkSpacing.md),
        ],
      ],
    );
  }

  // 领奖台骨架项:皇冠区 + 头像 56 圆 + 名字 + 获赞 + 基座(高度变化)
  Widget _skeletonPodiumSlot(double pedestalHeight) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SkeletonBox(
          width: 56,
          height: 56,
          borderRadius: BorderRadius.all(Radius.circular(28)),
        ),
        const SizedBox(height: KkSpacing.xs),
        const SkeletonLine(width: 60, height: 12),
        const SizedBox(height: 2),
        const SkeletonLine(width: 40, height: 10),
        const SizedBox(height: KkSpacing.xs),
        SkeletonBox(
          width: double.infinity,
          height: pedestalHeight,
          borderRadius: const BorderRadius.all(Radius.circular(KkRadius.sm)),
        ),
      ],
    );
  }

  // 名次行骨架(rank + avatar + name/stats + chip)
  Widget _skeletonRankRow() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.md,
        vertical: KkSpacing.md,
      ),
      decoration: BoxDecoration(
        color: KkColors.bgCard,
        borderRadius: BorderRadius.circular(KkRadius.md),
        border: Border.all(color: KkColors.bd),
      ),
      child: Row(
        children: [
          // rank 数字
          const SkeletonLine(width: 16, height: 24),
          const SizedBox(width: KkSpacing.md),
          // 头像 40
          const SkeletonBox(
            width: 40,
            height: 40,
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          const SizedBox(width: KkSpacing.md),
          // 名字 14 + 统计 11
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                SkeletonLine(height: 14),
                SizedBox(height: 4),
                SkeletonLine(height: 11),
              ],
            ),
          ),
          const SizedBox(width: KkSpacing.sm),
          // rankChange chip
          const SkeletonBox(
            width: 36,
            height: 20,
            borderRadius: BorderRadius.all(Radius.circular(KkRadius.pill)),
          ),
        ],
      ),
    );
  }

  // TabBar 风格复刻 kankan_screen._tabBar():KkType.body + teal indicator
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
          Tab(text: '项目'),
          Tab(text: '动态'),
          Tab(text: '作者'),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // 任务⑥:说明条——左「排名依据」副标题 + 右「X 分钟前更新」时间戳
  // ──────────────────────────────────────────────────────────────────
  // 在 TabBar 下、列表上。横向 KkSpacing.lg 内边距,与 TabBar / 列表对齐。
  // 副标题如实描述现有排序口径(项目/动态按 likes 降序、作者按累计获赞),
  // 不写代码没做的口径(如「按收藏」)。
  // 时间戳用 timeAgo(_lastUpdateMs):refresh 后回「刚刚更新」,随后「3 分钟前」等。
  // 铁律:coral 只给 rankChange 下降箭头——副标题/时间戳用 t3,不用 coral。零旁白。
  Widget _basisAndFreshnessBar() {
    // 三 Tab 排名依据(如实,与代码排序口径一致)
    const basis = [
      '大家最认可的 · 按点赞热度', // 0 项目:projectRepository.sorted('hot') 按 likes 降序
      '聊得最热的 · 按点赞热度', // 1 动态:postRepository.all()..sort likes 降序
      '最受认可的创作者 · 按累计获赞', // 2 作者:mockAuthorRanking 按总获赞聚合
    ];
    final idx = _tabCtrl.index.clamp(0, 2);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.sm,
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              basis[idx],
              style: KkType.bodySm.copyWith(
                fontSize: 12,
                color: KkColors.t3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: KkSpacing.sm),
          Text(
            '${timeAgo(_lastUpdateMs)}更新',
            style: KkType.mono.copyWith(
              fontSize: 11,
              color: KkColors.t3,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 项目榜 — 按 likes 降序,每项:排名 + ProjectCard + rankChange
// ──────────────────────────────────────────────────────────────────
class _ProjectRankingList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 真数据模式:项目榜读 GET /rankings?type=weekly_hot(埋点→hot_score→真热度)。
    // 动态榜/作者榜后端暂无(Post/关注是阶段3),仍走 mock。
    if (AppConfig.useRemote) {
      final async = ref.watch(remoteWeeklyHotProvider);
      return async.when(
        loading: () => const _RankingLoading(),
        error: (e, _) => RemoteError(
          message: '榜单加载失败',
          onRetry: () async {
            ref.invalidate(remoteWeeklyHotProvider);
          },
        ),
        data: (list) => _list(context, list, remote: true),
      );
    }
    final list = ref.watch(projectRepositoryProvider).sorted('hot');
    return _list(context, list, remote: false);
  }

  Widget _list(BuildContext context, List<Project> list, {required bool remote}) {
    if (list.isEmpty) {
      return ListView(
        children: const [EmptyState(variant: EmptyStateVariant.generic)],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        KkSpacing.lg, KkSpacing.md, KkSpacing.lg, KkSpacing.xxl,
      ),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: KkSpacing.md),
      itemBuilder: (context, i) {
        final project = list[i];
        return _RankRow(
          rank: i + 1,
          // 名次升降是 mock 演示数据;真数据没有历史名次,置 0(不显升降)。
          rankChange: remote ? 0 : mockProjectRankChange(project.id),
          // 信息密度:榜单用 compact 细行(56 缩略图 + 标题 + 计数),不用 180 大封面全卡,
          // 一屏能看更多名次。
          child: ProjectCard(project: project, compact: true),
        );
      },
    );
  }
}

// 真榜加载/错误态(项目榜远程模式用)。
class _RankingLoading extends StatelessWidget {
  const _RankingLoading();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(KkSpacing.xxl),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(KkColors.teal),
          ),
        ),
      );
}

// ──────────────────────────────────────────────────────────────────
// 动态榜 — 按 likes 降序,每项:排名 + PostCard + rankChange
// ──────────────────────────────────────────────────────────────────
class _PostRankingList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // all() 返回 unmodifiable,需 toList() 复制再排序
    final posts = ref.watch(postRepositoryProvider).all().toList()
      ..sort((a, b) => b.likes.compareTo(a.likes));
    if (posts.isEmpty) {
      return ListView(
        children: const [EmptyState(variant: EmptyStateVariant.generic)],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        KkSpacing.lg, KkSpacing.md, KkSpacing.lg, KkSpacing.xxl,
      ),
      itemCount: posts.length,
      separatorBuilder: (_, __) => const SizedBox(height: KkSpacing.sm),
      itemBuilder: (context, i) {
        final post = posts[i];
        return _RankRow(
          rank: i + 1,
          rankChange: mockPostRankChange(post.id),
          child: PostCard(
            post: post,
            onTap: () => context.push(KkRoutes.postDetail(post.id)),
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 作者榜 — Top3 领奖台 + rank 4+ 列表
// ──────────────────────────────────────────────────────────────────
class _AuthorRanking extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = mockAuthorRanking;
    if (list.isEmpty) {
      return ListView(
        children: const [EmptyState(variant: EmptyStateVariant.generic)],
      );
    }
    final top3 = list.take(3).toList();
    final rest = list.skip(3).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: KkSpacing.xxl),
      children: [
        if (top3.isNotEmpty) _Podium(entries: top3),
        const SizedBox(height: KkSpacing.md),
        for (final entry in rest)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KkSpacing.lg,
              vertical: KkSpacing.xs,
            ),
            child: _AuthorRankRow(entry: entry),
          ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 通用排名行:左 rank 数字 | 中内容(ProjectCard / PostCard)| 右 rankChange chip
// ──────────────────────────────────────────────────────────────────
class _RankRow extends StatelessWidget {
  final int rank;
  final int rankChange;
  final Widget child;

  const _RankRow({
    required this.rank,
    required this.rankChange,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左:大号排名数字(KkType.monoLg,t3)
        SizedBox(
          width: 32,
          child: Padding(
            padding: const EdgeInsets.only(top: KkSpacing.sm),
            child: Text(
              '$rank',
              style: KkType.monoLg.copyWith(color: KkColors.t3),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(width: KkSpacing.sm),
        // 中:内容卡片(自带 Tappable)
        Expanded(child: child),
        const SizedBox(width: KkSpacing.sm),
        // 右:rankChange chip
        Padding(
          padding: const EdgeInsets.only(top: KkSpacing.md),
          child: _RankChangeChip(change: rankChange),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 作者排名行(rank 4+):rank | avatar | name + stats | chip
// 整行 Tappable → push profile(HANDOFF §6.5 真路由,可深链)
// ──────────────────────────────────────────────────────────────────
class _AuthorRankRow extends ConsumerWidget {
  final AuthorRankingEntry entry;

  const _AuthorRankRow({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userByIdProvider(entry.userId));
    return Tappable(
      onTap: () => context.push(KkRoutes.profile(entry.userId)),
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.md,
          vertical: KkSpacing.md,
        ),
        decoration: BoxDecoration(
          color: KkColors.bgCard,
          borderRadius: BorderRadius.circular(KkRadius.md),
          border: Border.all(color: KkColors.bd),
        ),
        child: Row(
          children: [
            // 左:rank 数字
            SizedBox(
              width: 32,
              child: Text(
                '${entry.rank}',
                style: KkType.monoLg.copyWith(color: KkColors.t3),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: KkSpacing.md),
            // 头像
            KkAvatar(userId: entry.userId, user: user, size: 40),
            const SizedBox(width: KkSpacing.md),
            // 名字 + 真实统计
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user?.name ?? entry.userId,
                    style: KkType.body.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // 真实计数(HANDOFF §6.10):formatCount 不放大
                    '${formatCount(entry.totalLikes)} 获赞 · '
                    '${entry.projectCount} 项目 · '
                    '${entry.postCount} 动态',
                    style: KkType.mono.copyWith(
                      fontSize: 11,
                      color: KkColors.t3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: KkSpacing.sm),
            _RankChangeChip(change: entry.rankChange),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 名次升降 chip — HANDOFF §5:
//   +N  teal + arrow_upward
//   -N  coral(警示用法,本屏唯一 coral 出口)+ arrow_downward
//   0   t3 + remove
//   999 新锐(任务⑥ Part B 哨兵 [kRankNewEntrySentinel])→ mint + teal + auto_awesome,
//        不用 coral(铁律:coral 只给 rankChange 下降箭头)
// 数字用 KkType.mono size 11
// ──────────────────────────────────────────────────────────────────
class _RankChangeChip extends StatelessWidget {
  final int change;

  const _RankChangeChip({required this.change});

  @override
  Widget build(BuildContext context) {
    // 任务⑥ Part B:新上榜哨兵 → 「新锐」pill(mint + teal,不用 coral)。
    // 早 return,避免 999 被下方 isUp(change>0) 误判成 "+999"。
    if (change == kRankNewEntrySentinel) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: KkColors.mint,
          borderRadius: BorderRadius.circular(KkRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 12, color: KkColors.teal),
            const SizedBox(width: 2),
            Text(
              '新锐',
              style: KkType.mono.copyWith(
                fontSize: 11,
                color: KkColors.teal,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final isUp = change > 0;
    final isDown = change < 0;

    final Color fg;
    final Color bg;
    final IconData icon;
    final String text;

    if (isUp) {
      fg = KkColors.teal;
      bg = KkColors.mint;
      icon = Icons.arrow_upward;
      text = '+$change';
    } else if (isDown) {
      fg = KkColors.coral;
      bg = KkColors.coralMint;
      icon = Icons.arrow_downward;
      text = '$change'; // change 已含负号,如 "-3"
    } else {
      fg = KkColors.t3;
      bg = KkColors.bgSubtle;
      icon = Icons.remove;
      text = '0';
    }

    return Container(
      // 微 padding:chip 内部紧凑排版(icon 12 + text 11),用字面量避免 const 算术
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(KkRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 2),
          Text(
            text,
            style: KkType.mono.copyWith(
              fontSize: 11,
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 领奖台 — Top3 视觉顺序:左 2nd / 中 1st(最高,teal 强调)/ 右 3rd
// 入场动画 stagger:中间先出 → 左 → 右,用 flutter_animate
// ──────────────────────────────────────────────────────────────────
class _Podium extends ConsumerWidget {
  final List<AuthorRankingEntry> entries; // 长度 1..3,已按 rank 升序

  const _Podium({required this.entries});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // entries[0] = rank1, [1] = rank2, [2] = rank3
    final first = entries.length >= 1 ? entries[0] : null;
    final second = entries.length >= 2 ? entries[1] : null;
    final third = entries.length >= 3 ? entries[2] : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KkSpacing.lg, KkSpacing.lg, KkSpacing.lg, KkSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: second != null
                ? _PodiumSlot(entry: second, place: 2, delayMs: 120)
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: first != null
                ? _PodiumSlot(entry: first, place: 1, delayMs: 0)
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: third != null
                ? _PodiumSlot(entry: third, place: 3, delayMs: 240)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 单个领奖台位置
//   - 1st:皇冠(amber #C68A2E)+ 72px 头像(teal 描边)+ 名字 + teal 获赞数
//        + teal 基座(36h,白字数字)
//   - 2nd/3rd:无皇冠 + 60/56px 头像(无描边)+ 名字 + t3 获赞数
//        + bgSubtle 基座(28/22h,t3 数字)
// 整位 Tappable → push profile
// ──────────────────────────────────────────────────────────────────
class _PodiumSlot extends ConsumerWidget {
  final AuthorRankingEntry entry;
  final int place; // 1 / 2 / 3
  final int delayMs;

  const _PodiumSlot({
    required this.entry,
    required this.place,
    required this.delayMs,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userByIdProvider(entry.userId));
    final isFirst = place == 1;
    final avatarSize = isFirst ? 72.0 : (place == 2 ? 60.0 : 56.0);
    final pedHeight = isFirst ? 36.0 : (place == 2 ? 28.0 : 22.0);
    final pedColor = isFirst ? KkColors.teal : KkColors.bgSubtle;
    final pedNumberColor = isFirst ? Colors.white : KkColors.t3;

    final slot = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 皇冠 / 奖杯图标(仅 1st)— 用 metallic amber 字面量,不走 Material 色板
        if (isFirst) ...[
          const Icon(
            Icons.emoji_events,
            size: 28,
            color: Color(0xFFC68A2E),
          ),
          const SizedBox(height: KkSpacing.xs),
        ],
        // 头像(1st 加 teal 圆描边)
        Container(
          decoration: isFirst
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: KkColors.teal, width: 2.5),
                )
              : null,
          padding: isFirst ? const EdgeInsets.all(3) : EdgeInsets.zero,
          child: KkAvatar(
            userId: entry.userId,
            user: user,
            size: avatarSize,
          ),
        ),
        const SizedBox(height: KkSpacing.xs),
        // 名字
        Text(
          user?.name ?? entry.userId,
          style: KkType.bodySm.copyWith(
            fontWeight: FontWeight.w600,
            color: KkColors.t1,
            fontSize: isFirst ? 14 : 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        // 总获赞(1st 用 teal 强调)
        Text(
          '${formatCount(entry.totalLikes)} 获赞',
          style: KkType.mono.copyWith(
            fontSize: 11,
            color: isFirst ? KkColors.teal : KkColors.t3,
          ),
        ),
        const SizedBox(height: KkSpacing.xs),
        // 基座(高度递减,1st 最高)
        Container(
          width: double.infinity,
          height: pedHeight,
          decoration: BoxDecoration(
            color: pedColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(KkRadius.sm),
              topRight: Radius.circular(KkRadius.sm),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '$place',
            style: KkType.monoLg.copyWith(
              color: pedNumberColor,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );

    // 整位可点 → 跳作者 profile
    return Tappable(
      onTap: () => context.push(KkRoutes.profile(entry.userId)),
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: KkSpacing.xs),
        child: slot,
      ),
    )
        .animate()
        .fadeIn(
          duration: 360.ms,
          delay: delayMs.ms,
          curve: Curves.easeOutCubic,
        )
        .slideY(
          begin: 0.18,
          end: 0,
          duration: 360.ms,
          delay: delayMs.ms,
          curve: Curves.easeOutCubic,
        );
  }
}
