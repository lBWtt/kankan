import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/prefs.dart';
import 'core/theme/kk_colors.dart';
import 'core/theme/tokens.dart';

/// 入口。
///
/// HANDOFF §0:看看 = "看 AI 做出的有意思的东西 + 心得"的目的地。
/// Phase 1:ProviderScope 包根 → KankanApp(MaterialApp.router)。
///
/// 会话持久化:main 里先 await SharedPreferences,再 override 注入 prefsProvider,
/// 这样 tokenStore/auth 能同步读回登录令牌——web 刷新页面不掉登录。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 任务 2:全局错误兜底——某 widget build 抛异常时,release 下不再灰屏/红块。
  //   ErrorWidget.builder:渲染异常 widget 时显示的兜底(暖纸底 + Icon + 一句事实)。
  //   FlutterError.onError:release 下吞掉并 debugPrint,debug 下照常 presentError。
  //   零旁白(只「这里出了点问题」)/ 无 emoji / coral 只给 take(此处不用)。
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: KkColors.bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: KkColors.t3),
            const SizedBox(height: KkSpacing.md),
            Text(
              '这里出了点问题',
              style: KkType.body.copyWith(color: KkColors.t2),
            ),
          ],
        ),
      ),
    );
  };
  FlutterError.onError = (FlutterErrorDetails details) {
    if (kReleaseMode) {
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    } else {
      FlutterError.presentError(details);
    }
  };
  // 任务 2(补):异步/平台层未捕获异常兜底。FlutterError.onError 只覆盖 framework
  //   同步错误;Future 未 catch 等 zone 外异步异常走 PlatformDispatcher.onError,
  //   不注册的话 release 下会静默崩溃。返回 true = 已处理,阻止默认上抛。
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    if (kReleaseMode) {
      debugPrint('Uncaught async error: $error');
    } else {
      FlutterError.presentError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    }
    return true;
  };
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const KankanApp(),
    ),
  );
}
