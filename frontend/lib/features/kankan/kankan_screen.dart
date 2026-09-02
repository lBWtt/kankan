import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/pagination/infinite_scroll.dart';
import '../../core/pagination/page.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/domain_meta.dart';
import '../../core/widgets/cover_art.dart';
import '../../core/widgets/skeletons.dart';
import '../../core/widgets/tappable.dart';
import '../../data/api/projects_api.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/project_repository.dart';
import '../../l10n/kk_strings.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/paginated_projects_provider.dart';
import '../../router/routes.dart';
import '../shared/empty_state.dart';
import '../shared/kk_image.dart';
import '../shared/list_state_views.dart';
import '../shared/project_card.dart';
import '../shared/remote_error.dart';
import 'recommend_masonry.dart';

// ── [ZCode] 跨屏共享的领域筛选状态（me 页点领域 chip → 跳看看页并设置此筛选）──
class DomainFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? v) => state = v;
}

final kankanDomainFilterNotifier =
    NotifierProvider<DomainFilterNotifier, String?>(
        () => DomainFilterNotifier());

/// 「精选」= 本周编辑精选。remote 走后端 section=today_pick，mock 从内存 repo 取本周高赞。
final featuredProjectsProvider =
    FutureProvider.autoDispose<List<Project>>((ref) async {
  // ── [ZCode] 本周时间窗（周一 00:00 → 周日 23:59）──
  final now = DateTime.now();
  final monday = now.subtract(Duration(days: now.weekday - 1));
  final weekStartMs =
      DateTime(monday.year, monday.month, monday.day).millisecondsSinceEpoch;
  // ── [Claude 原始] 以下为原 featuredProjectsProvider 逻辑 ──
  if (AppConfig.useRemote) {
    final api = ref.watch(projectsApiProvider);
    final picked = await api.featured(limit: 12);
    // featured 表示运营本周选中的内容；项目本身可以早于本周创建。
    // 后端暂未返回“入选时间”，不能拿 createdAt 代替它。
    if (picked.isNotEmpty) return picked;
    // 兜底：运营还没设 featured_rank → 用本周高赞顶上
    final all = await api.list(limit: 20);
    final weekly = all.where((p) => p.createdAtMs >= weekStartMs).toList()
      ..sort((a, b) => b.likes.compareTo(a.likes));
    return weekly.take(8).toList();
  }
  // ── [Claude 原始] mock 模式 ──
  final all = ref.watch(projectRepositoryProvider).all().toList()
    ..sort((a, b) => b.likes.compareTo(a.likes));
  // mock 没有“入选时间”，按高赞模拟本周编辑选择，避免因种子日期陈旧而空屏。
  return all.take(8).toList();
});

/// 看看屏 — HANDOFF §6.9 项目 feed。
///
/// 三 Tab 真排序:
///   - 精选  seed 默认顺序(无 shuffle)
///   - 推荐  双栏瀑布(RecommendMasonry),按「想试数/takeaway」降序
///   - 热门  by likes 降序(真实点赞)
///
/// 领域筛选(横向 chip 行):全部 / AI图 / AI视频 / 网页 / App / 工具 / 开源 / Prompt
///
/// 计数铁律(HANDOFF §6.10):排序按真实 likes/createdAtMs,不放大不编造。
/// 零旁白(HANDOFF §3):空状态用 EmptyState,无"快来发第一个"引导。
class KankanScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;

  const KankanScreen({super.key, this.initialTabIndex = 1});

  @override
  ConsumerState<KankanScreen> createState() => _KankanScreenState();
}

