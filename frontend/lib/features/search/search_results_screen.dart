import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/levenshtein.dart';
import '../../core/utils/parse_count.dart';
import '../../core/utils/time_ago.dart';
import '../../core/widgets/kk_back_button.dart';
import '../../core/widgets/tappable.dart';
import '../../data/seed/mock_seed.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/search_repository.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/project_provider.dart';
import '../../providers/remote_post_provider.dart';
import '../../providers/remote_project_provider.dart';
import '../../providers/search_provider.dart';
import '../../router/routes.dart';
import '../shared/avatar.dart';
import '../shared/empty_state.dart';

/// 搜索结果屏 — HANDOFF §6.10 真实计数 + 修复 Web 版两个 bug。
///
/// 4 Tab:项目 / 动态 / 用户 / 话题。每个 Tab 标题带真实计数(从 SearchRepository)。
/// 初始 Tab = 第一个有结果的 Tab,全空时默认项目 Tab(HANDOFF §6.10)。
///
/// **修复 Web 版 bug 1:hashtag 跳空**
/// Web 版点 #tag 丢回搜索框;Flutter 端:点话题 → `KkRoutes.topic(tag)` 独立话题页。
///
/// **修复 Web 版 bug 2:自发项目堵死**
/// Web 版动态 quoteProjectId=null 时点卡片无去处;Flutter 端:整卡跳 `KkRoutes.postDetail`,
/// 不论是否引用项目,都进动态详情页(详情页内部再处理 quote 跳转)。
///
/// **搜索词高亮**
/// ProjectCard/PostCard 是封装组件,无法直接改内部文字高亮。这里用简化的「搜索结果卡」:
/// 标题/摘要/正文/标签全用 `HighlightedText` 包,匹配段 mint 底 + teal 字 + KkRadius.sm 圆角。
///
/// 计数铁律(HANDOFF §6.10):tab badge 取真实数组长度,不放大。
/// 零旁白(HANDOFF §3):无引导文案,空状态用 EmptyState generic。
///
/// **Phase 5 智能纠错(HANDOFF §6.2 — levenshtein 工具 4-d 子代理创建)**
/// 当 counts.total == 0 时,从 searchRepository 取候选词池(topic tag + user name
/// + project title),调 `suggestClosest(q, candidates, maxDistance: 2)` 找最接近
/// 的一个。找到 → 在 EmptyState 上方渲染 `_CorrectionCard`(陈述性「你是不是想搜:」
/// + teal 高亮候选词,点击 → `context.push(KkRoutes.searchResults(suggestion))`
/// 重新搜索)。找不到 → 只显示原 EmptyState。候选词池严格走 repository 真实计数,
/// 不编造(searchTopics('') 返回所有 tag;searchUsers('')/searchProjects('') 空
/// query 早退返空,故候选池以 tag 为主 — HANDOFF §6.10 真实计数铁律)。
class SearchResultsScreen extends ConsumerStatefulWidget {
  final String query;

  const SearchResultsScreen({super.key, required this.query});

