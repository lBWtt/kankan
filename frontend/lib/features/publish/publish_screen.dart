import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/network/app_exception.dart';
import '../../core/prefs.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/noise_background.dart';
import '../../core/widgets/tappable.dart';
import '../../data/api/media_api.dart';
import '../../data/api/projects_api.dart';
import '../../data/api/activity_api.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/project_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/paginated_projects_provider.dart';
import '../../providers/publish_provider.dart';
import '../../providers/remote_project_provider.dart';
import '../../router/routes.dart';
import '../feedback/feedback_sheet.dart';
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

enum _DraftExitAction { save, discard, keepEditing }

class _PublishScreenState extends ConsumerState<PublishScreen> {
  // 任务 A:草稿恢复(文本类字段;媒体 blob URL 刷新失效不存)。
  _PublishDraftSnapshot? _pendingDraft;
  bool _showDraftBanner = false;
  bool _sent = false;
  bool _isPublishing = false;
  Timer? _autosaveTimer;

  // 剪贴板里检测到的链接(进屏时读一次;给「体验地址」一键粘贴)。
  String? _clipboardUrl;
  final TextEditingController _tryUrlCtrl = TextEditingController();

  // 可选项默认收起（渐进式展开：首屏只留主角，点小图标才展开输入，降低"一堆要填"的畏难感）。
  bool _linkOpen = false;
  bool _tagsOpen = false;

  @override
  void initState() {
    super.initState();
    _loadDraft();
    _detectClipboardUrl();
  }

  String get _draftKey =>
      '${ref.read(authProvider).currentUser?.id ?? 'guest'}::${PrefsKeys.draftPublish}';

