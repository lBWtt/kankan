# 任务⑥：榜单页 排名依据副标题 + "X分钟前更新"

**先读** `docs/KANKAN_SPEC.md`。目标：给榜单页现有三 Tab（**项目/动态/作者**）补上原型的两个可信度细节——①每个榜的「排名依据」副标题；②「X 分钟前更新」时间戳。让榜单显得"有口径、在更新"，不是死数据。

> ⚠️ **不要改榜单结构**。现有三 Tab 是 项目/动态/作者（HANDOFF 定的），rankChange 名次徽标已有（teal↑/coral↓，见 `_RankChangeChip`）。本任务**只加副标题 + 时间戳**，不动排序逻辑、不改 Tab 语义。

## Part A（必做）：每 Tab 的「排名依据」副标题 + 更新时间戳
在 `ranking_screen.dart` 的 TabBar **下方、列表上方**，加一条随当前 Tab 变化的说明条：
- 左侧「排名依据」副标题（`KkType.bodySm`，`KkColors.t3`）。**如实描述现有排序口径**（现在项目/动态都是按 `likes` 降序，别写「按收藏」这种代码没做的口径）：
  - 项目 → `大家最认可的 · 按点赞热度`
  - 动态 → `聊得最热的 · 按点赞热度`
  - 作者 → `最受认可的创作者 · 按累计获赞`
- 右侧「更新时间」（`KkType.mono`，`t3`，`fontSize 11`）：`{X} 分钟前更新`。
  - 实现：模块级捕获一个 `DateTime`（首次进屏 = `DateTime.now()`），用现有 `timeAgo` 工具（在 `core/utils/time_ago.dart`，接收毫秒）显示，如 `刚刚更新` / `3 分钟前更新`。
  - 把现有**顶部 refresh 按钮**（现在是 no-op）接通：点一下 → `setState` 把时间戳刷成 `now()` → 文案回到「刚刚更新」（零旁白，不加 toast）。这样刷新按钮有真实反馈。
- 说明条横向 `KkSpacing.lg` 内边距，和 TabBar / 列表对齐；副标题左、时间戳右（`Row` + `Spacer`）。

## Part B（可选，可降级）：「新锐」徽标
- 现有 `_RankChangeChip(change: int)` 只显 +N/-N/0。给"新上榜"的项加一个「新锐」态：
  - 约定一个哨兵值（如 `mockProjectRankChange` 返回一个特殊大值，或加一个 `isNew` 判断），`_RankChangeChip` 收到时显示「新锐」pill（`mint` 底 + `teal` 文字，**不用 coral**）。
  - 在 mock 里把 1-2 个项目/动态标成新上榜。
- 若改 mock rankChange 数据源太绕，Part B 可整段跳过，只交 Part A。

## 铁律 + 约束（照 SPEC §6）
- **coral 只给 take**——本屏 coral 仅保留给 rankChange 的**下降箭头**（既有警示用法），副标题/时间戳/新锐 chip 一律不用 coral。
- 无 emoji（用 Icon）。零旁白。不改排序逻辑、不改 Tab 数量/语义。
- **别动** `lib/core/theme/*`、`network/*`、路由、其它屏。
- 只改 `lib/features/ranking/ranking_screen.dart`（+ Part B 若做,动 `mock_seed.dart` 的 rankChange 数据）。
- 在 main 最新基础上增量改,`flutter analyze` 0 error,开 PR。

## 交付
列出改了哪些文件,确认 analyze 无 error,说明有没有做 Part B,开 PR 给链接。
