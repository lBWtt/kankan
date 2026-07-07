import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/parse_count.dart';
import '../../core/widgets/kk_back_button.dart';
import '../../core/widgets/tappable.dart';
import '../../data/seed/mock_seed.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/post_repository.dart';
import '../../domain/repositories/project_repository.dart';
import '../../router/routes.dart';
import '../shared/empty_state.dart';
import '../shared/post_card.dart';
import '../shared/project_card.dart';
import '../shared/share_sheet.dart';

/// 话题页 — HANDOFF §6.2 + §6.10 真实 heat 聚合。
///
/// 双 Tab(动态 / 项目),按 tag 过滤:
///   - 动态:postRepositoryProvider.all() 过滤 tags.contains(tag),
///     按 createdAtMs 降序
///   - 项目:projectRepositoryProvider.byTag(tag),按 likes 降序
///
/// 热度卡片:heat / projectCount / postCount / totalLikes 必须从 mockTopics
/// 真实聚合值取(HANDOFF §6.10 禁 ×8+30 编造 — Web 版重灾区)。
/// mockTopics 启动时算一次:heat = projectCount*10 + postCount*5 +
/// totalLikes~/100(三方加权,反映真实热度)。
///
/// 零旁白(HANDOFF §3):空状态用 EmptyState.generic,无「快来发第一个」引导。
/// 珊瑚橙(HANDOFF §5)只给 take 动作,本屏不用 coral。
class TopicScreen extends ConsumerStatefulWidget {
  /// 话题名(不含 #),路由 path 参数已 URL decode
  final String tag;

  const TopicScreen({super.key, required this.tag});

  @override
  ConsumerState<TopicScreen> createState() => _TopicScreenState();
}

class _TopicScreenState extends ConsumerState<TopicScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 真实 heat 从 mockTopics 取(HANDOFF §6.10 禁编造)
    final topic = mockTopics.where((t) => t.tag == widget.tag).firstOrNull;

    return Scaffold(
      backgroundColor: KkColors.bg,
      appBar: _topBar(context),
      body: Column(
        children: [
          _heatCard(topic),
          _tabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _PostsTab(tag: widget.tag),
                _ProjectsTab(tag: widget.tag),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 顶栏:返回 / #tag(teal h1) / 分享 ──
  PreferredSizeWidget _topBar(BuildContext context) {
    return AppBar(
      backgroundColor: KkColors.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: const KkBackButton(),
      titleSpacing: 0,
      title: Text(
        '#${widget.tag}',
        style: KkType.h1.copyWith(color: KkColors.teal),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        Tappable(
          onTap: () {
            final t = mockTopics
                .where((t) => t.tag == widget.tag)
                .firstOrNull;
            showShareSheet(
              context,
              title: '#${widget.tag}',
              subtitle: '看看话题 · ${t?.projectCount ?? 0} 篇作品 · ${t?.postCount ?? 0} 条动态',
              shareType: 'topic',
              shareUrl: 'https://kankan.app/topic/${Uri.encodeComponent(widget.tag)}',
              coverPattern: 'grid',
              likes: t?.totalLikes,
            );
          },
          child: const Icon(Icons.ios_share_outlined,
              size: 22, color: KkColors.t1),
        ),
        const SizedBox(width: KkSpacing.sm),
      ],
    );
  }

  // ── 热度卡片(header,TabBar 之上)──
  //
  // 左:大号 heat 数字(32px mono teal)+ 「热度」副文(bodySm t3)
  // 右:三指标横排 — 项目数 / 动态数 / 总点赞
  //   数字用 KkType.mono,label 用 KkType.bodySm t3 灰
  // 整张卡:bgCard 圆角 + bd 边框
  Widget _heatCard(Topic? topic) {
    final heat = topic?.heat ?? 0;
    final projectCount = topic?.projectCount ?? 0;
    final postCount = topic?.postCount ?? 0;
    final totalLikes = topic?.totalLikes ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        KkSpacing.lg,
        KkSpacing.sm,
        KkSpacing.lg,
        KkSpacing.sm,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: KkColors.bgCard,
        borderRadius: BorderRadius.circular(KkRadius.lg),
        border: Border.all(color: KkColors.bd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左:heat 大号 + 标签
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$heat',
                style: KkType.monoLg.copyWith(
                  fontSize: 32,
                  color: KkColors.teal,
                ),
              ),
              const SizedBox(height: KkSpacing.xs),
              Text(
                '热度',
                style: KkType.bodySm.copyWith(color: KkColors.t3),
              ),
            ],
          ),
          const Spacer(),
          // 右:三个小指标横排
          Row(
            children: [
              _Stat(value: '$projectCount', label: '项目数'),
              const SizedBox(width: KkSpacing.lg),
              _Stat(value: '$postCount', label: '动态数'),
              const SizedBox(width: KkSpacing.lg),
              _Stat(value: formatCount(totalLikes), label: '总点赞'),
            ],
          ),
        ],
      ),
    );
  }

  // ── 双 Tab:动态 / 项目 ──
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
        tabs: const [Tab(text: '动态'), Tab(text: '项目')],
      ),
    );
  }
}

