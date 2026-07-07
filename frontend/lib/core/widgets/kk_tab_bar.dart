import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/kk_strings.dart';
import '../../providers/app_state_provider.dart';
import '../theme/kk_colors.dart';
import '../theme/tokens.dart';
import '../theme/noise_background.dart';
import 'tappable.dart';

/// 根 Shell:承载 StatefulNavigationShell + 底部 5 槽栏。
///
/// 布局:Scaffold(暖纸底 + 噪点) → body(navigationShell) → bottomNavigationBar(5 槽)。
///
/// 5 槽 = 4 branch + 1 FAB(不是 5 branch):
///   发现(0) | 看看(1) | [+ FAB] | 收藏(2) | 我的(3)
///
/// 为什么 + 不当 branch:它是 action(弹 sheet 发布),不是导航目的地。
/// 当 branch 会导致点 + 切到"发布 tab"且 shell 高亮它,违反原型行为。
/// 与 Next.js 原型一致。详见 README §A。
///
/// onPublishTap 由 router(composition root)注入,避免 core → features 反向依赖。
class KkRootShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  /// 点中间 + FAB 的回调。router 层注入(显示 PublishEntrySheet)。
  final VoidCallback onPublishTap;

  const KkRootShell({
    super.key,
    required this.navigationShell,
    required this.onPublishTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KkColors.bg,
      body: NoiseBackground(
        child: SafeArea(
          bottom: false,
          child: navigationShell,
        ),
      ),
      bottomNavigationBar: _KkBottomBar(
        currentIndex: navigationShell.currentIndex,
        onTabSelected: (i) => navigationShell.goBranch(
          i,
          // 重复点当前 Tab → 回到该 branch 初始位置(Phase 2 加 scroll-to-top)
          initialLocation: i == navigationShell.currentIndex,
        ),
        onPublishTap: onPublishTap,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 底部 5 槽栏
// ──────────────────────────────────────────────────────────────────

class _KkBottomBar extends ConsumerWidget {
  /// 当前激活的 branch index(0..3,跳过 FAB 槽)
  final int currentIndex;

  /// 选中某 branch
  final ValueChanged<int> onTabSelected;

  /// 点中间 + FAB
  final VoidCallback onPublishTap;

  const _KkBottomBar({
    required this.currentIndex,
    required this.onTabSelected,
    required this.onPublishTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 任务 4:底部 Tab 叠未读红点(「我的」 tab)。用 effectiveUnreadCount
    // (免打扰开启时归零,红点自动消失)。红点用 KkColors.like(情感色,与 me
    // 页铃铛红点一致;非 take,所以不用 coral)。
    final unreadCount = ref.watch(appStateProvider).effectiveUnreadCount;
    // P2-i18n:底栏 4 Tab 标签接 KkStrings(参考实现,其余屏按需迁移)。
    // 切 gen-l10n 时:改为 `AppLocalizations.of(context)!.discoverTab` 等。
    final s = ref.watch(kkStringsProvider);
    return Container(
      decoration: const BoxDecoration(
        color: KkColors.bgCard,
        border: Border(top: BorderSide(color: KkColors.bd)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              Expanded(child: _tab(context, 0, s.discoverTab, Icons.explore_outlined, Icons.explore, showBadge: false)),
              Expanded(child: _tab(context, 1, s.kankanTab, Icons.grid_view_outlined, Icons.grid_view, showBadge: false)),
              Expanded(child: _fab(s.publish)),
              Expanded(child: _tab(context, 2, s.libraryTab, Icons.bookmark_border_outlined, Icons.bookmark, showBadge: false)),
              Expanded(child: _tab(context, 3, s.meTab, Icons.person_outline, Icons.person, showBadge: unreadCount > 0)),
            ],
          ),
        ),
      ),
    );
  }

  /// branch index → Tab 槽。激活态:mint pill 底 + 墨绿图标/文字(动画过渡)。
  /// 任务 4:showBadge=true 时,图标右上角叠未读红点(KkColors.like 小圆点)。
  Widget _tab(BuildContext context, int branchIndex, String label,
      IconData icon, IconData activeIcon, {required bool showBadge}) {
    final isActive = currentIndex == branchIndex;
    final color = isActive ? KkColors.teal : KkColors.t3;

    return Tappable(
      onTap: () => onTabSelected(branchIndex),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // pill(mint 底,激活时显形,AnimatedContainer 过渡)+ 可选红点
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: KkDuration.med,
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive ? KkColors.mint : Colors.transparent,
                  borderRadius: BorderRadius.circular(KkRadius.pill),
                ),
                child: Icon(
                  isActive ? activeIcon : icon,
                  size: 22,
                  color: color,
                ),
              ),
              // 未读红点:图标右上角,8×8,KkColors.like
              if (showBadge)
                Positioned(
                  top: -1,
                  right: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: KkColors.like,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          AnimatedDefaultTextStyle(
            duration: KkDuration.med,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              fontFamily: 'NotoSerifSC',
            ),
            child: Text(label),
          ),
        ],
      ),
    );
  }

  /// 中间 + FAB。墨绿圆 + 白色加号。
  /// HANDOFF §5:珊瑚橙只给 take,FAB 用墨绿(品牌色),不用珊瑚橙。
  ///
  /// P2-i18n / 无障碍:[publishLabel] 用于 Tappable.semanticLabel(读屏念
  /// 「发布」)。Icon-only 按钮必须传语义标签,否则读屏只会念「加号按钮」。
  Widget _fab(String publishLabel) {
    return Tappable(
      onTap: onPublishTap,
      semanticLabel: publishLabel,
      borderRadius: BorderRadius.circular(KkRadius.pill),
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: KkColors.teal,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }
}
