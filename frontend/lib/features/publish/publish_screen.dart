import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/app_exception.dart';
import '../../core/prefs.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/noise_background.dart';
import '../../core/widgets/tappable.dart';
import '../../data/api/media_api.dart';
import '../../data/api/projects_api.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/project_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/paginated_projects_provider.dart';
import '../../providers/publish_provider.dart';
import '../../router/routes.dart';
import 'widgets/add_takeaway_sheet.dart';
import 'widgets/media_picker.dart';
import 'widgets/publish_preview.dart';

/// 项目发布屏 — HANDOFF §4:放什么系统猜什么,不让用户选类型。
///
/// 用户只管放东西,类型与拿走方式系统在后台判定:
///   - 传图/视频 → 成果(media),视频自动排前,首张作封面
///   - 写介绍 → 作者的话
///   - 贴文本 → take(复制) / 传文件 → take(下载) / 放链接 → 当场识别 GitHub/App Store/网址 → go
///   - "+"点开底部 sheet 三选一,"再加一样"可重复 → 多个素材
///   - 工作流链接(可选) → how(Phase 3 接)
///   - 全程零旁白、不选类型
///
/// 产出结构 = 详情端可组合渲染所读的 {media(视频优先), actions:[take/go/how]}
class PublishScreen extends ConsumerStatefulWidget {
  const PublishScreen({super.key});

