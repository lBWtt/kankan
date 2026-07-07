import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/time_ago.dart';
import '../../core/widgets/tappable.dart';
import '../../domain/models/models.dart';
import '../../providers/project_provider.dart';

/// HANDOFF §6.1 评论动作浮层 — 4 浮层拼图的最后一块。
///
/// 长按评论 → 弹出本 sheet,让用户对单条评论执行:
///   回复 / 复制 / 编辑(自己) / 删除(自己) / 举报(他人)
///
/// 设计原则:
///   - 零旁白(HANDOFF §3):无引导文案,只有按钮 label
///   - 触控铁律(HANDOFF §5):所有操作按钮 ≥ 44pt(Tappable 默认 minSize=44)
///   - 珊瑚橙(HANDOFF §5 §2.2):**仅「删除」按钮**用 KkColors.coral
///     (删除 = 拿走(自己评论),符合 take 语义例外;举报**不**用 coral)
///   - 真实计数:无计数(sheet 是操作菜单,非展示)
///   - 字体三声部:标题 NotoSerifSC / 数字 JetBrainsMono / 正文系统 sans
///
/// 调用方负责:
///   - 计算 `isOwn`(评论 authorId == 当前用户 id)
///   - 实现 `onDelete` 时弹二次确认对话框(HANDOFF 防误删)
///   - 实现 `onEdit` 时跳编辑屏或弹编辑 sheet
///   - 实现 `onReport` 时跳举报屏
Future<void> showCommentActionsSheet(
  BuildContext context, {
  required Comment comment,
  required String hostType,
  required String hostId,
  required bool isOwn,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
  VoidCallback? onReport,
  VoidCallback? onCopy,
  VoidCallback? onReply,
  /// 任务⑨:评论内容里提取的 URL(可选)。非空时 sheet 多显「打开链接」,
  /// 点 url_launcher.launchUrl 真开浏览器。空则不显此项。
  String? linkUrl,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: KkColors.bg,
    barrierColor: Colors.black54,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(KkRadius.xl),
      ),
    ),
    builder: (_) => CommentActionsSheet(
      comment: comment,
      hostType: hostType,
      hostId: hostId,
      isOwn: isOwn,
      onEdit: onEdit,
      onDelete: onDelete,
      onReport: onReport,
      onCopy: onCopy,
      onReply: onReply,
      linkUrl: linkUrl,
    ),
  );
}

class CommentActionsSheet extends ConsumerWidget {
  /// 目标评论
  final Comment comment;

  /// 宿主类型 'project' | 'post'
  final String hostType;

  /// 宿主 ID
  final String hostId;

  /// 是否是自己的评论(true → 显示编辑/删除,false → 显示举报)
  final bool isOwn;

  /// 编辑回调(外层弹编辑屏)
  final VoidCallback? onEdit;

  /// 删除回调(外层做二次确认对话框)
  final VoidCallback? onDelete;

  /// 举报回调(外层跳举报屏)
  final VoidCallback? onReport;

  /// 复制回调(本 sheet 内部已做 Clipboard.setData + SnackBar,
  /// 外层可选用此回调做埋点 / 状态同步)
  final VoidCallback? onCopy;

  /// 回复回调(外层做输入框聚焦 + 预填 @用户名)
  final VoidCallback? onReply;

  /// 任务⑨:评论内提取的 URL(可选)。非空时显「打开链接」tile。
  final String? linkUrl;

