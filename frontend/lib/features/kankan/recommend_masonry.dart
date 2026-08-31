import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';

import '../../core/pagination/infinite_scroll.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/login_gate.dart';
import '../../core/utils/parse_count.dart';
import '../../core/widgets/cover_art.dart';
import '../../core/widgets/tappable.dart';
import '../../domain/models/models.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/paginated_projects_provider.dart';
import '../../providers/project_provider.dart';
import '../../router/routes.dart';
import '../shared/avatar.dart';
import '../shared/empty_state.dart';
import '../shared/kk_image.dart';
import '../shared/remote_error.dart';

/// 看看「推荐」Tab —— 小红书式双栏瀑布流。
///
/// 布局（对应用户诉求「极少数高价值用宽一点，大多数双栏」）：
///   - 顶部：热度最高的极少数项目 → 全宽大卡（复用 ProjectCard）。
///   - 其余：双栏 masonry 紧凑卡，封面高度随图错落。
///
/// 数据与 _ProjectList 同源（paginatedProjectsProvider），支持无限滚动。
class RecommendMasonry extends ConsumerStatefulWidget {
  final String? domain;
  const RecommendMasonry({super.key, required this.domain});

  @override
  ConsumerState<RecommendMasonry> createState() => _RecommendMasonryState();
}

class _RecommendMasonryState extends ConsumerState<RecommendMasonry> {
  late final ScrollController _scrollCtrl;
  // 下拉刷新累加：>0 时按 (id, tick) 稳定重排，让「推荐」下拉能换个新排面。
  // 首屏(tick=0)保持后端 slate 编排顺序——内容宪法首屏不动。
  int _refreshTick = 0;
  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    InfiniteScroll.attach(
      _scrollCtrl,
      onLoadMore: () {
        ref.read(paginatedProjectsProvider.notifier).loadMore();
      },
    );
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(paginatedProjectsProvider);
    if (state.isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(KkSpacing.xxl),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(KkColors.teal),
          ),
        ),
      );
    }
    if (state.error != null && state.items.isEmpty) {
      return RemoteError(
        message: '加载失败',
        error: state.error,
        onRetry: () async =>
            ref.read(paginatedProjectsProvider.notifier).refresh(),
      );
    }

    final ni = ref.watch(appStateProvider).notInterestedIds;
    var list = state.items.where((p) => !ni.contains(p.id)).toList();
    if (widget.domain != null) {
      list = list.where((p) => p.domain == widget.domain).toList();
    }
    // 首页首批十条已由后端内容宪法 slate 编排；客户端必须保持返回顺序。
    // 但下拉刷新是「给我换个新排面」的明确动作：tick>0 时按 (id, tick) 稳定重排。
    // 用稳定 key 排序（而非 shuffle 整表），loadMore 追加时已看过的卡片不会乱跳。
    if (_refreshTick > 0) {
      list = [...list]..sort((a, b) => Object.hash(a.id, _refreshTick)
          .compareTo(Object.hash(b.id, _refreshTick)));
    }

    if (list.isEmpty) {
      return ListView(
        children: const [EmptyState(variant: EmptyStateVariant.generic)],
      );
    }

    // 推荐 = 纯双栏瀑布流（决策：不再抽头部全宽大卡，所有项目一视同仁进双栏）。
    return RefreshIndicator(
      color: KkColors.teal,
      onRefresh: () async {
        await ref.read(paginatedProjectsProvider.notifier).refresh();
        if (mounted) setState(() => _refreshTick++);
      },
      child: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          // 双栏瀑布流
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              KkSpacing.md,
              KkSpacing.sm,
              KkSpacing.md,
              KkSpacing.xxl,
            ),
            sliver: SliverMasonryGrid.count(
              crossAxisCount: 2,
              mainAxisSpacing: KkSpacing.md,
              crossAxisSpacing: KkSpacing.md,
              childCount: list.length + 1,
              itemBuilder: (context, i) {
                if (i == list.length) {
                  return LoadMoreIndicator(
                    enabled: state.isLoadingMore,
                  );
                }
                return _MasonryCard(project: list[i]);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 双栏瀑布流里的紧凑项目卡：封面（高度随 id 错落）+ 标题 + 作者 + 赞。
class _MasonryCard extends ConsumerWidget {
  final Project project;
  const _MasonryCard({required this.project});

  // 封面比例按 id 哈希取，制造瀑布错落感（同一项目稳定，不跳动）。
  static const _ratios = [1.0, 0.78, 1.3, 1.12, 0.9];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.read(analyticsProvider).trackImpressionOnce(project.id);
    final author = ref.watch(userByIdProvider(project.authorId));
    final appState = ref.watch(appStateProvider);
    final isLiked = appState.likedItemIds.contains(project.id);
    final likeCount = project.likes + (isLiked ? 1 : 0);

    final media = project.resultData.media;
    final coverUrl = (media.isNotEmpty && media.first.type == 'image')
        ? media.first.url
        : null;
    final ratio = _ratios[project.id.hashCode.abs() % _ratios.length];

    return Tappable(
      onTap: () {
        ref.read(analyticsProvider).track('card_click', projectId: project.id);
        ref.read(appStateProvider.notifier).recordBrowse(project.id);
        context.push(KkRoutes.detail(project.id));
      },
      borderRadius: BorderRadius.circular(KkRadius.lg),
      child: Container(
        decoration: BoxDecoration(
          color: KkColors.bgCard,
          borderRadius: BorderRadius.circular(KkRadius.lg),
          border: Border.all(color: KkColors.bd),
          boxShadow: KkElevation.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 封面（比例错落）
            AspectRatio(
              aspectRatio: ratio,
              child: (coverUrl != null && coverUrl.isNotEmpty)
                  // 走 KkImage：磁盘缓存，滑走再滑回不重新下载（修封面反复重载）。
                  ? KkImage(
                      url: coverUrl,
                      fit: BoxFit.cover,
                      placeholder: (_) => const CoverArt(pattern: 'grid'),
                    )
                  : const CoverArt(pattern: 'grid'),
            ),
            Padding(
              padding: const EdgeInsets.all(KkSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    project.title,
                    style: KkType.body.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: KkSpacing.sm),
                  Row(
                    children: [
                      KkAvatar(
                        userId: project.authorId,
                        user: author,
                        size: 18,
                      ),
                      const SizedBox(width: KkSpacing.xs),
                      Expanded(
                        child: Text(
                          author?.name ?? project.authorId,
                          style: KkType.mono
                              .copyWith(fontSize: 11, color: KkColors.t3),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // 直接点赞：点卡片右下角爱心即赞/取消（乐观本地 toggle），不用进详情。
                      GestureDetector(
                        onTap: () {
                          if (!guardLogin(context, ref)) return;
                          ref
                              .read(appStateProvider.notifier)
                              .toggleLike(project.id);
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isLiked ? Icons.favorite : Icons.favorite_border,
                              size: 15,
                              color: isLiked ? KkColors.like : KkColors.t3,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              formatCount(likeCount),
                              style: KkType.mono
                                  .copyWith(fontSize: 11, color: KkColors.t3),
                            ),
                          ],
                        ),
                      ),
                    ],
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
