// 这个文件是干什么的：审核队列页——管理员刷「待审」候选，一屏扫封面/标题/亮点/分数/风控标，
//   点开进详情做通过/不推荐/暂存/编辑。只在管理员构建（AppConfig.adminBuild）下可达。
// 它对应产品里的什么功能：内容审核后台的主列表（上线后同一份代码变浏览器后台）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../data/api/admin_api.dart';
import '../../router/routes.dart';
import 'admin_labels.dart';

class AdminReviewScreen extends ConsumerWidget {
  const AdminReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(adminQueueProvider);
    return Scaffold(
      backgroundColor: KkColors.bg,
      appBar: AppBar(
        backgroundColor: KkColors.bg,
        elevation: 0,
        title: const Text('内容审核', style: KkType.h3),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh, color: KkColors.t2),
            onPressed: () => ref.invalidate(adminQueueProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: KkColors.teal,
        onRefresh: () async => ref.refresh(adminQueueProvider.future),
        child: queue.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: KkColors.teal),
          ),
          error: (e, _) => _ErrorView(
            message: '$e',
            onRetry: () => ref.invalidate(adminQueueProvider),
          ),
          data: (items) {
            if (items.isEmpty) return const _EmptyView();
            return ListView.separated(
              padding: const EdgeInsets.all(KkSpacing.lg),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: KkSpacing.md),
              itemBuilder: (_, i) => _QueueCard(candidate: items[i]),
            );
          },
        ),
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  final AdminCandidate candidate;
  const _QueueCard({required this.candidate});

  @override
  Widget build(BuildContext context) {
    final cover = candidate.resolvedCover;
    return InkWell(
      borderRadius: BorderRadius.circular(KkRadius.md),
      onTap: () => context.push(KkRoutes.adminCandidate(candidate.id)),
      child: Container(
        decoration: BoxDecoration(
          color: KkColors.bgCard,
          borderRadius: BorderRadius.circular(KkRadius.md),
          border: Border.all(color: KkColors.bd),
          boxShadow: KkElevation.card,
        ),
        padding: const EdgeInsets.all(KkSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面缩略
            ClipRRect(
              borderRadius: BorderRadius.circular(KkRadius.sm),
              child: SizedBox(
                width: 72,
                height: 72,
                child: cover == null
                    ? Container(
                        color: KkColors.bgSubtle,
                        child: const Icon(Icons.image_not_supported_outlined,
                            color: KkColors.t4, size: 24),
                      )
                    : Image.network(
                        cover,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: KkColors.bgSubtle,
                          child: const Icon(Icons.broken_image_outlined,
                              color: KkColors.t4, size: 24),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: KkSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _ScoreBadge(score: candidate.score),
                      const SizedBox(width: KkSpacing.sm),
                      if (candidate.sourcePlatform != null)
                        Text(
                          platformLabel(candidate.sourcePlatform!),
                          style: KkType.mono.copyWith(color: KkColors.t3),
                        ),
                    ],
                  ),
                  const SizedBox(height: KkSpacing.xs),
                  Text(
                    candidate.title ?? '（无标题）',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KkType.h3.copyWith(fontSize: 15),
                  ),
                  if (candidate.tagline != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      candidate.tagline!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: KkType.bodySm,
                    ),
                  ],
                  if (candidate.riskFlags.isNotEmpty) ...[
                    const SizedBox(height: KkSpacing.sm),
                    Wrap(
                      spacing: KkSpacing.xs,
                      runSpacing: KkSpacing.xs,
                      children: candidate.riskFlags
                          .map((f) => RiskChip(flag: f))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 五维加权分徽章：≥80 绿、65-79 琥珀、其余灰。
class _ScoreBadge extends StatelessWidget {
  final int? score;
  const _ScoreBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final s = score;
    Color bg;
    Color fg;
    if (s == null) {
      bg = KkColors.bgSubtle;
      fg = KkColors.t3;
    } else if (s >= 80) {
      bg = KkColors.mint;
      fg = KkColors.tealDark;
    } else if (s >= 65) {
      bg = const Color(0xFFF6EFDD);
      fg = KkColors.amber;
    } else {
      bg = KkColors.bgSubtle;
      fg = KkColors.t3;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(KkRadius.sm),
      ),
      child: Text(
        s == null ? '未评分' : '$s 分',
        style: KkType.mono
            .copyWith(color: fg, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 160),
        Icon(Icons.inbox_outlined, size: 48, color: KkColors.t4),
        SizedBox(height: KkSpacing.md),
        Center(child: Text('队列空了，等下一批灌料', style: KkType.body)),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(KkSpacing.xl),
      children: [
        const SizedBox(height: 140),
        const Icon(Icons.cloud_off_outlined, size: 48, color: KkColors.t3),
        const SizedBox(height: KkSpacing.md),
        Text(message, textAlign: TextAlign.center, style: KkType.bodySm),
        const SizedBox(height: KkSpacing.lg),
        Center(
          child: OutlinedButton(
            onPressed: onRetry,
            child: const Text('重试'),
          ),
        ),
      ],
    );
  }
}
