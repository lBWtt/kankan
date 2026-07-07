import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/pagination/infinite_scroll.dart';
import '../../core/pagination/page.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/parse_count.dart';
import '../../core/widgets/cover_art.dart';
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

  static const _sorts = [('精选', 'featured'), ('热门', 'hot'), ('最新', 'new')];

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
    _tabCtrl = TabController(length: 3, vsync: this);
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
                      // 任务⑦:精选 Tab 顶部加「因为你看过 X」推荐横条(浏览史空则不渲染)。
                      // 不违反"精选无 shuffle"铁律——推荐条是列表之上的独立 section,
                      // 洗牌只作用于推荐条内部,_ProjectList 排序逻辑不动。
                      _FeaturedTab(domain: _domainFilter),
                      _ProjectList(sort: 'hot', domain: _domainFilter),
                      _ProjectList(sort: 'new', domain: _domainFilter),
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
          const SizedBox(width: KkSpacing.sm),
          // 真实项目数(禁编造)
          Consumer(builder: (context, ref, _) {
            final count = ref.watch(projectRepositoryProvider).all().length;
            return Text(
              '$count',
              style: KkType.mono.copyWith(color: KkColors.t3, fontSize: 13),
            );
          }),
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

// ──────────────────────────────────────────────────────────────────
// 任务⑦:精选 Tab —— 推荐横条 + 精选列表
// ──────────────────────────────────────────────────────────────────
// 把推荐条作为独立 section 放在精选列表之上(不违反"精选无 shuffle"铁律——
// 洗牌只作用于推荐条内部,_ProjectList 排序逻辑零改动)。
// browseHistory 为空 → 推荐条不渲染(零旁白,不占位),只显精选列表。
class _FeaturedTab extends ConsumerWidget {
  final String? domain;

