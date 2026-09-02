// 这个文件是干什么的：意见反馈底部弹窗——选类型(bug/建议/其他)+写内容+可选联系方式，
//   提交到后端 /feedback（自动带 App 版本/平台便于排障）。
// 它对应产品里的什么功能：设置页「反馈 Bug / 建议」的真实提交表单。
// 如果它出错了：提交失败会就地提示（不静默吞）。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/network/app_exception.dart';
import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/tappable.dart';
import '../../data/api/feedback_api.dart';

/// 打开反馈弹窗。返回是否提交成功（调用方可据此弹 toast）。
Future<bool> showFeedbackSheet(
  BuildContext context, {
  String? sourcePage,
  String? errorCode,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true, // 键盘弹起时表单上移
    backgroundColor: Colors.transparent,
    builder: (_) => _FeedbackSheet(
      sourcePage: sourcePage,
      errorCode: errorCode,
    ),
  );
  return ok ?? false;
}

class _FeedbackSheet extends ConsumerStatefulWidget {
  final String? sourcePage;
  final String? errorCode;

  const _FeedbackSheet({
    this.sourcePage,
    this.errorCode,
  });

  @override
  ConsumerState<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends ConsumerState<_FeedbackSheet> {
  final _contentCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  String _category = 'bug';
  bool _submitting = false;
  String? _error;

  static const _cats = <({String value, String label})>[
    (value: 'bug', label: 'Bug 故障'),
    (value: 'suggestion', label: '优化建议'),
    (value: 'other', label: '其他'),
  ];

  @override
  void dispose() {
    _contentCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      setState(() => _error = '写点内容再提交吧');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      await ref.read(feedbackApiProvider).submit(
            category: _category,
            content: content,
            contact: _contactCtrl.text.trim(),
            appVersion: '${packageInfo.version}+${packageInfo.buildNumber}',
            platform: defaultTargetPlatform.name, // android / iOS
            deviceInfo: defaultTargetPlatform.name,
            sourcePage: widget.sourcePage,
            errorCode: widget.errorCode,
          );
      if (mounted) Navigator.pop(context, true);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '提交失败，请稍后再试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: KkColors.bgCard,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(KkRadius.xl)),
        ),
        padding: const EdgeInsets.fromLTRB(
            KkSpacing.lg, KkSpacing.md, KkSpacing.lg, KkSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: KkColors.bd,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: KkSpacing.md),
            const Text('反馈 Bug / 建议', style: KkType.h2),
            const SizedBox(height: KkSpacing.xs),
            Text('直接告诉我哪坏了或想要什么，我会优先看。',
                style: KkType.bodySm.copyWith(color: KkColors.t3)),
            const SizedBox(height: KkSpacing.md),

            // 类型选择
            Row(
              children: [
                for (final c in _cats) ...[
                  _catChip(c.value, c.label),
                  const SizedBox(width: KkSpacing.sm),
                ],
              ],
            ),
            const SizedBox(height: KkSpacing.md),

            // 内容
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: KkSpacing.md, vertical: KkSpacing.sm),
              decoration: BoxDecoration(
                color: KkColors.bgSubtle,
                borderRadius: BorderRadius.circular(KkRadius.md),
                border: Border.all(color: KkColors.bd),
              ),
              child: TextField(
                controller: _contentCtrl,
                maxLines: 5,
                maxLength: 2000,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '例：详情页点返回偶尔白屏；希望动态能加话题…',
                  border: InputBorder.none,
                  isDense: true,
                  counterText: '',
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
            ),
            const SizedBox(height: KkSpacing.sm),

            // 联系方式（选填）
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: KkSpacing.md, vertical: KkSpacing.md),
              decoration: BoxDecoration(
                color: KkColors.bgSubtle,
                borderRadius: BorderRadius.circular(KkRadius.md),
                border: Border.all(color: KkColors.bd),
              ),
              child: TextField(
                controller: _contactCtrl,
                decoration: const InputDecoration(
                  hintText: '联系方式（选填，方便我回你）',
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: KkSpacing.sm),
              Text(_error!,
                  style: KkType.bodySm.copyWith(color: KkColors.like)),
            ],

            const SizedBox(height: KkSpacing.lg),
            Tappable(
              onTap: _submitting ? null : _submit,
              disabled: _submitting,
              borderRadius: BorderRadius.circular(KkRadius.md),
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _submitting ? KkColors.t3 : KkColors.teal,
                  borderRadius: BorderRadius.circular(KkRadius.md),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Text('提交',
                        style: KkType.body.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catChip(String value, String label) {
    final on = _category == value;
    return Tappable(
      onTap: () => setState(() => _category = value),
      borderRadius: BorderRadius.circular(KkRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: KkSpacing.md, vertical: KkSpacing.sm),
        decoration: BoxDecoration(
          color: on ? KkColors.teal : KkColors.bgSubtle,
          borderRadius: BorderRadius.circular(KkRadius.md),
          border: Border.all(color: on ? KkColors.teal : KkColors.bd),
        ),
        child: Text(
          label,
          style: KkType.bodySm.copyWith(
            color: on ? Colors.white : KkColors.t2,
            fontWeight: on ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
