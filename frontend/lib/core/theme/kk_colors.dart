import 'package:flutter/material.dart';

/// 看看色板 — 来自 HANDOFF §5 美术铁律。
///
/// 5 色族(单屏强调色 ≤ 3 种):
///   暖纸中性(底) + 墨绿(品牌,go/how) + 珊瑚橙(行动,**只给 take**) + 文字灰阶 + 边框
///
/// 珊瑚橙 #D85A30 是"这下东西归你了"的唯一信号(HANDOFF §2.2)。
/// 导流(go)不是"拿到手",不配珊瑚橙。别处禁用。
class KkColors {
  KkColors._();

  // ── 底色 ──
  /// 暖纸噪点底 #FBF9F4(HANDOFF §5)
  static const bg = Color(0xFFFBF9F4);
  static const bgCard = Color(0xFFFFFFFF);
  static const bgSubtle = Color(0xFFF5F1EA);

  // ── 品牌色:墨绿 ──
  /// 墨绿 #1D9E75(HANDOFF §5)— 品牌主色。go(描边)/ how(文字)用。
  static const teal = Color(0xFF1D9E75);
  static const tealDark = Color(0xFF157054);
  /// 墨绿浅底(mint)— Tab pill 激活底色等
  static const mint = Color(0xFFE8F5EE);

  // ── 行动色:珊瑚橙(只给 take)──
  /// 珊瑚橙 #D85A30(HANDOFF §5)— **只给 take(拿到手)动作,别处禁用**
  static const coral = Color(0xFFD85A30);
  static const coralDark = Color(0xFFB8482A);
  /// 珊瑚橙浅底
  static const coralMint = Color(0xFFFBEDE6);

  // ── 文字灰阶(Web 版 t1/t2/t3 体系)──
  /// 主文字
  static const t1 = Color(0xFF1F1B16);
  /// 次文字
  static const t2 = Color(0xFF5C544A);
  /// 弱文字/元数据
  static const t3 = Color(0xFF8A8275);
  /// 占位/禁用
  static const t4 = Color(0xFFB5AC9D);

  // ── 边框 / 分隔 ──
  /// 卡片边框
  static const bd = Color(0xFFE8E2D6);
  /// 分隔线
  static const divider = Color(0xFFEFE9DD);

  // ── 语义色(SSOT §1,取自 Web 原型全色板)──
  /// 点赞情感色(区别于 take 的珊瑚橙)。心用偏红,take 用珊瑚。
  static const like = Color(0xFFE0245E);
  /// 榜单第 1 / staff_pick
  static const gold = Color(0xFFB68A2E);
  /// 榜单第 2
  static const silver = Color(0xFF9F9B92);
  /// 榜单第 3
  static const bronze = Color(0xFFB97F4F);
  /// repo stars / 次要强调
  static const amber = Color(0xFFA57423);
}
