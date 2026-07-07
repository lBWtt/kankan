import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/kk_colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/file_download.dart';
import '../../../core/widgets/code_diff_block.dart';
import '../../../core/widgets/tappable.dart';
import '../../../data/seed/mock_seed.dart';
import '../../../domain/models/models.dart';

/// 动作区 — HANDOFF §2.2 三原语渲染,一行一个,任意组合。
///
/// **核心铁律(HANDOFF §2 / §7.1):用 switch 模式匹配 ActionItem sealed class,
/// 禁 if(artifactType) 硬编码分支。** 这是真假复用的试金石。
///
/// 颜色铁律(HANDOFF §5):
///   - TakeAction → 珊瑚橙 #D85A30(只此一处用珊瑚橙)
///   - GoAction   → 墨绿描边
///   - HowAction  → 次级墨绿文字,文案永远"工作流"
///
/// 按钮无"拿走"二字(HANDOFF §2.2):TakeAction 靠图标(下载/复制)表意 + 可选对象名。
/// take 成功后 takeawayCount +1(HANDOFF §2.2,与点赞同源体感)。
class ActionRow extends StatelessWidget {
  final List<ActionItem> actions;

  /// take 成功回调(详情页注入,用于 takeawayCount +1 + toast)
  final void Function(TakeAction action)? onTakeSuccess;

  const ActionRow({
    super.key,
    required this.actions,
    this.onTakeSuccess,
  });

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      // HANDOFF §2.2:无任何动作(纯心得)→ 动作区整块不显示。
      // 但此 widget 被调用即说明有动作;空时返回 0 高度(防御)。
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in actions) ...[
          _render(a),
          const SizedBox(height: KkSpacing.md),
        ],
        // 末尾不需要间距
        const SizedBox(height: 0),
      ],
    );
  }

  /// 模式匹配渲染 — HANDOFF §2 / §7.1 试金石。
  ///
  /// **禁 if(artifactType == 'xxx') 之类硬编码分支。**
  /// sealed class + switch 是 Dart 3 的原生穷举匹配,新增 ActionItem 子类时
  /// 编译器强制覆盖,不会漏。
  Widget _render(ActionItem a) {
    return switch (a) {
      TakeAction(:final source, :final takeKind, :final label) =>
        _TakeButton(
          source: source,
          takeKind: takeKind,
          label: label,
          onSuccess: () => onTakeSuccess?.call(a),
        ),
      GoAction(:final url, :final label) => _GoButton(url: url, label: label),
      HowAction(:final ref, :final label) =>
        _HowButton(ref: ref, label: label ?? '工作流'),
    };
  }
}

// ──────────────────────────────────────────────────────────────────
// take — 珊瑚橙,真复制/真下载,按钮无"拿走"字
// ──────────────────────────────────────────────────────────────────
class _TakeButton extends StatefulWidget {
  final String source;
  final String takeKind; // 'copy' | 'download'
  final String? label;
  final VoidCallback onSuccess;

  const _TakeButton({
    required this.source,
    required this.takeKind,
    required this.label,
    required this.onSuccess,
  });

  @override
  State<_TakeButton> createState() => _TakeButtonState();
}

