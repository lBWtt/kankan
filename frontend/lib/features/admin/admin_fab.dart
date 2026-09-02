// 这个文件是干什么的：管理员审核入口——一个可拖动的悬浮球，浮在所有页面之上，样式
//   刻意区别于消费端 UI（深色墨底 + 盾牌图标 + 待审数），点开进审核队列。
// 隔离：只在 app.dart 的 builder 里 `if (AppConfig.adminBuild)` 分支挂载，消费端构建
//   时该分支恒 false 被 tree-shake，整块（含审核页/接口）不进公开包。绝不碰现有 UI。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../data/api/admin_api.dart';
import '../../router/app_router.dart';
import '../../router/routes.dart';

/// 悬浮审核球。放在全局 Overlay 层（MaterialApp.builder），可上下拖动，吸附到右/左边。
class AdminFab extends ConsumerStatefulWidget {
  const AdminFab({super.key});
  @override
  ConsumerState<AdminFab> createState() => _AdminFabState();
}

class _AdminFabState extends ConsumerState<AdminFab> {
  // null = 未拖动，用默认位置（右下、底栏之上）。拖动后记住绝对坐标。
  Offset? _pos;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final pad = MediaQuery.of(context).padding;
    const w = 96.0, h = 44.0;
    final defaultPos = Offset(
      size.width - w - KkSpacing.md,
      size.height - h - pad.bottom - 96, // 悬在底栏上方
    );
    final pos = _pos ?? defaultPos;

    // 待审数（拉取失败/未授权则不显示数字，不打扰）。
    final count = ref.watch(adminQueueProvider).maybeWhen(
          data: (list) => list.length,
          orElse: () => null,
        );

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          final next = pos + d.delta;
          setState(() {
            _pos = Offset(
              next.dx.clamp(KkSpacing.sm, size.width - w - KkSpacing.sm),
              next.dy.clamp(
                  pad.top + KkSpacing.sm, size.height - h - KkSpacing.sm),
            );
          });
        },
        onTap: () => ref.read(goRouterProvider).push(KkRoutes.adminReview),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: KkColors.t1, // 深墨底：一眼区别于消费端暖纸/墨绿
              borderRadius: BorderRadius.circular(KkRadius.pill),
              boxShadow: KkElevation.overlay,
              border: Border.all(color: KkColors.teal, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_user_outlined,
                    color: Colors.white, size: 18),
                const SizedBox(width: 6),
                const Text('审核',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                if (count != null && count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: KkColors.teal,
                      borderRadius: BorderRadius.circular(KkRadius.pill),
                    ),
                    child: Text('$count',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
