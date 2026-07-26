import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/utils/local_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/app_config.dart';
import '../../core/network/app_exception.dart';
import '../../core/prefs.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/tappable.dart';
import '../../data/api/media_api.dart';
import '../../data/api/posts_api.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/post_repository.dart';
import '../../domain/repositories/project_repository.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/paginated_posts_provider.dart';
import '../../providers/project_provider.dart';
import '../../providers/remote_post_provider.dart';
import '../../providers/remote_project_provider.dart';
import '../../router/routes.dart';
import '../feedback/feedback_sheet.dart';

/// 任务⑭ 发动态 compose 屏 — 朋友圈发布器样式。
///
/// 版式(从上到下):
/// 1. 顶栏:左「取消」纯文字(t2)+ 右「发表」绿胶囊(teal,空内容 t4 置灰);中间留白。
/// 2. 大号多行文字输入(无边框,hint「这一刻的想法…」,0/500 淡计数)。
/// 3. 九宫格图片区(3 列,近正方形圆角,右上「×」移除,末尾虚线「+」添加格,满 9 隐藏)。
/// 4. 已选话题 chip 排(可删)。
/// 5. 引用项目卡(已选态,可删/跳详情)。
/// 6. 底部操作条(朋友圈式行):话题 / 引用项目(未选时)。零假按钮(不摆位置/提醒谁看/谁可以看)。
///
/// 不动:_send 发送逻辑、_close() 返回逻辑、Post 模型、postRepository、路由、theme、其它屏。
///
/// 铁律:coral 只给 take(本屏不用 coral,发表用 teal);无 emoji;零旁白(hint 只写事实);
/// 触控 ≥44pt;零假按钮;复用 image_picker 选图(不引新依赖,不改 MediaPicker 组件本身)。
class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key});

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

