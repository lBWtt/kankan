# 任务④：项目卡「可以拿走」行

**先读** `docs/KANKAN_SPEC.md`。目标：给 `ProjectCard` full 模式在 summary 下加一行「可以拿走什么 · 怎么用」的招牌描述行——这是本产品最核心的 UX,让人一眼看到「能拿到什么、怎么用」,直接驱动「想做/想拿走」意图。原型每张卡都有,现在 Flutter 缺。

**只改视觉样式 + 加一个可选 hint 字段,不动功能/数据语义/mock 计数/路由/provider/架构。**

## Part A（必做）：take chip 行
- `project_card.dart` full 模式在 summary 下、作者行上,加一行 take chip。
- 数据取现成的 `Project.actions`,用 `actions.whereType<TakeAction>().firstOrNull` 拿**第一个** TakeAction(**禁 `if(artifactType==...)` 硬编码分支**,铁律 §6.1)。
- 有 TakeAction → **珊瑚橙浅底 chip**(`KkColors.coralMint` 底 + `KkColors.coral` 文字/图标):
  - 图标按 `takeKind`:`copy` → `Icons.copy_outlined`;`download` → `Icons.download_outlined`。
  - 文字 = `label`(TakeAction.label,现有 mock 都有 label,不要编造)。
  - 圆角 `KkRadius.pill`(胶囊)或 `KkRadius.md`,内边距克制(`horizontal: KkSpacing.sm` 起、`vertical: KkSpacing.xs` 起)。
  - **不出现「拿走」二字**(铁律 §6 + HANDOFF §2.2),靠图标 + 名词表意。
- 无 TakeAction 但有 GoAction → 退化成 **teal「去看看」chip**(`KkColors.mint` 底 + `KkColors.teal` 文字 + `Icons.arrow_outward` 行尾),取 `actions.whereType<GoAction>().firstOrNull`。
- 都没有(纯 HowAction / 空)→ **整行不显示**(不占位、不留空)。

## Part B（做,可降级）：label · hint
- 给 `TakeAction` 加可选 `String? hint` 字段(`lib/domain/models/action_item.dart`)。
  - ⚠️ `TakeAction` 是手写 `@immutable` class(**不是 `@freezed`**),加字段**不需要 build_runner**——直接加 `final String? hint;` + 构造参数即可。
- 在 `mock_seed.dart` 给每个 `TakeAction` 补一句**真实具体**的用法 hint(不要编造计数,只是「怎么用」一句话):
  - Midjourney 提示词(copy)→ `hint: '粘进 Midjourney 就能跑'`
  - SDXL 节气提示词(copy)→ `hint: '粘进 SD Web UI 正向词框'`
  - 水墨游鱼动画文件(download .mp4)→ `hint: '下载后可直接发短视频'`
  - 图片压缩脚本(download .py)→ `hint: 'python 命令行直接跑'`
  - md2pdf 安装命令(copy)→ `hint: '终端粘贴即装好'`
  - GPT 代码评审系统提示词(copy)→ `hint: '粘进 GPT 当系统提示词'`
  - Claude 写作助手提示词(copy)→ `hint: '粘进 Claude 当系统提示词'`
- 卡片 take chip 显示成 **`label · hint`**:`label` 用 coral 加粗,`hint` 用 `coral.withAlpha(180)` 或 `t2` 更细字重,中间 `·` 分隔。
- hint 是 null → 只显 `label`(向后兼容)。

## 铁律（照 SPEC §6）
- **coral 只给 take**(chip 浅底 `coralMint` 也只给 take;退化「去看看」用 teal/mint,不用 coral)。
- **无 emoji** / **不出现「拿走」二字**(靠图标 + 名词表意)。
- **禁 `if(artifactType==...)` 硬编码**——用 `whereType<TakeAction>()` / `whereType<GoAction>()`。
- 触控 ≥44pt(chip 本身可点可不点;若可点,走 `Tappable`)。
- **零旁白**(无「立即获取」「点击拿走」之类引导句)。
- 计数仍是真实值,禁编造(`takeawayCount` 不动)。

## 约束
- **别动** `lib/core/theme/*`、`lib/core/network/*`、路由、其它屏。
- 只改 `project_card.dart`(+ Part B 动 `action_item.dart` / `mock_seed.dart`)。
- 不整包重生成,在 main 最新基础上增量改。
- `flutter analyze` 0 error。改完开 PR。

## 交付
列出改了哪些文件,确认 analyze 无 error,开 PR 给链接,并说明有没有做 Part B。