  const CommentActionsSheet({
    super.key,
    required this.comment,
    required this.hostType,
    required this.hostId,
    required this.isOwn,
    this.onEdit,
    this.onDelete,
    this.onReport,
    this.onCopy,
    this.onReply,
    this.linkUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final author = ref.watch(userByIdProvider(comment.authorId));
    final authorName = author?.name ?? comment.authorId;
    final preview = comment.content.length > 80
        ? '${comment.content.substring(0, 80)}…'
        : comment.content;

    // F-11:回复 / 编辑 / 删除 / 举报 仅当调用方传入对应回调时才渲染(移除空回调按钮,
    // 杜绝"点了没反应"的假按钮)。复制内容始终显示(内部已真实现 Clipboard.setData)。
    // 调用方目前只传 onCopy,故 sheet 实际只显示「复制内容」+「取消」;
    // CommentThread 操作行的「回复」按钮已独立接线(楼中楼回复),不依赖本 sheet。
    // Phase 5+ 接编辑屏 / 举报屏时,调用方传入对应回调即可自动出现按钮。
    final actionTiles = <Widget>[];
    if (onReply != null) {
      actionTiles.add(_ActionTile(
        icon: Icons.chat_bubble_outline,
        label: '回复',
        onTap: () => _popAndCallback(context, onReply),
      ));
    }
    actionTiles.add(_ActionTile(
      icon: Icons.copy_outlined,
      label: '复制内容',
      onTap: () => _copyContent(context),
    ));
    // 任务⑨:评论内含 URL 时显「打开链接」(url_launcher 真开浏览器)。
    // 无 URL 不显(避免假按钮)。tone normal — 打开链接不是 take,不用 coral。
    if (linkUrl != null && linkUrl!.isNotEmpty) {
      actionTiles.add(_ActionTile(
        icon: Icons.open_in_new,
        label: '打开链接',
        onTap: () => _openLink(context),
      ));
    }
    if (isOwn && onEdit != null) {
      actionTiles.add(_ActionTile(
        icon: Icons.edit_outlined,
        label: '编辑',
        onTap: () => _popAndCallback(context, onEdit),
      ));
    }
    if (isOwn && onDelete != null) {
      actionTiles.add(_ActionTile(
        icon: Icons.delete_outline,
        label: '删除',
        tone: _ActionTone.destructive,
        onTap: () => _popAndCallback(context, onDelete),
      ));
    }
    if (!isOwn && onReport != null) {
      actionTiles.add(_ActionTile(
        icon: Icons.flag_outlined,
        label: '举报',
        tone: _ActionTone.report,
        onTap: () => _popAndCallback(context, onReport),
      ));
    }
    // 用分隔线连接可见按钮(不在末尾加多余分隔线)
    final actionChildren = <Widget>[];
    for (var i = 0; i < actionTiles.length; i++) {
      actionChildren.add(actionTiles[i]);
      if (i < actionTiles.length - 1) {
        actionChildren.add(const _IndentedDivider());
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dragHandle(),
          const SizedBox(height: KkSpacing.md),
          _previewCard(authorName, preview),
          const SizedBox(height: KkSpacing.md),
          ...actionChildren,
          const SizedBox(height: KkSpacing.md),
          _cancelButton(context),
          // 底部安全区(避免被手势条遮挡)
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  // ── 顶部抓手 ──
  Widget _dragHandle() {
    return Center(
      child: Container(
        width: 48,
        height: 4,
        decoration: BoxDecoration(
          color: KkColors.bd,
          borderRadius: BorderRadius.circular(KkRadius.pill),
        ),
      ),
    );
  }

  // ── 评论预览卡(让用户确认操作的是哪条)──
  Widget _previewCard(String authorName, String preview) {
    return Container(
      padding: const EdgeInsets.all(KkSpacing.md),
      decoration: BoxDecoration(
        color: KkColors.bgSubtle,
        borderRadius: BorderRadius.circular(KkRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  authorName,
                  style: KkType.bodySm.copyWith(
                    color: KkColors.t1,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: KkSpacing.sm),
              Text(
                timeAgo(comment.createdAtMs),
                style: KkType.mono.copyWith(fontSize: 11, color: KkColors.t3),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            preview,
            style: KkType.bodySm.copyWith(color: KkColors.t2),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── 复制评论内容(真实现)──
  // 异步安全:await 前捕获 messenger,await 后 if (!context.mounted) return,
  // 再 Navigator.pop + SnackBar
  Future<void> _copyContent(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: comment.content));
    if (!context.mounted) return;
    Navigator.of(context).pop();
    onCopy?.call();
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('已复制'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── 任务⑨:打开评论内的链接 ──
  // 先 pop 本 sheet(避免浏览器回来时 sheet 还在),再 launchUrl 真开系统浏览器。
  // mode externalApplication:不占 app 内 WebView,符合「打开链接」语义。
  // 失败(无可用浏览器/URL 非法)→ SnackBar 一句话,零旁白。
  Future<void> _openLink(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final url = linkUrl!;
    Navigator.of(context).pop();
    final uri = Uri.tryParse(url);
    if (uri == null) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('链接无法打开'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('链接无法打开'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── 通用关闭 + 回调(回复/编辑/删除/举报)──
  void _popAndCallback(BuildContext context, VoidCallback? cb) {
    Navigator.of(context).pop();
    cb?.call();
  }

  // ── 取消按钮 ──
  Widget _cancelButton(BuildContext context) {
    return Tappable(
      onTap: () => Navigator.of(context).pop(),
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: KkColors.bgSubtle,
          borderRadius: BorderRadius.circular(KkRadius.md),
        ),
        alignment: Alignment.center,
        child: Text(
          '取消',
          style: KkType.bodySm.copyWith(
            color: KkColors.t2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ── 操作按钮三态色系 ──
enum _ActionTone {
  /// 普通(t2 icon + t1 label)
  normal,

  /// 删除(coral icon + coral label)— HANDOFF §5 删除语义例外
  destructive,

  /// 举报(t2 icon + t2 label)— 不用 coral,举报不是删除
  report,
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final _ActionTone tone;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tone = _ActionTone.normal,
  });

  @override
  Widget build(BuildContext context) {
    final (iconColor, labelColor) = switch (tone) {
      _ActionTone.normal => (KkColors.t2, KkColors.t1),
      _ActionTone.destructive => (KkColors.coral, KkColors.coral),
      _ActionTone.report => (KkColors.t2, KkColors.t2),
    };

    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KkRadius.md),
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.md,
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: KkSpacing.md),
          Expanded(
            child: Text(
              label,
              style: KkType.body.copyWith(color: labelColor),
            ),
          ),
          const Icon(Icons.chevron_right, color: KkColors.t3, size: 20),
        ],
      ),
    );
  }
}

/// 操作按钮之间的分隔线(indent 56 = 22 icon + 16 lg + 16 md ≈ 图标宽度对齐)
class _IndentedDivider extends StatelessWidget {
  const _IndentedDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: KkColors.divider,
      indent: 56,
    );
  }
}
