import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/prefs.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/admin_fab.dart';
import 'features/kankan/kankan_onboarding_sheet.dart';
import 'features/legal/privacy_consent_screen.dart';
import 'l10n/kk_strings.dart';
import 'providers/analytics_provider.dart';
import 'providers/app_state_provider.dart';
import 'providers/auth_provider.dart';
import 'router/app_router.dart';

/// 根 Widget。
///
/// MaterialApp.router + go_router。主题只 light(HANDOFF §5:深色模式 defer)。
/// debugShowCheckedModeBanner 关掉(原型不显示 debug 角标)。
///
/// Phase 4:启用 Hero 共享元素,配合 project_card 的 Hero tag
/// (`'project-cover-{project.id}'`)实现 cover 飞入详情页。
/// `MaterialHeroController` 是 Flutter material 库自带(Flutter 3.16+),
/// 无需额外 import。app_router 已用 CustomTransitionPage 透传 Hero widget,
/// Hero 飞行由本 controller 协调。
///
/// P2-i18n:本地化接线(用户:"未来会用英文,但不准备第一次就上线,接口留好就行"):
///   - localizationsDelegates:GlobalMaterial/Widgets/Cupertino 三件套(框架层
///     本地化,如日期/数字格式、Material 系统按钮文案)。
///   - supportedLocales:[zh, en](声明 app 支持这两种语言)。
///   - locale:写死 zh(默认中文);切 en 时改 `ref.watch(kkLocaleProvider)`。
///   - app 自身的字符串走 [KkStrings](lib/l10n/kk_strings.dart,手写免 codegen),
///     不依赖 flutter gen-l10n;切 gen-l10n 时 localizationsDelegates 改为
///     `AppLocalizations.localizationsDelegates`(三件套会自动包含)。
class KankanApp extends ConsumerStatefulWidget {
  const KankanApp({super.key});

  @override
  ConsumerState<KankanApp> createState() => _KankanAppState();
}

class _KankanAppState extends ConsumerState<KankanApp>
    with WidgetsBindingObserver {
  // 前台通知徽标轮询：在别的 tab 上时，别人给你点赞/关注/评论也能让红点自己亮起来，
  // 不必先打开通知中心才刷新。只在前台跑，切后台即停（省流量/省电）。
  Timer? _notifPollTimer;
  static const _notifPollInterval = Duration(seconds: 45);
  String? _privacyChoice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final prefs = ref.read(prefsProvider);
    _privacyChoice = hasPrivacyDecision(prefs)
        ? prefs.getString(PrefsKeys.kvPrivacyChoice)
        : null;
    if (_privacyChoice != null) _startNotifPolling();
  }

  @override
  void dispose() {
    _notifPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_privacyChoice == null) return;
    if (state == AppLifecycleState.resumed) {
      // 从后台切回前台也算一次活跃（DAU 按天去重，不会重复计人）。
      ref.read(analyticsProvider).track('app_open');
      // 回前台立刻对齐一次红点，再恢复轮询（后台期间攒下的通知即时显示）。
      _pollNotifBadge();
      _startNotifPolling();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _notifPollTimer?.cancel();
      unawaited(ref.read(analyticsProvider).flush());
    }
  }

  void _startNotifPolling() {
    _notifPollTimer?.cancel();
    _notifPollTimer =
        Timer.periodic(_notifPollInterval, (_) => _pollNotifBadge());
  }

  void _pollNotifBadge() {
    // 仅远端模式 + 已登录才有真实未读；否则 no-op（游客/demo 用本地 mock 未读）。
    if (!AppConfig.useRemote) return;
    if (!ref.read(authProvider).isLoggedIn) return;
    ref.read(appStateProvider.notifier).refreshUnreadBadge();
  }

  Future<void> _savePrivacyDecision(bool allowAnonymousAnalytics) async {
    final choice = allowAnonymousAnalytics
        ? privacyChoiceAccepted
        : privacyChoiceEssentialOnly;
    await ref.read(prefsProvider).setString(PrefsKeys.kvPrivacyChoice, choice);
    ref.invalidate(analyticsProvider);
    if (!mounted) return;
    setState(() => _privacyChoice = choice);
    _startNotifPolling();
  }

  @override
  Widget build(BuildContext context) {
    if (_privacyChoice == null) {
      return MaterialApp(
        title: const KkStrings.zh().appTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        locale: const Locale('zh'),
        home: PrivacyConsentScreen(onDecision: _savePrivacyDecision),
      );
    }
    final router = ref.watch(goRouterProvider);
    // 字号真生效:全局 textScaler 由 settings 的字号偏好驱动(app_state)。
    final scale = ref.watch(
      appStateProvider.select((s) => s.textScaleFactor),
    );
    // P2-i18n:当前写死 zh;切 en 时改为 `ref.watch(kkLocaleProvider)`。
    const locale = Locale('zh');
    // 同一安装包支持普通账号与管理员账号；只有后端确认 isAdmin 才显示审核悬浮球。
    final showAdminFab = ref.watch(authProvider.select((s) => s.isAdmin));
    return MaterialApp.router(
      // P2-i18n:app 文案当前由 KkStrings 手写(appTitle 等不直接走此处)。
      // MaterialApp.title 是任务切换器/系统标题栏显示的 app 名,这里用 zh 文案。
      title: const KkStrings.zh().appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
      // P2-i18n:本地化接线(框架层 Material/Cupertino/Widgets 系统文案 +
      // 日期/数字格式)。切 gen-l10n 时这里替换为 AppLocalizations.localizationsDelegates。
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      locale: locale,
      builder: (context, child) => _AppBootstrap(
        child: MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          // 管理员构建 + 已以管理员登录：在全局 Overlay 之上叠一个可拖动的审核悬浮球
          // （消费端 adminBuild=false 整块被 tree-shake；普通用户/未登录 isAdmin=false 不显示）。
          child: showAdminFab
              ? Stack(
                  children: [
                    child ?? const SizedBox.shrink(),
                    const AdminFab(),
                  ],
                )
              : (child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}

/// 位于 MaterialApp 下方的启动副作用承载点。
/// 这里的 context 已具备 MaterialLocalizations/Navigator，可安全弹 onboarding。
class _AppBootstrap extends ConsumerStatefulWidget {
  final Widget child;

  const _AppBootstrap({required this.child});

  @override
  ConsumerState<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<_AppBootstrap> {
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame());
  }

  Future<void> _afterFirstFrame() async {
    if (!mounted) return;
    ref.read(analyticsProvider).track('app_open');
    final prefs = ref.read(prefsProvider);
    if (prefs.getBool(PrefsKeys.kvKankanOnboardingSeen) == true) return;
    final overlayContext = rootNavigatorKey.currentState?.overlay?.context;
    if (overlayContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame());
      return;
    }
    await showKankanOnboardingSheet(overlayContext);
    if (mounted) {
      await prefs.setBool(PrefsKeys.kvKankanOnboardingSeen, true);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