// ── 热度卡片右侧小指标(数字 mono + label bodySm t3)──
class _Stat extends StatelessWidget {
  final String value;
  final String label;

  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: KkType.mono.copyWith(
            fontWeight: FontWeight.w600,
            color: KkColors.t1,
          ),
        ),
        const SizedBox(height: KkSpacing.xs),
        Text(
          label,
          style: KkType.bodySm.copyWith(color: KkColors.t3),
        ),
      ],
    );
  }
}

// ── 动态 Tab:该 tag 下所有 Post,按 createdAtMs 降序 ──
//
// 真排序(HANDOFF §6.9):Web 版重灾区是按 tag 子串匹配 + 随机排序;
// Flutter 端用 p.tags.contains(tag) 精确匹配 + 时间倒序。
class _PostsTab extends ConsumerWidget {
  final String tag;

  const _PostsTab({required this.tag});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(postRepositoryProvider);
    // all() 返回 List.unmodifiable,需 toList() 才能排序
    final list = repo.all().where((p) => p.tags.contains(tag)).toList()
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));

    if (list.isEmpty) {
      return ListView(
        children: const [EmptyState(variant: EmptyStateVariant.generic)],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        KkSpacing.lg,
        KkSpacing.sm,
        KkSpacing.lg,
        KkSpacing.xxl,
      ),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: KkSpacing.md),
      // F-33:PostCard 传 onTap → 点正文进动态详情(与 discover 屏一致)。
      // 不传时 PostCard 仅内部热区可点,正文区域无反应。
      itemBuilder: (context, i) => PostCard(
        post: list[i],
        onTap: () => context.push(KkRoutes.postDetail(list[i].id)),
      ),
    );
  }
}

// ── 项目 Tab:该 tag 下所有 Project,按 likes 降序 ──
//
// byTag(tag) 用 p.tags.contains(tag) 精确匹配(HANDOFF §6.2 — 真实 tags 索引,
// Web 版靠标题子串硬凑的罪)。
class _ProjectsTab extends ConsumerWidget {
  final String tag;

  const _ProjectsTab({required this.tag});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(projectRepositoryProvider);
    // byTag 返回 toList(),已是可变副本,直接排序
    final list = repo.byTag(tag)
      ..sort((a, b) => b.likes.compareTo(a.likes));

    if (list.isEmpty) {
      return ListView(
        children: const [EmptyState(variant: EmptyStateVariant.generic)],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        KkSpacing.lg,
        KkSpacing.sm,
        KkSpacing.lg,
        KkSpacing.xxl,
      ),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: KkSpacing.md),
      itemBuilder: (context, i) => ProjectCard(project: list[i]),
    );
  }
}
