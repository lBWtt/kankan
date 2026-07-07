import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'l10n/kk_strings.dart';
import 'providers/app_state_provider.dart';
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
class KankanApp extends ConsumerWidget {
  const KankanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    // 字号真生效:全局 textScaler 由 settings 的字号偏好驱动(app_state)。
    final scale = ref.watch(
      appStateProvider.select((s) => s.textScaleFactor),
    );
    // P2-i18n:当前写死 zh;切 en 时改为 `ref.watch(kkLocaleProvider)`。
    const locale = Locale('zh');
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
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: scale,
        maxScaleFactor: scale,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
