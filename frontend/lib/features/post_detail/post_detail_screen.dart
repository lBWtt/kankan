import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/parse_count.dart';
import '../../core/utils/time_ago.dart';
import '../../core/widgets/kk_back_button.dart';
import '../../core/widgets/kk_reaction_button.dart';
import '../../core/widgets/tappable.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/post_repository.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/project_provider.dart';
import '../../providers/remote_post_provider.dart';
import '../../router/routes.dart';
import '../shared/avatar.dart';
import '../shared/comment_thread.dart';
import '../shared/empty_state.dart';
import '../shared/image_lightbox.dart';
import '../shared/report_sheet.dart';
import '../shared/share_sheet.dart';

/// 动态详情页(PostDetailScreen)— HANDOFF §1 轻量详情。
///
/// HANDOFF §1 原文「动态不进库、无详情页」,但 Flutter 迁移规划 §7.4 列为
/// Phase 3 Tier 2 交付物:discover feed 的 post_card 需要点击目标。
/// 折中:此页是 PostCard 内容展开全屏 + CommentThread,不引入 resultData /
/// actions / takeaway(那些是 Project 详情的)。
///
/// 视觉复用 PostCard 的布局(作者行 / 正文 / 标签 / 引用项目 / 操作行),
/// 末尾追加 CommentThread(心得 N + 输入框)。
///
/// 计数铁律(HANDOFF §6.10):
///   - 点赞数 = post.likes + (isLiked ? 1 : 0)
///   - 评论数 = comments.length(CommentThread 内部已用 _comments.length)
/// 零旁白(HANDOFF §3):无「快来分享看法」之类引导。
/// 珊瑚橙(HANDOFF §5):只给 like 图标在已点赞时的情感色,别处禁用。
/// 更多 sheet 的 举报 / 不感兴趣 用 t1 文字,非珊瑚橙。
///
/// 任务 B:评论图标 onTap 原为空(哑火),改 Scrollable.ensureVisible 滚到
/// CommentThread。用 top-level key(单屏同时只一个 post_detail,无冲突)。
final GlobalKey _commentThreadKey =
    GlobalKey(debugLabel: 'postDetailCommentThread');