  const _FeaturedTab({required this.domain});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(appStateProvider).browseHistory;
    final hasHistory = history.isNotEmpty;
    return Column(
      children: [
        // 推荐条跨领域推荐(不受当前领域筛选限制),给用户发现 X 领域外相关项目。
        if (hasHistory) const _RecommendStrip(),
        Expanded(child: _ProjectList(sort: 'featured', domain: domain)),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 任务⑦:「因为你看过 X」推荐横条
// ──────────────────────────────────────────────────────────────────
// 留存钩子:给用户一个"接着逛"的理由。
//
// 数据(纯函数,禁编造):
//   - X = browseHistory.first(最近看过的);byId 取回;取不到往后找下一个有效 id。
//   - 候选 = 与 X 同领域 或 有交集 tag 的项目,排除 X 自己。
//   - 不足 ~6 个时用其余项目补齐(仍排除 X);最多 ~8 个。
//
// 换一批:ConsumerStatefulWidget 存 int _seed,点「换一批」_seed++,
//   按 (p.id.hashCode ^ _seed) 确定性重排(可复现,非随机)。
//
// 视觉:头部行 左「因为你看过 {X.title}」(t3 + t1 加粗 ellipsis) 右「换一批」
//   (teal + refresh 图标,Tappable ≥44pt);主体横向小卡 ~130 宽(封面+标题+赞,
//   参考「我的」页最近看过小卡),点击跳详情 + recordBrowse。
//
// 铁律:coral 只给 take(换一批用 teal);无 emoji;零旁白(标题就是"因为你看过 X");
//   禁 if(artifactType);触控 ≥44pt。
class _RecommendStrip extends ConsumerStatefulWidget {
  const _RecommendStrip();

  @override
  ConsumerState<_RecommendStrip> createState() => _RecommendStripState();
}

class _RecommendStripState extends ConsumerState<_RecommendStrip> {
  int _seed = 0;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(projectRepositoryProvider);
    final history = ref.watch(appStateProvider).browseHistory;

    // X = 浏览史里第一个能 byId 取回的项目(取不到往后找)。
    Project? x;
    for (final id in history) {
      final p = repo.byId(id);
      if (p != null) {
        x = p;
        break;
      }
    }
    if (x == null) return const SizedBox.shrink();

    final candidates = _buildCandidates(repo.all(), x);
    if (candidates.isEmpty) return const SizedBox.shrink();

    // 确定性重排(可复现,非随机):按 (p.id.hashCode ^ _seed) 排序。
    // _seed++ 换出不同顺序/子集。取最多 8 个。
    final shuffled = _deterministicShuffle(candidates, _seed).take(8).toList();

    return Container(
      // 列表区是 bgSubtle(任务②),推荐条用 bgCard 浮起,与精选列表卡同底。
      color: KkColors.bgCard,
      padding: const EdgeInsets.symmetric(
        vertical: KkSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(context, x.title),
          const SizedBox(height: KkSpacing.sm),
          SizedBox(
            height: 130, // 小卡:封面 84 + 标题/赞 + padding
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: KkSpacing.lg,
              ),
              itemCount: shuffled.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: KkSpacing.sm),
              itemBuilder: (context, i) {
                final p = shuffled[i];
                return _RecommendCard(
                  project: p,
                  onTap: () {
                    ref
                        .read(appStateProvider.notifier)
                        .recordBrowse(p.id);
                    context.push(KkRoutes.detail(p.id));
                  },
                );
              },
            ),
          ),
          // 极浅 divider 分隔推荐条与精选列表
          const Divider(
            color: KkColors.divider,
            height: 1,
            thickness: 0.5,
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Row(
        children: [
          Flexible(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '因为你看过 ',
                    style: KkType.bodySm.copyWith(
                      fontSize: 12,
                      color: KkColors.t3,
                    ),
                  ),
                  TextSpan(
                    text: title,
                    style: KkType.bodySm.copyWith(
                      fontSize: 12,
                      color: KkColors.teal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: KkSpacing.sm),
          // 换一批(teal + refresh 图标,Tappable ≥44pt)
          Tappable(
            onTap: () => setState(() => _seed++),
            child: Container(
              // padding 撑到 ~44pt 热区,文字+图标视觉紧凑
              padding: const EdgeInsets.symmetric(
                horizontal: KkSpacing.sm,
                vertical: KkSpacing.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.refresh,
                    size: 14,
                    color: KkColors.teal,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '换一批',
                    style: KkType.bodySm.copyWith(
                      fontSize: 12,
                      color: KkColors.teal,
                      fontWeight: FontWeight.w600,
                    ),
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

// ── 候选构建(纯函数,禁编造)──
// 与 X 同领域 或 有交集 tag,排除 X 自己。不足补齐(仍排除 X)。
List<Project> _buildCandidates(List<Project> all, Project x) {
  final related = <Project>[];
  final fallback = <Project>[];
  for (final p in all) {
    if (p.id == x.id) continue;
    final sameDomain = p.domain == x.domain;
    final tagOverlap =
        p.tags.any((t) => x.tags.contains(t));
    if (sameDomain || tagOverlap) {
      related.add(p);
    } else {
      fallback.add(p);
    }
  }
  // 不足 6 个时用 fallback 补齐(仍排除 X,上面已 continue)
  final result = [...related];
  if (result.length < 6) {
    for (final p in fallback) {
      if (result.length >= 6) break;
      result.add(p);
    }
  }
  return result;
}

// ── 确定性重排(可复现,非随机)──
// 按 (p.id.hashCode ^ _seed) 升序排序;_seed 变化 → 顺序变化。
// 确定性:同一 _seed 同一顺序,可复现(铁律:别用不可复现随机)。
List<Project> _deterministicShuffle(List<Project> list, int seed) {
  final copy = List<Project>.of(list);
  copy.sort(
    (a, b) => (a.id.hashCode ^ seed).compareTo(b.id.hashCode ^ seed),
  );
  return copy;
}

// ── 推荐小卡(参考「我的」页最近看过小卡:130 宽,封面 84 + 标题 + 赞)──
class _RecommendCard extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;

  const _RecommendCard({required this.project, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
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
              child: _RecommendCover(project: project),
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
                    style: KkType.mono
                        .copyWith(fontSize: 10, color: KkColors.t3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 推荐小卡封面(复用 CoverArt + Image.network 回退,参考 _RecentCover)──
class _RecommendCover extends StatelessWidget {
  final Project project;
  const _RecommendCover({required this.project});

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
