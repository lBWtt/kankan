// 这个文件是干什么的：展示《用户协议》/《隐私政策》正文的只读页面。
// 它对应产品里的什么功能：登录页「同意协议」里的链接、设置页「关于」里的两个入口。
// 如果它出错了：协议看不全 —— 影响上架合规。
//
// 渲染约定（正文见 legal_docs.dart）：`## ` 开头=小标题（加粗大字）、空行=段距、其余=正文段落。
import 'package:flutter/material.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/kk_back_button.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KkColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
          children: [
            const SizedBox(height: KkSpacing.sm),
            const Row(children: [KkBackButton()]),
            const SizedBox(height: KkSpacing.md),
            Text(title, style: KkType.h1),
            const SizedBox(height: KkSpacing.lg),
            ..._render(body),
            const SizedBox(height: KkSpacing.xxl),
          ],
        ),
      ),
    );
  }

  List<Widget> _render(String text) {
    final out = <Widget>[];
    for (final rawLine in text.trim().split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty) {
        out.add(const SizedBox(height: KkSpacing.md));
      } else if (line.startsWith('## ')) {
        out.add(
          Padding(
            padding: const EdgeInsets.only(top: KkSpacing.sm, bottom: KkSpacing.xs),
            child: Text(
              line.substring(3).trim(),
              style: KkType.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        );
      } else {
        out.add(
          Text(
            line,
            style: KkType.bodySm.copyWith(color: KkColors.t2, height: 1.6),
          ),
        );
      }
    }
    return out;
  }
}
