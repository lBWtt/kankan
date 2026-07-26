import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/kk_back_button.dart';
import '../../core/widgets/tappable.dart';
import '../../domain/models/models.dart';
import '../../providers/search_provider.dart';
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
    final topicsAsync = ref.watch(topTopicsProvider(30));

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
      body: topicsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ListView(
          children: const [EmptyState(variant: EmptyStateVariant.generic)],
        ),
        data: (topics) => topics.isEmpty
            ? ListView(
                children: const [
                  EmptyState(variant: EmptyStateVariant.generic),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  KkSpacing.lg,
                  KkSpacing.md,
                  KkSpacing.lg,
                  KkSpacing.xxl,
                ),
                children: [
                  // TOP3 用上方大卡展示；下方长条从第 4 名起，避免重复。
                  if (topics.length >= 3) ...[
                    _HotStage(topics: topics.take(3).toList()),
                    const SizedBox(height: KkSpacing.lg),
                  ],
                  for (int i = (topics.length >= 3 ? 3 : 0);
                      i < topics.length;
                      i++)
                    _TopicRow(
                      rank: i + 1,
                      topic: topics[i],
                      onTap: () => context.push(KkRoutes.topic(topics[i].tag)),
                    ),
                ],
              ),
      ),
    );
  }
}

class _HotStage extends StatelessWidget {
  final List<Topic> topics;

  const _HotStage({required this.topics});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KkSpacing.md),
      decoration: BoxDecoration(
        color: KkColors.bgCard,
        borderRadius: BorderRadius.circular(KkRadius.lg),
        boxShadow: KkElevation.card,
      ),
      child: Row(
        children: [
          for (int i = 0; i < topics.length; i++) ...[
            Expanded(child: _HotTopicCard(rank: i + 1, topic: topics[i])),
            if (i != topics.length - 1) const SizedBox(width: KkSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _HotTopicCard extends StatelessWidget {
  final int rank;
  final Topic topic;

  const _HotTopicCard({required this.rank, required this.topic});

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: () => context.push(KkRoutes.topic(topic.tag)),
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Container(
        padding: const EdgeInsets.all(KkSpacing.md),
        decoration: BoxDecoration(
          color: rank == 1 ? KkColors.mint : KkColors.bgSubtle,
          borderRadius: BorderRadius.circular(KkRadius.md),
          border: Border.all(color: rank == 1 ? KkColors.mint : KkColors.bd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TOP $rank',
              style: KkType.mono.copyWith(
                fontSize: 10,
                color: rank == 1 ? KkColors.teal : KkColors.t3,
              ),
            ),
            const SizedBox(height: KkSpacing.sm),
            Text(
              '#${topic.tag}',
              style: KkType.body.copyWith(
                color: KkColors.t1,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '${topic.projectCount} 项目 · ${topic.postCount} 动态',
              style: KkType.mono.copyWith(fontSize: 10, color: KkColors.t3),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

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
    final hot = rank <= 3;
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Container(
        margin: const EdgeInsets.only(bottom: KkSpacing.sm),
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
            SizedBox(
              width: 28,
              child: Text(
                rank.toString().padLeft(2, '0'),
                style: KkType.mono.copyWith(
                  fontSize: 12,
                  color: hot ? KkColors.teal : KkColors.t3,
                  fontWeight: hot ? FontWeight.w700 : FontWeight.w500,
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
            Text(
              '${topic.projectCount} 项目 · ${topic.postCount} 动态',
              style: KkType.mono.copyWith(
                fontSize: 11,
                color: KkColors.t3,
              ),
            ),
            const SizedBox(width: KkSpacing.xs),
            const Icon(Icons.chevron_right, size: 18, color: KkColors.t3),
          ],
        ),
      ),
    );
  }
}
