import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../providers/app_state_provider.dart';
import '../../providers/project_provider.dart';
import '../../router/routes.dart';
import 'avatar.dart';
import 'image_lightbox.dart';
import 'report_sheet.dart';

/// HANDOFF §1 动态卡(轻)— 发现页 feed 用。
///
/// 动态二分:文字 + 可选图 + 话题 + 引用项目(浮窗)。
/// 没有 resultData / actions(那是 Project 的)。
///
/// 任务⑮:补配图网格(1/2/3/4-9 布局)+ 引用卡改浅绿底 + 分类徽标。
///
/// 零旁白(HANDOFF §3):无"点赞 +1"等引导,只图标 + 真实数字。
/// 计数铁律(HANDOFF §6.10):likes/commentCount 取真实数组长度。
class PostCard extends ConsumerWidget {
  final Post post;
  final VoidCallback? onCommentTap;

  /// 整卡点击(→ 动态详情)。null 时仅内部热区可点(头像/作者名/引用/点赞/评论)。
  final VoidCallback? onTap;

  const PostCard({
    super.key,
    required this.post,
    this.onCommentTap,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final author = ref.watch(userByIdProvider(post.authorId));
    final appState = ref.watch(appStateProvider);
    final isLiked = appState.likedItemIds.contains(post.id);
    final likeCount = post.likes + (isLiked ? 1 : 0);
    // P2-i18n / 无障碍:点赞 / 评论 icon-only 按钮的 semanticLabel 接 KkStrings。
    // 整卡 Tappable 也传 semanticLabel(读屏念「动态:<作者>」)。
    final s = ref.watch(kkStringsProvider);

    final card = Container(
      decoration: const BoxDecoration(
        color: KkColors.bgCard,
        border: Border(
          bottom: BorderSide(color: KkColors.divider),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 作者行(顶对齐:名字/头像/关注按钮都贴顶,名字不再垂直居中)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TappableAvatar(
                userId: post.authorId,
                user: author,
                size: 36,
                onTap: () => context.push(KkRoutes.profile(post.authorId)),
              ),
              const SizedBox(width: KkSpacing.md),
              Expanded(
                // 修 bug:原来用 Tappable 包名字块,其内部 Center + minHeight44
                // 把名字垂直居中在 44px 盒里(用户反馈"名字在中间")。改自适应
                // GestureDetector,名字块贴顶显示。
                child: GestureDetector(
                  onTap: () => context.push(KkRoutes.profile(post.authorId)),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        author?.name ?? post.authorId,
                        style: KkType.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      // 第二行「简介 · 时间」对齐原型(简介≈作者角色;无简介退回 @id)。
                      Text(
                        '${(author?.bio != null && author!.bio!.isNotEmpty) ? author.bio : '@${post.authorId}'} · ${timeAgo(post.createdAtMs)}',
                        style: KkType.bodySm.copyWith(
                          fontSize: 12,
                          color: KkColors.t3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              _FollowButton(userId: post.authorId),
            ],
          ),
          const SizedBox(height: KkSpacing.md),
          // 正文
          Text(post.content, style: KkType.body.copyWith(height: 1.6)),
          // 配图网格(任务⑮A:1/2/3/4-9 布局,放正文下、标签/引用上)
          if (post.media.isNotEmpty) ...[
            const SizedBox(height: KkSpacing.md),
            _ImageGrid(media: post.media),
          ],
          // 标签(无 emoji,纯 #tag)
          if (post.tags.isNotEmpty) ...[
            const SizedBox(height: KkSpacing.sm),
            Wrap(
              spacing: KkSpacing.sm,
              runSpacing: KkSpacing.xs,
              children: [
                for (final t in post.tags)
                  Text(
                    '#$t',
                    style: KkType.bodySm.copyWith(color: KkColors.teal),
                  ),
              ],
            ),
          ],
          // 引用项目浮窗
          if (post.quoteProjectId != null) ...[
            const SizedBox(height: KkSpacing.md),
            _QuoteProject(projectId: post.quoteProjectId!),
          ],
          // 操作行:点赞 / 评论
          const SizedBox(height: KkSpacing.md),
          Row(
            children: [
              // 任务 C:点赞用 KkReactionButton——点亮 scale 弹 + haptic。
              // P2-无障碍:icon-only 按钮传 semanticLabel,读屏念「点赞 <n>」。
              KkReactionButton(
                icon: isLiked ? Icons.favorite : Icons.favorite_border,
                value: formatCount(likeCount),
                color: isLiked ? KkColors.like : KkColors.t3,
                isLit: isLiked,
                iconSize: 16,
                padding: const EdgeInsets.symmetric(
                  vertical: KkSpacing.sm,
                  horizontal: KkSpacing.xs,
                ),
                semanticLabel: '${s.like} ${formatCount(likeCount)}',
                onTap: () => ref
                    .read(appStateProvider.notifier)
                    .togglePostLike(post.id),
              ),
              const SizedBox(width: KkSpacing.lg),
              _IconStat(
                icon: Icons.chat_bubble_outline,
                // F-8:评论数取 commentsFor(post.id).length(与详情页 / 卡片同源),
                // 不用写死的 post.commentCount(D 类 bug 在 feed 复现)。
                value: formatCount(commentsFor(post.id).length),
                color: KkColors.t3,
                // P2-无障碍:icon-only 按钮传 semanticLabel,读屏念「评论 <n>」。
                semanticLabel:
                    '${s.comment} ${formatCount(commentsFor(post.id).length)}',
                // 默认:推全屏评论页(HANDOFF §6.1)。调用方可覆盖(如 discover 用底部弹层)。
                onTap: onCommentTap ??
                    () => context.push(KkRoutes.comments('post', post.id)),
              ),
              const Spacer(),
            ],
          ),
        ],
      ),
    );

    // 整卡点击 + 长按快捷菜单(内部热区优先,手势竞技场自然分离)。
    // D4:长按弹快捷菜单(不感兴趣 / 复制链接 / 举报),复用 _sheetItem 风格。
    // P2-无障碍:整卡 Tappable 传 semanticLabel,读屏念「动态:<作者名>」。
    return Tappable(
      onTap: onTap,
      onLongPress: () => _showQuickMenu(context, ref),
      borderRadius: BorderRadius.zero,
      semanticLabel: s.postSemantic(author?.name ?? post.authorId),
      child: card,
    );
  }

  // ── D4:长按动态卡快捷菜单 ──
  // 不感兴趣 → markNotInterested + toast「已减少类似推荐」(feed 重建过滤该动态);
  // 复制链接 → Clipboard + toast「链接已复制」(分享 URL 同 post_detail share_sheet);
  // 举报 → 复用 showReportSheet(prompt 说占位 toast,但 report_sheet 已是真举报,
  //   post_detail/profile/comment 多处复用;为一致性调真 sheet,不在长按菜单新写网络)。
  // sheetCtx 只用于关 quick menu;showReportSheet 用外层 context(pop 后 sheetCtx 失效)。
  void _showQuickMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KkColors.bgCard,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetItem(
              icon: Icons.visibility_off_outlined,
              label: '不感兴趣',
              onTap: () {
                final messenger = ScaffoldMessenger.maybeOf(sheetCtx);
                Navigator.pop(sheetCtx);
                ref
                    .read(appStateProvider.notifier)
                    .markNotInterested(post.id);
                messenger?.showSnackBar(
                  const SnackBar(
                    content: Text('已减少类似推荐'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            const Divider(height: 1, color: KkColors.divider),
            _sheetItem(
              icon: Icons.link_outlined,
              label: '复制链接',
              onTap: () async {
                final messenger = ScaffoldMessenger.maybeOf(sheetCtx);
                Navigator.pop(sheetCtx);
                await Clipboard.setData(
                  ClipboardData(text: 'https://kankan.app/post/${post.id}'),
                );
                messenger?.showSnackBar(
                  const SnackBar(
                    content: Text('链接已复制'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            const Divider(height: 1, color: KkColors.divider),
            _sheetItem(
              icon: Icons.flag_outlined,
              label: '举报',
              onTap: () {
                Navigator.pop(sheetCtx);
                showReportSheet(
                  context,
                  targetType: 'post',
                  targetId: post.id,
                );
              },
            ),
            const Divider(height: 1, color: KkColors.divider),
            _sheetItem(
              icon: Icons.close,
              label: '取消',
              onTap: () => Navigator.pop(sheetCtx),
            ),
          ],
        ),
      ),
    );
  }
}

// ── D4:长按菜单 item(复用 post_detail _sheetItem 风格,不提取公共组件避免改动面)──
Widget _sheetItem({
  required IconData icon,
  required String label,
  Color? color,
  VoidCallback? onTap,
}) {
  return Tappable(
    onTap: onTap,
    borderRadius: BorderRadius.zero,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.md,
        vertical: KkSpacing.md,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? KkColors.t2),
          const SizedBox(width: KkSpacing.md),
          Text(
            label,
            style: KkType.body.copyWith(color: color ?? KkColors.t1),
          ),
        ],
      ),
    ),
  );
}

// ── 任务⑮A:配图网格(按张数布局,小红书/朋友圈式)──
//
// 1 张 → 单大图(16:9,圆角 md)
// 2 张 → 并排(1:1,中间 xs 间距)
// 3 张 → 一行三(1:1)
// 4–9 张 → 3 列九宫格(1:1)
// >9 张 → 只显前 9,第 9 张叠「+N」遮罩
// 每张:Image.network(loadingBuilder/errorBuilder 回退 CoverArt,同 project_card);
// video 叠 play 图标。
//
// 任务 A:图片格点 → openImageLightbox(全屏缩放);视频格不进灯箱。
class _ImageGrid extends StatelessWidget {
  final List<MediaItem> media;

  const _ImageGrid({required this.media});

  @override
  Widget build(BuildContext context) {
    final shown = media.take(9).toList();
    final count = shown.length;
    final overflow = media.length - 9; // >0 表示有溢出

    // 任务 A:灯箱只收图片 url(video 排除),供 _GridCell onTap 用。
    final imageUrls = [for (final m in shown) if (m.type != 'video') m.url];

    if (count == 1) {
      // 单大图 16:9
      return _GridCell(
        media: shown[0],
        aspect: 16 / 9,
        borderRadius: KkRadius.md,
        overlayCount: overflow > 0 ? overflow : null,
        imageUrls: imageUrls,
        imageIndex: shown[0].type != 'video' ? 0 : null,
      );
    }

    if (count == 2) {
      return Row(
        children: [
          Expanded(
              child: _GridCell(
                  media: shown[0],
                  aspect: 1,
                  imageUrls: imageUrls,
                  imageIndex: shown[0].type != 'video' ? 0 : null)),
          const SizedBox(width: KkSpacing.xs),
          Expanded(
              child: _GridCell(
                  media: shown[1],
                  aspect: 1,
                  imageUrls: imageUrls,
                  imageIndex: shown[1].type != 'video'
                      ? (shown[0].type != 'video' ? 1 : 0)
                      : null)),
        ],
      );
    }

    if (count == 3) {
      return Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            Expanded(
                child: _GridCell(
                    media: shown[i],
                    aspect: 1,
                    imageUrls: imageUrls,
                    imageIndex: _imageIndexOf(imageUrls, shown, i))),
            if (i < 2) const SizedBox(width: KkSpacing.xs),
          ],
        ],
      );
    }

    // 4–9 张:3 列九宫格(AspectRatio 1:1,间距 xs)
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: KkSpacing.xs,
      crossAxisSpacing: KkSpacing.xs,
      childAspectRatio: 1,
      children: [
        for (var i = 0; i < count; i++)
          _GridCell(
            media: shown[i],
            aspect: 1,
            overlayCount: (i == 8 && overflow > 0) ? overflow : null,
            imageUrls: imageUrls,
            imageIndex: _imageIndexOf(imageUrls, shown, i),
          ),
      ],
    );
  }

