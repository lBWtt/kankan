# 任务②：编辑级排版精修（对齐原型的层次与留白）

**先读** `docs/KANKAN_SPEC.md`。目标：让列表/卡片/筛选更像原型的"编辑感"——层次分明、留白克制、细节精致。
**只改视觉样式，不动功能/数据/路由/provider/架构。** 下面每条都给了原型的确切值，照着做。

## 1. Feed / 列表背景分层（最高优先）
- 原型：列表容器背景是 `bg2 #F5F3EE`，卡片是白/暖纸 → 卡片"浮"起来，有编辑层次。
- 现状：Flutter 列表直接铺在暖纸底上，卡片和背景太接近，发闷。
- 改：给「看看 / 收藏(收藏 Tab) / 发现」的**列表滚动区**加一层 `KkColors.bgSubtle`（≈bg2）背景；卡片保持 `bgCard`。
- 注意：branch 屏在 `KkRootShell` 的 NoiseBackground 上——给列表区包一层 `Container(color: KkColors.bgSubtle)` 即可，别破坏底部 tab 栏。

## 2. 卡片间距
- 原型卡片间距 18px。Flutter 列表卡现在多是 `KkSpacing.md`(12)。
- 改：列表卡之间用 `KkSpacing.lg`(16) 起、偏向 18 的观感（可用 18 硬值或 lg）。统一。

## 3. 屏幕标题品牌点（签名细节）
- 原型每屏标题后有一个 **6px 的 teal 小圆点**（`.kktitle::after`）。
- 改：给「发现 / 看看 / 收藏 / 我的」的 `KkType.h1` 标题后面加一个 6×6 圆点（`KkColors.teal`），标题和圆点用 Row 排。
- 例：`Row(children:[Text('发现', style: KkType.h1), const SizedBox(width:7), Container(width:6,height:6,decoration:BoxDecoration(color:KkColors.teal, shape:BoxShape.circle))])`

## 4. 筛选 chip 精修（更编辑、更克制）
- 原型激活 chip = **bg2 底 + 0.5px 边框 + t1 加粗文字**（不是 teal 实心填充）。
- 现状：Flutter 激活 chip 是 teal 实心 + 白字，太重。
- 改：激活态 → `bgSubtle` 底 + `bd` 边框 + `t1` 加粗文字；未激活 → 透明底 + `t2` 文字。
- 范围：看看页领域 chip（全部/AI图/…）、素材页筛选 chip（全部/文本/文件/链接）。

## 铁律（详见 SPEC）
coral 只给 take / 无 emoji / 触控 ≥44pt / 零旁白 / 四态齐 / 禁不可变 `..sort` / 禁 `if(artifactType==...)` 分支。

## 约束
- **不动** `lib/core/theme/*`（token 我维护）、`lib/core/network/*`、数据/mock/路由/provider。
- **不改** 主 tab 指示器颜色（teal 保留）、不改点赞/收藏图标色——这些我另定。
- 不整包重生成，只改相关屏/组件文件（kankan/library/discover 屏 + 用到的 chip 组件）。
- `flutter analyze` 0 error。改完开 PR。

## 交付
列出改了哪些文件，确认 analyze 无 error，开 PR 给链接。