  @override
  ConsumerState<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends ConsumerState<PublishScreen> {
  // 任务 A:草稿恢复(文本类字段;媒体 blob URL 刷新失效不存)。
  _PublishDraftSnapshot? _pendingDraft;
  bool _showDraftBanner = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  void _loadDraft() {
    // 当前 draft state 非空(内存里跨屏保留)→ 不弹横条(用户在编辑中)。
    // draft state 空(const 初始,app 重启后)→ 读 prefs,有草稿则弹横条。
    final c = ref.read(publishDraftProvider);
    final hasContent = c.title.isNotEmpty ||
        c.summary.isNotEmpty ||
        c.authorNote.isNotEmpty ||
        (c.text != null && c.text!.isNotEmpty) ||
        c.tags.isNotEmpty;
    if (hasContent) {
      _showDraftBanner = false;
      return;
    }
    final raw = ref.read(prefsProvider).getString(PrefsKeys.draftPublish);
    if (raw == null || raw.isEmpty) {
      _showDraftBanner = false;
      return;
    }
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _pendingDraft = _PublishDraftSnapshot(
        title: (m['title'] as String?) ?? '',
        summary: (m['summary'] as String?) ?? '',
        authorNote: (m['authorNote'] as String?) ?? '',
        text: (m['text'] as String?) ?? '',
        tags: (m['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
        domain: m['domain'] as String?,
        hadMedia: (m['hadMedia'] as bool?) ?? false,
      );
      final d = _pendingDraft!;
      _showDraftBanner = d.title.isNotEmpty ||
          d.summary.isNotEmpty ||
          d.authorNote.isNotEmpty ||
          d.text.isNotEmpty ||
          d.tags.isNotEmpty;
    } catch (_) {
      _pendingDraft = null;
      _showDraftBanner = false;
    }
  }

  void _restoreDraft() {
    final d = _pendingDraft;
    if (d == null) return;
    final n = ref.read(publishDraftProvider.notifier);
    n.setTitle(d.title);
    n.setSummary(d.summary);
    n.setAuthorNote(d.authorNote);
    if (d.text.isNotEmpty) n.setText(d.text);
    if (d.domain != null) n.setDomain(d.domain!);
    for (final t in d.tags) {
      n.addTag(t);
    }
    setState(() => _showDraftBanner = false);
  }

  void _dismissDraft() {
    ref.read(prefsProvider).remove(PrefsKeys.draftPublish);
    setState(() {
      _showDraftBanner = false;
      _pendingDraft = null;
    });
  }

  void _saveDraft() {
    final d = ref.read(publishDraftProvider);
    final hasDraft = d.title.isNotEmpty ||
        d.summary.isNotEmpty ||
        d.authorNote.isNotEmpty ||
        (d.text != null && d.text!.isNotEmpty) ||
        d.tags.isNotEmpty;
    final prefs = ref.read(prefsProvider);
    if (hasDraft) {
      prefs.setString(
        PrefsKeys.draftPublish,
        jsonEncode({
          'title': d.title,
          'summary': d.summary,
          'authorNote': d.authorNote,
          'text': d.text ?? '',
          'tags': d.tags,
          'domain': d.domain,
          'hadMedia': d.media.isNotEmpty,
        }),
      );
    } else {
      prefs.remove(PrefsKeys.draftPublish);
    }
  }

  @override
  void dispose() {
    // 任务 A:未发送则存草稿(防丢稿);已发送(_sent=true)则跳过(_addAndFinish 已清 key)。
    if (!_sent) _saveDraft();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(publishDraftProvider);

    return Scaffold(
      backgroundColor: KkColors.bg,
      body: NoiseBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 顶栏(发布/取消)
              _topBar(context, ref),
              // 任务 A:草稿恢复横条。
              if (_showDraftBanner) _draftBanner(),
              // 表单
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: KkSpacing.xxl),
                  children: [
                    // 标题
                    _sectionTitle('标题'),
                    _titleField(ref),
                    _sectionDivider(),
                    // 一句话价值
                    _sectionTitle('一句话价值'),
                    _summaryField(ref),
                    _sectionDivider(),
                    // 成果区:传图/视频
                    _sectionTitle('成果', hint: '图 / 视频,视频自动排前'),
                    _mediaSection(context, ref, draft.media),
                    _sectionDivider(),
                    // 素材/actions(已加的列表 + "+" 按钮)
                    _sectionTitle('可拿走的东西', hint: '提示词 / 文件 / 链接'),
                    _actionsSection(context, ref, draft.actions),
                    _sectionDivider(),
                    // 作者的话
                    _sectionTitle('作者的话'),
                    _authorNoteField(ref),
                    _sectionDivider(),
                    // 标签
                    _sectionTitle('话题'),
                    _tagsSection(ref, draft.tags),
                    const SizedBox(height: KkSpacing.xl),
                    // 实时预览(复用 detail 渲染器)
                    _sectionTitle('预览'),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: KkSpacing.lg),
                      child: PublishPreview(),
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

  // ── 顶栏 ──
  Widget _topBar(BuildContext context, WidgetRef ref) {
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
            onTap: () {
              // 任务 A:取消不 reset()(保留 draft state,dispose 存 prefs 防丢稿)。
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(KkRoutes.discover);
              }
            },
            child: const Padding(
              padding: EdgeInsets.all(KkSpacing.md),
              child: Text('取消', style: KkType.body),
            ),
          ),
          const Spacer(),
          Text('发作品', style: KkType.h3),
          const Spacer(),
          Tappable(
            onTap: () => _publish(context, ref),
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
                '发布',
                style: TextStyle(
                  color: Colors.white,
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

  // 任务⑪B:段标题(克制 — t3 小字 + 可选 hint,零旁白)
  Widget _sectionTitle(String label, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KkSpacing.lg, KkSpacing.lg, KkSpacing.lg, KkSpacing.xs),
      child: Row(
        children: [
          // 品牌点(teal 小圆点,克制点缀)
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(right: KkSpacing.sm),
            decoration: const BoxDecoration(
              color: KkColors.teal,
              shape: BoxShape.circle,
            ),
          ),
          Text(
            label,
            style: KkType.bodySm.copyWith(
              color: KkColors.t2,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: KkSpacing.sm),
            Text(
              hint,
              style: KkType.bodySm.copyWith(color: KkColors.t3, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  // 段间分隔(极浅,呼吸感)
  Widget _sectionDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: KkSpacing.sm),
      child: Divider(height: 1, thickness: 0.5, color: KkColors.divider),
    );
  }

  // ── 标题 ──
  Widget _titleField(WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: TextField(
        onChanged: ref.read(publishDraftProvider.notifier).setTitle,
        style: KkType.h2,
        decoration: InputDecoration(
          hintText: '标题',
          hintStyle: KkType.h2.copyWith(color: KkColors.t3),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: KkSpacing.xs),
        ),
      ),
    );
  }

  // ── 一句话价值 ──
  Widget _summaryField(WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: TextField(
        onChanged: ref.read(publishDraftProvider.notifier).setSummary,
        style: KkType.body.copyWith(color: KkColors.t2),
        decoration: InputDecoration(
          hintText: '一句话说价值',
          hintStyle: KkType.body.copyWith(color: KkColors.t3),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: KkSpacing.xs),
        ),
      ),
    );
  }

  // ── 成果区:传图/视频 ──
  Widget _mediaSection(
    BuildContext context,
    WidgetRef ref,
    List<MediaItem> media,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MediaPicker(
            current: media,
            onPicked: ref.read(publishDraftProvider.notifier).addMedia,
            onRemoved: ref.read(publishDraftProvider.notifier).removeMediaAt,
          ),
        ],
      ),
    );
  }

  // ── 素材/actions ──
  Widget _actionsSection(
    BuildContext context,
    WidgetRef ref,
    List<ActionItem> actions,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 已加的素材列表
          for (var i = 0; i < actions.length; i++)
            _ActionChip(
              action: actions[i],
              onRemove: () =>
                  ref.read(publishDraftProvider.notifier).removeActionAt(i),
            ),
          // "+" 按钮(三选一 sheet)
          Tappable(
            onTap: () => _showAddSheet(context, ref),
            borderRadius: BorderRadius.circular(KkRadius.md),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                vertical: KkSpacing.md,
                horizontal: KkSpacing.lg,
              ),
              decoration: BoxDecoration(
                color: KkColors.bgSubtle,
                borderRadius: BorderRadius.circular(KkRadius.md),
                border: Border.all(
                  color: KkColors.bd,
                  style: BorderStyle.solid,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add, size: 18, color: KkColors.teal),
                  const SizedBox(width: KkSpacing.xs),
                  Text(
                    '加素材',
                    style: KkType.bodySm.copyWith(color: KkColors.teal),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 作者的话 ──
  Widget _authorNoteField(WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.xs,
      ),
      child: TextField(
        onChanged: ref.read(publishDraftProvider.notifier).setAuthorNote,
        maxLines: 3,
        minLines: 1,
        style: KkType.body,
        decoration: InputDecoration(
          hintText: '作者的话',
          hintStyle: KkType.body.copyWith(color: KkColors.t3),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: KkSpacing.xs),
        ),
      ),
    );
  }

  // ── 标签 ──
  Widget _tagsSection(WidgetRef ref, List<String> tags) {
    final ctrl = TextEditingController();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 已加标签
          if (tags.isNotEmpty) ...[
            Wrap(
              spacing: KkSpacing.sm,
              runSpacing: KkSpacing.sm,
              children: [
                for (final t in tags)
                  _TagChip(
                    tag: t,
                    onRemove: () =>
                        ref.read(publishDraftProvider.notifier).removeTag(t),
                  ),
              ],
            ),
            const SizedBox(height: KkSpacing.sm),
          ],
          // 输入框(回车加 tag)
          TextField(
            controller: ctrl,
            style: KkType.body,
            decoration: InputDecoration(
              hintText: '# 话题(回车加)',
              hintStyle: KkType.body.copyWith(color: KkColors.t3),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: KkSpacing.xs),
            ),
            onSubmitted: (v) {
              final t = v.trim().replaceAll('#', '');
              if (t.isNotEmpty) {
                ref.read(publishDraftProvider.notifier).addTag(t);
                ctrl.clear();
              }
            },
          ),
        ],
      ),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddTakeawaySheet(
        onAdded: ref.read(publishDraftProvider.notifier).addAction,
      ),
    );
  }

  Future<void> _publish(BuildContext context, WidgetRef ref) async {
    final draft = ref.read(publishDraftProvider);
    // 简单校验:至少有标题 + 一个内容(media 或 actions 或 text)
    if (draft.title.isEmpty) {
      _toast(context, '请填标题');
      return;
    }
    if (draft.media.isEmpty &&
        draft.actions.isEmpty &&
        (draft.text == null || draft.text!.isEmpty)) {
      _toast(context, '至少放一样东西');
      return;
    }

    // 登录 → 先真发后端(POST /projects)。成功用返回的真项目(真 uuid)入 feed;
    // 准入不过(409)提示文案、留草稿让用户补方法;其它错回退本地发布。
    // 未登录 → 本地 mock 发布(保持演示)。
    if (ref.read(authProvider).isLoggedIn) {
      try {
        // 先把图/视频真上传后端拿 media_ids（best-effort：某张失败跳过，不挡发布）。
        final mediaIds = await _uploadMedia(ref, draft);
        final remote = await ref
            .read(projectsApiProvider)
            .create(draft.toCreateJson(mediaIds: mediaIds));
        if (!context.mounted) return;
        _addAndFinish(context, ref, remote, '已发布到「看看」');
        return;
      } on AppException catch (e) {
        if (!context.mounted) return;
        if (e.code == 'PUBLISH_GATE_FAILED') {
          // 纯单图无方法 → 红线拒发。不入库,不重置草稿,让用户补方法后重发。
          _toast(context, e.message);
          return;
        }
        // 网络/其它后端错 → 回退本地发布,不挡用户。
        final local = draft.toProject(
          id: 'user_${DateTime.now().millisecondsSinceEpoch}',
          authorId: 'me',
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        _addAndFinish(context, ref, local, '已本地发布(后端未同步)');
        return;
      }
    }

    // 未登录:本地 mock 发布(内存级,发布后 discover/kankan/profile 重读即见)。
    final project = draft.toProject(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      authorId: 'me',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _addAndFinish(context, ref, project, '已发布: ${project.title}');
  }

  /// 把草稿里的图/视频真上传后端，返回 media_ids（保持草稿顺序，首张作封面）。
  /// best-effort：无字节（旧数据）或单张上传失败都跳过，不阻断发布。
  Future<List<String>> _uploadMedia(WidgetRef ref, PublishDraft draft) async {
    final notifier = ref.read(publishDraftProvider.notifier);
    final api = ref.read(mediaApiProvider);
    final ids = <String>[];
    for (final m in draft.media) {
      final bytes = notifier.bytesFor(m.url);
      if (bytes == null) continue;
      try {
        ids.add(await api.upload(bytes));
      } catch (_) {
        // 单张上传失败：跳过该张，项目仍发布（少一张图）。
      }
    }
    return ids;
  }

  /// 收尾:项目入内存 repo + 刷新依赖屏 + toast + 清草稿 + 返回。
  void _addAndFinish(
      BuildContext context, WidgetRef ref, Project project, String msg) {
    ref.read(projectRepositoryProvider).add(project);
    ref.invalidate(projectRepositoryProvider);
    ref.invalidate(paginatedProjectsProvider); // P0-1：分页流刷新看到新项目
    _toast(context, msg);
    ref.read(publishDraftProvider.notifier).reset();
    // 任务 A:发布成功清草稿 key + 标记 _sent(dispose 不再存)。
    ref.read(prefsProvider).remove(PrefsKeys.draftPublish);
    _sent = true;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(KkRoutes.discover);
    }
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ));
  }
}

