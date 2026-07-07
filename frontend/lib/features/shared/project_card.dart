import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/parse_count.dart';
import '../../core/utils/time_ago.dart';
import '../../core/widgets/cover_art.dart';
import '../../core/widgets/kk_reaction_button.dart';
import '../../core/widgets/tappable.dart';
import '../../domain/models/models.dart';
import '../../data/seed/mock_seed.dart';
import '../../l10n/kk_strings.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/project_provider.dart';
import '../../router/routes.dart';
import 'avatar.dart';

/// HANDOFF §1 项目卡(重)— 看看页 / 收藏页 / 我的页共用。
///
/// 项目有成果 + 素材,可进库,有详情页。卡显示:
///   - 封面(有 media 取首张,否则领域色块 + 图标)
///   - 标题 + 一句话价值
///   - 作者 + 领域
///   - 真实计数:点赞 / 心得 / 拿走(HANDOFF §6.10,取真实数组长度,禁编造)
///
/// 零旁白(HANDOFF §3):无"快来围观"之类引导。
///
/// Phase 4 Hero 共享元素(HANDOFF §5 动效系统):
///   - full 模式封面外层包 `Hero(tag: 'project-cover-{project.id}')`,
///     详情页 detail_screen 顶部 cover 用同 tag 配对,实现卡片 → 详情 cover 飞入过渡。
///   - compact 模式(56×56 缩略图)不参与 Hero,避免与 full 模式在同一屏同时
///     渲染同一 project.id 时造成 Hero tag 冲突(Flutter 同 tag 多 Hero 报错)。
///   - **约束**:同一 project.id 在同一屏只能出现一次该 Hero tag。若未来某屏需
///     同时展示 full + compact 同一项目,改用 flightShuttleBuilder 或为 compact
///     单独命名 tag。
///   - tag 命名约定:`'project-cover-{project.id}'`(4-f 子代理在 detail_screen
///     顶部 cover 用同 tag 配对)。
class ProjectCard extends ConsumerWidget {
  final Project project;
  final bool showAuthor;

  /// 紧凑模式(收藏页用,无封面,仅文字行)
  final bool compact;

