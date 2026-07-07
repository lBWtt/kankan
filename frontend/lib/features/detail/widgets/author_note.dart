import 'package:flutter/material.dart';

import '../../../core/theme/kk_colors.dart';
import '../../../core/theme/tokens.dart';

/// 作者的话 — HANDOFF §2.3 夹在成果与动作之间,居中。
///
/// 为空 → 整块隐藏(连标题),不留空。由 detail screen 控制是否渲染此 widget。
class AuthorNote extends StatelessWidget {
  final String note;

  const AuthorNote({super.key, required this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.xl,
        vertical: KkSpacing.lg,
      ),
      decoration: const BoxDecoration(
        color: KkColors.bgSubtle,
        border: Border.symmetric(
          vertical: BorderSide(color: KkColors.divider),
        ),
      ),
      child: Column(
        children: [
          // 引号装饰
          const Text(
            '"',
            style: TextStyle(
              fontFamily: 'NotoSerifSC',
              fontSize: 32,
              height: 0.8,
              color: KkColors.t4,
            ),
          ),
          const SizedBox(height: KkSpacing.sm),
          Text(
            note,
            style: KkType.body.copyWith(
              fontSize: 15,
              height: 1.7,
              color: KkColors.t2,
              fontFamily: 'NotoSerifSC',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