  /// 读剪贴板,若是 http/https 链接就记下来,在「体验地址」下方提示一键粘贴。
  Future<void> _detectClipboardUrl() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final t = data?.text?.trim() ?? '';
      if ((t.startsWith('http://') || t.startsWith('https://')) &&
          !t.contains(' ') &&
          t.length <= 2000) {
        if (mounted) setState(() => _clipboardUrl = t);
      }
    } catch (_) {
      // 剪贴板不可用,静默
    }
  }

  void _loadDraft() {
    // 当前 draft state 非空(内存里跨屏保留)→ 不弹横条(用户在编辑中)。
    // draft state 空(const 初始,app 重启后)→ 读 prefs,有草稿则弹横条。
    final c = ref.read(publishDraftProvider);
    final hasContent = c.title.isNotEmpty ||
        c.summary.isNotEmpty ||
        c.authorNote.isNotEmpty ||
        (c.text != null && c.text!.isNotEmpty) ||
        c.tags.isNotEmpty ||
        c.tryUrl.isNotEmpty ||
        c.actions.isNotEmpty;
    if (hasContent) {
      _showDraftBanner = false;
      return;
    }
    final raw = ref.read(prefsProvider).getString(_draftKey);
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
        tryUrl: (m['tryUrl'] as String?) ?? '',
        hadActions: (m['hadActions'] as bool?) ?? false,
        hadMedia: (m['hadMedia'] as bool?) ?? false,
      );
      final d = _pendingDraft!;
      _showDraftBanner = d.title.isNotEmpty ||
          d.summary.isNotEmpty ||
          d.authorNote.isNotEmpty ||
          d.text.isNotEmpty ||
          d.tags.isNotEmpty ||
          d.tryUrl.isNotEmpty ||
          d.hadActions;
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
    if (d.tryUrl.isNotEmpty) {
      n.setTryUrl(d.tryUrl);
      _tryUrlCtrl.text = d.tryUrl;
      _linkOpen = true;
    }
    if (d.domain != null) n.setDomain(d.domain!);
    for (final t in d.tags) {
      n.addTag(t);
    }
    setState(() => _showDraftBanner = false);
  }

  void _dismissDraft() {
    ref.read(prefsProvider).remove(_draftKey);
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
        d.tags.isNotEmpty ||
        d.tryUrl.isNotEmpty ||
        d.actions.isNotEmpty;
    final prefs = ref.read(prefsProvider);
    if (hasDraft) {
      prefs.setString(
        _draftKey,
        jsonEncode({
          'title': d.title,
          'summary': d.summary,
          'authorNote': d.authorNote,
          'text': d.text ?? '',
          'tags': d.tags,
          'domain': d.domain,
          'tryUrl': d.tryUrl,
          'hadActions': d.actions.isNotEmpty,
          'hadMedia': d.media.isNotEmpty,
        }),
      );
    } else {
      prefs.remove(_draftKey);
    }
  }

  @override
  void dispose() {
    _tryUrlCtrl.dispose();
    _autosaveTimer?.cancel();
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
    ref.listen<PublishDraft>(publishDraftProvider, (_, __) {
      _scheduleAutoSave();
    });
    final draft = ref.watch(publishDraftProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose(context, ref);
      },
      child: Scaffold(
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
                // 整个编辑区放进一张干净白卡（浮在暖色噪点底上）——从"半成品平铺"变"精致画布"。
                // 卡内：作品主角（大媒体）+ 名字/一句话 + 一排可选胶囊（点开才展开），留白式。
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(
                        KkSpacing.md, KkSpacing.sm, KkSpacing.md, 0),
                    decoration: const BoxDecoration(
                      color: KkColors.bgCard,
                      borderRadius: BorderRadius.vertical(
                          top: Radius.circular(KkRadius.xl)),
                      boxShadow: KkElevation.overlay,
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(KkRadius.xl)),
                      child: ListView(
                        padding: const EdgeInsets.only(
                            top: KkSpacing.xl, bottom: KkSpacing.xxl),
                        children: [
                          // 作品是主角：媒体放最上（大、邀请感）
                          _mediaBlock(context, ref, draft.media),
                          // 只两样"主"字段：名字（大）+ 一句话（灰、可选），无框留白
                          _titleSummary(ref),
                          // 原创 / 转载 声明（用户明确要）：说明是自己做的还是搬运的；转载需注明来源。
                          _originalToggle(ref, draft),
                          const SizedBox(height: KkSpacing.sm),
                          const Divider(
                            indent: KkSpacing.lg,
                            endIndent: KkSpacing.lg,
                            color: KkColors.divider,
                            height: KkSpacing.xl,
                          ),
                          // 可选项收进一排胶囊，点开才展开对应输入（已填的高亮）
                          _optionalBar(context, ref, draft),
                          if (_linkVisible(draft)) _linkField(ref),
                          if (draft.actions.isNotEmpty)
                            _attachmentsList(ref, draft.actions),
                          if (_tagsVisible(draft)) _tagsField(ref, draft.tags),
                          // 预览（有内容才显示，避免空标题悬着）
                          if (draft.title.trim().isNotEmpty ||
                              draft.media.isNotEmpty)
                            _previewBlock(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 原创 / 转载 声明 ──
  Widget _originalToggle(WidgetRef ref, PublishDraft draft) {
    final n = ref.read(publishDraftProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          KkSpacing.lg, KkSpacing.sm, KkSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _segChip('原创作品', draft.isOriginal, () => n.setIsOriginal(true)),
              const SizedBox(width: KkSpacing.sm),
              _segChip('转载分享', !draft.isOriginal, () => n.setIsOriginal(false)),
            ],
          ),
          if (!draft.isOriginal) ...[
            const SizedBox(height: KkSpacing.sm),
            TextField(
              onChanged: n.setSourceUrl,
              keyboardType: TextInputType.url,
              style: KkType.bodySm,
              decoration: InputDecoration(
                isDense: true,
                hintText: '来源链接（转载必填，注明出处）',
                hintStyle: KkType.bodySm.copyWith(color: KkColors.t4),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(KkRadius.md)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: KkSpacing.md, vertical: KkSpacing.sm),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _segChip(String label, bool active, VoidCallback onTap) {
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KkRadius.pill),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: KkSpacing.md, vertical: 6),
        decoration: BoxDecoration(
          color: active ? KkColors.teal : KkColors.bgSubtle,
          borderRadius: BorderRadius.circular(KkRadius.pill),
          border: Border.all(color: active ? KkColors.teal : KkColors.bd),
        ),
        child: Text(
          label,
          style: KkType.bodySm.copyWith(
            color: active ? Colors.white : KkColors.t2,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
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
            onTap: () => _requestClose(context, ref),
            child: const Padding(
              padding: EdgeInsets.all(KkSpacing.md),
              child: Text('取消', style: KkType.body),
            ),
          ),
          const Spacer(),
          Text('发作品', style: KkType.h3),
          const Spacer(),
          Tappable(
            onTap: _isPublishing ? null : () => _publish(context, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: KkSpacing.lg,
                vertical: KkSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: _isPublishing ? KkColors.t4 : KkColors.teal,
                borderRadius: BorderRadius.circular(KkRadius.pill),
              ),
              child: Text(
                _isPublishing ? '发布中' : '发布',
                style: const TextStyle(
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

  bool get _hasUnsavedDraft {
    final d = ref.read(publishDraftProvider);
    return d.title.trim().isNotEmpty ||
        d.summary.trim().isNotEmpty ||
        d.authorNote.trim().isNotEmpty ||
        (d.text?.trim().isNotEmpty ?? false) ||
        d.tags.isNotEmpty ||
        d.tryUrl.trim().isNotEmpty ||
        d.actions.isNotEmpty ||
        d.media.isNotEmpty;
  }

  Future<void> _requestClose(BuildContext context, WidgetRef ref) async {
    if (_isPublishing) return;
    if (!_hasUnsavedDraft) {
      _close(context);
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
              label: '放弃',
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
    if (!context.mounted ||
        action == null ||
        action == _DraftExitAction.keepEditing) {
      return;
    }
    if (action == _DraftExitAction.save) {
      _saveDraft();
      _toast(context, '草稿已保存');
    } else {
      ref.read(prefsProvider).remove(_draftKey);
      _sent = true;
    }
    _close(context);
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

  // 填充式输入外壳：bgSubtle 圆角底 + 可选前缀图标，让输入区一眼看出"能填"。
  Widget _filledInput({IconData? icon, required Widget field}) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: KkSpacing.md, vertical: 2),
      decoration: BoxDecoration(
        color: KkColors.bgSubtle,
        borderRadius: BorderRadius.circular(KkRadius.md),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: KkColors.t3),
            const SizedBox(width: KkSpacing.sm),
          ],
          Expanded(child: field),
        ],
      ),
    );
  }

  bool _linkVisible(PublishDraft d) => _linkOpen || d.tryUrl.trim().isNotEmpty;
  bool _tagsVisible(PublishDraft d) => _tagsOpen || d.tags.isNotEmpty;

  void _saveDraftNow(BuildContext context) {
    _saveDraft();
    _toast(context, '草稿已保存');
  }

  // ── 成果区:传图/视频（作品是主角，最上、留白）──
  Widget _mediaBlock(
      BuildContext context, WidgetRef ref, List<MediaItem> media) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          KkSpacing.lg, 0, KkSpacing.lg, KkSpacing.xs),
      child: MediaPicker(
        current: media,
        onPicked: ref.read(publishDraftProvider.notifier).addMedia,
        onRemoved: ref.read(publishDraftProvider.notifier).removeMediaAt,
      ),
    );
  }

  // ── 作品名（大） + 一句话（灰、可选）——留白式无框，像在写标题 ──
  Widget _titleSummary(WidgetRef ref) {
    final n = ref.read(publishDraftProvider.notifier);
    final draft = ref.watch(publishDraftProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          KkSpacing.lg, KkSpacing.md, KkSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            onChanged: n.setTitle,
            style: KkType.h1,
            minLines: 1,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: '给作品起个名字',
              hintStyle: KkType.h1.copyWith(color: KkColors.t3),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: KkSpacing.xs),
          TextField(
            onChanged: n.setSummary,
            style: KkType.body.copyWith(color: KkColors.t2),
            minLines: 1,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: '一句话亮点，例如：把 Git 日志变成可读周报',
              hintStyle: KkType.body.copyWith(color: KkColors.t3),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: KkSpacing.lg),
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: KkColors.mint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.notes_rounded,
                    size: 17, color: KkColors.teal),
              ),
              const SizedBox(width: KkSpacing.sm),
              Text('作品详情', style: KkType.h3),
              const Spacer(),
              Text(
                '${draft.authorNote.trim().length}',
                style: KkType.mono.copyWith(
                  fontSize: 11,
                  color: KkColors.t3,
                ),
              ),
            ],
          ),
          const SizedBox(height: KkSpacing.sm),
          _filledInput(
            field: TextField(
              onChanged: n.setAuthorNote,
              minLines: 3,
              maxLines: 8,
              style: KkType.body.copyWith(height: 1.65, color: KkColors.t1),
              decoration: InputDecoration(
                hintText: '问题、用法、亮点，想写多少写多少。',
                hintStyle:
                    KkType.body.copyWith(color: KkColors.t3, height: 1.65),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: KkSpacing.sm),
          Tappable(
            onTap: () => _saveDraftNow(context),
            borderRadius: BorderRadius.circular(KkRadius.pill),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KkSpacing.sm,
                vertical: 4,
              ),
              child: Text(
                '存草稿',
                style: KkType.bodySm.copyWith(color: KkColors.t3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 可选项胶囊排：体验链接 / 话题 / 附件（点开才展开；已填的高亮）──
  Widget _optionalBar(BuildContext context, WidgetRef ref, PublishDraft draft) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.lg, vertical: KkSpacing.xs),
      child: Wrap(
        spacing: KkSpacing.sm,
        runSpacing: KkSpacing.sm,
        children: [
          _optPill(Icons.link_rounded, '体验链接', active: _linkVisible(draft),
              onTap: () {
            if (_linkVisible(draft)) {
              _tryUrlCtrl.clear();
              ref.read(publishDraftProvider.notifier).setTryUrl('');
              setState(() => _linkOpen = false);
            } else {
              setState(() => _linkOpen = true);
            }
          }),
          _optPill(Icons.tag, '话题',
              active: _tagsVisible(draft),
              onTap: () => setState(() => _tagsOpen = !_tagsOpen)),
          _optPill(Icons.attach_file,
              draft.actions.isEmpty ? '附件' : '附件 · ${draft.actions.length}',
              active: draft.actions.isNotEmpty,
              onTap: () => _showAddSheet(context, ref)),
        ],
      ),
    );
  }

  Widget _optPill(IconData icon, String label,
      {required bool active, required VoidCallback onTap}) {
    final c = active ? KkColors.teal : KkColors.t3;
    // GestureDetector（非 Tappable）：Tappable 内部 Center+minHeight 会在 Wrap 里撑满整行
    // → 每个胶囊独占一行居中。GestureDetector 自适应内容宽，三颗胶囊并成一排。
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
            horizontal: KkSpacing.md, vertical: KkSpacing.sm),
        decoration: BoxDecoration(
          color: active ? KkColors.mint : KkColors.bgSubtle,
          borderRadius: BorderRadius.circular(KkRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: c),
            const SizedBox(width: KkSpacing.xs),
            Text(label,
                style: KkType.bodySm.copyWith(
                    color: c,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  // ── 体验链接输入（展开时）：填充式 + 剪贴板一键粘贴 ──
  Widget _linkField(WidgetRef ref) {
    final draft = ref.watch(publishDraftProvider);
    final showPaste = _clipboardUrl != null &&
        _clipboardUrl!.isNotEmpty &&
        draft.tryUrl.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          KkSpacing.lg, KkSpacing.sm, KkSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _filledInput(
            icon: _linkIcon(draft.tryUrl),
            field: TextField(
              controller: _tryUrlCtrl,
              onChanged: ref.read(publishDraftProvider.notifier).setTryUrl,
              keyboardType: TextInputType.url,
              autofocus: _linkOpen && draft.tryUrl.isEmpty,
              style: KkType.body.copyWith(color: KkColors.t2),
              decoration: InputDecoration(
                hintText: 'https://…（作品网站 / app 地址）',
                hintStyle: KkType.body.copyWith(color: KkColors.t3),
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: KkSpacing.sm),
              ),
            ),
          ),
          if (showPaste) ...[
            const SizedBox(height: KkSpacing.sm),
            _pasteChip(ref),
          ],
        ],
      ),
    );
  }

  IconData _linkIcon(String url) {
    final value = url.toLowerCase();
    if (value.contains('github.com')) return Icons.code_rounded;
    if (value.contains('apps.apple.com')) return Icons.apple;
    if (value.contains('play.google.com')) return Icons.android;
    return Icons.public_rounded;
  }

  // ── 附件列表（复制/下载/外链 chips；由 附件 胶囊打开 sheet 添加）──
  Widget _attachmentsList(WidgetRef ref, List<ActionItem> actions) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          KkSpacing.lg, KkSpacing.sm, KkSpacing.lg, 0),
      child: Column(
        children: [
          for (var i = 0; i < actions.length; i++)
            _ActionChip(
              action: actions[i],
              onRemove: () =>
                  ref.read(publishDraftProvider.notifier).removeActionAt(i),
            ),
        ],
      ),
    );
  }

  Widget _pasteChip(WidgetRef ref) {
    return Tappable(
      onTap: () {
        final url = _clipboardUrl!;
        _tryUrlCtrl.text = url;
        ref.read(publishDraftProvider.notifier).setTryUrl(url);
        setState(() => _clipboardUrl = null);
      },
      borderRadius: BorderRadius.circular(KkRadius.pill),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: KkSpacing.sm, vertical: 5),
        decoration: BoxDecoration(
          color: KkColors.mint,
          borderRadius: BorderRadius.circular(KkRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.content_paste, size: 13, color: KkColors.teal),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '检测到链接，粘贴',
                style:
                    KkType.bodySm.copyWith(color: KkColors.teal, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 话题输入（展开时）：已加 chips + 填充式输入 ──
  Widget _tagsField(WidgetRef ref, List<String> tags) {
    final ctrl = TextEditingController();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          KkSpacing.lg, KkSpacing.sm, KkSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          _filledInput(
            icon: Icons.tag,
            field: TextField(
              controller: ctrl,
              autofocus: _tagsOpen && tags.isEmpty,
              style: KkType.body,
              decoration: InputDecoration(
                hintText: '话题（回车加）',
                hintStyle: KkType.body.copyWith(color: KkColors.t3),
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: KkSpacing.sm),
              ),
              onSubmitted: (v) {
                final t = v.trim().replaceAll('#', '');
                if (t.isNotEmpty) {
                  ref.read(publishDraftProvider.notifier).addTag(t);
                  ctrl.clear();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── 预览（有内容才显示，避免空标题悬着）：低调小标题 + 预览卡 ──
  Widget _previewBlock() {
    return Padding(
      padding: const EdgeInsets.only(top: KkSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                KkSpacing.lg, 0, KkSpacing.lg, KkSpacing.sm),
            child: Row(
              children: [
                const Icon(Icons.visibility_outlined,
                    size: 14, color: KkColors.t3),
                const SizedBox(width: KkSpacing.xs),
                Text('预览', style: KkType.bodySm.copyWith(color: KkColors.t3)),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: KkSpacing.lg),
            child: PublishPreview(),
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
    if (_isPublishing) return;
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
    // 转载必须注明来源（后端也会拒，前端先友好拦一下）。
    if (!draft.isOriginal && draft.sourceUrl.trim().isEmpty) {
      _toast(context, '转载请填来源链接');
      return;
    }

    setState(() => _isPublishing = true);
    try {
      // 登录 → 先真发后端(POST /projects)。成功用返回的真项目(真 uuid)入 feed;
      // 准入不过(409)提示文案、留草稿让用户补方法;其它错回退本地发布。
      // 未登录 → 本地 mock 发布(保持演示)。
      if (ref.read(authProvider).isLoggedIn) {
        try {
          final mediaIds = await _uploadMedia(ref, draft);
          final remote = await ref
              .read(projectsApiProvider)
              .create(draft.toCreateJson(mediaIds: mediaIds));
          if (!context.mounted) return;
          _addAndFinish(context, ref, remote, '已发布');
          return;
        } on AppException catch (e) {
          if (!context.mounted) return;
          if (e.code == 'PUBLISH_GATE_FAILED') {
            // 纯单图无方法 → 红线拒发。不入库,不重置草稿,让用户补方法后重发。
            _toast(context, e.message);
            return;
          }
          // 上线构建(useRemote)：不掩盖后端错——如实报错，让 API/鉴权/上传/DB 问题暴露，
          // 不再把失败伪装成「已本地发布」的假成功。
          if (AppConfig.useRemote) {
            _toast(context, '发布失败：${e.message}', error: e);
            return;
          }
          // demo 构建(mock)：回退本地发布,不挡演示。
          final local = draft.toProject(
            id: 'user_${DateTime.now().millisecondsSinceEpoch}',
            authorId: 'me',
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
          );
          _addAndFinish(context, ref, local, '已本地发布(后端未同步)');
          return;
        }
      }

      final from = Uri.encodeComponent(KkRoutes.publish);
      context.push('${KkRoutes.login}?from=$from');
    } finally {
      if (context.mounted && !_sent) setState(() => _isPublishing = false);
    }
  }

  /// 把草稿里的图/视频真上传后端，返回 media_ids（保持草稿顺序，首张作封面）。
  /// 媒体上传失败会阻断发布，避免预览里有图/视频但最终详情缺失。
  Future<List<String>> _uploadMedia(WidgetRef ref, PublishDraft draft) async {
    final notifier = ref.read(publishDraftProvider.notifier);
    final api = ref.read(mediaApiProvider);
    final ids = <String>[];
    for (final m in draft.media) {
      final bytes = notifier.bytesFor(m.url);
      if (bytes == null) {
        throw const AppException(
          code: 'MEDIA_MISSING',
          message: '图片或视频需要重新添加',
        );
      }
      try {
        ids.add(await api.upload(bytes));
      } on AppException {
        rethrow;
      } catch (_) {
        throw const AppException(
          code: 'MEDIA_UPLOAD_FAILED',
          message: '图片或视频上传失败，请重试',
        );
      }
    }
    return ids;
  }

  /// 收尾:项目入内存 repo + 刷新依赖屏 + toast + 清草稿 + 返回。
  void _addAndFinish(
      BuildContext context, WidgetRef ref, Project project, String msg) {
    if (!AppConfig.useRemote) {
      ref.read(projectRepositoryProvider).add(project);
      ref.invalidate(projectRepositoryProvider);
    }
    ref.invalidate(paginatedProjectsProvider); // P0-1：分页流刷新看到新项目
    ref.invalidate(myProjectsProvider);
    ref.invalidate(myActivityProvider);
    _toast(context, msg);
    ref.read(publishDraftProvider.notifier).reset();
    // 任务 A:发布成功清草稿 key + 标记 _sent(dispose 不再存)。
    ref.read(prefsProvider).remove(_draftKey);
    _sent = true;
    context.go('${KkRoutes.kankan}?tab=latest');
  }

  void _scheduleAutoSave() {
    if (_sent) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 500), _saveDraft);
  }

  void _close(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(KkRoutes.discover);
    }
  }

  void _toast(BuildContext context, String msg, {Object? error}) {
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
          action: error == null
              ? null
              : SnackBarAction(
                  label: '\u53cd\u9988',
                  onPressed: () => showFeedbackSheet(
                    context,
                    sourcePage: KkRoutes.publish,
                    errorCode: code,
                  ),
                ),
        ),
      );
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
  final String tryUrl;
  final bool hadActions;
  final bool hadMedia;

  const _PublishDraftSnapshot({
    required this.title,
    required this.summary,
    required this.authorNote,
    required this.text,
    required this.tags,
    required this.domain,
    required this.tryUrl,
    required this.hadActions,
    required this.hadMedia,
  });
}
