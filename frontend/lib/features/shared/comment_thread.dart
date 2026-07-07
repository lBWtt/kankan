import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/network/app_exception.dart';
import '../../core/pagination/infinite_scroll.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/backend_id.dart';
import '../../core/utils/time_ago.dart';
import '../../core/utils/parse_count.dart';
import '../../core/widgets/tappable.dart';
import '../../data/api/comments_api.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/post_repository.dart';
import '../../domain/repositories/project_repository.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/paginated_comments_provider.dart';
import '../../providers/project_provider.dart';
import '../../router/routes.dart';
import 'avatar.dart';
import 'comment_actions_sheet.dart';
import 'report_sheet.dart';

/// HANDOFF §6.1 CommentThread — 统一评论组件。
///
/// 四处一致(详情内联 / 评论页 / 动态弹层 / 动态详情):
///   - 评论列表(楼中楼回复)
///   - 点赞(真实计数,可切换)
///   - 回复(楼中楼,可嵌套一层)
///   - 输入框(真发送,加入内存 state)
///
/// 零旁白(HANDOFF §3):输入框 placeholder 只写"写心得"/"回复{名字}",
/// 不写"快来分享你的看法吧"之类引导。
///
/// 计数铁律(HANDOFF §6.10):评论数取 comments.length(真实),
/// 不做 ×N 放大。点赞数取 comment.likes + (用户已点赞?1:0)。
class CommentThread extends ConsumerStatefulWidget {
  /// 宿主类型 'project' | 'post'
  final String hostType;

  /// 宿主 ID
  final String hostId;

  /// 初始评论列表(从 repository 同步读)
  final List<Comment> initialComments;

  /// 是否显示输入框(详情页内联用 true,纯列表展示可 false)
  final bool showInput;

  /// 是否显示标题("心得 N")
  final bool showHeader;

  /// 长按评论回调(可选)。
  ///
  /// 传入则评论长按(avatar + 正文区域)触发,通常接入 showCommentActionsSheet;
  /// 不传则无长按行为(默认 null,不破坏现有调用方)。
  /// 操作行(点赞 / 回复按钮)不包长按,避免长按点赞按钮误触发。
  final void Function(Comment)? onCommentLongPress;

  /// F-4:评论列表变更(发送 / 删除)回调(可选)。
  ///
  /// 详情页内联 CommentThread 传入,触发外层 rebuild → 底栏「心得 N」从同源
  /// commentsFor 重读,与 header 计数实时一致(杜绝"心得 N+1 / 心得 N"分裂)。
  /// 不传则忽略(评论页 / 弹层等不依赖外层计数实时刷新的场景)。
  final VoidCallback? onChanged;

  /// 是否内联在父滚动容器里(P0-1 收口)。
  ///
  /// - `true`:CommentThread 用 Column 渲染(shrinkWrap 语义),不挂自己的
  ///   ScrollController,不做无限滚动。适合 detail_screen SliverToBoxAdapter /
  ///   post_detail_screen ListView / comments_screen SingleChildScrollView
  ///   等父级已提供滚动的场景。首屏一页 + 发评论/删评论后 invalidate 重拉首页。
  /// - `false`(默认):CommentThread 拥有自己的滚动容器(ListView.builder +
  ///   ScrollController + InfiniteScroll + LoadMoreIndicator)。适合
  ///   comment_bottom_sheet Expanded 等父级无滚动容器的场景。
  ///
  /// mock 模式忽略此参数(始终 Column 渲染,mock Page.last hasMore=false)。
  final bool inlineInScroll;

  const CommentThread({
    super.key,
    required this.hostType,
    required this.hostId,
    required this.initialComments,
    this.showInput = true,
    this.showHeader = true,
    this.onCommentLongPress,
    this.onChanged,
    this.inlineInScroll = false,
  });

  @override
  ConsumerState<CommentThread> createState() => _CommentThreadState();
}