  /// 计算该格在 imageUrls 中的下标(视频格返回 null → 不开灯箱)。
  /// 按该格在 shown 里的位置 i,数它之前有多少张图片。
  int? _imageIndexOf(List<String> imageUrls, List<MediaItem> shown, int i) {
    if (shown[i].type == 'video') return null;
    var idx = 0;
    for (var j = 0; j < i; j++) {
      if (shown[j].type != 'video') idx++;
    }
    return idx < imageUrls.length ? idx : null;
  }
}

// ── 单格(Image.network + CoverArt 回退;video 叠 play;溢出叠+N)──
// 任务 A:imageIndex != null → 图片格,Tappable 包裹开灯箱;video 不包。
class _GridCell extends StatelessWidget {
  final MediaItem media;
  final double aspect;
  final double borderRadius;
  final int? overlayCount; // >0 时叠「+N」遮罩(仅溢出末格)
  /// 图片格:该格在 imageUrls 中的下标(非 null → 点开灯箱)。
  /// 视频格:null(不进灯箱)。
  final List<String> imageUrls;
  final int? imageIndex;

  const _GridCell({
    required this.media,
    required this.aspect,
    required this.imageUrls,
    this.imageIndex,
    this.borderRadius = KkRadius.sm,
    this.overlayCount,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo = media.type == 'video';
    final url = isVideo ? (media.poster ?? media.url) : media.url;
    final cell = AspectRatio(
      aspectRatio: aspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 图/封面:有 URL → Image.network(loading/error 回退 CoverArt);
            // 无 URL → CoverArt 占位(同 project_card 套路,不引新依赖)
            if (url.isNotEmpty)
              Image.network(
                url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const CoverArt(pattern: 'grid');
                },
                errorBuilder: (context, error, stackTrace) =>
                    const CoverArt(pattern: 'grid'),
              )
            else
              const CoverArt(pattern: 'grid'),
            // video 叠 play 图标
            if (isVideo)
              Center(
                child: Icon(Icons.play_circle_outline,
                    size: 36, color: Colors.white.withAlpha(220)),
              ),
            // 溢出末格叠「+N」浅黑遮罩
            if (overlayCount != null && overlayCount! > 0)
              Container(
                color: Colors.black.withAlpha(140),
                alignment: Alignment.center,
                child: Text(
                  '+$overlayCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'NotoSerifSC',
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // 任务 A:图片格(imageIndex != null)→ Tappable 包裹开灯箱;video 不包。
    if (imageIndex != null && imageUrls.isNotEmpty) {
      return Tappable(
        onTap: () => openImageLightbox(
          context,
          urls: imageUrls,
          initialIndex: imageIndex!,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        child: cell,
      );
    }
    return cell;
  }
}

// ── 引用项目浮窗(任务⑮B:浅绿底 + 分类徽标)──
class _QuoteProject extends ConsumerWidget {
  final String projectId;

  const _QuoteProject({required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectByIdProvider(projectId));
    return project.when(
      loading: () => const SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (p) {
        if (p == null) return const SizedBox.shrink();
        return Tappable(
          onTap: () => context.push(KkRoutes.detail(p.id)),
          borderRadius: BorderRadius.circular(KkRadius.md),
          child: Container(
            padding: const EdgeInsets.all(KkSpacing.md),
            decoration: BoxDecoration(
              // 浅绿底(原型样式,区别于原 bgSubtle 中性底)
              color: KkColors.mint,
              borderRadius: BorderRadius.circular(KkRadius.md),
            ),
            child: Row(
              children: [
                // 小封面(40×40,圆角,领域色块 + 图标)
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: KkColors.bgCard,
                    borderRadius: BorderRadius.circular(KkRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _domainIcon(p.domain),
                    size: 20,
                    color: KkColors.teal,
                  ),
                ),
                const SizedBox(width: KkSpacing.md),
                // 项目名(t1 粗) + @handle(t3,作者 handle)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p.title,
                        style: KkType.bodySm.copyWith(
                          fontWeight: FontWeight.w700,
                          color: KkColors.t1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@${p.authorId}',
                        style: KkType.mono.copyWith(
                          fontSize: 11,
                          color: KkColors.t3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: KkSpacing.sm),
                // 右上分类徽标(teal 描边 pill + 中文 label)
                _DomainBadge(domain: p.domain),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── 分类徽标(teal 描边 pill + 中文 label,映射同 me _domainLabel)──
class _DomainBadge extends StatelessWidget {
  final String domain;

  const _DomainBadge({required this.domain});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(KkRadius.pill),
        border: Border.all(color: KkColors.teal, width: 0.8),
      ),
      child: Text(
        _domainLabel(domain),
        style: const TextStyle(
          color: KkColors.teal,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          fontFamily: 'NotoSerifSC',
        ),
      ),
    );
  }

  /// 7 领域值 → 中文标签(与 me 页 _domainLabel / profile_edit._domainOptions 同源)。
  static const _map = <String, String>{
    'ai_image': 'AI图',
    'ai_video': 'AI视频',
    'web': '网页',
    'app': 'App',
    'tool': '工具',
    'opensource': '开源',
    'prompt': 'Prompt',
  };

  static String _domainLabel(String value) => _map[value] ?? value;
}

/// 领域 → 图标(同 project_card._domainIcon,引用卡小封面用)。
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
      return Icons.article_outlined;
  }
}

// ── 关注按钮(本地状态,Phase 3 接全局 follow)──
class _FollowButton extends ConsumerWidget {
  final String userId;

  const _FollowButton({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = ref.watch(appStateProvider).followedUserIds.contains(userId);
    return Tappable(
      onTap: () =>
          ref.read(appStateProvider.notifier).toggleFollow(userId),
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
          following ? '已关注' : '关注',
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

// ── 图标 + 数字按钮(44pt 热区)──
class _IconStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  /// P2-无障碍:可选语义标签(icon-only 按钮必须传)。透传到 Tappable。
  final String? semanticLabel;

  const _IconStat({
    required this.icon,
    required this.value,
    required this.color,
    this.onTap,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: KkSpacing.sm,
          horizontal: KkSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: KkType.mono.copyWith(fontSize: 12, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