enum _DraftExitAction { save, discard, keepEditing }

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  final _contentCtrl = TextEditingController();
  final List<MediaItem> _media = [];
  final Map<String, Uint8List> _mediaBytes = {}; // url→bytes（远程发布真上传用）
  final List<String> _tags = [];
  String? _quoteProjectId;
  Project? _quoteProject;

  // 任务 A:草稿恢复。_pendingDraft 进屏时从 prefs 读,非空则显横条;
  // _sent=true 表示已成功发送(dispose 时不再存草稿,且已清 key)。
  _ComposeDraft? _pendingDraft;
  bool _showDraftBanner = false;
  bool _sent = false;
  bool _isPublishing = false;
  Timer? _autosaveTimer;

  @override
  void initState() {
    super.initState();
    _loadDraft();
    _contentCtrl.addListener(_scheduleAutoSave);
  }

  String get _draftKey =>
      '${ref.read(authProvider).currentUser?.id ?? 'guest'}::${PrefsKeys.draftCompose}';

  void _loadDraft() {
    final raw = ref.read(prefsProvider).getString(_draftKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _pendingDraft = _ComposeDraft(
        content: (m['content'] as String?) ?? '',
        tags: (m['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
        hadMedia: (m['hadMedia'] as bool?) ?? false,
      );
      _showDraftBanner = _pendingDraft != null &&
          (_pendingDraft!.content.trim().isNotEmpty ||
              _pendingDraft!.tags.isNotEmpty ||
              _pendingDraft!.hadMedia);
    } catch (_) {
      _pendingDraft = null;
      _showDraftBanner = false;
    }
  }

  void _restoreDraft() {
    if (_pendingDraft == null) return;
    setState(() {
      _contentCtrl.text = _pendingDraft!.content;
      _tags
        ..clear()
        ..addAll(_pendingDraft!.tags);
      _showDraftBanner = false;
    });
    _scheduleAutoSave();
  }

  void _dismissDraft() {
    ref.read(prefsProvider).remove(_draftKey);
    setState(() {
      _showDraftBanner = false;
      _pendingDraft = null;
    });
  }

  void _saveDraft() {
    final content = _contentCtrl.text;
    final tags = _tags;
    final hasDraft =
        content.trim().isNotEmpty || tags.isNotEmpty || _media.isNotEmpty;
    final prefs = ref.read(prefsProvider);
    if (hasDraft) {
      prefs.setString(
        _draftKey,
        jsonEncode({
          'content': content,
          'tags': tags,
          'hadMedia': _media.isNotEmpty,
        }),
      );
    } else {
      prefs.remove(_draftKey);
    }
  }

  @override
  void dispose() {
    // 任务 A:未发送则存草稿(防丢稿);已发送(_sent=true)则跳过(_send 已清 key)。
    if (!_sent) _saveDraft();
    _autosaveTimer?.cancel();
    _contentCtrl.dispose();
    super.dispose();
  }

  bool get _canSend {
    final text = _contentCtrl.text.trim();
    return text.isNotEmpty || _media.isNotEmpty;
  }

  Future<void> _send() async {
    if (_isPublishing) return;
    final text = _contentCtrl.text.trim();
    if (text.isEmpty && _media.isEmpty) {
      _toast('写点什么再发');
      return;
    }

    setState(() => _isPublishing = true);
    try {
      // 登录 → 真发后端（POST /posts，先上传图拿 media_ids）；未登录/失败 → 本地 mock。
      if (ref.read(authProvider).isLoggedIn) {
        try {
          final mediaIds = await _uploadMedia();
          // ── [ZCode] 纯图无文发送分享图片，不再传空格被后端 reject ──
          await ref.read(postsApiProvider).create({
            'content': text.isEmpty ? '分享图片' : text,
            'tags': _tags,
            if (_quoteProjectId != null) 'quote_project_id': _quoteProjectId,
            if (mediaIds.isNotEmpty) 'media_ids': mediaIds,
          });
          if (!mounted) return;
          ref.invalidate(remotePostsProvider); // 动态流刷新看到新动态
          ref.invalidate(paginatedPostsProvider); // P0-1：分页流也刷新（发现页推荐流）
          // 「关注」流靠 userPostsProvider 补齐我自己的动态，发完也要刷新它才立刻可见。
          final selfId = ref.read(authProvider).currentUser?.id;
          if (selfId != null) ref.invalidate(userPostsProvider(selfId));
          _finish('已发送');
          return;
        } on AppException catch (e) {
          // 上线构建(useRemote)：如实报错并停下，不把失败伪装成「已本地发布」的假成功。
          if (AppConfig.useRemote) {
            if (mounted) _toast('发送失败：${e.message}', error: e);
            return;
          }
          // demo 构建(mock)：落到本地发布，不挡演示。
          if (mounted) _toast('后端未同步（${e.message}），已本地发布');
        } catch (e) {
          // ── [ZCode] 兜底：非 AppException 的错误也要显示 ──
          if (mounted) _toast('发送失败：$e', error: e);
          if (AppConfig.useRemote) return;
        }
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final post = Post(
        id: 'user_post_$now',
        content: text.isEmpty ? '分享图片' : text,
        authorId: 'me',
        media: List.of(_media),
        tags: List.of(_tags),
        quoteProjectId: _quoteProjectId,
        likes: 0,
        commentCount: 0,
        createdAtMs: now,
      );
      ref.read(postRepositoryProvider).addPost(post);
      // 让依赖 postRepositoryProvider 的屏(discover 推荐/关注/profile 动态)刷新
      ref.invalidate(postRepositoryProvider);
      ref.invalidate(paginatedPostsProvider); // P0-1：分页流刷新看到新动态
      _finish('已发送');
    } finally {
      if (mounted && !_sent) setState(() => _isPublishing = false);
    }
  }

  /// 上传图片拿 media_ids（best-effort：某张失败跳过，不挡发布）。
  Future<List<String>> _uploadMedia() async {
    final api = ref.read(mediaApiProvider);
    final ids = <String>[];
    for (final m in _media) {
      final bytes = _mediaBytes[m.url];
      if (bytes == null) {
        throw const AppException(code: 'MEDIA_MISSING', message: '图片需要重新添加');
      }
      try {
        ids.add(await api.upload(bytes));
      } on AppException {
        rethrow;
      } catch (_) {
        throw const AppException(
            code: 'MEDIA_UPLOAD_FAILED', message: '图片上传失败，请重试');
      }
    }
    return ids;
  }

  /// 收尾:清草稿 + 标记已发 + toast + 关屏。
  void _finish(String msg) {
    ref.read(prefsProvider).remove(_draftKey);
    _sent = true;
    _toast(msg);
    context.go('${KkRoutes.discover}?tab=following');
  }

  void _scheduleAutoSave() {
    if (_sent) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 500), _saveDraft);
  }

  bool get _hasUnsavedDraft =>
      _contentCtrl.text.trim().isNotEmpty ||
      _tags.isNotEmpty ||
      _media.isNotEmpty;

  Future<void> _requestClose() async {
    if (!_hasUnsavedDraft) {
      _close();
      return;
    }
    final action = await showModalBottomSheet<_DraftExitAction>(
      context: context,
      backgroundColor: KkColors.bgCard,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KkSpacing.lg,
                KkSpacing.lg,
                KkSpacing.lg,
                KkSpacing.md,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('保存这次编辑？', style: KkType.h3),
              ),
            ),
            _exitSheetItem(
              icon: Icons.save_outlined,
              label: '保存草稿',
              onTap: () => Navigator.pop(sheetCtx, _DraftExitAction.save),
            ),
            const Divider(height: 1, color: KkColors.divider),
            _exitSheetItem(
              icon: Icons.delete_outline,
              label: '丢弃',
              onTap: () => Navigator.pop(sheetCtx, _DraftExitAction.discard),
            ),
            const Divider(height: 1, color: KkColors.divider),
            _exitSheetItem(
              icon: Icons.close,
              label: '继续编辑',
              onTap: () =>
                  Navigator.pop(sheetCtx, _DraftExitAction.keepEditing),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null || action == _DraftExitAction.keepEditing) {
      return;
    }
    if (action == _DraftExitAction.save) {
      _saveDraft();
      _toast('草稿已保存');
    } else {
      ref.read(prefsProvider).remove(_draftKey);
      _sent = true;
    }
    _close();
  }

  /// 关屏兜底(同 KkBackButton):能 pop 就 pop,否则回发现页根。
  /// 修 bug:原来只 `if(canPop) pop()`,栈不可 pop 时「取消」哑火返回不了。
  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(KkRoutes.discover);
    }
  }

  void _toast(String msg, {Object? error}) {
    final code = error is AppException
        ? (error.statusCode != null
            ? 'HTTP_${error.statusCode}_${error.code}'
            : error.code)
        : error?.runtimeType.toString();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          action: error == null
              ? null
              : SnackBarAction(
                  label: '\u53cd\u9988',
                  onPressed: () => showFeedbackSheet(
                    context,
                    sourcePage: KkRoutes.compose,
                    errorCode: code,
                  ),
                ),
        ),
      );
  }

  /// 九宫格选图 — 复用 image_picker.pickMultiImage(同 MediaPicker 图片逻辑),
  /// 不引新依赖、不改 MediaPicker 组件本身(publish 页仍用 MediaPicker)。
  /// 满 9 张截断(Post 最多 9 图)。
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    try {
      final files = await picker.pickMultiImage(imageQuality: 85);
      if (files.isEmpty) return;
      // 读真字节缓存起来（远程发布时真上传后端；web 上传靠它）。
      final picked = <(MediaItem, Uint8List)>[];
      for (final f in files) {
        if (_media.length + picked.length >= 9) break;
        picked.add((
          MediaItem(type: 'image', url: f.path, alt: '本地图片'),
          await f.readAsBytes()
        ));
      }
      if (!mounted) return;
      setState(() {
        for (final (item, bytes) in picked) {
          _media.add(item);
          _mediaBytes[item.url] = bytes;
        }
      });
      _scheduleAutoSave();
    } catch (e) {
      // ── [ZCode] 区分用户取消 vs 真实错误，不能全静默吞掉 ──
      if (mounted) _toast('选图失败：$e');
    }
  }

  /// 话题添加 — 朋友圈式:点底部「话题」行弹 dialog 输入,回车或点「添加」入列。
  void _addTagDialog() {
    final ctrl = TextEditingController();
    void submit() {
      final t = ctrl.text.trim().replaceAll('#', '');
      if (t.isNotEmpty && !_tags.contains(t)) {
        setState(() => _tags.add(t));
        _scheduleAutoSave();
      }
      Navigator.pop(context);
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KkColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KkRadius.lg),
        ),
        title: Text('添加话题', style: KkType.h3),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: KkType.body,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: '# 话题',
            hintStyle: KkType.body.copyWith(color: KkColors.t3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KkRadius.sm),
              borderSide: const BorderSide(color: KkColors.bd),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KkRadius.sm),
              borderSide: const BorderSide(color: KkColors.teal, width: 1.2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: KkSpacing.md,
              vertical: KkSpacing.md,
            ),
          ),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: KkType.body.copyWith(color: KkColors.t2)),
          ),
          TextButton(
            onPressed: submit,
            child: Text('添加',
                style: KkType.body.copyWith(
                    color: KkColors.teal, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        backgroundColor: KkColors.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _topBar(),
              // 任务 A:草稿恢复横条(进屏时 prefs 有草稿才显;恢复/忽略后消失)。
              if (_showDraftBanner) _draftBanner(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: KkSpacing.xxl),
                  children: [
                    _contentField(),
                    const SizedBox(height: KkSpacing.sm),
                    _imageGrid(),
                    if (_tags.isNotEmpty) ...[
                      const SizedBox(height: KkSpacing.lg),
                      _tagsChips(),
                    ],
                    if (_quoteProjectId != null) ...[
                      const SizedBox(height: KkSpacing.lg),
                      _quoteCard(),
                    ],
                    const SizedBox(height: KkSpacing.xl),
                    // 底部操作条(朋友圈式行):只放已实现入口。
                    _actionRow(
                      icon: Icons.tag_outlined,
                      label: '话题',
                      value: _tags.isEmpty ? null : '已选 ${_tags.length} 个',
                      onTap: _addTagDialog,
                    ),
                    if (_quoteProjectId == null)
                      _actionRow(
                        icon: Icons.link,
                        label: '引用项目',
                        onTap: _pickProject,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 顶栏(取消纯文字 / 发表绿胶囊;中间留白,朋友圈式)──
  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.sm,
        vertical: KkSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: KkColors.divider)),
      ),
      child: Row(
        children: [
          Tappable(
            onTap: _isPublishing ? null : _requestClose,
            child: Padding(
              padding: const EdgeInsets.all(KkSpacing.md),
              child:
                  Text('取消', style: KkType.body.copyWith(color: KkColors.t2)),
            ),
          ),
          const Spacer(),
          // 朋友圈式:中间留白(极简,不放标题)
          const Spacer(),
          Tappable(
            // ── [ZCode] 按钮始终可点，让用户看到具体报错，不静默失败 ──
            onTap: _isPublishing ? null : _send,
            borderRadius: BorderRadius.circular(KkRadius.pill),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: KkSpacing.lg,
                vertical: KkSpacing.sm,
              ),
              decoration: BoxDecoration(
                // 空内容置灰(非 coral;发表不是 take,用 teal)
                color: _isPublishing
                    ? KkColors.t4
                    : (_canSend ? KkColors.teal : KkColors.t4),
                borderRadius: BorderRadius.circular(KkRadius.pill),
              ),
              child: Text(
                _isPublishing ? '发布中' : '发表',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'NotoSerifSC',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 任务 A:草稿恢复横条(bgSubtle 底 + 一行字 + 恢复/忽略;hadMedia 时加小字提示)──
  Widget _draftBanner() {
    final hadMedia = _pendingDraft?.hadMedia ?? false;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: KkColors.bgSubtle,
        border: Border(bottom: BorderSide(color: KkColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '恢复上次草稿?',
                  style: KkType.bodySm.copyWith(
                    color: KkColors.t1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (hadMedia)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '图片需重新添加',
                      style: KkType.mono.copyWith(
                        fontSize: 10,
                        color: KkColors.t3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Tappable(
            onTap: _dismissDraft,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KkSpacing.md,
                vertical: KkSpacing.sm,
              ),
              child: Text(
                '忽略',
                style: KkType.bodySm.copyWith(color: KkColors.t3),
              ),
            ),
          ),
          Tappable(
            onTap: _restoreDraft,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KkSpacing.md,
                vertical: KkSpacing.sm,
              ),
              child: Text(
                '恢复',
                style: KkType.bodySm.copyWith(
                  color: KkColors.teal,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 多行文字(主输入区,朋友圈式大留白;0/500 淡计数)──
  Widget _contentField() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.lg,
      ),
      child: TextField(
        controller: _contentCtrl,
        autofocus: true,
        maxLines: 8,
        minLines: 4,
        maxLength: 500,
        style: KkType.body,
        decoration: InputDecoration(
          hintText: '这一刻的想法…',
          hintStyle: KkType.body.copyWith(color: KkColors.t3),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
          counterStyle: KkType.mono.copyWith(fontSize: 10, color: KkColors.t3),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  // ── 九宫格图片区(3 列,近正方形圆角,×移除,末尾虚线+添加格)──
  Widget _imageGrid() {
    final screenW = MediaQuery.of(context).size.width;
    // 3 列:屏宽 - 左右 padding(2*lg) - 2 个间隙(2*xs)。
    // 防御:首帧/过渡期屏宽可能为 0（引擎 "Width is zero" 帧），算出的 cellSize 会变负，
    // 负尺寸的格子会让整屏布局失败→黑屏。宽度非正时先用兜底值，下一帧宽度正常再重算。
    final usableW = screenW - 2 * KkSpacing.lg - 2 * KkSpacing.xs;
    final cellSize = usableW > 3 ? usableW / 3 : 100.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Wrap(
        spacing: KkSpacing.xs,
        runSpacing: KkSpacing.xs,
        children: [
          for (int i = 0; i < _media.length; i++)
            _GridThumb(
              media: _media[i],
              size: cellSize,
              onRemove: () {
                setState(() => _media.removeAt(i));
                _scheduleAutoSave();
              },
            ),
          if (_media.length < 9) _AddCell(size: cellSize, onTap: _pickImage),
        ],
      ),
    );
  }

  // ── 已选话题 chip 排(可删)──
  Widget _tagsChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Wrap(
        spacing: KkSpacing.sm,
        runSpacing: KkSpacing.sm,
        children: [
          for (final t in _tags)
            _TagChip(
              tag: t,
              onRemove: () {
                setState(() => _tags.remove(t));
                _scheduleAutoSave();
              },
            ),
        ],
      ),
    );
  }

  // ── 引用项目卡(已选态,可删/跳详情)──
  Widget _quoteCard() {
    final repo = ref.read(projectRepositoryProvider);
    final project = _quoteProject ?? repo.byId(_quoteProjectId!);
    if (project == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: _QuoteProjectCard(
        project: project,
        onRemove: () => setState(() {
          _quoteProjectId = null;
          _quoteProject = null;
        }),
      ),
    );
  }

  // ── 底部操作条行(朋友圈式:icon + 标签 + 值 + 箭头,顶分隔线)──
  Widget _actionRow({
    required IconData icon,
    required String label,
    String? value,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: KkColors.divider)),
      ),
      child: Tappable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KkSpacing.lg,
            vertical: KkSpacing.md,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: KkColors.t2),
              const SizedBox(width: KkSpacing.md),
              Text(label, style: KkType.body),
              const Spacer(),
              if (value != null) ...[
                Flexible(
                  child: Text(
                    value,
                    style: KkType.bodySm.copyWith(color: KkColors.t3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: KkSpacing.xs),
              ],
              const Icon(Icons.chevron_right, size: 18, color: KkColors.t3),
            ],
          ),
        ),
      ),
    );
  }

  /// 选引用项目 — 只展示真实相关来源：我的作品 / 收藏 / 最近看过的项目。
  Future<void> _pickProject() async {
    final repo = ref.read(projectRepositoryProvider);
    final sections = <({String title, List<Project> projects})>[];
    final seen = <String>{};
    List<Project> dedupe(List<Project> items) {
      final out = <Project>[];
      for (final p in items) {
        if (seen.add(p.id)) out.add(p);
      }
      return out;
    }

    if (AppConfig.useRemote && ref.read(authProvider).isLoggedIn) {
      final mine = dedupe(await ref.read(myProjectsProvider.future));
      if (mine.isNotEmpty) sections.add((title: '我的作品', projects: mine));

      final favs = dedupe(await ref.read(remoteFavoritesProvider.future));
      if (favs.isNotEmpty) sections.add((title: '收藏', projects: favs));

      final recent = <Project>[];
      for (final id in ref.read(appStateProvider).browseHistory.take(12)) {
        final p = await ref.read(projectByIdProvider(id).future);
        if (p != null) recent.add(p);
      }
      final recentDeduped = dedupe(recent);
      if (recentDeduped.isNotEmpty) {
        sections.add((title: '最近看过的项目', projects: recentDeduped));
      }
    } else {
      final local = dedupe(repo.all().take(20).toList());
      if (local.isNotEmpty) sections.add((title: '可引用项目', projects: local));
    }

    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KkColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KkRadius.xl)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(KkSpacing.lg),
              child: Row(
                children: [
                  Text('引用项目', style: KkType.h3),
                  const Spacer(),
                  Tappable(
                    onTap: () => Navigator.pop(sheetCtx),
                    child:
                        const Icon(Icons.close, size: 22, color: KkColors.t1),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: KkColors.divider),
            Flexible(
              child: sections.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(KkSpacing.xl),
                      child: Text(
                        '还没有可引用的项目',
                        style: KkType.body.copyWith(color: KkColors.t3),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final section in sections) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              KkSpacing.lg,
                              KkSpacing.lg,
                              KkSpacing.lg,
                              KkSpacing.xs,
                            ),
                            child: Text(
                              section.title,
                              style: KkType.bodySm.copyWith(
                                color: KkColors.t3,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          for (final p in section.projects)
                            Tappable(
                              onTap: () {
                                setState(() {
                                  _quoteProjectId = p.id;
                                  _quoteProject = p;
                                });
                                Navigator.pop(sheetCtx);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: KkSpacing.lg,
                                  vertical: KkSpacing.md,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.article_outlined,
                                        size: 20, color: KkColors.t2),
                                    const SizedBox(width: KkSpacing.md),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.title,
                                            style: KkType.body,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (p.summary.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              p.summary,
                                              style: KkType.bodySm.copyWith(
                                                color: KkColors.t3,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right,
                                        size: 18, color: KkColors.t3),
                                  ],
                                ),
                              ),
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

  Widget _exitSheetItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Tappable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.lg,
          vertical: KkSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: KkColors.t2),
            const SizedBox(width: KkSpacing.md),
            Text(label, style: KkType.body),
          ],
        ),
      ),
    );
  }
}