// ── 小组件 ──
class _ActionChip extends StatelessWidget {
  final ActionItem action;
  final VoidCallback onRemove;

  const _ActionChip({required this.action, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = _meta(action);
    return Container(
      margin: const EdgeInsets.only(bottom: KkSpacing.sm),
      padding: const EdgeInsets.symmetric(
        vertical: KkSpacing.sm,
        horizontal: KkSpacing.md,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(KkRadius.sm),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: KkSpacing.xs),
          Expanded(
            child: Text(
              label,
              style: KkType.bodySm.copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Tappable(
            onTap: onRemove,
            child: Icon(Icons.close, size: 14, color: color),
          ),
        ],
      ),
    );
  }

  (IconData, String, Color) _meta(ActionItem a) {
    return switch (a) {
      TakeAction(:final takeKind, :final label) => (
          takeKind == 'copy' ? Icons.copy_outlined : Icons.download_outlined,
          label ?? (takeKind == 'copy' ? '复制' : '下载'),
          KkColors.coral, // 珊瑚橙只给 take
        ),
      GoAction(:final url, :final label) => (
          Icons.arrow_outward,
          label ?? url,
          KkColors.teal,
        ),
      HowAction(:final label) => (
          Icons.account_tree_outlined,
          label ?? '工作流',
          KkColors.teal,
        ),
    };
  }
}

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
            child: Icon(Icons.close, size: 12, color: KkColors.teal),
          ),
        ],
      ),
    );
  }
}

// ── 任务 A:publish 草稿快照(只存文本类字段;媒体 blob URL 刷新失效不存)──
class _PublishDraftSnapshot {
  final String title;
  final String summary;
  final String authorNote;
  final String text;
  final List<String> tags;
  final String? domain;
  final bool hadMedia;

  const _PublishDraftSnapshot({
    required this.title,
    required this.summary,
    required this.authorNote,
    required this.text,
    required this.tags,
    required this.domain,
    required this.hadMedia,
  });
}
