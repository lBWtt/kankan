import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/noise_background.dart';
import '../../core/widgets/cover_art.dart';
import '../../core/widgets/kk_back_button.dart';
import '../../core/widgets/kk_reaction_button.dart';
import '../../core/widgets/tappable.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/project_repository.dart';
import '../../core/network/app_exception.dart';
import '../../core/utils/backend_id.dart';
import '../../data/api/projects_api.dart';
import '../../data/seed/mock_seed.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/clue_provider.dart';
import '../../providers/project_provider.dart';
import '../../router/routes.dart';
import 'widgets/action_row.dart';
import 'widgets/author_note.dart';
import 'widgets/io_block_view.dart';
import 'widgets/media_carousel.dart';
import 'widgets/repo_card.dart';
import '../shared/comment_thread.dart';
import '../shared/share_sheet.dart';

/// 项目详情页 — HANDOFF §2 可组合渲染的指挥中心。
///
/// **核心铁律(HANDOFF §2 / §7.1):渲染代码里禁 `if (artifactType == ...)` 之类
/// 硬编码分支。** 按 resultData 有什么渲染什么,任意组合。
///
/// 页面顺序固定(HANDOFF §2.3):
///   标题 → 一句话价值 → 作者+关注 → 成果区 → 作者的话(居中)→ 动作区 →
///   心得讨论 → 相关项目 → 底栏
///
/// 作者的话为空 → 整块隐藏(连标题)。
/// 无任何动作 → 动作区整块不显示。
/// 取项目封面图 URL(image→url,video→poster,无→null)。分享海报背景用。
/// 与 _DetailCover / ProjectCard._Cover 同源。
String? _coverImageUrl(Project project) {
  final media = project.resultData.media;
  if (media.isEmpty) return null;
  final first = media.first;
  if (first.type == 'image') return first.url;
  if (first.type == 'video') return first.poster;
  return null;
}

class DetailScreen extends ConsumerStatefulWidget {
  final String projectId;