// ── 九宫格缩略图(圆角 + 右上×移除)──
class _GridThumb extends StatelessWidget {
  final MediaItem media;
  final double size;
  final VoidCallback onRemove;

  const _GridThumb({
    required this.media,
    required this.size,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(KkRadius.sm),
            child: SizedBox.expand(child: _buildImage()),
          ),
          // 右上×移除(热区 44,视觉小圆贴角)
          Positioned(
            right: 0,
            top: 0,
            child: Tappable(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(KkRadius.pill),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Color(0xCC000000),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    if (media.url.startsWith('http')) {
      return Image.network(media.url,
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder());
    }
    // 本地选取的图片：移动端 Image.file / web blob URL → 真显示（不再用随机占位图）。
    return localImage(media.url,
        fit: BoxFit.cover, placeholder: _placeholder());
  }

  Widget _placeholder() {
    return Container(
      color: KkColors.bgSubtle,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: KkColors.t3, size: 24),
    );
  }
}

// ── 九宫格末尾虚线+添加格(满 9 隐藏)──
class _AddCell extends StatelessWidget {
  final double size;
  final VoidCallback onTap;

  const _AddCell({required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Tappable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KkRadius.sm),
        child: Container(
          decoration: BoxDecoration(
            color: KkColors.bgSubtle,
            borderRadius: BorderRadius.circular(KkRadius.sm),
          ),
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: KkColors.bd,
              radius: KkRadius.sm,
            ),
            child: Center(
              child: Icon(Icons.add, size: 28, color: KkColors.t3),
            ),
          ),
        ),
      ),
    );
  }
}