  @override
  ConsumerState<SearchResultsScreen> createState() =>
      _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    // 初始 Tab = 第一个有结果的 Tab,全空时默认项目 Tab。
    final counts = ref.read(searchRepositoryProvider).counts(widget.query);
    final initialIdx = counts.projects > 0
        ? 0
        : counts.posts > 0
            ? 1
            : counts.users > 0
                ? 2
                : counts.topics > 0
                    ? 3
                    : 0;
    _tabCtrl = TabController(
      length: 4,
      vsync: this,
      initialIndex: initialIdx,
    );
    _ctrl = TextEditingController(text: widget.query);
    _ctrl.addListener(_onCtrlChanged);
  }

  void _onCtrlChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrlChanged);
    _ctrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _search(String q) {
    final s = q.trim();
    if (s.isEmpty) return;
    if (s == widget.query) return;
    ref.read(appStateProvider.notifier).addRecentSearch(s);
    // 在结果页里改词再搜：replace 当前结果页而非 push，避免连搜多次后要按同样多次
    // 返回才回到发现（从搜索输入页首次进入仍是 push，返回键正确回到输入页）。
    context.replace(KkRoutes.searchResults(s));
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(searchRepositoryProvider);
    final q = widget.query;
    var counts = repo.counts(q);
    // 远端模式：四个 Tab 全走后端搜索（/projects?q= 、/posts?q= 、/users/search 、/topics），
    // 计数以后端结果为准；加载中先按 0 显示，数据到齐后 badge 自动补上。
    if (AppConfig.useRemote) {
      final remote = ref.watch(remoteSearchProjectsProvider(q));
      final remotePosts = ref.watch(remoteSearchPostsProvider(q));
      final remoteUsers = ref.watch(searchUsersProvider(q));
      final remoteTopics = ref.watch(searchTopicsProvider(q));
      final isLoading = remote.isLoading ||
          remotePosts.isLoading ||
          remoteUsers.isLoading ||
          remoteTopics.isLoading;
      counts = SearchCounts(
        projects: remote.asData?.value.length ?? 0,
        posts: remotePosts.asData?.value.length ?? 0,
        users: remoteUsers.asData?.value.length ?? 0,
        topics: remoteTopics.asData?.value.length ?? 0,
      );
      if (isLoading && counts.total == 0) {
        return Scaffold(
          backgroundColor: KkColors.bg,
          appBar: AppBar(
            backgroundColor: KkColors.bg,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: const KkBackButton(),
            titleSpacing: 0,
            title: _searchField(),
          ),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
    }

    return Scaffold(
      backgroundColor: KkColors.bg,
      appBar: AppBar(
        backgroundColor: KkColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const KkBackButton(),
        titleSpacing: 0,
        title: _searchField(),
      ),
      body: counts.total == 0
          ? _buildEmptyBody(q, ref)
          : Column(
              children: [
                _tabBar(counts),
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _ProjectsTab(query: q),
                      _PostsTab(query: q),
                      _UsersTab(query: q),
                      _TopicsTab(query: q),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// 渲染全空状态(counts.total == 0)。
  ///
  /// 在 EmptyState 上方可选挂一张 `_CorrectionCard` —— 当 [suggestClosest] 从候选词池
  /// 找到距离 ≤2 的近邻词时显示;找不到则只显示 EmptyState。
  Widget _buildEmptyBody(String q, WidgetRef ref) {
    final suggestion = _suggestCorrection(q, ref);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (suggestion != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
              child: _CorrectionCard(
                suggestion: suggestion,
                onTap: () => context.push(KkRoutes.searchResults(suggestion)),
              ),
            ),
            const SizedBox(height: KkSpacing.lg),
          ],
          const EmptyState(
            variant: EmptyStateVariant.generic,
            title: '没有相关内容',
          ),
        ],
      ),
    );
  }

  /// 从 searchRepository 取候选词池,调 [suggestClosest] 找最接近 [q] 的一个。
  ///
  /// 候选词池来源(HANDOFF §6.10 真实计数,不编造):
  ///   - `repo.searchTopics('')` → 所有 tag(空 query 时返回全集,见
  ///     search_repository.dart:78)
  ///   - `repo.searchUsers('')` → 空(空 query 早退,见 search_repository.dart:59)
  ///   - `repo.searchProjects('')` → 空(空 query 早退,见 search_repository.dart:30)
  ///
  /// 故实际候选池以 topic tag 为主,但保持调用三方遵循「真实计数」原则 —— 未来若 repo
  /// 改为支持空 query 返回全集,候选池自动扩充,本方法无需改。
  String? _suggestCorrection(String q, WidgetRef ref) {
    final repo = ref.read(searchRepositoryProvider);
    final candidates = <String>[
      ...repo.searchTopics('').map((t) => t.tag),
      ...repo.searchUsers('').map((u) => u.name),
      ...repo.searchProjects('').map((p) => p.title),
    ];
    return suggestClosest(q, candidates, maxDistance: 2);
  }

  Widget _searchField() {
    // 修 bug（第二次）：之前用 prefixIcon + isDense + 定高 42，在 AppBar 语境下
    // InputDecoration 的内在高度把文字基线挤出可见区 → 搜索词「有（×在）却不显示」。
    // 改稳妥写法：图标改成 Row 里的兄弟节点（不占输入框内在高度）；输入框 isCollapsed
    // + contentPadding 归零，让它贴着父容器高度、不再自撑高，文字就能正常显示。
    return Container(
      height: 42,
      margin: const EdgeInsets.only(right: KkSpacing.lg),
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.md),
      decoration: BoxDecoration(
        color: KkColors.bgSubtle,
        borderRadius: BorderRadius.circular(KkRadius.pill),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: KkColors.t3),
          const SizedBox(width: KkSpacing.sm),
          Expanded(
            child: TextField(
              controller: _ctrl,
              autofocus: false,
              textInputAction: TextInputAction.search,
              textAlignVertical: TextAlignVertical.center,
              style: KkType.body.copyWith(color: KkColors.t1),
              decoration: InputDecoration(
                hintText: '搜索',
                hintStyle: KkType.body.copyWith(color: KkColors.t4),
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
              ),
              onSubmitted: _search,
            ),
          ),
          if (_ctrl.text.isNotEmpty)
            Tappable(
              onTap: _ctrl.clear,
              borderRadius: BorderRadius.circular(KkRadius.pill),
              child: const Padding(
                padding: EdgeInsets.only(left: KkSpacing.xs),
                child: Icon(Icons.close, size: 16, color: KkColors.t3),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabBar(SearchCounts counts) {
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
          _tab('项目', counts.projects),
          _tab('动态', counts.posts),
          _tab('用户', counts.users),
          _tab('话题', counts.topics),
        ],
      ),
    );
  }

  /// 单个 Tab:label(body,随选中态变色) + 计数(mono t3 size 11)。
  /// 用 Text.rich 让 label 继承 TabBar 的 DefaultTextStyle(选中/未选中色),
  /// 计数段固定 mono 风格。
  Widget _tab(String label, int count) {
    return Tab(
      child: Text.rich(
        TextSpan(
          text: label,
          children: [
            TextSpan(
              text: ' $count',
              style: KkType.mono.copyWith(fontSize: 11, color: KkColors.t3),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// HighlightedText — 独立 widget,query 为空或无匹配时回退到 Text
// ──────────────────────────────────────────────────────────────────

/// 把 text 按 query 分段,匹配段高亮(mint 底 + teal 字 + KkRadius.sm 圆角)。
///
/// 实现细节:
///   - query 为空 OR text 不含 query(不分大小写)→ 直接返回 `Text(text, style: baseStyle)`
///   - 否则用 `RichText` + `TextSpan` + `WidgetSpan` 拼接:非匹配段是 TextSpan,
///     匹配段是 WidgetSpan(包小 Container 做 mint 底 + 圆角)
///   - WidgetSpan 用 `PlaceholderAlignment.baseline` + `TextBaseline.alphabetic`
///     让高亮段与周围文字基线对齐,2px 横向 padding 让圆角背景视觉外延
class HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle baseStyle;
  final int? maxLines;
  final TextOverflow overflow;

  const HighlightedText({
    super.key,
    required this.text,
    required this.query,
    required this.baseStyle,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    if (q.isEmpty) {
      return Text(text,
          style: baseStyle, maxLines: maxLines, overflow: overflow);
    }
    final lower = text.toLowerCase();
    final lq = q.toLowerCase();
    if (!lower.contains(lq)) {
      return Text(text,
          style: baseStyle, maxLines: maxLines, overflow: overflow);
    }

    final spans = <InlineSpan>[];
    var start = 0;
    while (true) {
      final idx = lower.indexOf(lq, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: baseStyle));
      }
      // 高亮段用纯 TextSpan + backgroundColor（紧贴字形的底色，无 padding、不打断文字流）。
      // 原来用 WidgetSpan 包 Container（2px padding + 圆角）→ 命中词中间时把词拆成「Oll ama」，很丑。
      spans.add(TextSpan(
        text: text.substring(idx, idx + q.length),
        style: baseStyle.copyWith(
          color: KkColors.teal,
          fontWeight: FontWeight.w600,
          backgroundColor: KkColors.mint,
        ),
      ));
      start = idx + q.length;
    }
    return RichText(
      maxLines: maxLines,
      overflow: overflow,
      text: TextSpan(children: spans, style: baseStyle),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 项目 Tab — 简化搜索结果卡(标题/摘要/标签高亮,不直接用 ProjectCard)
// ──────────────────────────────────────────────────────────────────

class _ProjectsTab extends ConsumerWidget {
  final String query;
  const _ProjectsTab({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 远端模式：后端 GET /projects?q=（匹配 title/tagline/tools）。demo/本地：内存搜索。
    if (AppConfig.useRemote) {
      final async = ref.watch(remoteSearchProjectsProvider(query));
      return async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: EmptyState(variant: EmptyStateVariant.generic),
        ),
        data: (list) => _list(list),
      );
    }
    final repo = ref.watch(searchRepositoryProvider);
    return _list(repo.searchProjects(query));
  }

  Widget _list(List<Project> list) {
    if (list.isEmpty) {
      return const Center(
        child: EmptyState(variant: EmptyStateVariant.generic),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        KkSpacing.lg,
        KkSpacing.md,
        KkSpacing.lg,
        KkSpacing.xxl,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: KkSpacing.md),
          child: _ProjectHit(project: list[i], query: query),
        );
      },
    );
  }
}

class _ProjectHit extends ConsumerWidget {
  final Project project;
  final String query;
  const _ProjectHit({required this.project, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final author = ref.watch(userByIdProvider(project.authorId));
    return Tappable(
      onTap: () {
        ref.read(appStateProvider.notifier).recordBrowse(project.id);
        context.push(KkRoutes.detail(project.id));
      },
      borderRadius: BorderRadius.circular(KkRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(KkSpacing.md),
        decoration: BoxDecoration(
          color: KkColors.bgCard,
          borderRadius: BorderRadius.circular(KkRadius.lg),
          border: Border.all(color: KkColors.bd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HighlightedText(
              text: project.title,
              query: query,
              baseStyle: KkType.h3,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            HighlightedText(
              text: project.summary,
              query: query,
              baseStyle: KkType.bodySm,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (project.tags.isNotEmpty) ...[
              const SizedBox(height: KkSpacing.sm),
              Wrap(
                spacing: KkSpacing.xs,
                runSpacing: KkSpacing.xs,
                children: [
                  for (final t in project.tags)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KkSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: KkColors.mint,
                        borderRadius: BorderRadius.circular(KkRadius.sm),
                      ),
                      child: HighlightedText(
                        text: '#$t',
                        query: query,
                        baseStyle: KkType.bodySm.copyWith(
                          color: KkColors.teal,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: KkSpacing.sm),
            Row(
              children: [
                KkAvatar(userId: project.authorId, user: author, size: 20),
                const SizedBox(width: KkSpacing.xs),
                Flexible(
                  child: Text(
                    author?.name ?? project.authorId,
                    style: KkType.bodySm.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: KkSpacing.sm),
                Text(
                  timeAgo(project.createdAtMs),
                  style: KkType.mono.copyWith(fontSize: 11, color: KkColors.t3),
                ),
                const Spacer(),
                Icon(Icons.favorite_border, size: 12, color: KkColors.t3),
                const SizedBox(width: 2),
                Text(
                  formatCount(project.likes),
                  style: KkType.mono.copyWith(fontSize: 11, color: KkColors.t3),
                ),
                const SizedBox(width: KkSpacing.sm),
                Icon(Icons.chat_bubble_outline, size: 12, color: KkColors.t3),
                const SizedBox(width: 2),
                Text(
                  // F-8b:评论数取 commentsFor(project.id).length(与详情页 / 项目卡同源)。
                  formatCount(commentsFor(project.id).length),
                  style: KkType.mono.copyWith(fontSize: 11, color: KkColors.t3),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 动态 Tab — 简化搜索结果卡(正文/标签高亮,不直接用 PostCard)
// **修复 Web 版 bug 2:整卡 → postDetail(不论 quoteProjectId 是否为 null)**
// ──────────────────────────────────────────────────────────────────

class _PostsTab extends ConsumerWidget {
  final String query;
  const _PostsTab({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 远端模式：后端 GET /posts?q=（匹配正文）。demo/本地：内存搜索。
    if (AppConfig.useRemote) {
      final async = ref.watch(remoteSearchPostsProvider(query));
      return async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: EmptyState(variant: EmptyStateVariant.generic),
        ),
        data: (list) => _list(list),
      );
    }
    final repo = ref.watch(searchRepositoryProvider);
    return _list(repo.searchPosts(query));
  }

  Widget _list(List<Post> list) {
    if (list.isEmpty) {
      return const Center(
        child: EmptyState(variant: EmptyStateVariant.generic),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: KkSpacing.sm),
      itemCount: list.length,
      itemBuilder: (context, i) => _PostHit(post: list[i], query: query),
    );
  }
}

class _PostHit extends ConsumerWidget {
  final Post post;
  final String query;
  const _PostHit({required this.post, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final author = ref.watch(userByIdProvider(post.authorId));
    return Tappable(
      // 修复 Web 版 bug 2:纯动态 quoteProjectId=null 整卡跳 postDetail(不跳 detail)。
      // 引用项目的动态也跳 postDetail — 详情页内部展示 quote 并可独立点入 detail。
      onTap: () => context.push(KkRoutes.postDetail(post.id)),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.lg,
          vertical: KkSpacing.md,
        ),
        decoration: const BoxDecoration(
          color: KkColors.bgCard,
          border: Border(bottom: BorderSide(color: KkColors.divider)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 作者行
            Row(
              children: [
                KkAvatar(userId: post.authorId, user: author, size: 20),
                const SizedBox(width: KkSpacing.xs),
                Flexible(
                  child: Text(
                    author?.name ?? post.authorId,
                    style: KkType.bodySm.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: KkSpacing.sm),
                Text(
                  timeAgo(post.createdAtMs),
                  style: KkType.mono.copyWith(fontSize: 11, color: KkColors.t3),
                ),
                const Spacer(),
                if (post.quoteProjectId != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KkSpacing.xs,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: KkColors.mint,
                      borderRadius: BorderRadius.circular(KkRadius.sm),
                    ),
                    child: Text(
                      '引用项目',
                      style: KkType.mono.copyWith(
                        fontSize: 10,
                        color: KkColors.teal,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: KkSpacing.sm),
            HighlightedText(
              text: post.content,
              query: query,
              baseStyle: KkType.body.copyWith(height: 1.5),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (post.tags.isNotEmpty) ...[
              const SizedBox(height: KkSpacing.sm),
              Wrap(
                spacing: KkSpacing.xs,
                runSpacing: KkSpacing.xs,
                children: [
                  for (final t in post.tags)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KkSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: KkColors.mint,
                        borderRadius: BorderRadius.circular(KkRadius.sm),
                      ),
                      child: HighlightedText(
                        text: '#$t',
                        query: query,
                        baseStyle: KkType.bodySm.copyWith(
                          color: KkColors.teal,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: KkSpacing.sm),
            Row(
              children: [
                Icon(Icons.favorite_border, size: 12, color: KkColors.t3),
                const SizedBox(width: 2),
                Text(
                  formatCount(post.likes),
                  style: KkType.mono.copyWith(fontSize: 11, color: KkColors.t3),
                ),
                const SizedBox(width: KkSpacing.lg),
                Icon(Icons.chat_bubble_outline, size: 12, color: KkColors.t3),
                const SizedBox(width: 2),
                Text(
                  // F-8c:评论数取 commentsFor(post.id).length(与动态详情页同源)。
                  formatCount(commentsFor(post.id).length),
                  style: KkType.mono.copyWith(fontSize: 11, color: KkColors.t3),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 用户 Tab — 用户行(头像 + 名字 + bio + 关注按钮,整行 → profile)
// ──────────────────────────────────────────────────────────────────

class _UsersTab extends ConsumerWidget {
  final String query;
  const _UsersTab({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 远端模式：后端 GET /users/search?q=（昵称/简介）。demo/本地：内存搜索。
    if (AppConfig.useRemote) {
      final async = ref.watch(searchUsersProvider(query));
      return async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: EmptyState(variant: EmptyStateVariant.generic),
        ),
        data: _list,
      );
    }
    return _list(ref.watch(searchRepositoryProvider).searchUsers(query));
  }

  Widget _list(List<KkUser> list) {
    if (list.isEmpty) {
      return const Center(
        child: EmptyState(variant: EmptyStateVariant.generic),
      );
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, i) => _UserRow(user: list[i], query: query),
    );
  }
}

class _UserRow extends ConsumerWidget {
  final KkUser user;
  final String query;
  const _UserRow({required this.user, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tappable(
      onTap: () => context.push(KkRoutes.profile(user.id)),
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
          children: [
            KkAvatar(userId: user.id, user: user, size: 40),
            const SizedBox(width: KkSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  HighlightedText(
                    text: user.name,
                    query: query,
                    baseStyle:
                        KkType.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  // @handle：稳定用户名，改名也能靠它搜到人（搜索命中时高亮）。
                  if (user.handle != null && user.handle!.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    HighlightedText(
                      text: '@${user.handle!}',
                      query: query.replaceAll('@', ''),
                      baseStyle: KkType.mono
                          .copyWith(fontSize: 11, color: KkColors.t3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (user.bio != null) ...[
                    const SizedBox(height: 2),
                    HighlightedText(
                      text: user.bio!,
                      query: query,
                      baseStyle: KkType.bodySm.copyWith(color: KkColors.t3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    '${formatCount(user.followingIds.length)} 关注 · ${formatCount(user.followerIds.length)} 粉丝',
                    style: KkType.mono.copyWith(
                      fontSize: 11,
                      color: KkColors.t4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: KkSpacing.md),
            _FollowButton(userId: user.id),
          ],
        ),
      ),
    );
  }
}

class _FollowButton extends ConsumerWidget {
  final String userId;
  const _FollowButton({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following =
        ref.watch(appStateProvider).followedUserIds.contains(userId);
    return Tappable(
      onTap: () => ref.read(appStateProvider.notifier).toggleFollow(userId),
      borderRadius: BorderRadius.circular(KkRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: KkSpacing.xs,
          horizontal: KkSpacing.md,
        ),
        decoration: BoxDecoration(
          color: following ? KkColors.bgSubtle : KkColors.teal,
          borderRadius: BorderRadius.circular(KkRadius.pill),
          border: following ? Border.all(color: KkColors.bd) : null,
        ),
        child: Text(
          following ? '已关注' : '+ 关注',
          style: TextStyle(
            color: following ? KkColors.t2 : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'NotoSerifSC',
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 话题 Tab — 话题行(#tag teal w600 + 副文 mono t3)
// **修复 Web 版 bug 1:hashtag 跳空 —— 整行 → KkRoutes.topic(tag)(不丢回搜索框)**
// ──────────────────────────────────────────────────────────────────

class _TopicsTab extends ConsumerWidget {
  final String query;
  const _TopicsTab({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 远端模式：/topics 全量后按子串筛。demo/本地：内存聚合搜索。
    if (AppConfig.useRemote) {
      final async = ref.watch(searchTopicsProvider(query));
      return async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: EmptyState(variant: EmptyStateVariant.generic),
        ),
        data: _list,
      );
    }
    return _list(ref.watch(searchRepositoryProvider).searchTopics(query));
  }

  Widget _list(List<Topic> list) {
    if (list.isEmpty) {
      return const Center(
        child: EmptyState(variant: EmptyStateVariant.generic),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: KkSpacing.sm),
      itemCount: list.length,
      itemBuilder: (context, i) => _TopicRow(topic: list[i], query: query),
    );
  }
}

class _TopicRow extends StatelessWidget {
  final Topic topic;
  final String query;
  const _TopicRow({required this.topic, required this.query});

  @override
  Widget build(BuildContext context) {
    return Tappable(
      // 修复 Web 版 bug 1:hashtag 跳空 —— 点话题 → KkRoutes.topic(tag)
      onTap: () => context.push(KkRoutes.topic(topic.tag)),
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
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  HighlightedText(
                    text: '#${topic.tag}',
                    query: query,
                    baseStyle: KkType.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: KkColors.teal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${topic.projectCount} 项目 · ${topic.postCount} 动态 · ${topic.heat}',
                    style: KkType.mono.copyWith(
                      color: KkColors.t3,
                      fontSize: 11,
                    ),
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
}

// ──────────────────────────────────────────────────────────────────
// _CorrectionCard — 全空结果时的「你是不是想搜:X」纠错建议卡(Phase 5)
// ──────────────────────────────────────────────────────────────────

/// Phase 5 智能纠错卡片(HANDOFF §6.2 — levenshtein 工具 4-d 子代理创建)。
///
/// 当 searchRepository.counts(q).total == 0 且 [suggestClosest] 找到近邻候选词时,
/// 在 EmptyState 上方挂此卡。点击 → `context.push(KkRoutes.searchResults(suggestion))`
/// 重新搜索候选词。
///
/// 文案铁律(HANDOFF §3 零旁白):陈述性「你是不是想搜:」,不写「猜你想搜」等引导。
/// 触控铁律(HANDOFF §5):外层 Tappable(minSize 默认 KkTouch.minTarget = 44pt)。
/// 配色铁律(HANDOFF §4):只用 KkColors.*(bgSubtle / teal / t3),无禁止色板。
class _CorrectionCard extends StatelessWidget {
  final String suggestion;
  final VoidCallback onTap;

  const _CorrectionCard({
    required this.suggestion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Container(
        padding: const EdgeInsets.all(KkSpacing.lg),
        decoration: BoxDecoration(
          color: KkColors.bgSubtle,
          borderRadius: BorderRadius.circular(KkRadius.md),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 18, color: KkColors.teal),
            const SizedBox(width: KkSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '你是不是想搜:',
                    style: KkType.bodySm.copyWith(color: KkColors.t3),
                  ),
                  Text(
                    suggestion,
                    style: KkType.body.copyWith(
                      color: KkColors.teal,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: KkSpacing.sm),
            const Icon(Icons.chevron_right, size: 18, color: KkColors.t3),
          ],
        ),
      ),
    );
  }
}