class _CommentThreadState extends ConsumerState<CommentThread> {
  // mock 模式:本地 _comments(从 widget.initialComments 同步初始化 + setState 追加)。
  // remote 模式:_comments 不用,build 时从 paginatedCommentsProvider 派生 state.items。
  late List<Comment> _comments = List.of(widget.initialComments);
  final _ctrl = TextEditingController();
  final _replyCtrl = TextEditingController();
  final _editCtrl = TextEditingController();
  String? _replyingTo; // 正在回复的评论 ID;null = 顶级评论
  String? _editingId; // 任务⑨:正在编辑的评论 ID;null = 非编辑态

  // 真数据模式:useRemote + 真后端宿主(UUID)→ 评论从后端读/写。
  bool get _remote => AppConfig.useRemote && looksLikeBackendId(widget.hostId);
  String get _paginatedKey => commentThreadKey(widget.hostType, widget.hostId);

  // remote 模式 + !inlineInScroll 时,CommentThread 拥有自己的 ScrollController
  // (挂在 ListView.builder 上 + InfiniteScroll 触底加载更多)。
  // inlineInScroll=true 或 mock 模式不创建(用父级滚动 / 无需滚动)。
  ScrollController? _ownScrollCtrl;

  @override
  void initState() {
    super.initState();
    if (_remote && !widget.inlineInScroll) {
      _ownScrollCtrl = ScrollController();
      InfiniteScroll.attach(_ownScrollCtrl!, onLoadMore: () {
        // hasMore=false 时 Notifier.loadMore no-op(mock + remote 末页)。
        ref.read(paginatedCommentsProvider(_paginatedKey).notifier).loadMore();
      });
    }
    // remote 模式首屏加载:paginatedCommentsProvider 是 autoDispose.family,
    // 首次 watch 时自动 build() → microtask 触发 fetchPage → 拉首页评论 +
    // mergeLikedIds 并入 app_state。无需手动 _reloadRemote(原 mock 谱系方案)。
  }

