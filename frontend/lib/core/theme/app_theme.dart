import 'package:flutter/material.dart';

import 'kk_colors.dart';
import 'tokens.dart';
// 字体 family 常量 + 回退链见 lib/core/fonts/font_family.dart。
// 经 tokens.dart 的 KkType.* 间接绑定,本文件不直接引用 KkFonts,避免 unused_import。

/// 主题。HANDOFF §5:暂不做深色模式,只 light。
///
/// 不在 ThemeData 层覆写 cardTheme / buttonTheme 等(CardThemeData 在
/// 不同 Flutter 版本 API 漂移)。卡片/按钮样式 Phase 2 起用专门 KkCard /
/// KkButton 组件管控,避免 ThemeData 兼容性坑。
///
/// ## 字体接线(P2)
/// `textTheme` / `appBarTheme.titleTextStyle` 经 `KkType.*` 间接绑定
/// `KkFonts.title` / `KkFonts.mono` + `fontFamilyFallback`:
///   - 标题语义槽(displayLarge / displayMedium / titleLarge)
///     → `KkType.h1/h2/h3` → `KkFonts.title` + `KkFonts.titleFallback`
///   - 等宽语义槽(labelSmall)→ `KkType.mono` → `KkFonts.mono` + `KkFonts.monoFallback`
///
/// pubspec.yaml 未声明 `fonts:` 段时,Flutter 按回退链匹配系统已安装字体,
/// 视觉接近品牌、不崩。详见 `lib/core/fonts/font_family.dart`。
class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: KkColors.bg,
      canvasColor: KkColors.bg,
      // HANDOFF §5:珊瑚橙只给 take(拿到手)动作,别处禁用。
      // 因此不设 secondary / error = coral(会泄漏到 Material 语义槽)。
      // secondary / error 留 Material 默认;coral 只在 KkColors.coral 定义处待命,
      // Phase 2 take 动作按钮才显式引用。
      colorScheme: ColorScheme.light(
        primary: KkColors.teal,
        surface: KkColors.bgCard,
        onPrimary: Colors.white,
        onSurface: KkColors.t1,
      ),
      dividerColor: KkColors.divider,
      splashFactory: InkSparkle.splashFactory,
      // 文字主题:把 KkType 接入 Material 默认语义
      // (KkType 内已带 KkFonts.title/mono + fontFamilyFallback,见 tokens.dart)
      textTheme: const TextTheme(
        displayLarge: KkType.h1,
        displayMedium: KkType.h2,
        titleLarge: KkType.h3,
        bodyLarge: KkType.body,
        bodyMedium: KkType.bodySm,
        labelSmall: KkType.mono,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: KkColors.bg,
        foregroundColor: KkColors.t1,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        // KkType.h3 已带 KkFonts.title + titleFallback,系统缺字时优雅降级
        titleTextStyle: KkType.h3,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: KkColors.bgCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(KkRadius.xl)),
        ),
      ),
    );

    return base;
  }
}
