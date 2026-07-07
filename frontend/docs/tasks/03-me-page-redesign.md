# 任务③：我的页(me_screen)整屏重构

**先读** `docs/KANKAN_SPEC.md`。目标：把 `lib/features/me/me_screen.dart` 重构成"个人主页"式布局（渐变 banner + 大头像 + inline 统计 + 贡献卡 + 关注领域/话题 + 最近看过）。
> ⚠️ 你看不到设计图，下面是逐块的精确规格，照着做。**签到卡这次不做（跳过）。相机/封面图上传也不做（未实现的功能不摆假按钮）。**

## 整体
`me_screen` 用可滚动 `ListView`（或 CustomScrollView），从上到下如下 8 块。底部留白 `KkSpacing.xxxl` 清底部 tab 栏。

## 1. 顶部渐变 banner
- 一个约 **160px 高**的容器铺在最顶（贴状态栏下）。
- 背景：**暖色柔和线性渐变**（浅珊瑚/浅橙 → 暖纸底），例：`LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomCenter, colors: [Color(0xFFF3E1CE), KkColors.bg])`。别太艳，和暖纸底自然过渡。
- 右上角一排小图标（叠在 banner 上，半透明底圆按钮）：
  - **通知铃** `Icons.notifications_outlined` → `KkRoutes.notifications`，带未读红点（`appState.unreadNotifIds.length`，>0 显红点）。
  - **设置齿轮** `Icons.settings_outlined` → `KkRoutes.settings`。
  - （不放相机/封面按钮。）

## 2. 头像 + 名字（压在 banner 下沿）
- **大头像**（约 72×72 圆形，复用 `KkAvatar`），用 Stack/负 margin **压在 banner 底边**（一半在 banner 上、一半在下）。
- 头像右侧或下方：**名字**（`KkType.h2`，serif）+ 一个 **「编辑资料」** 小链接（`KkColors.teal`，`KkType.bodySm`）→ `KkRoutes.profileEdit`。

## 3. inline 四联统计（不要方框！）
- 一行四列平铺：**关注 / 粉丝 / 获赞 / 收藏**，每列 = 大数字（`KkType.monoLg` 或 h2）+ 下方小标签（`KkColors.t3`，11px）。
- 真实值：关注=`followingCount`、粉丝=`followerCount`、获赞=`totalLikes`（已算）、收藏=`appState.savedProjectIds.length`。
- 可点：关注/粉丝 → `KkRoutes.follows(...)`；收藏 → `context.go(KkRoutes.library)`。
- **纯 inline 文字，无边框无卡片**（这是取代之前"违和三方框"的关键）。

## 4.（跳过 签到卡）

## 5. 我的贡献 卡片
- 一张**白卡**（`bgCard` + `KkElevation.card` + `KkRadius.lg` 圆角 + `KkSpacing.lg` 内边距，横向 margin `lg`）。
- 卡内头部一行：左「**我的贡献**」（`KkType.h3`）＋右「**最近 13 周 · 共 N 次活跃**」（`KkType.mono`，`t3`；N=`mockHeatmapCells` 里 count>0 的格子数或活跃总和）。
- 卡内主体：`ContributionHeatmap(cells: mockHeatmapCells)` + 底部「少 ▢▢▣▣ 多」图例。
- 整卡可点 → `KkRoutes.activity`。
- **需要重新 import** `widgets/contribution_heatmap.dart` 和 `mock_seed.dart` 的 `mockHeatmapCells`（之前精简时删了，这次加回）。

## 6. 我关注的领域
- 段标题「**我关注的领域**」（`KkType.body` 加粗或 h3）。
- 下面一排 chip：用户的关注领域（去现有数据找：`profile_edit` 屏的关注领域 / `me` user 数据；找不到就用 `mock_seed` 里加 2-3 个如「Vibe Coding」「知识管理」）+ 末尾一个「**+ 调整**」chip → `KkRoutes.profileEdit`。
- chip 样式沿用任务②的克制风（`bgSubtle` 底 + `bd` 细边 + `t1` 文字）。

## 7. 我关注的话题
- 段标题「**我关注的话题**」。
- 有数据 → 一排 `#话题` chip；没有 → 一行浅字「`#` 还没有关注的话题」（`t3`，零旁白空态即可，别加引导句）。

## 8. 最近看过 + 清空
- 段标题行：左「**最近看过**」＋右「**清空**」小链接（`t3`）→ 调 `appState` 清 `browseHistory`（找现有清理方法；没有就跳过清空按钮的功能，先留视觉）。
- 主体：`appState.browseHistory` 对应的项目，横向缩略图/小卡列表（复用 `ProjectCard(compact:true)` 或小封面）。空 → `EmptyState` 或浅字空态。

## 美感统一（我的要求）
- **贡献卡** 和其它卡片一样用 `bgCard + KkElevation.card + lg 圆角`，别用描边风，全屏卡片风格一致。
- banner 别太高、渐变别太艳；头像/名字对比要清楚。

## 铁律 + 约束（照 SPEC）
- coral 只给 take / 无 emoji / 触控 ≥44pt / **零旁白** / 禁不可变 `..sort` / 禁 artifactType 分支。
- **别动** `lib/core/theme/*`、`lib/core/network/*`、路由定义、其它屏。
- 主要改 `me_screen.dart`；如需少量 mock（领域/话题）可加到 `mock_seed.dart`，**别动其它数据/逻辑**。
- 保留「设置 / 通知」入口（放 banner 右上，见第 1 块），别把它们弄丢。
- `flutter analyze` 0 error。开 PR。

## 交付
列出改了哪些文件，确认 analyze 无 error，开 PR 给链接。
