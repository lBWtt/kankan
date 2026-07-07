import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/kk_back_button.dart';
import '../../core/widgets/tappable.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/search_repository.dart';
import '../../router/routes.dart';
import '../shared/empty_state.dart';

/// 任务⑬B:话题广场 — 热门话题榜(全话题按 heat 降序)。
///
/// 现状(任务前):只有单个话题页 /topic/:tag,没有话题广场/今日话题入口。
/// 本屏 = 全话题 Top 30 榜,发现页「今日话题 → 话题广场」入口直达此。
///
/// 数据(复用,禁编造):
///   - searchRepository.topTopics(limit:30) → 复用 searchTopics('') 聚合,
///     heat = projectCount×10 + postCount×5 + totalLikes÷100(SPEC §6.4)。
///   - 按 heat 降序,取前 30。
///
/// 行布局:名次(mono t3)+ #tag(t1 w600)+ {projectCount} 项目 · {postCount} 动态
///   (mono t3 11px)+ chevron。整行 Tappable → topic(tag)。
///
/// 铁律(SPEC §6):
///   - coral 只给 take——话题/热度/入口一律 teal 或中性,不用 coral。
///   - 无 emoji(用 # + Icon);零旁白(标题就是"话题广场",无副标题)。
///   - 触控 ≥44pt(Tappable);计数真实聚合(SPEC §6.4 禁编造)。
class TopicPlazaScreen extends ConsumerWidget {
  const TopicPlazaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topics = ref.watch(searchRepositoryProvider).topTopics(limit: 30);

    return Scaffold(
      backgroundColor: KkColors.bg,
      appBar: AppBar(
        backgroundColor: KkColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const KkBackButton(),
        titleSpacing: 0,
        title: Text('话题广场', style: KkType.h2),
      ),
      body: topics.isEmpty
          ? ListView(
              children: const [
                EmptyState(variant: EmptyStateVariant.generic),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: KkSpacing.xxl),
              itemCount: topics.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: KkColors.divider, indent: 44),
              itemBuilder: (context, i) => _TopicRow(
                rank: i + 1,
                topic: topics[i],
                onTap: () => context.push(KkRoutes.topic(topics[i].tag)),
              ),
            ),
    );
  }
}

/// 话题榜行:名次 + #tag + 计数 + chevron。
///
/// 名次:mono t3 w600,固定宽 28(对齐两位数)。Top 3 不上色(克制,避免
/// 与榜单页 medal 色系重复且 coral 铁律禁用),统一 t3。
class _TopicRow extends StatelessWidget {
  final int rank;
  final Topic topic;
  final VoidCallback onTap;

  const _TopicRow({
    required this.rank,
    required this.topic,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.lg,
          vertical: KkSpacing.md,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                style: KkType.mono.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: KkColors.t3,
                ),
              ),
            ),
            const SizedBox(width: KkSpacing.sm),
            Expanded(
              child: Text(
                '#${topic.tag}',
                style: KkType.body.copyWith(
                  color: KkColors.t1,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: KkSpacing.sm),
            Text(
              '${topic.projectCount} 项目 · ${topic.postCount} 动态',
              style: KkType.mono.copyWith(fontSize: 11, color: KkColors.t3),
            ),
            const SizedBox(width: KkSpacing.xs),
            const Icon(Icons.chevron_right, size: 18, color: KkColors.t4),
          ],
        ),
      ),
    );
  }
}
