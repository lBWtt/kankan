import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/time_ago.dart';
import '../../core/widgets/tappable.dart';
import '../../data/api/interactions_api.dart';
import '../../domain/models/models.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/remote_project_provider.dart';
import '../../router/routes.dart';
import '../shared/empty_state.dart';
import '../shared/list_state_views.dart';
import '../shared/project_card.dart';
import '../shared/remote_error.dart';

/// 鏀惰棌灞?鈥?HANDOFF 搂6.3 鍙屾。:鏀惰棌 + 鎴戞嬁璧扮殑銆?
///
/// 鍙?Tab:
///   - 鏀惰棌  appState.savedProjectIds 鈫?ProjectCard.compact
///   - 鎴戞嬁璧扮殑  appState.savedTakeaways,鎸?鏂囨湰/鏂囦欢/閾炬帴 涓夋。瀛愬垎绫?
///
/// 銆屾垜鎷胯蛋鐨勩€嶆槸 HANDOFF 搂6.3 寮洪渶姹?Web 鐗堝畬鍏ㄦ病鏈?:瀛樹笅浜嗗緱鏈夊湴鏂规壘鍥炪€?
/// 鎸?kind 鍒嗙被灞曠ず,鐐规潯鐩兘璺冲洖鍘熼」鐩?闀挎寜鍒犻櫎銆?
///
/// 璁℃暟閾佸緥(HANDOFF 搂6.10):tab 鏍囩涓婄殑鏁板瓧 = 鐪熷疄鏁扮粍闀垮害,涓嶆斁澶с€?
/// 闆舵梺鐧?HANDOFF 搂3):绌虹姸鎬佺敤 EmptyState,鏃?蹇幓鏀惰棌鐐逛笢瑗?寮曞銆?
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  /// 鍔犺浇鎬?Phase 5 鎺ョ湡鍚庣鏃?鎶婅繖涓?_loading 鍒囧埌鐪?await 缃戠粶璇锋眰鍗冲彲銆?
  /// 鐜板湪 mock 鏁版嵁鏄悓姝ョ殑,300ms 鍋囧欢杩熻楠ㄦ灦灞忔湁灞曠ず鏈轰細銆?
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    if (AppConfig.useRemote) {
      // 杩滅鏈夌湡瀹炲姞杞芥€侊紝涓嶆憜 300ms 鍋囬鏋躲€?
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
    final appState = ref.watch(appStateProvider);
    // effective = 鍚庣鏉ョ殑鐪熷疄鏀惰棌锛坮emoteFavoritesProvider锛孶UID 瀹屾暣鍗＄墖锛屽惈 author+counts锛夛紝
    // 鎸?savedIds 杩囨护銆傛敹钘忓繀椤荤櫥褰曪紙product-ia 搂2锛夛紝娓稿/鏈櫥褰?savedIds 涓虹┖ 鈫?鏀惰棌椤典负绌猴紝
    // **涓嶅洖钀?mock 婕旂ず鏀惰棌**锛堟棭鏈熸浘鏈?mock 鍏滃簳锛屽凡鍘绘帀锛泃ab 璁℃暟涓庡垪琛ㄥ悓婧愶紝鍙?effective.length锛夈€?
    // 涔愯鍙栨秷鏀惰棌锛堜粠 savedIds 绉婚櫎锛夊嵆鏃堕殣钘忥紝鏃犻渶绛?provider 閲嶆媺銆?
    final savedIds = appState.savedProjectIds;
    final remoteFavorites = ref.watch(remoteFavoritesProvider);
    final remoteFavs = (remoteFavorites.value ?? const <Project>[])
        .where((p) => savedIds.contains(p.id));
    final realSaved = <Project>[...remoteFavs];
    final effective = realSaved;

    return Column(
      children: [
        _topBar(),
        // loading 鏃堕攣浣?Tab,閬垮厤鍦ㄩ鏋跺睆鏈熼棿鍒?Tab銆?
        IgnorePointer(
          ignoring: _loading,
          child: _tabBar(),
        ),
        Expanded(
          child: ColoredBox(
            // 浠诲姟鈶?鍒楄〃鍖?bg2 搴?鍗＄墖 bgCard "娴?璧锋潵
            color: KkColors.bgSubtle,
            child: _loading
                ? _skeletonList()
                : TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _SavedTab(
                        effective: effective,
                        loading: AppConfig.useRemote &&
                            remoteFavorites.isLoading &&
                            savedIds.isNotEmpty,
                        error: AppConfig.useRemote && savedIds.isNotEmpty
                            ? remoteFavorites.error
                            : null,
                        onRetry: () async =>
                            ref.invalidate(remoteFavoritesProvider),
                      ),
                      const _TakeawayTab(),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // 鈹€鈹€ 鍔犺浇鎬侀鏋跺睆:3 涓?ProjectCardSkeleton,涓?_SavedTab 鍒楄〃杈硅窛涓€鑷?鈹€鈹€
  // _SavedTab 鐨?ProjectCard.compact 鑷甫杈硅窛,杩欓噷 ProjectCardSkeleton
  // 澶栧眰鍖?KkSpacing.lg 妯悜 + sm 椤?3 涓箣闂?md 闂磋窛,妯℃嫙鐪熷疄鏀惰棌鍒楄〃瑙傛劅銆?
  Widget _skeletonList() {
    return const ProjectListSkeleton(
      padding: EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.sm,
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.md,
      ),
      child: Row(
        children: [
          // 浠诲姟鈶?鏍囬鍚?6脳6 teal 鍝佺墝鐐?
          Text('收藏', style: KkType.h1),
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
          Tab(text: '收藏'),
          Tab(text: '素材'),
        ],
      ),
    );
  }
}

// 鈹€鈹€ 鏀惰棌 Tab 鈹€鈹€
class _SavedTab extends StatelessWidget {
  /// 鐖剁骇宸茬畻濂界殑鏈夋晥鍒楄〃(鐪熷疄鏀惰棌鎴?mock 鍏滃簳),涓?tab 璁℃暟鍚屾簮銆?
  final List<Project> effective;
  final bool loading;
  final Object? error;
  final Future<void> Function() onRetry;

  const _SavedTab({
    required this.effective,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const ProjectListSkeleton(
        padding: EdgeInsets.fromLTRB(
          KkSpacing.lg,
          KkSpacing.sm,
          KkSpacing.lg,
          KkSpacing.xxxl,
        ),
      );
    }
    if (error != null && effective.isEmpty) {
      return RemoteError(
        message: '收藏加载失败',
        error: error,
        onRetry: onRetry,
      );
    }
    if (effective.isEmpty) {
      return ListView(
        children: const [EmptyState(variant: EmptyStateVariant.saved)],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        KkSpacing.lg,
        KkSpacing.sm,
        KkSpacing.lg,
        KkSpacing.xxxl + KkSpacing.md,
      ),
      itemCount: effective.length,
      separatorBuilder: (_, __) => const SizedBox(height: KkSpacing.lg),
      itemBuilder: (context, i) => ProjectCard(project: effective[i]),
    );
  }
}

// 鈹€鈹€ 鎴戞嬁璧扮殑 Tab 鈹€鈹€
class _TakeawayTab extends ConsumerStatefulWidget {
  const _TakeawayTab();

  @override
  ConsumerState<_TakeawayTab> createState() => _TakeawayTabState();
}

class _TakeawayTabState extends ConsumerState<_TakeawayTab> {
  String _filter = 'all'; // all | visit | material

  static const _filters = <(String, String)>[
    ('全部', 'all'),
    ('去看看', 'visit'),
    ('存素材', 'material'),
  ];

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final remoteTryAsync = ref.watch(remoteTryItemsProvider);
    final remoteTryProjects = remoteTryAsync.value ?? const <TryProjectItem>[];
    final remoteTryTakeaways = remoteTryProjects.map((item) {
      final p = item.project;
      return SavedTakeaway(
        id: 'try-${p.id}',
        projectId: p.id,
        projectTitle: p.title,
        domain: p.domain,
        kind: 'link',
        source: p.tryUrl?.isNotEmpty == true ? p.tryUrl! : p.summary,
        label: p.status == 'published' ? '去看看' : '去看看 · 来源不可访问',
        savedAtMs: item.triedAtMs,
      );
    });
    final byId = <String, SavedTakeaway>{
      for (final t in remoteTryTakeaways) t.id: t,
      for (final t in appState.savedTakeaways) t.id: t,
    };
    final all = byId.values.toList()
      ..sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));
    final list = switch (_filter) {
      'visit' => all.where((t) => t.id.startsWith('try-')).toList(),
      'material' => all.where((t) => !t.id.startsWith('try-')).toList(),
      _ => all,
    };

    return Column(
      children: [
        _filterBar(),
        Expanded(
          child: AppConfig.useRemote &&
                  remoteTryAsync.isLoading &&
                  appState.savedTakeaways.isEmpty
              ? const CompactListSkeleton()
              : AppConfig.useRemote &&
                      remoteTryAsync.error != null &&
                      list.isEmpty
                  ? RemoteError(
                      message: '素材加载失败',
                      error: remoteTryAsync.error,
                      onRetry: () async =>
                          ref.invalidate(remoteTryItemsProvider),
                    )
                  : list.isEmpty
                      ? ListView(
                          children: const [
                            EmptyState(variant: EmptyStateVariant.takeaway),
                          ],
                        )
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (context, i) => _TakeawayTile(
                            takeaway: list[i],
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _filterBar() {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.lg,
          vertical: KkSpacing.sm,
        ),
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: KkSpacing.sm),
        itemBuilder: (context, i) {
          final (label, value) = _filters[i];
          final selected = _filter == value;
          return Tappable(
            onTap: () => setState(() => _filter = value),
            borderRadius: BorderRadius.circular(KkRadius.pill),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: KkSpacing.md,
                vertical: KkSpacing.sm,
              ),
              decoration: BoxDecoration(
                // 浠诲姟鈶?婵€娲绘€?bg2 搴?+ bd 杈规 + t1 鍔犵矖(鍘熷瀷鍏嬪埗椋?
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

// 鈹€鈹€ 鎷胯蛋鏉＄洰 鈹€鈹€
class _TakeawayTile extends ConsumerWidget {
  final SavedTakeaway takeaway;

  const _TakeawayTile({required this.takeaway});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, kindLabel, color) = _meta(takeaway.kind);
    final unavailable = takeaway.label?.contains('来源不可访问') == true;

    return Tappable(
      onTap: () {
        if (unavailable) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('来源作品已不可访问')),
          );
          return;
        }
        context.push(KkRoutes.detail(takeaway.projectId));
      },
      onLongPress: () => _showDeleteMenu(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.lg,
          vertical: KkSpacing.md,
        ),
        decoration: const BoxDecoration(
          color: KkColors.bgCard,
          border: Border(bottom: BorderSide(color: KkColors.divider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // kind 鍥炬爣
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(KkRadius.sm),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: KkSpacing.md),
            // 鍐呭
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 椤圭洰鏍囬 + kind 鏍囩
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          takeaway.projectTitle,
                          style: KkType.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: KkSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: KkSpacing.xs,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withAlpha(20),
                          borderRadius: BorderRadius.circular(KkRadius.sm),
                        ),
                        child: Text(
                          kindLabel,
                          style: KkType.bodySm.copyWith(
                            color: color,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // source 棰勮
                  Text(
                    takeaway.source,
                    style: KkType.bodySm.copyWith(
                      color: KkColors.t3,
                      fontFamily:
                          takeaway.kind == 'text' ? 'JetBrainsMono' : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // label + 鏃堕棿
                  Row(
                    children: [
                      if (takeaway.label != null) ...[
                        Text(
                          takeaway.label!,
                          style: KkType.bodySm.copyWith(
                            color: KkColors.t2,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: KkSpacing.sm),
                      ],
                      Text(
                        timeAgo(takeaway.savedAtMs),
                        style: KkType.mono.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: KkColors.t3),
          ],
        ),
      ),
    );
  }

  void _showDeleteMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tappable(
              onTap: () {
                ref.read(appStateProvider.notifier).removeTakeaway(takeaway.id);
                Navigator.pop(context);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: KkSpacing.md,
                ),
                child: Center(
                  child: Text(
                    '删除',
                    style: KkType.body.copyWith(color: KkColors.coral),
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: KkColors.divider),
            Tappable(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: KkSpacing.md),
                child: const Center(child: Text('取消', style: KkType.body)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  (IconData, String, Color) _meta(String kind) {
    switch (kind) {
      case 'text':
        return (Icons.text_snippet_outlined, '文本', KkColors.coral);
      case 'file':
        return (Icons.attach_file_outlined, '文件', KkColors.coral);
      case 'link':
        return (Icons.link_outlined, '链接', KkColors.teal);
      default:
        return (Icons.download_outlined, '素材', KkColors.coral);
    }
  }
}