class _KankanScreenState extends ConsumerState<KankanScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  // ── [ZCode] _domainFilter 改为跨屏共享 provider，me 页点领域 chip 可联动 ──
  // ── [Claude 原始] String? _domainFilter; // null = 全部 ──

  /// 加载态:Phase 5 接真后端时,把这个 _loading 切到真 await 网络请求即可。
  /// 现在 mock 数据是同步的,300ms 假延迟让骨架屏有展示机会。
  bool _loading = true;

  // 顺序：精选 / 推荐 / 最新；默认落在「推荐」（见 initState initialIndex）。
  static const _sorts = [('精选', 'featured'), ('推荐', 'new'), ('最新', 'new')];

  @override
  void initState() {
    super.initState();
    // 默认落在「推荐」Tab（index 1）——瀑布流是主逛区。
    final hasIncomingDomain = ref.read(kankanDomainFilterNotifier) != null;
    _tabCtrl = TabController(
      length: 3,
      vsync: this,
      initialIndex: hasIncomingDomain ? 2 : widget.initialTabIndex.clamp(0, 2),
    );
    // 切 Tab 时重建：推荐 Tab 不显示领域分类条（用户反馈「推荐里面不要有分类」）。
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) setState(() {});
    });
    if (AppConfig.useRemote) {
      // 远端有真实加载态（paginatedProjectsProvider isLoading），不摆 300ms 假骨架。
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
    // KkRootShell 已提供 NoiseBackground + SafeArea,branch 屏只返回内容。
    return Column(
      children: [
        _topBar(),
        // loading 时锁住 Tab,避免在骨架屏期间切条件。
        IgnorePointer(ignoring: _loading, child: _tabBar()),
        // 领域筛选条已移除（用户决策：领域退到后台，用户只关注「话题 + 人」，不再暴露领域这层）。
        Expanded(
          child: ColoredBox(
            // 任务②:列表区 bg2 底,卡片 bgCard "浮"起来,编辑层次
            color: KkColors.bgSubtle,
            child: _loading
                ? _skeletonContent()
                : TabBarView(
                    controller: _tabCtrl,
                    // 恢复横滑切 Tab（默认 physics）：用户反馈完全禁掉太不方便。
                    // 默认手势竞技场按主导轴判定，纵向浏览一般不会误触横滑。
                    children: [
                      // 精选：App Store「Today / 编辑精选」式——一屏一张大图故事卡。
                      const _FeaturedTab(),
                      // 推荐：小红书式双栏瀑布流。不接受领域筛选（无分类条），恒显全部。
                      const RecommendMasonry(domain: null),
                      // 最新：按发布时间倒序，发布成功后回到这里确认入流。
                      _ProjectList(sort: 'new', domain: null),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ── 加载态骨架屏:3 个 ProjectCardSkeleton,边距与 _ProjectList 一致 ──
  Widget _skeletonContent() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        KkSpacing.lg,
        KkSpacing.sm,
        KkSpacing.lg,
        KkSpacing.xxl,
      ),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(height: KkSpacing.lg),
      itemBuilder: (_, __) => const ProjectCardSkeleton(),
    );
  }

  Widget _topBar() {
    // P2-i18n / 无障碍:榜单 + 搜索图标都是 icon-only 按钮,必须传 semanticLabel,
    // 否则读屏只会念「按钮」无具体含义。标签接 KkStrings(zh: 榜单 / 搜索)。
    final s = ref.watch(kkStringsProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.md,
      ),
      child: Row(
        children: [
          // 任务②:标题后 6×6 teal 品牌点(签名细节)
          Text('看看', style: KkType.h1),
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
            onTap: () => context.push(KkRoutes.ranking),
            semanticLabel: s.ranking,
            child: const Icon(Icons.emoji_events_outlined,
                size: 22, color: KkColors.t1),
          ),
          const SizedBox(width: KkSpacing.md),
          Tappable(
            onTap: () => context.push(KkRoutes.search),
            semanticLabel: s.search,
            child: const Icon(Icons.search, size: 22, color: KkColors.t1),
          ),
        ],
      ),
    );
  }

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
        tabs: [for (final s in _sorts) Tab(text: s.$1)],
      ),
    );
  }
}

// ── 项目列表(按 sort + domain 真排序)──
// P0-1 分页：用 paginatedProjectsProvider（游标分页 + 无限滚动 + 去重）。
// mock 模式下 provider 一次性返回全部（hasMore=false），行为与旧版一致。
// 3 个 tab（精选/热门/最新）共享同一分页 state，各自客户端 filter+sort。
class _ProjectList extends ConsumerStatefulWidget {
  final String sort;
  final String? domain;

  const _ProjectList({required this.sort, required this.domain});

  @override
  ConsumerState<_ProjectList> createState() => _ProjectListState();
}

class _ProjectListState extends ConsumerState<_ProjectList> {
  late final ScrollController _scrollCtrl;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    InfiniteScroll.attach(_scrollCtrl, onLoadMore: () {
      ref.read(paginatedProjectsProvider.notifier).loadMore();
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  String get sort => widget.sort;
  String? get domain => widget.domain;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(paginatedProjectsProvider);
    return RefreshIndicator(
      color: KkColors.teal,
      onRefresh: () async {
        await ref.read(paginatedProjectsProvider.notifier).refresh();
        // mock：同步刷 projectRepository（顶部计数 / 推荐条读它）。
        ref.invalidate(projectRepositoryProvider);
      },
      child: _body(context, state),
    );
  }

  Widget _body(BuildContext context, PaginatedState<Project> state) {
    if (state.isLoading) {
      return _skeleton();
    }
    if (state.error != null && state.items.isEmpty) {
      return RemoteError(
        message: '加载失败',
        error: state.error,
        onRetry: () async =>
            ref.read(paginatedProjectsProvider.notifier).refresh(),
      );
    }
    // 客户端过滤「不感兴趣」+ domain，再按 sort 排序（mock/remote 通用）。
    final ni = ref.watch(appStateProvider).notInterestedIds;
    var list = state.items.where((p) => !ni.contains(p.id)).toList();
    if (domain != null) {
      list = list.where((p) => p.domain == domain).toList();
    }
    list = _applySort(list);
    if (list.isEmpty) {
      return ListView(
        children: const [EmptyState(variant: EmptyStateVariant.generic)],
      );
    }
    return _cardListView(list, state);
  }

  List<Project> _applySort(List<Project> src) {
    final list = List<Project>.of(src);
    switch (sort) {
      case 'hot':
        // 热门 = 按真实点赞降序（与"推荐"用「想试数/takeaway」区分开，别两个 Tab 一样）。
        list.sort((a, b) {
          final c = b.likes.compareTo(a.likes);
          return c != 0 ? c : b.createdAtMs.compareTo(a.createdAtMs);
        });
      case 'new':
        list.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      case 'featured':
      default:
        break; // 保持返回顺序
    }
    return list;
  }

  Widget _cardListView(List<Project> list, PaginatedState<Project> state) {
    return ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(
        KkSpacing.lg,
        KkSpacing.sm,
        KkSpacing.lg,
        KkSpacing.xxl,
      ),
      // +1：底部加载指示器。
      itemCount: list.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: KkSpacing.lg),
      itemBuilder: (context, i) {
        if (i == list.length) {
          return LoadMoreIndicator(enabled: state.isLoadingMore);
        }
        return ProjectCard(project: list[i], showAuthor: true);
      },
    );
  }

  Widget _skeleton() {
    return const ProjectListSkeleton();
  }
}

