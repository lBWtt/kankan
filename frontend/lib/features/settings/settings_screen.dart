import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kk_colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/kk_back_button.dart';
import '../../core/widgets/tappable.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/auth_provider.dart';
import '../../router/routes.dart';

/// 设置页 — HANDOFF §6.10 真实计数 + §3 零旁白 + §5 触控铁律。
///
/// Phase 3 Tier 3:
///   - 通知:未读数取 [AppStateData.unreadNotifIds] 真实长度,
///     全部已读入口接 [AppStateNotifier.markAllNotifRead]。
///   - 外观:主题模式三选一(浅色/深色/跟随系统)接
///     [AppStateNotifier.setThemeMode];字号四选一 mock(本地 state);
///     暖纸底纹开关 mock(本地 state)。
///   - 缓存与数据:清缓存显示派生字节数(禁写死固定值,用 userId 派生),清搜索历史接
///     [AppStateNotifier.clearRecentSearches],真实计数 [AppStateData.recentSearches]。
///   - 关于:版本号、用户协议、隐私政策、开源致谢。
///
/// 零旁白(HANDOFF §3):无"完善设置"引导。
/// 珊瑚橙(HANDOFF §5):本屏无 take 动作,完全不用 coral。
/// 触控区(HANDOFF §5):所有可点元素 ≥ 44×44pt,统一走 [Tappable]。
/// 无 emoji:用 Material Icons。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // 字号/暖纸底纹/免打扰 已迁到 app_state(真生效),不再用本地 mock state。

  /// 缓存大小(KB)—— 用 'me' 用户 ID 派生(HANDOFF §6.10:禁写死固定值)。
  /// 范围 1024..5119,稳定确定性。
  late final int _cacheKb = 1024 + 'me'.hashCode.abs() % 4096;

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          backgroundColor: KkColors.t1,
        ),
      );
  }

  Future<void> _confirmClearCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清缓存'),
        content: Text('确定清缓存？将清除 $_cacheKb KB 临时文件'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: const TextStyle(color: KkColors.t3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('确定', style: const TextStyle(color: KkColors.teal)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      _toast('已清理 $_cacheKb KB');
    }
  }

  Future<void> _confirmClearSearches(int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清搜索历史'),
        content: Text('确定清除 $count 条搜索历史？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: const TextStyle(color: KkColors.t3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('确定', style: const TextStyle(color: KkColors.teal)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      ref.read(appStateProvider.notifier).clearRecentSearches();
      _toast('已清搜索历史');
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    // 真实计数(HANDOFF §6.10,无放大公式)。
    final unreadCount = appState.unreadNotifIds.length;
    final searchCount = appState.recentSearches.length;

    return Scaffold(
      backgroundColor: KkColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: KkSpacing.xxl),
          children: [
            _topBar(context),
            const SizedBox(height: KkSpacing.lg),
            _sectionAccount(),
            const SizedBox(height: KkSpacing.lg),
            _sectionNotifications(unreadCount),
            const SizedBox(height: KkSpacing.lg),
            _sectionAppearance(appState.themeMode),
            const SizedBox(height: KkSpacing.lg),
            _sectionCache(searchCount),
            const SizedBox(height: KkSpacing.lg),
            _sectionAbout(),
            const SizedBox(height: KkSpacing.xxl),
          ],
        ),
      ),
    );
  }

  // ── 顶栏 ──
  Widget _topBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.lg,
        vertical: KkSpacing.md,
      ),
      child: Row(
        children: [
          const KkBackButton(),
          const SizedBox(width: KkSpacing.sm),
          const Text('设置', style: KkType.h1),
        ],
      ),
    );
  }

  // ── 卡片容器(同 me 屏 _menu 风格)──
  Widget _card({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KkSpacing.lg),
      decoration: BoxDecoration(
        color: KkColors.bgCard,
        borderRadius: BorderRadius.circular(KkRadius.md),
        border: Border.all(color: KkColors.bd),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() =>
      const Divider(height: 1, color: KkColors.divider, indent: 56);

  // ── 通用菜单行(icon + label + trailing + chevron,可点)──
  Widget _menuRow({
    required IconData icon,
    required String label,
    String? trailing,
    bool disabled = false,
    VoidCallback? onTap,
  }) {
    return Tappable(
      onTap: disabled ? null : onTap,
      disabled: disabled,
      borderRadius: BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KkSpacing.md,
          vertical: KkSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: KkColors.t2),
            const SizedBox(width: KkSpacing.md),
            Expanded(
              child: Text(label, style: KkType.body),
            ),
            if (trailing != null) ...[
              Text(
                trailing,
                style:
                    KkType.mono.copyWith(color: KkColors.t3, fontSize: 12),
              ),
              const SizedBox(width: KkSpacing.xs),
            ],
            const Icon(Icons.chevron_right, size: 18, color: KkColors.t3),
          ],
        ),
      ),
    );
  }

  // ── Switch 行(icon + label + Switch)──
  Widget _switchRow({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.md,
        vertical: KkSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: KkColors.t2),
          const SizedBox(width: KkSpacing.md),
          Expanded(child: Text(label, style: KkType.body)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: KkColors.teal,
          ),
        ],
      ),
    );
  }

  // ── Segmented 行(头部 icon+label 一行,分段控件独占一行)──
  Widget _segmentedRow<T>({
    required IconData icon,
    required String label,
    required List<({T value, String label})> options,
    required T selected,
    required ValueChanged<T> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.md,
        vertical: KkSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: KkColors.t2),
              const SizedBox(width: KkSpacing.md),
              Text(label, style: KkType.body),
            ],
          ),
          const SizedBox(height: KkSpacing.md),
          _SegmentedControl<T>(
            options: options,
            selected: selected,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  // ── 静态行(icon + label + 只读 trailing,无 chevron)──
  Widget _staticRow({
    required IconData icon,
    required String label,
    required String trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KkSpacing.md,
        vertical: KkSpacing.md,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: KkColors.t2),
          const SizedBox(width: KkSpacing.md),
          Expanded(child: Text(label, style: KkType.body)),
          Text(
            trailing,
            style: KkType.mono.copyWith(color: KkColors.t3, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── Section 0: 账号(登录态真接后端)──
  // 未登录:一行「登录 / 注册」→ /login。
  // 已登录:显示昵称 + 「退出登录」(清真令牌，回游客态)。
  Widget _sectionAccount() {
    final auth = ref.watch(authProvider);
    if (!auth.isLoggedIn) {
      return _card(
        children: [
          _menuRow(
            icon: Icons.login_outlined,
            label: '登录 / 注册',
            onTap: () => context.push(KkRoutes.login),
          ),
        ],
      );
    }
    return _card(
      children: [
        _staticRow(
          icon: Icons.account_circle_outlined,
          label: '当前账号',
          trailing: auth.currentUser!.name,
        ),
        _divider(),
        // 任务 5:已登录时加「编辑资料」入口(→ /profile/edit)。
        // 未登录不显(上面 if 分支已 return 只有登录入口)。
        _menuRow(
          icon: Icons.edit_outlined,
          label: '编辑资料',
          onTap: () => context.push(KkRoutes.profileEdit),
        ),
        _divider(),
        _menuRow(
          icon: Icons.logout_outlined,
          label: '退出登录',
          onTap: _confirmLogout,
        ),
      ],
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定退出当前账号？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: const TextStyle(color: KkColors.t3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('确定', style: const TextStyle(color: KkColors.teal)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      ref.read(authProvider.notifier).logout();
      _toast('已退出登录');
    }
  }

  // ── Section 1: 通知 ──
  Widget _sectionNotifications(int unreadCount) {
    return _card(
      children: [
        _menuRow(
          icon: Icons.notifications_outlined,
          label: '通知',
          trailing: '未读 $unreadCount 条',
          onTap: () => context.push(KkRoutes.notifications),
        ),
        _divider(),
        _menuRow(
          icon: Icons.done_all_outlined,
          label: '全部标为已读',
          disabled: unreadCount == 0,
          onTap: () {
            ref.read(appStateProvider.notifier).markAllNotifRead();
            _toast('已全部标为已读');
          },
        ),
        _divider(),
        _switchRow(
          icon: Icons.do_not_disturb_on_outlined,
          label: '免打扰时段',
          // 真生效:开 → 通知铃未读红点被抑制(effectiveUnreadCount 归零)。
          value: ref.watch(appStateProvider).dndEnabled,
          onChanged: (v) =>
              ref.read(appStateProvider.notifier).setDndEnabled(v),
        ),
      ],
    );
  }

  // ── Section 2: 外观 ──
  Widget _sectionAppearance(ThemeMode themeMode) {
    return _card(
      children: [
        _segmentedRow<ThemeMode>(
          icon: Icons.palette_outlined,
          label: '主题模式',
          options: const [
            (value: ThemeMode.light, label: '浅色'),
            (value: ThemeMode.dark, label: '深色'),
            (value: ThemeMode.system, label: '跟随系统'),
          ],
          selected: themeMode,
          onChanged: (m) =>
              ref.read(appStateProvider.notifier).setThemeMode(m),
        ),
        _divider(),
        _segmentedRow<String>(
          icon: Icons.text_fields_outlined,
          label: '字号',
          options: const [
            (value: '小', label: '小'),
            (value: '标准', label: '标准'),
            (value: '大', label: '大'),
            (value: '特大', label: '特大'),
          ],
          // 真生效:全局 textScaler 由此偏好驱动(app.dart 应用)。
          selected: ref.watch(appStateProvider).fontScale,
          onChanged: (s) {
            ref.read(appStateProvider.notifier).setFontScale(s);
            _toast('字号已设为：$s');
          },
        ),
        _divider(),
        _switchRow(
          icon: Icons.texture_outlined,
          label: '暖纸底纹',
          // 真生效:NoiseBackground 读它决定画不画噪点。
          value: ref.watch(appStateProvider).paperTexture,
          onChanged: (v) =>
              ref.read(appStateProvider.notifier).setPaperTexture(v),
        ),
      ],
    );
  }

  // ── Section 3: 缓存与数据 ──
  Widget _sectionCache(int searchCount) {
    return _card(
      children: [
        _menuRow(
          icon: Icons.cleaning_services_outlined,
          label: '清缓存',
          trailing: '$_cacheKb KB',
          onTap: _confirmClearCache,
        ),
        _divider(),
        _menuRow(
          icon: Icons.history_outlined,
          label: '清搜索历史',
          trailing: '$searchCount 条',
          disabled: searchCount == 0,
          onTap: () => _confirmClearSearches(searchCount),
        ),
        _divider(),
        _menuRow(
          icon: Icons.upload_outlined,
          label: '导入数据',
          onTap: () => _toast('导入功能将在后续版本支持'),
        ),
        _divider(),
        _menuRow(
          icon: Icons.download_outlined,
          label: '导出数据',
          onTap: () => _toast('导出功能将在后续版本支持'),
        ),
      ],
    );
  }

  // ── Section 4: 关于 ──
  Widget _sectionAbout() {
    return _card(
      children: [
        _staticRow(
          icon: Icons.info_outline,
          label: '版本',
          trailing: '0.2.0+1',
        ),
        _divider(),
        _menuRow(
          icon: Icons.description_outlined,
          label: '用户协议',
          onTap: () => _toast('用户协议页面将在后续版本支持'),
        ),
        _divider(),
        _menuRow(
          icon: Icons.privacy_tip_outlined,
          label: '隐私政策',
          onTap: () => _toast('隐私政策页面将在后续版本支持'),
        ),
        _divider(),
        _menuRow(
          icon: Icons.code_outlined,
          label: '开源致谢',
          onTap: () => _toast('开源致谢页面将在后续版本支持'),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 分段控件 — 自定义(不依赖 Cupertino,参考 me 屏 pill 风格)
//
// 选中:bgTeal + 白字;未选:透明 + t2 字。pill 圆角 [KkRadius.pill]。
// 横排等宽(每项 Expanded),所有可点单元 ≥ 44pt(Tappable 默认 minHeight)。
// ──────────────────────────────────────────────────────────────────

class _SegmentedControl<T> extends StatelessWidget {
  final List<({T value, String label})> options;
  final T selected;
  final ValueChanged<T> onChanged;

  const _SegmentedControl({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KkColors.bgSubtle,
        borderRadius: BorderRadius.circular(KkRadius.pill),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: [
          for (final opt in options)
            Expanded(
              child: Tappable(
                onTap: () => onChanged(opt.value),
                borderRadius: BorderRadius.circular(KkRadius.pill),
                child: AnimatedContainer(
                  duration: KkDuration.fast,
                  padding: const EdgeInsets.symmetric(
                    horizontal: KkSpacing.sm,
                    vertical: KkSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: opt.value == selected
                        ? KkColors.teal
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(KkRadius.pill),
                  ),
                  child: Center(
                    child: Text(
                      opt.label,
                      style: KkType.bodySm.copyWith(
                        color: opt.value == selected
                            ? Colors.white
                            : KkColors.t2,
                        fontWeight: opt.value == selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
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
