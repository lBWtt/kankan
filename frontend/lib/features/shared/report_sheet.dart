import 'package:flutter/material.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/tappable.dart';

/// 任务⑫A:举报原因选择 sheet — 共享,接三处入口(post / user / comment)。
///
/// 现状(任务前):「举报」是空壳死按钮(onTap 只 Navigator.pop,啥也不干)。
/// 本 sheet 把举报变成真功能:选原因 → 关 sheet + toast「已举报,我们会尽快核实」。
///
/// 设计:
///   - 标题「选择举报原因」+ 4 个原因列(照原型)
///     · 垃圾内容(广告、刷屏、恶意推广)
///     · 抄袭侵权(盗用他人原创内容)
///     · 不实信息(虚假、误导性内容)
///     · 以上都不是 → 展开补充说明输入框 + 确认
///   - 前 3 个点选直接提交;第 4 个展开输入框,填完点「确认」提交
///   - 提交 = 关 sheet + SnackBar「已举报,我们会尽快核实」
///
/// 铁律(SPEC §6):
///   - coral 只给 take——举报/原因项一律 t1/t2,不用 coral(举报不是删除,
///     不混 take 视觉)。确认按钮用 teal(提交动作,非 take)。
///   - 无 emoji(用 Icon);零旁白(只列原因,不写"举报后会怎样")。
///   - 触控 ≥44pt(Tappable 内置 minTarget)。
///
/// [targetType] / [targetId]:mock 阶段只用 toast,Phase 5 接后端时传给举报 API。
Future<void> showReportSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
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
    builder: (_) => _ReportSheet(
      targetType: targetType,
      targetId: targetId,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  final String targetType;
  final String targetId;

  const _ReportSheet({
    required this.targetType,
    required this.targetId,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _ctrl = TextEditingController();
  bool _otherExpanded = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 提交举报:关 sheet + toast(零旁白,只陈述已举报事实)。
  /// reason 仅本地用(Phase 5 接后端时随 targetType/targetId 一起上报)。
  void _submit([String? reason]) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('已举报，我们会尽快核实'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleOther() {
    setState(() => _otherExpanded = !_otherExpanded);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.md,
      ),
      // isScrollControlled + 底部留键盘高度,展开输入框时不被遮挡
      child: AnimatedPadding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        duration: const Duration(milliseconds: 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dragHandle(),
            const SizedBox(height: KkSpacing.md),
            const Text(
              '选择举报原因',
              style: KkType.h3,
            ),
            const SizedBox(height: KkSpacing.md),
            _ReasonTile(
              label: '垃圾内容',
              desc: '广告、刷屏、恶意推广',
              onTap: () => _submit('垃圾内容'),
            ),
            const _IndentedDivider(),
            _ReasonTile(
              label: '抄袭侵权',
              desc: '盗用他人原创内容',
              onTap: () => _submit('抄袭侵权'),
            ),
            const _IndentedDivider(),
            _ReasonTile(
              label: '不实信息',
              desc: '虚假、误导性内容',
              onTap: () => _submit('不实信息'),
            ),
            const _IndentedDivider(),
            _ReasonTile(
              label: '以上都不是',
              desc: null,
              trailing: Icon(
                _otherExpanded
                    ? Icons.expand_less
                    : Icons.expand_more,
                size: 20,
                color: KkColors.t3,
              ),
              onTap: _toggleOther,
            ),
            if (_otherExpanded) ...[
              const SizedBox(height: KkSpacing.sm),
              _SupplementField(
                controller: _ctrl,
                onSubmit: () => _submit(
                  _ctrl.text.trim().isEmpty
                      ? '以上都不是'
                      : '以上都不是：${_ctrl.text.trim()}',
                ),
              ),
            ],
            const SizedBox(height: KkSpacing.md),
            _cancelButton(context),
            // 底部安全区
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

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

/// 原因行:label(t1 w600)+ 可选 desc(t3 bodySm)+ 右侧 trailing(默认 chevron)。
/// 零旁白:只写原因名 + 一句话释义,不写后果。不用 coral。
class _ReasonTile extends StatelessWidget {
  final String label;
  final String? desc;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _ReasonTile({
    required this.label,
    required this.onTap,
    this.desc,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KkRadius.md),
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: KkType.body.copyWith(
                    color: KkColors.t1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (desc != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    desc!,
                    style: KkType.bodySm.copyWith(color: KkColors.t3),
                  ),
                ],
              ],
            ),
          ),
          trailing ??
              const Icon(Icons.chevron_right, color: KkColors.t3, size: 20),
        ],
      ),
    );
  }
}

/// 「以上都不是」展开后的补充说明输入框 + 确认按钮。
/// 确认按钮 teal(提交不是 take,不用 coral)。
class _SupplementField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;

  const _SupplementField({
    required this.controller,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KkSpacing.md),
      decoration: BoxDecoration(
        color: KkColors.bgSubtle,
        borderRadius: BorderRadius.circular(KkRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            style: KkType.body,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: '补充说明',
              hintStyle: KkType.body.copyWith(color: KkColors.t4),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: KkSpacing.md,
                vertical: KkSpacing.sm,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KkRadius.md),
                borderSide: const BorderSide(color: KkColors.bd),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KkRadius.md),
                borderSide: const BorderSide(color: KkColors.teal),
              ),
            ),
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: KkSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: Tappable(
              onTap: onSubmit,
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
                  '确认',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    fontFamily: 'NotoSerifSC',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 原因行之间的分隔线(indent 56 ≈ 对齐图标列宽,本 sheet 无图标列但沿用
/// comment_actions_sheet 的视觉一致性)。
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
