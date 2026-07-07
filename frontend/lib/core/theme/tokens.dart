import 'package:flutter/material.dart';

import '../fonts/font_family.dart';
import 'kk_colors.dart';

/// 设计 token — 间距 / 圆角 / 字号 / 时长 / 触控。
///
/// 全 App 只用这里的常量,不硬编码数字(保证一致性)。
/// HANDOFF §5:触控区 ≥ 44×44pt 是铁律。

/// 间距体系(4 的倍数)
class KkSpacing {
  KkSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
}

/// 圆角体系
class KkRadius {
  KkRadius._();
  static const sm = 6.0;   // 小标签
  static const md = 12.0;  // 卡片
  static const lg = 16.0;  // 大卡片(暖纸品牌偏柔和)
  static const xl = 20.0;  // sheet 顶部
  static const pill = 999.0; // 胶囊
}

/// 高度 / 阴影体系(SSOT §1)
///
/// 暖纸品牌用暖色阴影(基色 #16130F),不用纯黑,避免发灰发脏。
/// 卡片轻抬升,浮层重一档。Feed 行(分隔线式)不用阴影。
class KkElevation {
  KkElevation._();

  /// 卡片:与 Web 原型完全一致
  /// (原型 CSS: 0 1px 2px rgba(22,19,15,.05), 0 12px 28px -18px rgba(22,19,15,.24))
  static const card = [
    BoxShadow(
      color: Color(0x0D16130F), // rgba(22,19,15,.05)
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x3D16130F), // rgba(22,19,15,.24)
      blurRadius: 28,
      offset: Offset(0, 12),
      spreadRadius: -18,
    ),
  ];

  /// 浮层 / sheet / 底栏:更强一档
  static const overlay = [
    BoxShadow(
      color: Color(0x2916130F),
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: -6,
    ),
  ];
}

/// 字号体系(三声部字体)
///
/// HANDOFF §5:
///   - 标题:Noto Serif SC(衬线,必须含中文子集)
///   - 元数据/数字:JetBrains Mono(等宽)
///   - 正文:系统 sans(Material 默认)
class KkType {
  KkType._();

  // 大标题 / 首屏 hero(衬线,编辑感)— SSOT §1
  // fontFamilyFallback:pubspec 未声明 fonts: 段时按系统已安装衬线降级,不崩。
  static const display = TextStyle(
    fontFamily: KkFonts.title,
    fontFamilyFallback: KkFonts.titleFallback,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: KkColors.t1,
  );

  // 标题(衬线)— fontFamily 找不到时按 fontFamilyFallback 降级到系统衬线
  static const h1 = TextStyle(
    fontFamily: KkFonts.title,
    fontFamilyFallback: KkFonts.titleFallback,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: KkColors.t1,
  );
  static const h2 = TextStyle(
    fontFamily: KkFonts.title,
    fontFamilyFallback: KkFonts.titleFallback,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.35,
    color: KkColors.t1,
  );
  static const h3 = TextStyle(
    fontFamily: KkFonts.title,
    fontFamilyFallback: KkFonts.titleFallback,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: KkColors.t1,
  );

  // 正文(系统 sans)
  static const body = TextStyle(
    fontSize: 15,
    height: 1.5,
    color: KkColors.t1,
  );
  static const bodySm = TextStyle(
    fontSize: 13,
    height: 1.45,
    color: KkColors.t2,
  );

  // 元数据/数字(等宽)— fontFamilyFallback:系统已安装同名等宽字体时直接命中
  static const mono = TextStyle(
    fontFamily: KkFonts.mono,
    fontFamilyFallback: KkFonts.monoFallback,
    fontSize: 13,
    height: 1.4,
    color: KkColors.t2,
  );
  static const monoLg = TextStyle(
    fontFamily: KkFonts.mono,
    fontFamilyFallback: KkFonts.monoFallback,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: KkColors.t1,
  );
}

/// 动画时长
class KkDuration {
  KkDuration._();
  static const fast = Duration(milliseconds: 150);
  static const med = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
}

/// 触控区铁律
class KkTouch {
  KkTouch._();
  /// HANDOFF §5:所有可点元素实际点击区 ≥ 44×44pt
  static const minTarget = 44.0;
}
