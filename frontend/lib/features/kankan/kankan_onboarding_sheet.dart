import 'package:flutter/material.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/tappable.dart';
import '../feedback/feedback_sheet.dart';

Future<void> showKankanOnboardingSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _KankanOnboardingSheet(),
  );
}

class _KankanOnboardingSheet extends StatelessWidget {
  const _KankanOnboardingSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: KkColors.bgCard,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(KkRadius.xl)),
        ),
        padding: const EdgeInsets.fromLTRB(
          KkSpacing.lg,
          KkSpacing.md,
          KkSpacing.lg,
          KkSpacing.lg,
        ),
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
            const Text('\u6b22\u8fce\u6765\u770b\u770b', style: KkType.h2),
            const SizedBox(height: KkSpacing.xs),
            Text(
              '\u8fd9\u91cc\u662f\u53d1\u73b0 AI \u505a\u51fa\u6765\u7684\u5c0f\u4ea7\u54c1\u7684\u5730\u65b9\u3002',
              style: KkType.bodySm.copyWith(color: KkColors.t3),
            ),
            const SizedBox(height: KkSpacing.md),
            const _OnboardingCard(
              icon: Icons.auto_awesome_outlined,
              title: '\u53d1\u73b0\u597d\u4e1c\u897f',
              body:
                  '\u770b\u522b\u4eba\u505a\u51fa\u6765\u7684 AI \u5c0f\u4ea7\u54c1\uff0c\u6536\u85cf\u60f3\u6162\u6162\u770b\u7684\u9879\u76ee\u3002',
            ),
            const SizedBox(height: KkSpacing.sm),
            const _OnboardingCard(
              icon: Icons.bookmark_add_outlined,
              title: '\u6536\u96c6\u7075\u611f',
              body:
                  '\u9047\u5230\u6709\u7528\u7684\u5185\u5bb9\uff0c\u53ef\u4ee5\u5b58\u7d20\u6750\uff1b\u559c\u6b22\u67d0\u4e2a\u65b9\u5411\uff0c\u53ef\u4ee5\u5173\u6ce8\u9886\u57df\u3002',
            ),
            const SizedBox(height: KkSpacing.sm),
            const _OnboardingCard(
              icon: Icons.rocket_launch_outlined,
              title: '\u4e00\u8d77\u628a\u5b83\u53d8\u597d',
              body:
                  '\u4f60\u4e5f\u53ef\u4ee5\u53d1\u5e03\u81ea\u5df1\u7684\u4f5c\u54c1\uff1b\u9047\u5230 bug \u5c31\u76f4\u63a5\u53cd\u9988\u3002',
            ),
            const SizedBox(height: KkSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Tappable(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(KkRadius.md),
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: KkColors.teal,
                        borderRadius: BorderRadius.circular(KkRadius.md),
                      ),
                      child: Text(
                        '\u5f00\u59cb\u770b',
                        style: KkType.body.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: KkSpacing.sm),
                Tappable(
                  onTap: () async {
                    Navigator.pop(context);
                    await showFeedbackSheet(
                      context,
                      sourcePage: '/kankan/onboarding',
                    );
                  },
                  borderRadius: BorderRadius.circular(KkRadius.md),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(
                      horizontal: KkSpacing.md,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: KkColors.bgSubtle,
                      borderRadius: BorderRadius.circular(KkRadius.md),
                      border: Border.all(color: KkColors.bd),
                    ),
                    child: const Icon(
                      Icons.bug_report_outlined,
                      size: 20,
                      color: KkColors.t2,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _OnboardingCard({
    required this.icon,
    required this.title,
    required this.body,
  });

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: KkColors.teal),
          const SizedBox(width: KkSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: KkType.body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(body, style: KkType.bodySm.copyWith(color: KkColors.t3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
