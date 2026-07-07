# 任务⑩：他人主页对齐「我的」页 + 我的页 chip 精修

**先读** `docs/KANKAN_SPEC.md`。两件事：(A) 他人主页 `profile_screen` 的头部升级成和「我的」页（任务③重构后）一致的视觉语言；(B) 精修「我的」页 领域/话题 chip 区（用户反馈"太丑"）。质量标杆参考 **发现页 `PostCard` 的卡片质感**（清晰层次、克制）。

## A. profile_screen 头部对齐 me_screen
现状：`profile_screen` 头部是老式 `_profileCard`（64 头像 + 名字/简介 + 关注/粉丝/获赞 + 关注/编辑按钮）+ TabBar（作品/动态）。而「我的」页（`me_screen`）已是：暖色渐变 banner + 72 大头像压 banner 下沿 + 名字 + inline 统计。两者不一致，用户点他人主页有割裂感。

**做**：把 me_screen 头部的视觉语言搬到 profile_screen（**复用同样的 token/结构**，别新造）：
- 顶部**暖色渐变 banner**（同 me：`LinearGradient([Color(0xFFF3E1CE), KkColors.bg])`，约 140–160 高）。
- **大头像**（72，白边圈）压 banner 下沿。
- 名字（`KkType.h2`）+ 简介（有则显，`t3`）。
- **inline 统计**（关注/粉丝/获赞，纯文字无框，同 me 的 `_statBlock` 风格），可点跳 follows。
- 右侧/下方放**关注按钮**（他人）或**编辑资料**（自己）——保留现有 `_followButton`/`_editButton` 逻辑，只调位置融入新头部。
- banner 右上可放返回（`KkBackButton`）/更多（拉黑举报 sheet，现有）。
- **保留** TabBar（作品/动态）和其余不变。
- **不搬** 贡献热力图/关注领域/最近看过（那些是"我的"页自己的，他人主页不加）。

## B. me_screen 领域/话题 chip 精修
现状 `_followedDomainsSection` / `_followedTopicsSection` 用 `Wrap` + 朴素 chip（bgSubtle + bd + pill），窄栏下换行显散、`+调整` 落单行显得突兀。
- 让两段 chip **视觉统一**（领域 chip 与话题 chip 同一套样式/高度/内边距）。
- `+调整` 做成末尾**幽灵 chip**（透明底 + 虚线或细边 + `+` 图标），跟在领域 chip 行末尾自然收尾，别单独占一行显得掉队。
- chip 内边距略收紧，行/列间距 `KkSpacing.sm`，`Wrap` 左对齐。
- 目标：这两段看起来像"精心排过"，达到发现页卡片那种克制精致，不是"随便堆的 tag"。
- 空态照旧（话题空 → 浅字）。

## 铁律 + 约束（照 SPEC §6）
- coral 只给 take（本任务不涉及 take，全程别用 coral）。无 emoji（用 Icon）。零旁白。触控 ≥44pt。
- **别动** `lib/core/theme/*`、`network/*`、路由、后端接入文件、其它屏。
- A 改 `profile_screen.dart`（可抽 me_screen 头部为共享 widget 放 `features/shared/`，或各自实现但视觉一致——优先抽共享，避免以后再分叉）；B 改 `me_screen.dart`（+ 若抽共享 chip 组件放 shared）。
- 在 main 最新基础上增量改，`flutter analyze` 0 error，开 PR。

## 交付
列出改了哪些文件，确认 analyze 无 error，开 PR 给链接。