  const ProjectCard({
    super.key,
    required this.project,
    this.showAuthor = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 埋点:卡片曝光(会话内同项目只记一次)。真后端项目(UUID)才发。
    ref.read(analyticsProvider).trackImpressionOnce(project.id);
    if (compact) return _compact(context, ref);
    return _full(context, ref);
  }

  Widget _full(BuildContext context, WidgetRef ref) {
    final author = ref.watch(userByIdProvider(project.authorId));
    final appState = ref.watch(appStateProvider);
    final isSaved = appState.savedProjectIds.contains(project.id);
    final isLiked = appState.likedItemIds.contains(project.id);
    final likeCount = project.likes + (isLiked ? 1 : 0);
    // P2-i18n / 无障碍:整卡 + 点赞 + 收藏 icon-only 按钮的 semanticLabel。
    final s = ref.watch(kkStringsProvider);

    return Tappable(
      onTap: () {
        ref.read(analyticsProvider).track('card_click', projectId: project.id);
        ref.read(appStateProvider.notifier).recordBrowse(project.id);
        context.push(KkRoutes.detail(project.id));
      },
      borderRadius: BorderRadius.circular(KkRadius.lg),
      // P2-无障碍:整卡 Tappable 传 semanticLabel,读屏念「项目:<标题>」。
      semanticLabel: s.projectSemantic(project.title),
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
            // 封面(Hero 共享元素,4-f 子代理在 detail_screen 顶部用同 tag 配对)
            Hero(
              tag: 'project-cover-${project.id}',
              child: _Cover(project: project),
            ),
            // 内容
            Padding(
              padding: const EdgeInsets.all(KkSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(project.title, style: KkType.h3, maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    project.summary,
                    style: KkType.bodySm,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // 任务④:招牌 take 行(can-takeaway)——summary 下、作者行上。
                  // 有 TakeAction → 珊瑚橙浅底 chip;否则有 GoAction → 退化 teal「去看看」;
                  // 都无(纯 HowAction / 空)→ 整行不显示。禁 if(artifactType) 分支(SPEC §6.1)。
                  if (project.actions.whereType<TakeAction>().isNotEmpty ||
                      project.actions.whereType<GoAction>().isNotEmpty) ...[
                    const SizedBox(height: KkSpacing.sm),
                    _TakeawayChip(actions: project.actions),
                  ],
                  if (showAuthor) ...[
                    const SizedBox(height: KkSpacing.md),
                    Tappable(
                      onTap: () =>
                          context.push(KkRoutes.profile(project.authorId)),
                      borderRadius: BorderRadius.circular(KkRadius.sm),
                      child: Row(
                        children: [
                          KkAvatar(
                              userId: project.authorId, user: author, size: 20),
                          const SizedBox(width: KkSpacing.xs),
                          Text(
                            author?.name ?? project.authorId,
                            style: KkType.bodySm.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: KkSpacing.sm),
                          Text(
                            timeAgo(project.createdAtMs),
                            style: KkType.mono.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: KkSpacing.md),
                  // 真实计数行(HANDOFF §6.10)
                  Row(
                    children: [
                      // 任务 C:点赞用 KkReactionButton——点亮 scale 弹 + haptic。
                      // P2-无障碍:icon-only 按钮传 semanticLabel,读屏念「点赞 <n>」。
                      KkReactionButton(
                        icon: isLiked
                            ? Icons.favorite
                            : Icons.favorite_border,
                        value: formatCount(likeCount),
                        color: isLiked ? KkColors.like : KkColors.t3,
                        isLit: isLiked,
                        iconSize: 14,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 4,
                        ),
                        semanticLabel:
                            '${s.like} ${formatCount(likeCount)}',
                        onTap: () => ref
                            .read(appStateProvider.notifier)
                            .toggleLike(project.id),
                      ),
                      const SizedBox(width: KkSpacing.lg),
                      _Stat(
                        icon: Icons.chat_bubble_outline,
                        // F-9:评论数取 commentsFor(project.id).length(与详情页同源),
                        // 不用写死的 project.commentCount(D 类 bug 在卡片复现)。
                        value: formatCount(commentsFor(project.id).length),
                        color: KkColors.t3,
                      ),
                      if (project.takeawayCount > 0) ...[
                        const SizedBox(width: KkSpacing.lg),
                        _Stat(
                          icon: Icons.download_outlined,
                          value: formatCount(project.takeawayCount),
                          color: KkColors.t3,
                        ),
                      ],
                      const Spacer(),
                      // 收藏(任务 C:用 KkReactionButton——点亮 scale 弹 + haptic)。
                      // P2-无障碍:icon-only 按钮传 semanticLabel,读屏念「收藏」。
                      KkReactionButton(
                        icon: isSaved
                            ? Icons.bookmark
                            : Icons.bookmark_border_outlined,
                        color: isSaved ? KkColors.teal : KkColors.t3,
                        isLit: isSaved,
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        semanticLabel: s.save,
                        onTap: () => ref
                            .read(appStateProvider.notifier)
                            .toggleSave(project.id),
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

  Widget _compact(BuildContext context, WidgetRef ref) {
    // P2-i18n / 无障碍:整卡 Tappable 传 semanticLabel,读屏念「项目:<标题>」。
    final s = ref.watch(kkStringsProvider);
    return Tappable(
      onTap: () {
        ref.read(analyticsProvider).track('card_click', projectId: project.id);
        ref.read(appStateProvider.notifier).recordBrowse(project.id);
        context.push(KkRoutes.detail(project.id));
      },
      semanticLabel: s.projectSemantic(project.title),
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
            // 小封面(B2:Hero 配对详情页 'project-cover-{id}',紧凑卡飞入详情。
            // library/ranking 各自单屏项目唯一,不同屏不冲突,discover 用 _full 不混用)
            Hero(
              tag: 'project-cover-${project.id}',
              child: _Cover(project: project, width: 56, height: 56),
            ),
            const SizedBox(width: KkSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(project.title,
                      style: KkType.body.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    project.summary,
                    style: KkType.bodySm.copyWith(color: KkColors.t3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        // F-9:compact 模式评论数同源 commentsFor(详情页 / full 模式一致)。
                        '${formatCount(project.likes)} 赞 · ${formatCount(commentsFor(project.id).length)} 心得',
                        style: KkType.mono.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: KkColors.t3),
          ],
        ),
      ),
    );
  }
}

// ── 封面(真实封面图 + CoverArt 回退)──
//
// 任务①真实封面图:有 URL → Image.network(loadingBuilder/errorBuilder 回退 CoverArt);
// 无 URL → CoverArt 占位。video 叠 play 按钮;无封面时叠领域图标。
// 外层 ProjectCard Container 已 clipBehavior.antiAlias,_Cover 不再单独 ClipRRect。
class _Cover extends StatelessWidget {
  final Project project;
  final double? width;
  final double? height;

  const _Cover({required this.project, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    final w = width ?? double.infinity;
    final h = height ?? 180.0;
    // compact 模式(传了 width 通常是 56×56):小尺寸用 grid 简化图案,
    // 看不出复杂的波浪 / 山峦 / 水墨细节
    final isCompact = width != null;
    final hasMedia = project.resultData.media.isNotEmpty;
    final first = hasMedia ? project.resultData.media.first : null;
    final isImage = hasMedia && first!.type == 'image';
    final isVideo = hasMedia && first!.type == 'video';
    // 封面 URL:image 用 first.url;video 用 first.poster;无 media → null(走 CoverArt 占位)
    final coverUrl = isImage
        ? first.url
        : (isVideo ? first.poster : null);

    final pattern = isCompact ? 'grid' : _domainPattern(project.domain);
    final domainIcon = _domainIcon(project.domain);

    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 封面:有 URL → Image.network(loadingBuilder/errorBuilder 回退 CoverArt);
          // 无 URL → CoverArt 占位(任务①真实封面图,不引入新依赖)
          if (coverUrl != null && coverUrl.isNotEmpty)
            Image.network(
              coverUrl,
              fit: BoxFit.cover,
              width: w,
              height: h,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return CoverArt(pattern: pattern, width: w, height: h);
              },
              errorBuilder: (context, error, stackTrace) =>
                  CoverArt(pattern: pattern, width: w, height: h),
            )
          else
            CoverArt(pattern: pattern, width: w, height: h),
          // 半透明压暗遮罩,让前景 play / domain icon 更突出
          Container(color: Colors.black.withAlpha(20)),
          // 前景:video 叠 play 按钮(真图上);无封面时叠领域图标(有真图不叠,图本身即视觉)
          if (isVideo)
            Center(
              child: Icon(Icons.play_circle_outline,
                  size: 48, color: Colors.white.withAlpha(220)),
            )
          else if (coverUrl == null || coverUrl.isEmpty)
            Center(
              child: Icon(domainIcon,
                  size: 36, color: Colors.white.withAlpha(200)),
            ),
        ],
      ),
    );
  }

  IconData _domainIcon(String domain) {
    switch (domain) {
      case 'ai_image':
        return Icons.image_outlined;
      case 'ai_video':
        return Icons.play_circle_outline;
      case 'web':
        return Icons.language;
      case 'app':
        return Icons.phone_iphone;
      case 'tool':
        return Icons.build_outlined;
      case 'opensource':
        return Icons.code;
      case 'prompt':
        return Icons.chat_bubble_outline;
      default:
        return Icons.work_outline;
    }
  }

  /// 领域 → CoverArt 图案映射(HANDOFF §5 装饰用,5 种图案对应不同领域语义)
  ///
  /// - ai_image   → circles(同心圆,呼应图像生成的扩散感)
  /// - ai_video   → waves(波浪,呼应视频流动)
  /// - web        → grid(网格,呼应网页结构)
  /// - app        → mountains(山峦,呼应 app 层叠架构)
  /// - tool       → grid(网格,工具感)
  /// - opensource → ink(水墨,开源文化感)
  /// - prompt     → waves(波浪,文字流动)
  /// - 兜底        → mountains
  String _domainPattern(String domain) {
    switch (domain) {
      case 'ai_image':
        return 'circles';
      case 'ai_video':
        return 'waves';
      case 'web':
        return 'grid';
      case 'app':
        return 'mountains';
      case 'tool':
        return 'grid';
      case 'opensource':
        return 'ink';
      case 'prompt':
        return 'waves';
      default:
        return 'mountains';
    }
  }
}

// ── 计数小标(无 44pt 要求,纯展示)──
class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _Stat({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(value, style: KkType.mono.copyWith(fontSize: 11, color: color)),
      ],
    );
  }
}

// ── 任务④:招牌 take 行(can-takeaway row)──
//
// 在 summary 下、作者行上,显示「能拿走什么 · 怎么用」——本产品最核心 UX,
// 让人一眼看到「能拿到什么、怎么用」,直接驱动「想做/想拿走」意图。原型每张卡都有。
//
// 渲染规则(禁 if(artifactType) 硬编码分支,SPEC §6.1——用 whereType 模式匹配):
// - 有 TakeAction → 珊瑚橙浅底 chip(coralMint 底 + coral 图标/文字);
//   图标按 takeKind:copy → copy_outlined / download → download_outlined;
//   文字 = label · hint(任务④ Part B,hint null 只显 label,向后兼容)。
// - 无 TakeAction 有 GoAction → 退化 teal「去看看」chip(mint 底 + teal 文字 + ↗)。
// - 都无(纯 HowAction / 空)→ 整行不显示(调用方 whereType 判断;此 widget 防御返回 shrink)。
//
// 铁律(SPEC §6):
// - coral 只给 take(go 退化用 teal/mint,不用 coral)。
// - 无「拿走」二字(靠图标 + 名词表意),零旁白,无 emoji。
// - 触控 ≥44pt:此 chip 是「招牌描述」纯展示,点击由卡片整体承担(已 Tappable),
//   故 chip 自身不可点,不强制 44pt(44pt 仅约束可交互元素)。
class _TakeawayChip extends StatelessWidget {
  final List<ActionItem> actions;

  const _TakeawayChip({required this.actions});

  @override
  Widget build(BuildContext context) {
    // 禁 if(artifactType) 硬编码分支(SPEC §6.1)——用 whereType 模式匹配。
    final take = actions.whereType<TakeAction>().firstOrNull;
    if (take != null) return _takeChip(take);
    final go = actions.whereType<GoAction>().firstOrNull;
    if (go != null) return _goChip();
    return const SizedBox.shrink();
  }

  Widget _takeChip(TakeAction take) {
    final isCopy = take.takeKind == 'copy';
    final icon = isCopy ? Icons.copy_outlined : Icons.download_outlined;
    final label = take.label ?? (isCopy ? '复制' : '下载');
    final hasHint = take.hint != null && take.hint!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.sm,
        vertical: 6.0,
      ),
      decoration: BoxDecoration(
        // 珊瑚橙浅底(SPEC §6.2:coral 只给 take)
        color: KkColors.coralMint,
        borderRadius: BorderRadius.circular(KkRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: KkColors.coral),
          const SizedBox(width: KkSpacing.xs),
          Text(
            label,
            style: KkType.bodySm.copyWith(
              fontSize: 12,
              color: KkColors.coral,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hasHint) ...[
            Text(
              ' · ',
              // 微调:分隔点用中性 t3,和 hint 一致(label 才是品牌色焦点)
              style: KkType.bodySm.copyWith(
                fontSize: 12,
                color: KkColors.t3,
              ),
            ),
            Flexible(
              child: Text(
                take.hint!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // 微调:hint「怎么用」用中性 t2,让"拿到什么"(label coral)与
                // "怎么用"(灰)层次分明,不至于整条都珊瑚橙"发满"。
                style: KkType.bodySm.copyWith(
                  fontSize: 12,
                  color: KkColors.t2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _goChip() {
    // 退化:teal「去看看」(mint 底 + teal 文字 + ↗)。不用 coral(SPEC §6.2)。
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.sm,
        vertical: 6.0,
      ),
      decoration: BoxDecoration(
        color: KkColors.mint,
        borderRadius: BorderRadius.circular(KkRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '去看看',
            style: KkType.bodySm.copyWith(
              fontSize: 12,
              color: KkColors.teal,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.arrow_outward,
            size: 14,
            color: KkColors.teal,
          ),
        ],
      ),
    );
  }
}