  @override
  void dispose() {
    _ownScrollCtrl?.dispose();
    _ctrl.dispose();
    _replyCtrl.dispose();
    _editCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // remote 模式:watch 分页 state(loading → items 空 + isLoading=true;
    // data → items 填充;error → items 空 + error 非 null)。
    final paginatedState =
        _remote ? ref.watch(paginatedCommentsProvider(_paginatedKey)) : null;
    final comments = paginatedState?.items ?? _comments;
    final isLoading = paginatedState?.isLoading ?? false;
    final isLoadingMore = paginatedState?.isLoadingMore ?? false;

    // 远程模式 + 自有滚动容器:ListView.builder + InfiniteScroll + LoadMoreIndicator。
    // 其余(inlineInScroll=true 或 mock):Column 渲染(原结构,父级提供滚动)。
    if (_remote && !widget.inlineInScroll) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showHeader) _header(comments.length),
          Expanded(
            child: _remoteListView(comments, isLoading, isLoadingMore),
          ),
          if (widget.showInput) ...[
            const SizedBox(height: KkSpacing.sm),
            _inputBar(),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader) _header(comments.length),
        if (isLoading && comments.isEmpty)
          _loadingHint()
        else if (comments.isEmpty)
          _emptyHint()
        else
          for (final c in comments)
            _CommentTile(
              comment: c,
              onLike: () => _toggleLike(c.id),
              onReply: () => _startReply(c.id),
              // P0-1 收口:remote likedIds 由 paginatedCommentsProvider.fetchPage
              // mergeLikedIds 并入 app_state.likedItemIds;mock 也走同一字段。
              // 统一从 app_state 读,isLiked 真源单一。
              isLiked: ref.watch(appStateProvider).likedItemIds.contains(c.id),
              // 任务⑨:外部 onCommentLongPress 作为可选 override;
              // 外部没传则用内部 _showActions(接通复制/编辑(own)/删除(own)/打开链接)。
              onLongPress: widget.onCommentLongPress ?? _showActions,
            ),
        if (widget.showInput) ...[
          const SizedBox(height: KkSpacing.sm),
          _inputBar(),
        ],
      ],
    );
  }

  Widget _header(int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.md,
      ),
      child: Text('心得 $count', style: KkType.h3),
    );
  }

  Widget _emptyHint() {
    return Padding(
      padding: const EdgeInsets.all(KkSpacing.xl),
      child: Text(
        '暂无心得',
        style: KkType.bodySm.copyWith(color: KkColors.t4),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _loadingHint() {
    return const Padding(
      padding: EdgeInsets.all(KkSpacing.xl),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  /// remote 模式 + 自有滚动容器:评论列表 ListView.builder。
  Widget _remoteListView(
    List<Comment> comments,
    bool isLoading,
    bool isLoadingMore,
  ) {
    if (isLoading && comments.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (comments.isEmpty) {
      return ListView(
        children: [_emptyHint()],
      );
    }
    // +1:底部加载指示器(追加加载时显示)。hasMore=false 时 LoadMoreIndicator
    // 自身 SizedBox.shrink,不占位。
    return ListView.builder(
      controller: _ownScrollCtrl,
      padding: const EdgeInsets.only(bottom: KkSpacing.xxl),
      itemCount: comments.length + 1,
      itemBuilder: (context, i) {
        if (i == comments.length) {
          return LoadMoreIndicator(enabled: isLoadingMore);
        }
        final c = comments[i];
        return _CommentTile(
          comment: c,
          onLike: () => _toggleLike(c.id),
          onReply: () => _startReply(c.id),
          isLiked: ref.watch(appStateProvider).likedItemIds.contains(c.id),
          onLongPress: widget.onCommentLongPress ?? _showActions,
        );
      },
    );
  }

  void _startReply(String commentId) {
    setState(() => _replyingTo = commentId);
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
      _replyCtrl.clear();
    });
  }

  /// P0-1 收口:统一走 appState.toggleCommentLike(mock 短 id 本地即真源;
  /// remote UUID 乐观 toggle likedItemIds + 后端同步 + 失败回滚)。
  /// 不再用本地 _remoteLiked Set(原双轨),likedIds 真源单一在 app_state。
  void _toggleLike(String commentId) {
    ref.read(appStateProvider.notifier).toggleCommentLike(commentId);
  }

  void _toast(String msg) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── 任务⑨:长按评论 → 动作 sheet(内部接通,直接改 _comments)──
  // 把长按 → sheet 逻辑收进 _CommentThreadState,使 sheet 的删除/编辑
  // 回调能直接 setState 改本组件 _comments(从外部调用够不到内部 state)。
  // own = authorId == 'me';仅 own 显编辑/删除;linkUrl 从 content 正则提取。
  void _showActions(Comment c) {
    final linkUrl = _extractUrl(c.content);
    showCommentActionsSheet(
      context,
      comment: c,
      hostType: widget.hostType,
      hostId: widget.hostId,
      isOwn: c.authorId == 'me',
      onCopy: () {}, // sheet 内部已真实现 Clipboard,空回调占位
      onEdit: () => _startEdit(c),
      onDelete: () => _confirmDelete(c),
      // 任务⑫:他人评论显「举报」(comment_actions_sheet onReport 参数已存在,
      // 传了自动出按钮)。sheet 内部先 pop 本 sheet 再回调,接 showReportSheet。
      onReport: () => showReportSheet(
        context,
        targetType: 'comment',
        targetId: c.id,
      ),
      linkUrl: linkUrl,
    );
  }

  /// 从评论正文提取第一个 http(s) URL(无则 null)。
  /// 任务⑨:评论含 URL 时给 sheet 传 linkUrl,显「打开链接」。
  static String? _extractUrl(String content) {
    final m = RegExp(r'https?://\S+').firstMatch(content);
    return m?.group(0);
  }

  // ── 任务⑨:编辑模式(仿 _replyingTo,加 _editingId)──
  // 进入:预填 _editCtrl = content,输入栏切到编辑态(顶部提示「编辑」+取消)。
  // 提交:替换该评论 content(map copyWith),同步 repository.updateComment,
  // 清 _editingId。零旁白(提示条只写「编辑」,不写「修改后会怎样」)。
  void _startEdit(Comment c) {
    setState(() {
      _editingId = c.id;
      _editCtrl.text = c.content;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingId = null;
      _editCtrl.clear();
    });
  }

  void _submitEdit() {
    final id = _editingId;
    if (id == null) return;
    final text = _editCtrl.text.trim();
    if (text.isEmpty) return;
    Comment? updated;
    setState(() {
      _comments = _comments.map((c) {
        if (c.id == id) {
          updated = c.copyWith(content: text);
          return updated!;
        }
        return c;
      }).toList();
    });
    if (updated != null) {
      // 同步 mockComments(与 _submit 写入对称),杜绝 detail 底栏计数/内容分裂。
      if (widget.hostType == 'project') {
        ref
            .read(projectRepositoryProvider)
            .updateComment(updated!);
      } else {
        ref.read(postRepositoryProvider).updateComment(updated!);
      }
    }
    widget.onChanged?.call();
    _editCtrl.clear();
    _editingId = null;
    FocusScope.of(context).unfocus();
  }

  // ── 任务⑨:删除(二次确认 → removeWhere + 同步 repository + onChanged)──
  // 零旁白:AlertDialog 只列「删除这条心得?」+ 删除/取消,不写后果说明。
  // 删除按钮 coral(删自己评论 = take 语义例外,SPEC §6)。
  void _confirmDelete(Comment c) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('删除这条心得?'),
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
              _doDelete(c);
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

  void _doDelete(Comment c) {
    // 远程模式:乐观移除(PaginatedNotifier.removeItem 即时反馈)→ 后端 delete →
    // 失败 refresh 回滚。不再用本地 _comments.removeWhere(build 用 provider items)。
    if (_remote) {
      ref
          .read(paginatedCommentsProvider(_paginatedKey).notifier)
          .removeItem(c.id);
      () async {
        try {
          await ref.read(commentsApiProvider).delete(c.id);
          // 后端确认成功,乐观态即正确,无需重拉。
        } on AppException catch (e) {
          if (mounted) {
            _toast(e.message);
            // 失败 → refresh 重拉首页恢复(rollback 乐观移除)。
            await ref
                .read(paginatedCommentsProvider(_paginatedKey).notifier)
                .refresh();
          }
        }
      }();
      widget.onChanged?.call();
      return;
    }
    setState(() {
      _comments.removeWhere((x) => x.id == c.id);
    });
    // 同步 mockComments(对称 addComment),杜绝 detail 底栏「心得 N」
    // 从 commentsFor 重读时计数分裂(删除后底栏计数应同步减 1)。
    if (widget.hostType == 'project') {
      ref.read(projectRepositoryProvider).removeComment(c.id);
    } else {
      ref.read(postRepositoryProvider).removeComment(c.id);
    }
    widget.onChanged?.call();
  }

  void _submit() {
    final isReply = _replyingTo != null;
    final text = (isReply ? _replyCtrl.text : _ctrl.text).trim();
    if (text.isEmpty) return;

    // 远程模式:发到后端 → refresh 重拉首页(新评论出现)。清输入、收起回复态。
    if (_remote) {
      final parentId = isReply ? _replyingTo : null;
      setState(() {
        if (isReply) {
          _replyCtrl.clear();
          _replyingTo = null;
        } else {
          _ctrl.clear();
        }
      });
      FocusScope.of(context).unfocus();
      () async {
        try {
          await ref.read(commentsApiProvider)
              .create(widget.hostType, widget.hostId, text, parentId: parentId);
          // 发送成功 → refresh 重拉首页(PaginatedNotifier.refresh 保留旧 items
          // 直到新页到达,无空窗闪烁)。
          await ref
              .read(paginatedCommentsProvider(_paginatedKey).notifier)
              .refresh();
          widget.onChanged?.call();
        } on AppException catch (e) {
          if (mounted) _toast(e.message);
        }
      }();
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final newComment = Comment(
      id: 'local_${now}_${_comments.length}',
      hostType: widget.hostType,
      hostId: widget.hostId,
      authorId: 'me',
      content: text,
      likes: 0,
      createdAtMs: now,
    );

    // F-4:写入内存 repository(mockComments,与 detail 底栏 / 卡片 / 全屏评论页同源),
    // 杜绝"评论只存 local state,pop 走再回来丢失 + 计数分裂"。
    // 仅顶级评论写入 repo(楼中楼 replies 是 Comment 内嵌列表,不单独入 mockComments)。
    if (!isReply) {
      if (widget.hostType == 'project') {
        ref
            .read(projectRepositoryProvider)
            .addComment(widget.hostType, widget.hostId, newComment);
      } else {
        ref
            .read(postRepositoryProvider)
            .addComment(widget.hostType, widget.hostId, newComment);
      }
    }

    setState(() {
      if (isReply) {
        // 楼中楼:找到父评论,加入 replies
        _comments = _comments.map((c) {
          if (c.id == _replyingTo) {
            return c.copyWith(replies: [...c.replies, newComment]);
          }
          return c;
        }).toList();
      } else {
        _comments = [..._comments, newComment];
      }
    });

    // F-4:通知外层(如 detail_screen)重建,底栏「心得 N」从同源 commentsFor 重读。
    widget.onChanged?.call();

    if (isReply) {
      _replyCtrl.clear();
      _replyingTo = null;
    } else {
      _ctrl.clear();
    }
    FocusScope.of(context).unfocus();
  }

  Widget _inputBar() {
    // 任务⑨:编辑模式优先(编辑一条评论时不应同时回复/发新评论)。
    // 三态:editing > replying > normal,各自有顶部提示条 + 输入框预填。
    final isEditing = _editingId != null;
    final isReply = !isEditing && _replyingTo != null;
    final TextEditingController ctrl;
    final VoidCallback onSubmit;
    final VoidCallback onCancel;
    final String hint;
    final String submitLabel;
    final String modeLabel;
    if (isEditing) {
      ctrl = _editCtrl;
      onSubmit = _submitEdit;
      onCancel = _cancelEdit;
      hint = '编辑心得';
      submitLabel = '保存';
      modeLabel = '编辑';
    } else if (isReply) {
      ctrl = _replyCtrl;
      onSubmit = _submit;
      onCancel = _cancelReply;
      hint = '回复…';
      submitLabel = '发送';
      modeLabel = '回复';
    } else {
      ctrl = _ctrl;
      onSubmit = _submit;
      onCancel = () {};
      hint = '写心得';
      submitLabel = '发送';
      modeLabel = '';
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: KkColors.bgCard,
        border: Border(top: BorderSide(color: KkColors.bd)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEditing || isReply)
            Padding(
              padding: const EdgeInsets.only(bottom: KkSpacing.sm),
              child: Row(
                children: [
                  Text(
                    modeLabel,
                    style: KkType.bodySm.copyWith(color: KkColors.t3),
                  ),
                  const SizedBox(width: KkSpacing.xs),
                  Tappable(
                    onTap: onCancel,
                    child: const Icon(Icons.close,
                        size: 14, color: KkColors.t3),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  autofocus: isEditing || isReply,
                  minLines: 1,
                  maxLines: 4,
                  style: KkType.body,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: KkType.body.copyWith(color: KkColors.t4),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: KkSpacing.md,
                      vertical: KkSpacing.sm,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(KkRadius.pill),
                      borderSide: const BorderSide(color: KkColors.bd),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(KkRadius.pill),
                      borderSide: const BorderSide(color: KkColors.teal),
                    ),
                  ),
                  onSubmitted: (_) => onSubmit(),
                ),
              ),
              const SizedBox(width: KkSpacing.sm),
              Tappable(
                onTap: onSubmit,
                borderRadius: BorderRadius.circular(KkRadius.pill),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KkSpacing.lg,
                    vertical: KkSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    // 编辑保存按钮用 teal(保存不是 take,不用 coral;
                    // coral 仅给「删除」这一 destructive 动作)。
                    color: KkColors.teal,
                    borderRadius: BorderRadius.circular(KkRadius.pill),
                  ),
                  child: Text(
                    submitLabel,
                    style: const TextStyle(
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
        ],
      ),
    );
  }
}

// ── 评论单元(含楼中楼)──
class _CommentTile extends ConsumerWidget {
  final Comment comment;
  final VoidCallback onLike;
  final VoidCallback onReply;
  final bool isLiked;

  /// 长按评论回调(可空)—— CommentThread 转发 onCommentLongPress。
  /// 触发区域:avatar + 正文(操作行不包,避免长按点赞 / 回复按钮误触发)。
  final void Function(Comment)? onLongPress;

  const _CommentTile({
    required this.comment,
    required this.onLike,
    required this.onReply,
    required this.isLiked,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final author = ref.watch(userByIdProvider(comment.authorId));
    final likeCount = comment.likes + (isLiked ? 1 : 0);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: onLongPress == null
                ? null
                : () => onLongPress!(comment),
            behavior: HitTestBehavior.opaque,
            child: TappableAvatar(
              userId: comment.authorId,
              user: author,
              size: 32,
              onTap: () => context.push(KkRoutes.profile(comment.authorId)),
            ),
          ),
          const SizedBox(width: KkSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onLongPress: onLongPress == null
                      ? null
                      : () => onLongPress!(comment),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            author?.name ?? comment.authorId,
                            style: KkType.bodySm.copyWith(
                              fontWeight: FontWeight.w600,
                              color: KkColors.t1,
                            ),
                          ),
                          const SizedBox(width: KkSpacing.sm),
                          Text(
                            timeAgo(comment.createdAtMs),
                            style: KkType.mono.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(comment.content, style: KkType.body),
                    ],
                  ),
                ),
                const SizedBox(height: KkSpacing.sm),
                // 操作行:点赞 / 回复(零旁白,只图标 + 数字)
                // 不包长按,避免长按点赞按钮触发评论操作 sheet
                Row(
                  children: [
                    Tappable(
                      onTap: onLike,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isLiked
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 14,
                            color: isLiked ? KkColors.like : KkColors.t3,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            formatCount(likeCount),
                            style: KkType.mono.copyWith(
                              fontSize: 11,
                              color: isLiked ? KkColors.like : KkColors.t3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: KkSpacing.lg),
                    Tappable(
                      onTap: onReply,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.chat_bubble_outline,
                              size: 14, color: KkColors.t3),
                          const SizedBox(width: 4),
                          Text(
                            '回复',
                            style: KkType.mono.copyWith(
                                fontSize: 11, color: KkColors.t3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // 楼中楼
                if (comment.replies.isNotEmpty) ...[
                  const SizedBox(height: KkSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(KkSpacing.sm),
                    decoration: BoxDecoration(
                      color: KkColors.bgSubtle,
                      borderRadius: BorderRadius.circular(KkRadius.sm),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final r in comment.replies) ...[
                          _ReplyTile(reply: r),
                          if (r != comment.replies.last)
                            const SizedBox(height: KkSpacing.sm),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplyTile extends ConsumerWidget {
  final Comment reply;

  const _ReplyTile({required this.reply});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final author = ref.watch(userByIdProvider(reply.authorId));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KkAvatar(userId: reply.authorId, user: author, size: 20),
        const SizedBox(width: KkSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                author?.name ?? reply.authorId,
                style: KkType.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: KkColors.t1,
                ),
              ),
              const SizedBox(height: 2),
              Text(reply.content, style: KkType.bodySm),
            ],
          ),
        ),
      ],
    );
  }
}