class PostDetailScreen extends ConsumerWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // mock 优先 + 远程兜底（真数据模式下 uuid 动态从后端拉）。
    final postAsync = ref.watch(postByIdProvider(postId));
    final post = postAsync.value;
    return Scaffold(
      backgroundColor: KkColors.bg,
      appBar: _appBar(context, ref, post),
      body: postAsync.isLoading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(KkColors.teal),
              ),
            )
          : (post == null ? _notFound(context) : _body(context, ref, post)),
    );
  }

  // ── 顶栏:返回 / 作者名(单行 ellipsis)/ 更多 ──
  PreferredSizeWidget _appBar(BuildContext context, WidgetRef ref, Post? post) {
    final authorName = post?.authorId ?? '';
    return AppBar(
      backgroundColor: KkColors.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: const KkBackButton(),
      titleSpacing: 0,
      title: Text(
        authorName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: KkType.body.copyWith(fontWeight: FontWeight.w600),
      ),
      actions: [
        Tappable(
          // post 为 null(动态不存在)时不弹 more sheet(无意义)。
          onTap: () {
            if (post != null) _showMoreSheet(context, ref, post);
          },
          child: const Icon(Icons.more_horiz, size: 22, color: KkColors.t1),
        ),
        const SizedBox(width: KkSpacing.sm),
      ],
    );
  }

  // ── 不存在 / 已删除 ──
  Widget _notFound(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const EmptyState(
            variant: EmptyStateVariant.generic,
            title: '动态不存在或已删除',
          ),
          const SizedBox(height: KkSpacing.md),
          Tappable(
            onTap: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(KkRoutes.discover);
              }
            },
            borderRadius: BorderRadius.circular(KkRadius.pill),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: KkSpacing.lg,
                vertical: KkSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: KkColors.teal,
                borderRadius: BorderRadius.circular(KkRadius.pill),
              ),
              child: const Text(
                '返回',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFamily: 'NotoSerifSC',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 主体 ──
  Widget _body(BuildContext context, WidgetRef ref, Post post) {
    final author = ref.watch(userByIdProvider(post.authorId));
    final appState = ref.watch(appStateProvider);
    final isLiked = appState.likedItemIds.contains(post.id);
    final likeCount = post.likes + (isLiked ? 1 : 0);
    final comments = ref.read(postRepositoryProvider).commentsFor(post.id);
    final isMe = post.authorId == 'me';

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // 1. 作者行(头像 36px / 名字 / 时间 / 关注按钮—非自己才显示)
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KkSpacing.lg,
            vertical: KkSpacing.md,
          ),
          child: Row(
            children: [
              TappableAvatar(
                userId: post.authorId,
                user: author,
                size: 36,
                onTap: () => context.push(KkRoutes.profile(post.authorId)),
              ),
              const SizedBox(width: KkSpacing.md),
              Expanded(
                child: Tappable(
                  onTap: () => context.push(KkRoutes.profile(post.authorId)),
                  borderRadius: BorderRadius.circular(KkRadius.sm),
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
                      Text(
                        timeAgo(post.createdAtMs),
                        style: KkType.mono.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              if (!isMe) _FollowButton(userId: post.authorId),
            ],
          ),
        ),
        // 2. 正文(全屏无 maxLines)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
          child: Text(post.content, style: KkType.body.copyWith(height: 1.6)),
        ),
        // 3. 标签(可点 → 搜索该 tag)
        if (post.tags.isNotEmpty) ...[
          const SizedBox(height: KkSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
            child: Wrap(
              spacing: KkSpacing.sm,
              runSpacing: KkSpacing.xs,
              children: [
                for (final t in post.tags)
                  Tappable(
                    onTap: () => context.push(KkRoutes.searchResults(t)),
                    borderRadius: BorderRadius.circular(KkRadius.sm),
                    child: Text(
                      '#$t',
                      style: KkType.bodySm.copyWith(color: KkColors.teal),
                    ),
                  ),
              ],
            ),
          ),
        ],
        // 4. 引用项目浮窗(复用 post_card 视觉)
        if (post.quoteProjectId != null) ...[
          const SizedBox(height: KkSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
            child: _QuoteProject(projectId: post.quoteProjectId!),
          ),
        ],
        // 5. 图片网格(若有 — Post.media 仅 image,无视频)
        if (post.media.isNotEmpty) ...[
          const SizedBox(height: KkSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
            child: _ImageGrid(media: post.media),
          ),
        ],
        // 6. 操作行:点赞(coral 已点赞情感色)/ 评论 / 分享
        const SizedBox(height: KkSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
          child: Row(
            children: [
              // 任务 C:点赞用 KkReactionButton——点亮 scale 弹 + haptic。
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
                onTap: () =>
                    ref.read(appStateProvider.notifier).togglePostLike(post.id),
              ),
              const SizedBox(width: KkSpacing.lg),
              _IconStat(
                icon: Icons.chat_bubble_outline,
                value: formatCount(comments.length),
                color: KkColors.t3,
                // 任务 B:原空 onTap(哑火)→ 滚到 CommentThread(ensureVisible)。
                onTap: () {
                  final ctx = _commentThreadKey.currentContext;
                  if (ctx != null) {
                    Scrollable.ensureVisible(
                      ctx,
                      alignment: 0.0,
                      duration: const Duration(milliseconds: 300),
                    );
                  }
                },
              ),
              const SizedBox(width: KkSpacing.lg),
              _IconStat(
                icon: Icons.ios_share_outlined,
                value: '',
                color: KkColors.t3,
                onTap: () {
                  final author =
                      ref.read(userByIdProvider(post.authorId));
                  // 动态有配图 → 用第一张做海报背景(image→url,video→poster)。
                  final firstMedia =
                      post.media.isNotEmpty ? post.media.first : null;
                  final cover = firstMedia == null
                      ? null
                      : (firstMedia.type == 'image'
                          ? firstMedia.url
                          : firstMedia.poster);
                  showShareSheet(
                    context,
                    title: post.content.split('\n').first,
                    subtitle: author?.name,
                    authorName: author?.name,
                    shareType: 'post',
                    shareUrl: 'https://kankan.app/post/${post.id}',
                    coverPattern: 'waves',
                    coverImageUrl: cover,
                    likes: post.likes,
                  );
                },
              ),
              const Spacer(),
            ],
          ),
        ),
        // 7. 分隔线
        const SizedBox(height: KkSpacing.md),
        const Divider(height: 1, color: KkColors.divider),
        // 8. 心得讨论(CommentThread:header 显示「心得 N」+ 输入框 + 长按 hook)
        CommentThread(
          key: _commentThreadKey,
          hostType: 'post',
          hostId: post.id,
          initialComments: comments,
          showInput: true,
          showHeader: true,
          // P0-1 收口:动态详情内联在 ListView 里,父级提供滚动 →
          // inlineInScroll: true(Column 渲染,首屏一页,发评论/删评论后 refresh 重拉)。
          inlineInScroll: true,
          // 任务⑨:长按 → 动作 sheet 收进 CommentThread 内部(_showActions),
          // 接通复制/编辑(own)/删除(own)/打开链接。不再外部传 onCommentLongPress。
        ),
        // 底部留白(给输入框 SafeArea 腾位)
        const SizedBox(height: KkSpacing.xxl),
      ],
    );
  }

  // ── 更多操作 sheet(举报 / 不感兴趣 / 删除自己的)— HANDOFF §5:t1 文字,非珊瑚橙 ──
  // 任务⑫:举报 → showReportSheet(post);不感兴趣 → markNotInterested +
  // toast「已减少类似推荐」+ 回 feed(该动态从流过滤消失)。
  // 任务:own(authorId=='me')出「删除」(珊瑚橙,删自己内容=take 语义例外)。
  void _showMoreSheet(BuildContext context, WidgetRef ref, Post post) {
    final isMe = post.authorId == 'me';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KkColors.bgCard,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 自己的动态 → 删除(coral,置顶,destructive)
            if (isMe) ...[
              _sheetItem(
                icon: Icons.delete_outline,
                label: '删除',
                color: KkColors.coral,
                weight: FontWeight.w600,
                onTap: () {
                  Navigator.pop(context); // 关 more sheet
                  _confirmDeletePost(context, ref, post);
                },
              ),
              const Divider(height: 1, color: KkColors.divider, indent: 56),
            ],
            _sheetItem(
              icon: Icons.flag_outlined,
              label: '举报',
              onTap: () {
                Navigator.pop(context);
                showReportSheet(
                  context,
                  targetType: 'post',
                  targetId: post.id,
                );
              },
            ),
            const Divider(height: 1, color: KkColors.divider, indent: 56),
            _sheetItem(
              icon: Icons.visibility_off_outlined,
              label: '不感兴趣',
              onTap: () {
                final messenger = ScaffoldMessenger.maybeOf(context);
                Navigator.pop(context); // 关 more sheet
                ref
                    .read(appStateProvider.notifier)
                    .markNotInterested(post.id);
                // 回到 feed:discover/kankan watch appState,重建后该动态被过滤
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(KkRoutes.discover);
                }
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
              icon: Icons.close,
              label: '取消',
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  // ── 任务:删除自己的动态(二次确认 → removePost + invalidate + pop)──
  // 零旁白:AlertDialog 只列「删除这条动态?」+ 删除/取消,不写后果说明。
  // 删除按钮 coral(删自己内容 = take 语义例外,与评论删除一致,SPEC §6)。
  void _confirmDeletePost(BuildContext context, WidgetRef ref, Post post) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('删除这条动态?'),
        contentTextStyle: KkType.body.copyWith(color: KkColors.t1),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.md,
          vertical: KkSpacing.sm,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              '取消',
              style: KkType.bodySm.copyWith(color: KkColors.t2),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(postRepositoryProvider).removePost(post.id);
              // 刷新依赖 postRepositoryProvider 的屏
              // (discover 推荐/关注/profile 动态 重建后该动态消失)。
              ref.invalidate(postRepositoryProvider);
              // 删除后在动态详情页 → pop 回上一页。
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(KkRoutes.discover);
              }
            },
            child: Text(
              '删除',
              style: KkType.bodySm.copyWith(
                color: KkColors.coral,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetItem({
    required IconData icon,
    required String label,
    Color? color,
    FontWeight? weight,
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
              style: KkType.body.copyWith(
                color: color ?? KkColors.t1,
                fontWeight: weight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 引用项目浮窗(从 post_card.dart 复制视觉,不依赖私有 widget)──
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
              color: KkColors.bgSubtle,
              borderRadius: BorderRadius.circular(KkRadius.md),
              border: Border.all(color: KkColors.bd),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: KkColors.mint,
                    borderRadius: BorderRadius.circular(KkRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.bookmark_outlined,
                    size: 18,
                    color: KkColors.teal,
                  ),
                ),
                const SizedBox(width: KkSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p.title,
                        style: KkType.bodySm.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        p.summary,
                        style: KkType.bodySm.copyWith(
                          color: KkColors.t3,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
      },
    );
  }
}

// ── 关注按钮(从 post_card.dart 复制视觉,接全局 follow 状态)──
class _FollowButton extends ConsumerWidget {
  final String userId;

  const _FollowButton({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following =
        ref.watch(appStateProvider).followedUserIds.contains(userId);
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

  const _IconStat({
    required this.icon,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: KkSpacing.sm,
          horizontal: KkSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            if (value.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                value,
                style: KkType.mono.copyWith(fontSize: 12, color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 图片网格(单图大图 / 2-4 张 2 列 / 5+ 三列)──
///
/// Post.media 只允许 image(HANDOFF §1 — 视频走 Project)。
/// mock 阶段 URL 是占位,用色块 + 图标替代真实图;Phase 5 接真图时换
/// CachedNetworkImage,接口不变。
///
/// 任务 A:每格点 → openImageLightbox(全屏缩放,收真实 url 列表)。
class _ImageGrid extends StatelessWidget {
  final List<MediaItem> media;

  const _ImageGrid({required this.media});

  @override
  Widget build(BuildContext context) {
    final images = media.where((m) => m.type == 'image').toList();
    if (images.isEmpty) return const SizedBox.shrink();

    final crossCount = images.length == 1
        ? 1
        : images.length <= 4
            ? 2
            : 3;

    final urls = [for (final m in images) m.url];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        mainAxisSpacing: KkSpacing.xs,
        crossAxisSpacing: KkSpacing.xs,
        childAspectRatio: 1,
      ),
      itemCount: images.length,
      itemBuilder: (context, i) {
        return Tappable(
          onTap: () => openImageLightbox(
            context,
            urls: urls,
            initialIndex: i,
          ),
          borderRadius: BorderRadius.circular(KkRadius.md),
          child: Container(
            decoration: BoxDecoration(
              color: KkColors.bgSubtle,
              borderRadius: BorderRadius.circular(KkRadius.md),
              border: Border.all(color: KkColors.bd),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.image_outlined,
              size: 28,
              color: KkColors.t4,
            ),
          ),
        );
      },
    );
  }
}
