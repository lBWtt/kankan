import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/kk_back_button.dart';
import '../../core/widgets/tappable.dart';
import '../../domain/models/topic.dart';
import '../../domain/repositories/search_repository.dart';
import '../../providers/app_state_provider.dart';
import '../../router/routes.dart';

/// 搜索屏 — HANDOFF §3 零旁白。
///
/// Phase 4 三块:
///   1. 输入框(autofocus,实时回车跳 results,带 clear 按钮)
///   2. 输入实时联想(空 → 隐藏):前缀匹配 topics/users/projects 各 3,
///      Tappable → 直接 _submit(建议词)
///   3. 输入为空时:
///      a. 最近搜索按时间分组(今天 / 昨天 / 更早,从 AppStateData
///         .recentSearchesWithTime 派生)
///      b. 热门话题(SearchRepository.searchTopics('') 聚合真实 heat 排序,前 8)
///
/// 点击词条 / 回车 → push /search/results/{query}(HANDOFF §6.7 真路由,可深链)。
/// 零旁白:无"输入你想搜的内容"引导,placeholder 只写"搜索"。
/// 时间分组标题只写"今天/昨天/更早",建议项只显示词 + 类型图标(无引导文案)。
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    // HANDOFF 铁律:setState 前 mounted 防护
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onInputChanged);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String q) {
    final s = q.trim();
    if (s.isEmpty) return;
    ref.read(appStateProvider.notifier).addRecentSearch(s);
    context.push(KkRoutes.searchResults(s));
  }

  @override
  Widget build(BuildContext context) {
    final input = _ctrl.text.trim();
    final searchRepo = ref.watch(searchRepositoryProvider);

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
      body: input.isEmpty
          ? _buildEmptyInput(context, searchRepo)
          : _buildSuggestions(context, searchRepo, input),
    );
  }

  // ── 输入为空:最近搜索(时间分组)+ 热门话题(原 Phase 3 逻辑)──

  Widget _buildEmptyInput(BuildContext context, SearchRepository searchRepo) {
    final recentWithTime = ref.watch(appStateProvider).recentSearchesWithTime;
    final hotTopics = searchRepo.searchTopics('').take(8).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: KkSpacing.md),
      children: [
        if (recentWithTime.isNotEmpty) ...[
          _sectionHeader(
            title: '最近搜索',
            actionLabel: '清空',
            onAction: () => ref
                .read(appStateProvider.notifier)
                .clearRecentSearches(),
          ),
          _recentGrouped(recentWithTime),
          const SizedBox(height: KkSpacing.xl),
        ],
        _sectionHeader(title: '热门话题'),
        if (hotTopics.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KkSpacing.lg,
              vertical: KkSpacing.md,
            ),
            child: Text(
              '暂无',
              style: KkType.bodySm.copyWith(color: KkColors.t4),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
            child: Column(
              children: [
                for (final t in hotTopics) _topicTile(t),
              ],
            ),
          ),
      ],
    );
  }

  /// 最近搜索按时间分组:今天 / 昨天 / 更早。
  /// items 已按时间戳降序排列(最新在前,来自 AppStateData.recentSearchesWithTime)。
  Widget _recentGrouped(List<({String query, int createdAtMs})> items) {
    final now = DateTime.now();
    final todayStart =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    const dayMs = 24 * 60 * 60 * 1000;
    final yesterdayStart = todayStart - dayMs;

    final today = <({String query, int createdAtMs})>[];
    final yesterday = <({String query, int createdAtMs})>[];
    final earlier = <({String query, int createdAtMs})>[];
    for (final e in items) {
      if (e.createdAtMs >= todayStart) {
        today.add(e);
      } else if (e.createdAtMs >= yesterdayStart) {
        yesterday.add(e);
      } else {
        earlier.add(e);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (today.isNotEmpty) ...[
          _groupHeader('今天'),
          _chipWrap(today),
        ],
        if (yesterday.isNotEmpty) ...[
          _groupHeader('昨天'),
          _chipWrap(yesterday),
        ],
        if (earlier.isNotEmpty) ...[
          _groupHeader('更早'),
          _chipWrap(earlier),
        ],
      ],
    );
  }

  Widget _groupHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KkSpacing.lg,
        KkSpacing.sm,
        KkSpacing.lg,
        KkSpacing.xs,
      ),
      child: Row(
        children: [
          const Icon(Icons.access_time, size: 14, color: KkColors.t4),
          const SizedBox(width: KkSpacing.xs),
          Text(
            title,
            style: KkType.bodySm.copyWith(color: KkColors.t4, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _chipWrap(List<({String query, int createdAtMs})> items) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Wrap(
        spacing: KkSpacing.sm,
        runSpacing: KkSpacing.sm,
        children: [
          for (final e in items)
            _recentChip(
              e.query,
              onTap: () => _submit(e.query),
              onDelete: () => ref
                  .read(appStateProvider.notifier)
                  .removeRecentSearch(e.query),
            ),
        ],
      ),
    );
  }

  // ── 输入非空:实时联想(topics/users/projects 前缀匹配)──

  Widget _buildSuggestions(
    BuildContext context,
    SearchRepository searchRepo,
    String input,
  ) {
    final suggestions = _buildSuggestionList(searchRepo, input);
    if (suggestions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: KkSpacing.xxl),
          child: Text(
            '暂无',
            style: KkType.bodySm.copyWith(color: KkColors.t4),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: KkSpacing.sm),
      itemCount: suggestions.length,
      itemBuilder: (_, i) => _suggestionTile(suggestions[i]),
    );
  }

  /// 前 3 条 topics(tag 前缀)+ 3 条 users(name 前缀)+ 3 条 projects(title 前缀)。
  /// searchRepo.searchXxx(input) 返回 contains 匹配,再本地过滤 startsWith。
  /// (startsWith ⊂ contains,过滤后即前缀匹配结果。)
  List<_Suggestion> _buildSuggestionList(
    SearchRepository searchRepo,
    String input,
  ) {
    final s = input.trim().toLowerCase();
    if (s.isEmpty) return const [];
    final out = <_Suggestion>[];

    // Topics:tag 前缀匹配(取前 3)
    var topicCount = 0;
    for (final t in searchRepo.searchTopics(s)) {
      if (!t.tag.toLowerCase().startsWith(s)) continue;
      out.add(_Suggestion(
        label: '#${t.tag}',
        value: t.tag,
        kind: _Kind.topic,
      ));
      if (++topicCount >= 3) break;
    }
    // Users:name 前缀匹配(取前 3)
    var userCount = 0;
    for (final u in searchRepo.searchUsers(s)) {
      if (!u.name.toLowerCase().startsWith(s)) continue;
      out.add(_Suggestion(
        label: u.name,
        value: u.name,
        kind: _Kind.user,
      ));
      if (++userCount >= 3) break;
    }
    // Projects:title 前缀匹配(取前 3)
    var projectCount = 0;
    for (final p in searchRepo.searchProjects(s)) {
      if (!p.title.toLowerCase().startsWith(s)) continue;
      out.add(_Suggestion(
        label: p.title,
        value: p.title,
        kind: _Kind.project,
      ));
      if (++projectCount >= 3) break;
    }
    return out;
  }

  Widget _suggestionTile(_Suggestion s) {
    final icon = switch (s.kind) {
      _Kind.topic => Icons.tag,
      _Kind.user => Icons.person_outline,
      _Kind.project => Icons.work_outline,
    };
    return Tappable(
      onTap: () => _submit(s.value),
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.lg,
          vertical: KkSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: KkColors.t3),
            const SizedBox(width: KkSpacing.md),
            Expanded(
              child: Text(
                s.label,
                style: KkType.body.copyWith(color: KkColors.t1),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 输入框(Phase 4:加 suffix clear 按钮,新 UX 下清空才能看最近搜索)──

  Widget _searchField() {
    return Container(
      height: 36,
      margin: const EdgeInsets.only(right: KkSpacing.lg),
      decoration: BoxDecoration(
        color: KkColors.bgSubtle,
        borderRadius: BorderRadius.circular(KkRadius.pill),
      ),
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        autofocus: true,
        textInputAction: TextInputAction.search,
        style: KkType.body,
        decoration: InputDecoration(
          hintText: '搜索',
          hintStyle: KkType.body.copyWith(color: KkColors.t4),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: KkSpacing.md,
            vertical: 0,
          ),
          prefixIcon: const Icon(Icons.search, size: 18, color: KkColors.t3),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 36,
          ),
          suffixIcon: _ctrl.text.isNotEmpty
              ? Tappable(
                  onTap: _ctrl.clear,
                  borderRadius: BorderRadius.circular(KkRadius.pill),
                  child:
                      const Icon(Icons.close, size: 16, color: KkColors.t3),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 36,
          ),
          border: InputBorder.none,
        ),
        onSubmitted: _submit,
      ),
    );
  }

  // ── 通用组件 ──

  Widget _sectionHeader({
    required String title,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.sm,
      ),
      child: Row(
        children: [
          Text(title, style: KkType.h3.copyWith(fontSize: 15)),
          const Spacer(),
          if (actionLabel != null && onAction != null)
            Tappable(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KkSpacing.xs,
                  vertical: KkSpacing.xs,
                ),
                child: Text(
                  actionLabel,
                  style: KkType.bodySm.copyWith(color: KkColors.t3),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _recentChip(String q, {VoidCallback? onTap, VoidCallback? onDelete}) {
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KkRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.md,
          vertical: KkSpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: KkColors.bgCard,
          borderRadius: BorderRadius.circular(KkRadius.pill),
          border: Border.all(color: KkColors.bd),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(q, style: KkType.bodySm.copyWith(color: KkColors.t2)),
            const SizedBox(width: KkSpacing.xs),
            Tappable(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(10),
              child: const Icon(Icons.close,
                  size: 12, color: KkColors.t4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topicTile(Topic t) {
    return Tappable(
      onTap: () => _submit(t.tag),
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.sm,
          vertical: KkSpacing.md,
        ),
        child: Row(
          children: [
            // rank 序号(等宽)
            SizedBox(
              width: 28,
              child: Text(
                '#${hotRank(t)}',
                style: KkType.mono.copyWith(
                  color: KkColors.t4,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: KkSpacing.sm),
            // tag
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '#${t.tag}',
                    style: KkType.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: KkColors.teal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${t.projectCount} 项目 · ${t.postCount} 动态',
                    style: KkType.bodySm.copyWith(
                      color: KkColors.t3,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            // heat(等宽数字)
            Text(
              '${t.heat}',
              style: KkType.mono.copyWith(
                color: KkColors.t2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 当前 tile 在 hotTopics 里的序号(从 1 开始)
  int hotRank(Topic t) {
    final all = ref.read(searchRepositoryProvider).searchTopics('');
    return all.indexOf(t) + 1;
  }
}

/// 建议项类型 — 区分 topics / users / projects,仅用于显示类型图标。
enum _Kind { topic, user, project }

class _Suggestion {
  final String label;
  final String value;
  final _Kind kind;
  const _Suggestion({
    required this.label,
    required this.value,
    required this.kind,
  });
}