// ══════════════════════════════════════════════════════════════════
// 精选 = App Store「Today / 编辑精选」式：日期头 + 一屏一张大图故事卡。
// 与「热门(点赞/热度)」区分开——精选是编辑策展，一图一故事，慢逛。
// ══════════════════════════════════════════════════════════════════
class _FeaturedTab extends ConsumerWidget {
  const _FeaturedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(featuredProjectsProvider);
    return async.when(
      loading: () => const ProjectListSkeleton(),
      error: (e, __) => RemoteError(
        message: '精选加载失败',
        error: e,
        onRetry: () async => ref.invalidate(featuredProjectsProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return ListView(
            children: const [EmptyState(variant: EmptyStateVariant.generic)],
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: KkSpacing.xxl),
          itemCount: list.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) return const _EditorialHeader();
            return _FeaturedCard(project: list[i - 1]);
          },
        );
      },
    );
  }
}

// ── [ZCode] 周头部：本周日期范围 +「本周精选」──
// ── [Claude 原始] 为单日「X月X日 · 周X」+「编辑精选」──
class _EditorialHeader extends StatelessWidget {
  const _EditorialHeader();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    String _fmt(DateTime d) => '${d.month}月${d.day}日';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          KkSpacing.lg, KkSpacing.lg, KkSpacing.lg, KkSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_fmt(monday)} — ${_fmt(sunday)}',
            style: KkType.bodySm.copyWith(
                color: KkColors.t3,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 2),
          Text('本周精选', style: KkType.h1),
        ],
      ),
    );
  }
}

// 大图故事卡：3:4 竖版封面铺满，上下渐变压暗，顶 kicker（领域）、底 大标题 + 一句话。
class _FeaturedCard extends StatelessWidget {
  final Project project;
  const _FeaturedCard({required this.project});

  static const _patterns = ['waves', 'mountains', 'circles', 'ink', 'grid'];

  @override
  Widget build(BuildContext context) {
    final media = project.resultData.media;
    final first = media.isNotEmpty ? media.first : null;
    final coverUrl = first == null
        ? null
        : (first.type == 'image' ? first.url : first.poster);
    final pattern = _patterns[project.id.hashCode.abs() % _patterns.length];
    final kicker = domainLabel(project.domain);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          KkSpacing.lg, KkSpacing.sm, KkSpacing.lg, KkSpacing.lg),
      child: GestureDetector(
        onTap: () => context.push(KkRoutes.detail(project.id)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(KkRadius.xl),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 封面（无图 → CoverArt 图案兜底）
                if (coverUrl != null && coverUrl.isNotEmpty)
                  KkImage(
                    url: coverUrl,
                    fit: BoxFit.cover,
                    placeholder: (c) => CoverArt(pattern: pattern),
                  )
                else
                  CoverArt(pattern: pattern),
                // 上下渐变压暗：让顶部 kicker 与底部标题都清晰可读
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x8C000000),
                        Color(0x00000000),
                        Color(0x00000000),
                        Color(0xC2000000),
                      ],
                      stops: [0, 0.32, 0.5, 1],
                    ),
                  ),
                ),
                // 顶 kicker：编辑精选 · 领域
                Positioned(
                  top: KkSpacing.lg,
                  left: KkSpacing.lg,
                  right: KkSpacing.lg,
                  child: Text(
                    '编辑精选 · $kicker',
                    style: KkType.bodySm.copyWith(
                      color: Colors.white.withAlpha(230),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                // 底 大标题 + 一句话
                Positioned(
                  left: KkSpacing.lg,
                  right: KkSpacing.lg,
                  bottom: KkSpacing.lg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        project.title,
                        style: KkType.h1.copyWith(color: Colors.white),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (project.summary.isNotEmpty) ...[
                        const SizedBox(height: KkSpacing.xs),
                        Text(
                          project.summary,
                          style: KkType.body
                              .copyWith(color: Colors.white.withAlpha(210)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
