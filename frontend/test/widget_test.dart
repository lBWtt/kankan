// Widget 冒烟测试:app 启动 + 底栏 + Tab 切换。
//
// 文件结构:
//   1. 【保留】原有「app 启动冒烟:挂载 MaterialApp」测试。
//      原版用 `const ProviderScope(child: KankanApp())` 未 override prefsProvider,
//      但 AppStateNotifier.build() 经由 authProvider → tokenStoreProvider →
//      prefsProvider 会抛 UnimplementedError 导致 KankanApp.build() 失败。
//      这里补上 prefsProvider override,让冒烟测试真正能挂起 MaterialApp。
//      (测试名与 expect 不变,只补启动前置。)
//   2. 【新增】带 prefsProvider override 的启动冒烟:验证 4 个 Tab + FAB 结构。
//   3. 【新增】Tab 切换冒烟:发现 → 看看 → 收藏 → 我的,每个 Tab 被激活后对应
//      branch 屏被构建(StatefulShellRoute.indexedStack 懒加载)。
//
// 限制说明(任务明确):deep widget 测试需要 running backend/mock providers,
// 这里只做 boot + 基本导航冒烟,不深入屏内交互。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kankan_flutter/app.dart';
import 'package:kankan_flutter/core/prefs.dart';
import 'package:kankan_flutter/features/discover/discover_screen.dart';
import 'package:kankan_flutter/features/kankan/kankan_screen.dart';
import 'package:kankan_flutter/features/library/library_screen.dart';
import 'package:kankan_flutter/features/me/me_screen.dart';

void main() {
  // SharedPreferences 在所有 widget 测试前切到 mock(避免平台 channel 调用)。
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ──────────────────────────────────────────────────────────────────
  // 1. 【保留·原 test】app 启动冒烟:挂载 MaterialApp。
  //    补上 prefsProvider override(原版未 override 会经 prefsProvider 抛
  //    UnimplementedError 导致挂不起 MaterialApp)。测试名与 expect 不变。
  // ──────────────────────────────────────────────────────────────────
  testWidgets('app 启动冒烟:挂载 MaterialApp', (WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: const KankanApp(),
      ),
    );
    // DiscoverScreen.initState 起了 300ms 假加载 timer——用 pumpAndSettle 等其落定，
    // 否则测试结束时有 pending timer 触发断言失败。
    await tester.pumpAndSettle();
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  // ──────────────────────────────────────────────────────────────────
  // 2. 【新增】带 prefsProvider override 的启动冒烟:底栏 4 Tab + FAB。
  // ──────────────────────────────────────────────────────────────────
  testWidgets('app 启动冒烟(override prefs):底栏 4 Tab + FAB 结构',
      (WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: const KankanApp(),
      ),
    );
    // discover 屏 initState 有 300ms 假延迟,pumpAndSettle 等其落定。
    await tester.pumpAndSettle();

    // MaterialApp 挂载成功。
    expect(find.byType(MaterialApp), findsOneWidget);

    // 底栏 4 个 Tab 文案都在。「发现」合法出现 2 次(底栏标签 + DiscoverScreen 的 H1
    // 标题,当前屏 onstage),故用 findsWidgets;其余 Tab 屏未构建/offstage,仅底栏一处。
    expect(find.text('发现'), findsWidgets);
    expect(find.text('看看'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    // FAB:Icons.add(墨绿圆 + 白色加号)。
    expect(find.byIcon(Icons.add), findsOneWidget);

    // 初始 Tab = 发现(0),DiscoverScreen 已构建。
    expect(find.byType(DiscoverScreen), findsOneWidget);
  });

  // ──────────────────────────────────────────────────────────────────
  // 3. 【新增】Tab 切换:发现 → 看看 → 收藏 → 我的。
  //    StatefulShellRoute.indexedStack 懒加载:点过的 branch 才构建对应屏。
  // ──────────────────────────────────────────────────────────────────
  testWidgets('Tab 切换冒烟:发现 → 看看 → 收藏 → 我的',
      (WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: const KankanApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 初始:发现 Tab 已构建。
    expect(find.byType(DiscoverScreen), findsOneWidget);

    // 切到「看看」(branch 1)。
    await tester.tap(find.text('看看'));
    await tester.pumpAndSettle();
    expect(find.byType(KankanScreen), findsOneWidget);

    // 切到「收藏」(branch 2)。
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);

    // 切到「我的」(branch 3)。
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.byType(MeScreen), findsOneWidget);

    // 回到「发现」(验证可以来回切,不卡死)。
    await tester.tap(find.text('发现'));
    await tester.pumpAndSettle();
    expect(find.byType(DiscoverScreen), findsOneWidget);
  });

  // ──────────────────────────────────────────────────────────────────
  // 4. 【新增】FAB 存在性:已在 test #2 中验证 find.byIcon(Icons.add) findsOneWidget。
  //    不再深入点击弹 sheet(flutter_animate 动画 + 后续 push /publish 路由会引入
  //    pumpAndSettle 时序问题,且任务明确「Keep it minimal — just boot + basic nav」)。
  // ──────────────────────────────────────────────────────────────────
}
