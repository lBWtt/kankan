import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/kk_colors.dart';
import '../../router/routes.dart';
import 'tappable.dart';

/// 统一返回按钮 — HANDOFF §6.7 真路由铁律。
///
/// 直达深链页(/detail/x、/search、/notifications、/u/x、/post/x、
/// /profile/edit 等)时,Navigator 栈可能为空,context.pop() 会抛
/// GoError: nothing to pop,停在原页。本组件统一兜底:
///   - 能 pop → context.pop()
///   - 不能 pop → context.go(KkRoutes.discover) 回发现页根
///
/// 全 App 复用,一处改全部生效。视觉与原内联返回按钮完全一致
/// (Tappable + Icons.arrow_back 22pt t1),零视觉回归。
/// 触控热区 ≥44pt(HANDOFF §4,Tappable 自带 ConstrainedBox min 44)。
class KkBackButton extends StatelessWidget {
  final Color? color;
  final double size;

  const KkBackButton({super.key, this.color, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(KkRoutes.discover);
        }
      },
      child: Icon(Icons.arrow_back, color: color ?? KkColors.t1, size: size),
    );
  }
}