/// 虚线圆角边框 painter(九宫格「+」添加格用)。
/// 用 PathMetric 沿 RRect 路径等距取 dash,得真圆角虚线(非四边直线凑)。
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, this.radius = KkRadius.sm});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dashWidth = 4.0;
    const dashGap = 3.0;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}

// ── 话题 chip(可删)──
class _TagChip extends StatelessWidget {
  final String tag;
  final VoidCallback onRemove;

  const _TagChip({required this.tag, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.md,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: KkColors.mint,
        borderRadius: BorderRadius.circular(KkRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#$tag',
            style: KkType.bodySm.copyWith(color: KkColors.teal),
          ),
          const SizedBox(width: KkSpacing.xs),
          Tappable(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 12, color: KkColors.teal),
          ),
        ],
      ),
    );
  }
}

// ── 引用项目小卡(已选态,可删/跳详情)──
class _QuoteProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onRemove;

  const _QuoteProjectCard({required this.project, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KkSpacing.md),
      decoration: BoxDecoration(
        color: KkColors.bgSubtle,
        borderRadius: BorderRadius.circular(KkRadius.md),
        border: Border.all(color: KkColors.bd),
      ),
      child: Row(
        children: [
          const Icon(Icons.article_outlined, size: 18, color: KkColors.teal),
          const SizedBox(width: KkSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  project.title,
                  style: KkType.bodySm.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '@ 引用项目',
                  style: KkType.mono.copyWith(fontSize: 10, color: KkColors.t3),
                ),
              ],
            ),
          ),
          const SizedBox(width: KkSpacing.sm),
          Tappable(
            onTap: () => context.push(KkRoutes.detail(project.id)),
            child: const Icon(Icons.open_in_new, size: 16, color: KkColors.t3),
          ),
          const SizedBox(width: KkSpacing.xs),
          Tappable(
            onTap: () {
              onRemove();
            },
            child: const Icon(Icons.close, size: 16, color: KkColors.t3),
          ),
        ],
      ),
    );
  }
}

// ── 任务 A:compose 草稿数据(只存文本类字段;媒体 blob URL 刷新失效不存)──
class _ComposeDraft {
  final String content;
  final List<String> tags;
  final bool hadMedia;

  const _ComposeDraft({
    required this.content,
    required this.tags,
    required this.hadMedia,
  });
}
