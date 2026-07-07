import 'package:flutter/material.dart';

import '../../../core/theme/kk_colors.dart';
import '../../../core/theme/tokens.dart';

/// 成果区 io 渲染器 — HANDOFF §2.1 prompt/文本的"输入→输出**效果**"。
///
/// **不是代码 diff、不是 prompt 原文**(HANDOFF §2.1)。
/// 展示:输入(prompt / 配置) → 输出(AI 生成的效果)。
///
/// 卡片样式:左竖线 + 浅底 + 输入/输出两段,中间一个箭头分隔。
import '../../../domain/models/models.dart';

class IoBlockView extends StatelessWidget {
  final IoBlock io;

  const IoBlockView({super.key, required this.io});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KkColors.bgSubtle,
        borderRadius: BorderRadius.circular(KkRadius.md),
        border: Border.all(color: KkColors.bd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 可选 model 标签
          if (io.model != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KkSpacing.lg,
                KkSpacing.md,
                KkSpacing.lg,
                0,
              ),
              child: Text(
                io.model!,
                style: KkType.mono.copyWith(
                  color: KkColors.teal,
                  fontSize: 12,
                ),
              ),
            ),
          // 输入
          _section('输入', io.input, isInput: true),
          // 分隔箭头
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            color: KkColors.divider,
            child: const Icon(
              Icons.arrow_downward,
              size: 16,
              color: KkColors.t3,
            ),
          ),
          // 输出
          _section('输出', io.output, isInput: false),
        ],
      ),
    );
  }

  Widget _section(String label, String content, {required bool isInput}) {
    return Padding(
      padding: const EdgeInsets.all(KkSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: KkType.mono.copyWith(
              fontSize: 11,
              color: KkColors.t3,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            content,
            style: KkType.body.copyWith(
              height: 1.5,
              fontFamily: io.lang != null ? 'JetBrainsMono' : null,
              fontSize: io.lang != null ? 13 : 14,
            ),
          ),
        ],
      ),
    );
  }
}
