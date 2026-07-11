import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/pagination/infinite_scroll.dart';
import '../../core/pagination/page.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/skeletons.dart';
import '../../core/widgets/tappable.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/project_repository.dart';
import '../../l10n/kk_strings.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/paginated_projects_provider.dart';
import '../../router/routes.dart';
import '../shared/empty_state.dart';
import '../shared/project_card.dart';
import '../shared/remote_error.dart';
import 'recommend_masonry.dart';

/// 看看屏 — HANDOFF §6.9 项目 feed。
///
/// 三 Tab 真排序(Web 版重灾区,Flutter 从零做对):
///   - 精选  seed 默认顺序(mock seed 顺序即精选,无 shuffle)
///   - 热门  by likes 降序(真实计数)
///   - 最新  by createdAtMs 降序
///
/// 领域筛选(横向 chip 行):全部 / AI图 / AI视频 / 网页 / App / 工具 / 开源 / Prompt
///
/// 计数铁律(HANDOFF §6.10):排序按真实 likes/createdAtMs,不放大不编造。
/// 零旁白(HANDOFF §3):空状态用 EmptyState,无"快来发第一个"引导。
class KankanScreen extends ConsumerStatefulWidget {
  const KankanScreen({super.key});

  @override
  ConsumerState<KankanScreen> createState() => _KankanScreenState();
}

class _KankanScreenState extends ConsumerState<KankanScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  String? _domainFilter; // null = 全部

  /// 加载态:Phase 5 接真后端时,把这个 _loading 切到真 await 网络请求即可。
  /// 现在 mock 数据是同步的,300ms 假延迟让骨架屏有展示机会。
  bool _loading = true;

  // 顺序：精选 / 推荐 / 热门；默认落在「推荐」（见 initState initialIndex）。
  static const _sorts = [('精选', 'featured'), ('推荐', 'new'), ('热门', 'hot')];

  static const _domains = <(String, String?)>[
    ('全部', null),
    ('AI图', 'ai_image'),
    ('AI视频', 'ai_video'),
    ('网页', 'web'),
    ('App', 'app'),
    ('工具', 'tool'),
    ('开源', 'opensource'),
    ('Prompt', 'prompt'),
  ];

  @override
  void initState() {
    super.initState();
    // 默认落在「推荐」Tab（index 1）——瀑布流是主逛区。
    _tabCtrl = TabController(length: 3, vsync: this, initialIndex: 1);
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
        // loading 时锁住 Tab + 领域筛选,避免在骨架屏期间切条件。
        IgnorePointer(ignoring: _loading, child: _tabBar()),
        IgnorePointer(ignoring: _loading, child: _domainFilterBar()),
        Expanded(
          child: ColoredBox(
            // 任务②:列表区 bg2 底,卡片 bgCard "浮"起来,编辑层次
            color: KkColors.bgSubtle,
            child: _loading
                ? _skeletonContent()
                : TabBarView(
                    controller: _tabCtrl,
                    children: [
                      // 三 Tab（精选/推荐/热门）共享分页 state，各自客户端 filter+sort。
                      _ProjectList(sort: 'featured', domain: _domainFilter),
                      // 推荐：小红书式双栏瀑布流（极少数高价值全宽大卡 + 其余双栏）。默认 Tab。
                      RecommendMasonry(domain: _domainFilter),
                      _ProjectList(sort: 'hot', domain: _domainFilter),
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

  // 领域筛选横向 chip 行
  Widget _domainFilterBar() {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.lg,
          vertical: KkSpacing.sm,
        ),
        itemCount: _domains.length,
        separatorBuilder: (_, __) => const SizedBox(width: KkSpacing.sm),
        itemBuilder: (context, i) {
          final (label, value) = _domains[i];
          final selected = _domainFilter == value;
          return Tappable(
            onTap: () => setState(() => _domainFilter = value),
            borderRadius: BorderRadius.circular(KkRadius.pill),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: KkSpacing.md,
                vertical: KkSpacing.sm,
              ),
              decoration: BoxDecoration(
                // 任务②:激活态 bg2 底 + bd 边框 + t1 加粗(原型克制风,非 teal 实心)
                color: selected ? KkColors.bgSubtle : Colors.transparent,
                borderRadius: BorderRadius.circular(KkRadius.pill),
                border: Border.all(color: KkColors.bd),
              ),
              child: Center(
                child: Text(
                  label,
                  style: KkType.bodySm.copyWith(
                    color: selected ? KkColors.t1 : KkColors.t2,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
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
        message: '连不上服务器',
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
        list.sort((a, b) => b.takeawayCount.compareTo(a.takeawayCount));
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
        KkSpacing.lg, KkSpacing.sm, KkSpacing.lg, KkSpacing.xxl,
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        KkSpacing.lg, KkSpacing.sm, KkSpacing.lg, KkSpacing.xxl,
      ),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(height: KkSpacing.lg),
      itemBuilder: (_, __) => const ProjectCardSkeleton(),
    );
  }
}