  const DetailScreen({super.key, required this.projectId});

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  // F-5/F-6:底栏「心得 N」/ 拿走计数点击后滚动到对应区块(ensureVisible,
  // 无需 ScrollController,自动找最近 Scrollable)。
  final GlobalKey _commentsKey = GlobalKey();
  final GlobalKey _actionsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 埋点:详情打开(漏斗 detail_view + hot_score 详情权重)。真后端项目(UUID)才发。
    ref.read(analyticsProvider).track('detail_view', projectId: widget.projectId);
  }

  void _scrollToComments() {
    final ctx = _commentsKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          alignment: 0.1, duration: const Duration(milliseconds: 300));
    }
  }

  void _scrollToActions() {
    final ctx = _actionsKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          alignment: 0.1, duration: const Duration(milliseconds: 300));
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectAsync = ref.watch(projectByIdProvider(widget.projectId));

    return Scaffold(
      backgroundColor: KkColors.bg,
      body: NoiseBackground(
        child: SafeArea(
          bottom: false,
          child: projectAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败: $e')),
            data: (project) {
              if (project == null) {
                return const Center(child: Text('项目不存在'));
              }
              return _body(context, project);
            },
          ),
        ),
      ),
      bottomNavigationBar: null, // 由 _body 内 CustomScrollView 末尾的底栏处理
    );
  }

  Widget _body(BuildContext context, Project project) {
    final author = ref.watch(userByIdProvider(project.authorId));
    // F-1:用顶层函数 commentsFor(project.id)(mock_seed 导出),
    // 不再用 ProjectRepository.commentsFor —— 该方法不存在(编译阻断)。
    // 与 CommentThread / 卡片 / 全屏评论页同源(都读 mockComments)。
    final comments = commentsFor(project.id);

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            // 顶栏
            _topBar(context, ref, project),
            // 顶部封面(Phase 4 Hero 接收端,与 project_card _full 模式同 tag 配对)
            SliverToBoxAdapter(child: _cover(project)),
            // 标题 + 一句话价值 + 作者
            SliverToBoxAdapter(child: _header(project, author)),
            // 成果区(可组合渲染核心)
            SliverToBoxAdapter(child: _results(project)),
            // 作者的话(空 → 整块隐藏)
            if (project.authorNote != null &&
                project.authorNote!.isNotEmpty)
              SliverToBoxAdapter(child: AuthorNote(note: project.authorNote!)),
            // 动作区(空 → 整块不显示)
            if (project.actions.isNotEmpty)
              SliverToBoxAdapter(
                child: Container(
                  key: _actionsKey,
                  child: _actions(project),
                ),
              ),
            // 实现线索入口(ZAI_PLAYBOOK P0:主信号「想看怎么做」→ 跳 clue 屏)
            // 不进 ActionRow(sealed,本任务不动),独立成块。永远显示。
            SliverToBoxAdapter(child: _clueEntry(project)),
            // 心得讨论(Phase 4:CommentThread 统一组件接入 + 长按 hook)
            SliverToBoxAdapter(
              child: Container(
                key: _commentsKey,
                child: CommentThread(
                  hostType: 'project',
                  hostId: project.id,
                  initialComments: comments,
                  showInput: true,
                  showHeader: true,
                  // P0-1 收口:详情页内联在 CustomScrollView 的 SliverToBoxAdapter 里,
                  // 父级提供滚动 → inlineInScroll: true(Column 渲染,首屏一页,
                  // 发评论/删评论后 refresh 重拉首页)。无限滚动走全屏 comments_screen。
                  inlineInScroll: true,
                  // F-4:发评论后回调,触发本屏 rebuild → 底栏「心得 N」
                  // 从同源 commentsFor 重读,计数与 header 实时一致。
                  // 任务⑨:删除/编辑也走此回调(内部 _doDelete/_submitEdit 同步
                  // mockComments,底栏 commentsFor 重读与新内容一致)。
                  onChanged: () {
                    if (mounted) setState(() {});
                  },
                  // 任务⑨:长按 → 动作 sheet 收进 CommentThread 内部(_showActions),
                  // 接通复制/编辑(own)/删除(own)/打开链接。不再外部传 onCommentLongPress。
                ),
              ),
            ),
            // 底部留白(给底栏腾位)
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
        // 滚动跟随底栏(评论框 ↔ 拿走按钮切换 — Web 版规范)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _bottomBar(project),
        ),
      ],
    );
  }

  // ── 顶部封面(Phase 4 Hero 接收端)──
  //
  // 与 project_card.dart _full 模式的 `'project-cover-{project.id}'` tag 配对,
  // 实现卡片 → 详情页 cover 飞入过渡。结构镜像 ProjectCard._Cover
  // (CoverArt + 半透明遮罩 + 领域图标),保证飞行态视觉一致。
  // _Cover 是 project_card 私有 widget,这里就地内联一份(任务约束
  // 「不改 project_card」,无法提取共享 widget)。
  Widget _cover(Project project) {
    return Hero(
      tag: 'project-cover-${project.id}',
      child: _DetailCover(project: project),
    );
  }

  // ── 顶栏 ──
  SliverAppBar _topBar(BuildContext context, WidgetRef ref, Project project) {
    return SliverAppBar(
      pinned: false,
      floating: true,
      snap: true,
      backgroundColor: KkColors.bg,
      surfaceTintColor: Colors.transparent,
      leading: const KkBackButton(),
      actions: [
        Tappable(
          onTap: () {
            final author = ref.read(userByIdProvider(project.authorId));
            showShareSheet(
              context,
              title: project.title,
              subtitle: project.summary,
              authorName: author?.name,
              shareType: 'project',
              shareUrl: 'https://kankan.app/project/${project.id}',
              coverPattern: 'mountains',
              // 用作品真封面做海报背景(每个项目不一样,不再是那几个抽象图案)。
              coverImageUrl: _coverImageUrl(project),
              likes: project.likes,
            );
          },
          child: const Icon(Icons.ios_share_outlined,
              color: KkColors.t1, size: 22),
        ),
        // 任务:own(authorId=='me')出删除入口(珊瑚橙,删自己内容=take 语义例外,SPEC §6)
        if (project.authorId == 'me') ...[
          Tappable(
            onTap: () => _confirmDeleteProject(context, ref, project),
            child: const Icon(Icons.delete_outline,
                color: KkColors.coral, size: 22),
          ),
          const SizedBox(width: KkSpacing.sm),
        ] else
          const SizedBox(width: KkSpacing.sm),
      ],
    );
  }

  // ── 任务:删除自己的项目(二次确认 → removeProject + invalidate + pop)──
  // 零旁白:AlertDialog 只列「删除这个项目?」+ 删除/取消,不写后果说明。
  // 删除按钮 coral(删自己内容 = take 语义例外,与评论删除一致,SPEC §6)。
  void _confirmDeleteProject(
      BuildContext context, WidgetRef ref, Project project) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('删除这个项目?'),
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
            onPressed: () async {
              Navigator.of(ctx).pop();
              final messenger = ScaffoldMessenger.of(context);
              // 真后端项目(UUID)+ 登录 → 先后端软删;失败提示、不本地删(保持一致)。
              // mock 项目 / 未登录 → 只本地删(演示)。
              if (ref.read(authProvider).isLoggedIn &&
                  looksLikeBackendId(project.id)) {
                try {
                  await ref.read(projectsApiProvider).delete(project.id);
                } on AppException catch (e) {
                  messenger.showSnackBar(SnackBar(
                    content: Text('删除失败：${e.message}'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ));
                  return;
                }
              }
              ref.read(projectRepositoryProvider).removeProject(project.id);
              // 刷新依赖 projectRepositoryProvider / projectByIdProvider 的屏
              // (discover/kankan/profile/me 重建后该项目消失)。
              ref.invalidate(projectByIdProvider(project.id));
              // 删除后在详情页 → pop 回上一页。
              if (!context.mounted) return;
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

  // ── 标题 + 一句话价值 + 作者 ──
  Widget _header(Project project, KkUser? author) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题(衬线)
          Text(project.title, style: KkType.h1),
          const SizedBox(height: KkSpacing.sm),
          // 一句话价值
          Text(project.summary, style: KkType.body.copyWith(color: KkColors.t2)),
          const SizedBox(height: KkSpacing.lg),
          // 作者 + 关注
          Row(
            children: [
              _Avatar(userId: project.authorId, size: 36),
              const SizedBox(width: KkSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      author?.name ?? project.authorId,
                      style: KkType.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      _timeAgo(project.createdAtMs),
                      style: KkType.mono.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              // 关注按钮(任务 C:接全局 appStateProvider.followedUserIds,
              // 与 post_card / post_detail / profile 同源,A 屏点 B 屏同步)。
              if (project.authorId != 'me') _FollowButton(userId: project.authorId),
            ],
          ),
          const SizedBox(height: KkSpacing.lg),
        ],
      ),
    );
  }

  // ── 成果区:可组合渲染核心(HANDOFF §2.1 4 渲染器)──
  ///
  /// **禁 if(artifactType == ...) 硬编码分支。** 按 resultData 有什么渲染什么:
  ///   - media 非空 → MediaCarousel(视频优先 + 照片轮播)
  ///   - repo 非空  → RepoCard
  ///   - io 非空   → IoBlockView
  ///   - text 非空 → 纯正文
  /// 任一为空 → 不出空展示块。多个可并存。
  Widget _results(Project project) {
    final rd = project.resultData;
    final children = <Widget>[];

    // media(视频优先 + 照片轮播)
    if (rd.media.isNotEmpty) {
      children.add(MediaCarousel(media: rd.media));
    }
    // repo(仓库卡)
    if (rd.repo != null) {
      if (children.isNotEmpty) children.add(const SizedBox(height: KkSpacing.md));
      children.add(RepoCard(repo: rd.repo!));
    }
    // io(输入→输出效果)
    if (rd.io != null) {
      if (children.isNotEmpty) children.add(const SizedBox(height: KkSpacing.md));
      children.add(IoBlockView(io: rd.io!));
    }
    // text(纯正文,无 media/repo/io 时)
    if (rd.text != null && rd.text!.isNotEmpty) {
      if (children.isNotEmpty) children.add(const SizedBox(height: KkSpacing.md));
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
          child: Text(rd.text!, style: KkType.body.copyWith(height: 1.7)),
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  // ── 动作区:3 原语任意组合(HANDOFF §2.2)──
  Widget _actions(Project project) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.md,
      ),
      child: ActionRow(
        actions: project.actions,
        onTakeSuccess: (action) {
          // HANDOFF §2.2:take 成功后 takeawayCount +1
          ref.read(projectRepositoryProvider).incrementTakeaway(project.id);
          // 强制刷新
          ref.invalidate(projectByIdProvider(project.id));
        },
      ),
    );
  }

  // ── 实现线索入口(ZAI_PLAYBOOK P0 主信号)──
  //
  // 详情页「想看怎么做」→ push 到 /clue/{id}。独立成块,不动 ActionRow
  // (sealed,本任务约束)。墨绿浅底 + lightbulb 图标 + 实时「N 人想知道」计数
  // (来自 clueInteractionProvider,与 clue 屏主信号区同源)。无珊瑚橙(无 take)。
  Widget _clueEntry(Project project) {
    final count = ref.watch(clueInteractionProvider).howToCount(project.id);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.sm,
      ),
      child: Tappable(
        onTap: () => context.push(KkRoutes.clue(project.id)),
        borderRadius: BorderRadius.circular(KkRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: KkSpacing.md,
            horizontal: KkSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: KkColors.mint,
            borderRadius: BorderRadius.circular(KkRadius.md),
            border: Border.all(color: KkColors.teal.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lightbulb_outline,
                  size: 18, color: KkColors.teal),
              const SizedBox(width: KkSpacing.sm),
              Expanded(
                child: Text(
                  '想看怎么做',
                  style: const TextStyle(
                    color: KkColors.teal,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    fontFamily: 'NotoSerifSC',
                  ),
                ),
              ),
              Text(
                '$count 人想知道',
                style: KkType.mono.copyWith(fontSize: 12, color: KkColors.teal),
              ),
              const SizedBox(width: KkSpacing.xs),
              const Icon(Icons.chevron_right, size: 16, color: KkColors.teal),
            ],
          ),
        ),
      ),
    );
  }

  // ── 滚动跟随底栏 ──
  Widget _bottomBar(Project project) {
    // F-1:心得计数取顶层 commentsFor(project.id).length(与 CommentThread /
    // 卡片 / 全屏评论页同源),不用写死的 commentCount,也不用 repo.commentsFor
    // (ProjectRepository 无此方法,编译阻断)。
    final comments = commentsFor(project.id);
    final hasTake = project.actions.any((a) => a is TakeAction);
    // F-6:点赞接全局 appState.toggleLike,与其他屏一致(post_card / post_detail)。
    final appState = ref.watch(appStateProvider);
    final isLiked = appState.likedItemIds.contains(project.id);
    final likeCount = project.likes + (isLiked ? 1 : 0);
    return Container(
      decoration: const BoxDecoration(
        color: KkColors.bgCard,
        border: Border(top: BorderSide(color: KkColors.bd)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KkSpacing.lg,
            vertical: KkSpacing.sm,
          ),
          child: Row(
            children: [
              // 评论入口:F-5 点击滚动到内联 CommentThread(与其他屏评论入口一致:有反应)
              Expanded(
                child: Tappable(
                  onTap: _scrollToComments,
                  borderRadius: BorderRadius.circular(KkRadius.pill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: KkSpacing.md,
                      horizontal: KkSpacing.lg,
                    ),
                    decoration: BoxDecoration(
                      color: KkColors.bgSubtle,
                      borderRadius: BorderRadius.circular(KkRadius.pill),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline,
                            size: 16, color: KkColors.t3),
                        const SizedBox(width: KkSpacing.sm),
                        Text(
                          '心得 ${comments.length}',
                          style: KkType.bodySm,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: KkSpacing.sm),
              // 点赞:F-6 接 toggleLike(参照 post_detail_screen._IconStat 写法)。
              // 任务 C:用 KkReactionButton——点亮时 scale 弹 + haptic(取消不弹)。
              KkReactionButton(
                icon: isLiked ? Icons.favorite : Icons.favorite_border,
                value: _fmtCount(likeCount),
                color: isLiked ? KkColors.like : KkColors.t2,
                isLit: isLiked,
                onTap: () => ref
                    .read(appStateProvider.notifier)
                    .toggleLike(project.id),
              ),
              const SizedBox(width: KkSpacing.sm),
              // 拿走计数(若有 take 动作):F-6 点击滚动到动作区(拿走按钮所在)
              if (hasTake)
                _IconStat(
                  icon: Icons.download_outlined,
                  value: _fmtCount(project.takeawayCount),
                  color: KkColors.coral, // 珊瑚橙只给 take(HANDOFF §5)
                  onTap: _scrollToActions,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtCount(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}w';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  String _timeAgo(int ms) {
    final diff = DateTime.now().millisecondsSinceEpoch - ms;
    if (diff < 0) return '刚刚';
    final min = diff ~/ 60000;
    if (min < 60) return '$min分钟前';
    final hr = min ~/ 60;
    if (hr < 24) return '$hr小时前';
    final day = hr ~/ 24;
    if (day == 1) return '昨天';
    return '$day天前';
  }
}

// ── 顶部封面(详情页 Hero 接收端,镜像 ProjectCard._Cover 结构)──
//
// 任务①真实封面图:与 ProjectCard._Cover 同源(Image.network + CoverArt 回退)。
// height 220 比 ProjectCard 的 180 略高,详情页视觉层级更突出(Hero 自动插值尺寸)。
// 与卡片同 URL → Hero 飞行态无缝衔接。
class _DetailCover extends StatelessWidget {
  final Project project;

  const _DetailCover({required this.project});

  @override
  Widget build(BuildContext context) {
    final hasMedia = project.resultData.media.isNotEmpty;
    final first = hasMedia ? project.resultData.media.first : null;
    final isImage = hasMedia && first!.type == 'image';
    final isVideo = hasMedia && first!.type == 'video';
    // 封面 URL:与 ProjectCard._Cover 同源(image→url, video→poster, 无→null)
    final coverUrl = isImage
        ? first.url
        : (isVideo ? first.poster : null);
    final pattern = _domainPattern(project.domain);

    return SizedBox(
      width: double.infinity,
      height: 220,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 封面:有 URL → Image.network(loadingBuilder/errorBuilder 回退 CoverArt);
          // 无 URL → CoverArt 占位(与 ProjectCard._Cover 同源,Hero 无缝衔接)
          if (coverUrl != null && coverUrl.isNotEmpty)
            Image.network(
              coverUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: 220,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return CoverArt(
                    pattern: pattern, width: double.infinity, height: 220);
              },
              errorBuilder: (context, error, stackTrace) => CoverArt(
                  pattern: pattern, width: double.infinity, height: 220),
            )
          else
            CoverArt(
              pattern: pattern,
              width: double.infinity,
              height: 220,
            ),
          Container(color: Colors.black.withAlpha(20)),
          // 前景:video 叠 play 按钮(真图上);无封面时叠领域图标(有真图不叠)
          if (isVideo)
            Center(
              child: Icon(
                Icons.play_circle_outline,
                size: 56,
                color: Colors.white.withAlpha(220),
              ),
            )
          else if (coverUrl == null || coverUrl.isEmpty)
            Center(
              child: Icon(
                _domainIcon(project.domain),
                size: 48,
                color: Colors.white.withAlpha(200),
              ),
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

  /// 领域 → CoverArt 图案映射(与 ProjectCard._Cover._domainPattern 同表)
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

// ── 小组件 ──
class _Avatar extends StatelessWidget {
  final String userId;
  final double size;

  const _Avatar({required this.userId, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: KkColors.mint,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        userId.isNotEmpty ? userId[0].toUpperCase() : '?',
        style: TextStyle(
          color: KkColors.teal,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.4,
          fontFamily: 'JetBrainsMono',
        ),
      ),
    );
  }
}

// 任务 C:从 StatefulWidget 本地态改为 ConsumerWidget 接全局 follow。
// 旧实现用 bool _following + setState,与全局 appStateProvider.followedUserIds
// 不同步 → 详情页点了关注,profile/discover 的关注态不变(A 屏点 B 屏不变)。
// 现统一 watch 全局态,与 post_card._FollowButton / post_detail._FollowButton 同源。
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
          vertical: KkSpacing.sm,
          horizontal: KkSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: following ? KkColors.bgSubtle : KkColors.teal,
          borderRadius: BorderRadius.circular(KkRadius.pill),
          border: following
              ? Border.all(color: KkColors.bd)
              : null,
        ),
        child: Text(
          following ? '已关注' : '关注',
          style: TextStyle(
            color: following ? KkColors.t2 : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: 'NotoSerifSC',
          ),
        ),
      ),
    );
  }
}

class _IconStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color? color;
  // F-6:点赞 / 拿走计数的点击回调(参照 post_detail_screen._IconStat 已接线写法)。
  final VoidCallback? onTap;

  const _IconStat({required this.icon, required this.value, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.sm,
          vertical: KkSpacing.md,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color ?? KkColors.t2),
            const SizedBox(width: 4),
            Text(
              value,
              style: KkType.mono.copyWith(
                fontSize: 12,
                color: color ?? KkColors.t2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
