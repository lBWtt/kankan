/// 字体 family 常量 + 优雅降级 helper。
///
/// HANDOFF §5 三声部字体:
///   - 标题:Noto Serif SC(衬线,**必须含中文子集**,Web 版踩过 subsets:['latin']
///     不含中文的坑 → Flutter 端自托管子集化文件,见 assets/fonts/README.md)
///   - 元数据/数字:JetBrains Mono(等宽)
///   - 正文:系统 sans(不显式命名,走 Material 默认)
///
/// ## 接口留好,资源待投(P2 策略)
/// `pubspec.yaml` 默认注释掉 `fonts:` 段,因此本仓库不携带 .ttf 资源,
/// `flutter pub get` 不会因缺失资源文件而报错。`KkFonts.title` / `KkFonts.mono`
/// 仍是有效的 family 名字符串——Flutter 找不到匹配的声明字体时,会按
/// `fontFamilyFallback` 顺序匹配系统已安装的同名字体,再降级到 generic family
/// (`serif` / `monospace`),不会崩。视觉接近品牌、中文正常显示。
///
/// 真要切到自托管子集时,只需:
///   1. 把 `assets/fonts/NotoSerifSC-Subset.ttf`、`JetBrainsMono-Regular.ttf`
///      放进 `assets/fonts/`(生成命令见该目录 README.md)。
///   2. 取消 `pubspec.yaml` 末尾 `fonts:` 段注释。
///   3. `flutter pub get`。无需改 lib/ 任何一行。
import 'package:flutter/material.dart';

class KkFonts {
  KkFonts._();

  // ── family 名(对应 pubspec.yaml `fonts: - family:` 段)──

  /// 标题衬线 family 名。
  static const title = 'NotoSerifSC';

  /// 等宽 family 名。
  static const mono = 'JetBrainsMono';

  // ── 回退链(系统已安装的近似字体)──
  //
  // pubspec 未声明 `fonts:` 段时,Flutter 拿不到自托管 .ttf,会按此列表
  // 顺序在系统已安装字体里找。命中后视觉与品牌一致;全不命中时降级到
  // generic family(`serif` / `monospace`)。

  /// 标题衬线回退链。
  /// 顺序:Google Fonts 官方名 → 思源系列 → iOS 宋体 → generic serif。
  static const titleFallback = <String>[
    'Noto Serif SC',
    'Source Han Serif SC',
    'Songti SC',
    'serif',
  ];

  /// 等宽回退链。
  /// 顺序:JetBrains Mono → Roboto Mono → Android 默认等宽 → generic monospace。
  static const monoFallback = <String>[
    'JetBrains Mono',
    'Roboto Mono',
    'Droid Sans Mono',
    'monospace',
  ];

  // ── TextStyle helper ──
  //
  // 已经在 `lib/core/theme/tokens.dart` 里定义了完整的字号/字重体系的
  // `KkType.*` 常量,优先用那些。本 helper 给"想直接拿一个带 fallback 的
  // 标题/等宽 style、又不想自己拼 fontFamilyFallback 列表"的临时场景用。

  /// 标题衬线 TextStyle(带 fontFamilyFallback)。
  ///
  /// 用法:
  /// ```dart
  /// Text('标题', style: KkFonts.titleStyle(fontSize: 24, fontWeight: w700));
  /// ```
  /// 已有 TextStyle 想补 fallback 的场景,直接 copyWith:
  /// ```dart
  /// someStyle.copyWith(
  ///   fontFamily: KkFonts.title,
  ///   fontFamilyFallback: KkFonts.titleFallback,
  /// );
  /// ```
  static TextStyle titleStyle({
    double fontSize = 17,
    FontWeight fontWeight = FontWeight.w600,
    double height = 1.4,
    Color? color,
    TextDecoration? decoration,
  }) {
    return TextStyle(
      fontFamily: title,
      fontFamilyFallback: titleFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      color: color,
      decoration: decoration,
    );
  }

  /// 等宽 TextStyle(带 fontFamilyFallback)。
  static TextStyle monoStyle({
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w400,
    double height = 1.4,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: mono,
      fontFamilyFallback: monoFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      color: color,
    );
  }
}