class _TakeButtonState extends State<_TakeButton> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final isCopy = widget.takeKind == 'copy';
    final icon = isCopy ? Icons.copy_outlined : Icons.download_outlined;
    final doneIcon = Icons.check;

    // HANDOFF §2.2:按钮无"拿走"二字。图标表意 + 可选对象名(label)。
    final text = widget.label ?? (isCopy ? '复制' : '下载');

    return Tappable(
      onTap: _onTap,
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: KkSpacing.md,
          horizontal: KkSpacing.lg,
        ),
        decoration: BoxDecoration(
          // 珊瑚橙(HANDOFF §5:只给 take)
          color: _done ? KkColors.coralMint : KkColors.coral,
          borderRadius: BorderRadius.circular(KkRadius.md),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _done ? doneIcon : icon,
              color: _done ? KkColors.coral : Colors.white,
              size: 18,
            ),
            const SizedBox(width: KkSpacing.sm),
            Text(
              _done ? '已${isCopy ? '复制' : '下载'}' : text,
              style: TextStyle(
                color: _done ? KkColors.coral : Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                fontFamily: 'JetBrainsMono',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onTap() async {
    final isCopy = widget.takeKind == 'copy';
    try {
      if (isCopy) {
        // 真复制到剪贴板
        await Clipboard.setData(ClipboardData(text: widget.source));
      } else {
        // Phase 5：真后台下载（dio → 临时目录）+ toast。
        // web 平台 path_provider 不可用，走 url_launcher 兜底（浏览器下载）。
        await _downloadFile();
      }
      if (!mounted) return;
      setState(() => _done = true);
      widget.onSuccess();
      // 2 秒后恢复
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _done = false);
      });
    } catch (_) {
      // Phase 5：失败 toast（不再静默）。
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('下载失败，稍后再试'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 真下载：dio 流式下载到临时目录，成功 toast「已保存」。
  /// web 无 path_provider → 退 url_launcher 让浏览器处理。
  Future<void> _downloadFile() async {
    final uri = Uri.tryParse(widget.source);
    if (uri == null) return;
    // web 兜底：浏览器原生下载。
    if (kIsWeb) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    final savePath = await downloadUrlToFile(widget.source);
    if (!mounted) return;
    if (savePath != null) {
      final name = savePath.split('/').last;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('已保存到 $name'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      // 下载失败 → 退 url_launcher 让浏览器处理（best-effort）。
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ──────────────────────────────────────────────────────────────────
// go — 墨绿描边,真开外链,行尾 ↗
// ──────────────────────────────────────────────────────────────────
class _GoButton extends StatelessWidget {
  final String url;
  final String? label;

  const _GoButton({required this.url, required this.label});

  @override
  Widget build(BuildContext context) {
    final text = label ?? _defaultLabel(url);
    return Tappable(
      onTap: () => _openUrl(url),
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: KkSpacing.md,
          horizontal: KkSpacing.lg,
        ),
        decoration: BoxDecoration(
          // 墨绿描边(HANDOFF §2.2)
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(KkRadius.md),
          border: Border.all(color: KkColors.teal, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              text,
              style: const TextStyle(
                color: KkColors.teal,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                fontFamily: 'JetBrainsMono',
              ),
            ),
            const SizedBox(width: KkSpacing.xs),
            // 行尾 ↗(go 表意)
            const Icon(
              Icons.arrow_outward,
              size: 16,
              color: KkColors.teal,
            ),
          ],
        ),
      ),
    );
  }

  /// HANDOFF §4:放链接 → 当场识别 GitHub/App Store/网址 → 默认 label
  String _defaultLabel(String url) {
    final u = url.toLowerCase();
    if (u.contains('github.com')) return 'GitHub';
    if (u.contains('apps.apple.com')) return 'App Store';
    if (u.contains('play.google.com')) return 'Google Play';
    // 取域名
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.isNotEmpty) return uri.host;
    return '访问';
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ──────────────────────────────────────────────────────────────────
// how — 次级墨绿文字,文案永远"工作流"
// Phase 3 Tier 4:点击 inline 展开工作流 diff(不再跳页)。
// ──────────────────────────────────────────────────────────────────
class _HowButton extends StatefulWidget {
  final String ref;
  final String label; // 永远"工作流"(HANDOFF §2.2)

  const _HowButton({required this.ref, required this.label});

  @override
  State<_HowButton> createState() => _HowButtonState();
}

class _HowButtonState extends State<_HowButton> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // HANDOFF §2.2 how 动作:ref 在 mockWorkflows 找不到时,展开显示灰字兜底。
    final workflow = findWorkflow(widget.ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 按钮(点击 toggle 展开/收起)
        Tappable(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(KkRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: KkSpacing.sm,
              horizontal: KkSpacing.lg,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _expanded
                      ? Icons.unfold_less_outlined
                      : Icons.account_tree_outlined,
                  size: 16,
                  color: KkColors.teal,
                ),
                const SizedBox(width: KkSpacing.xs),
                Text(
                  _expanded ? '收起工作流' : widget.label, // "工作流"
                  style: const TextStyle(
                    color: KkColors.teal,
                    fontSize: 14,
                    fontFamily: 'NotoSerifSC',
                  ),
                ),
              ],
            ),
          ),
        ),
        // 展开内容:AnimatedSize 折叠高度 + AnimatedOpacity 渐入渐出。
        AnimatedSize(
          duration: KkDuration.med,
          curve: Curves.easeInOut,
          child: AnimatedOpacity(
            opacity: _expanded ? 1.0 : 0.0,
            duration: KkDuration.med,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: KkSpacing.sm),
                    child: workflow == null
                        ? Text(
                            '工作流详情暂未提供',
                            style: KkType.bodySm
                                .copyWith(color: KkColors.t3),
                          )
                        : Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 任务⑤:旧→新流程 + 省下时间叙事对比
                              // (原型第二强「想做」钩子)。oldFlow/newFlow
                              // 任一 null → 整块不渲染(向后兼容)。
                              if (workflow.oldFlow != null &&
                                  workflow.newFlow != null)
                                _FlowCompare(
                                  oldFlow: workflow.oldFlow!,
                                  newFlow: workflow.newFlow!,
                                  saved: workflow.saved,
                                ),
                              CodeDiffBlock(
                                title: workflow.title,
                                before: workflow.before,
                                after: workflow.after,
                                language: workflow.language,
                              ),
                            ],
                          ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 任务⑤:旧流程 → 新流程 + 省下时间 叙事对比块
// ──────────────────────────────────────────────────────────────────
// 在 _HowButton 展开的 CodeDiffBlock 之上渲染(见上)。原型第二强「想做」钩子——
// 让人直观看到「以前多麻烦、现在多快」。
//
// 版式(克制,与详情页呼吸感一致):
//   - 上下两段:旧流程(t3 弱)/ 新流程(teal 强)
//   - 每段:小标题 + 步骤列表(每步前一个小圆点)
//   - 底部醒目「省下 {saved}」chip:mint 底 + teal 字 + bolt 图标
//
// 铁律(SPEC §6):
//   - coral 只给 take——「省下」chip 用 teal/mint,不用 coral。
//   - 无 emoji(用 Icon)。零旁白。不出现「拿走」二字。
//   - oldFlow/newFlow null → 整块不渲染(调用方已判断,此 widget 防御)。
class _FlowCompare extends StatelessWidget {
  final List<String> oldFlow;
  final List<String> newFlow;
  final String? saved;

  const _FlowCompare({
    required this.oldFlow,
    required this.newFlow,
    this.saved,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: KkSpacing.md),
      padding: const EdgeInsets.all(KkSpacing.md),
      decoration: BoxDecoration(
        color: KkColors.bgSubtle,
        borderRadius: BorderRadius.circular(KkRadius.md),
        border: Border.all(color: KkColors.bd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 旧流程(弱)
          _FlowSection(
            label: '旧流程',
            steps: oldFlow,
            labelColor: KkColors.t3,
            stepColor: KkColors.t2,
            dotColor: KkColors.t3,
          ),
          const SizedBox(height: KkSpacing.md),
          // 新流程(强)
          _FlowSection(
            label: '新流程',
            steps: newFlow,
            labelColor: KkColors.teal,
            stepColor: KkColors.t1,
            dotColor: KkColors.teal,
            stepBold: true,
          ),
          // 省下 chip(mint + teal,不用 coral)
          if (saved != null && saved!.isNotEmpty) ...[
            const SizedBox(height: KkSpacing.md),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: KkSpacing.md,
                  vertical: KkSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: KkColors.mint,
                  borderRadius: BorderRadius.circular(KkRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.bolt,
                      size: 14,
                      color: KkColors.teal,
                    ),
                    const SizedBox(width: KkSpacing.xs),
                    Text(
                      saved!,
                      style: KkType.bodySm.copyWith(
                        fontSize: 12,
                        color: KkColors.teal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// _FlowCompare 的单段(旧/新流程):小标题 + 步骤列表(每步前小圆点)。
class _FlowSection extends StatelessWidget {
  final String label;
  final List<String> steps;
  final Color labelColor;
  final Color stepColor;
  final Color dotColor;
  final bool stepBold;

  const _FlowSection({
    required this.label,
    required this.steps,
    required this.labelColor,
    required this.stepColor,
    required this.dotColor,
    this.stepBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: KkType.bodySm.copyWith(
            fontSize: 11,
            color: labelColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: KkSpacing.xs),
        for (final step in steps) ...[
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: KkSpacing.sm),
                Expanded(
                  child: Text(
                    step,
                    style: KkType.bodySm.copyWith(
                      fontSize: 13,
                      color: stepColor,
                      fontWeight:
                          stepBold ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
