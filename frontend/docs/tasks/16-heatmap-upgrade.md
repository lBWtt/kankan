# 任务⑯：贡献热力图升级（3 统计盒 + 26 周 + 月/星期标签 + 最长连续）

**先读** `docs/KANKAN_SPEC.md`。目标：把贡献热力图（`lib/features/me/widgets/contribution_heatmap.dart`）升级到 web 原型那种信息量——3 个统计盒 + 26 周 + 月份/星期标签 + 图例。

## A. mock 数据扩到 26 周
`mock_seed.dart` 的 `mockHeatmapCells` 现在生成 86 天（~12 周）。改成 **182 天（26 周）**：`for (var i = 181; i >= 0; i--)`（`_mockHeatLevel(i)` 已能处理任意 dayIndex，不用改）。

## B. 3 个统计盒（替换现有一行文字 stats）
`showStats` 现在渲染一行「总贡献 · N 天活跃 · 本月 N」。改成**三个圆角浅盒并排**（原型样式）：
- **总贡献** = `cells.fold(sum of level)`（或 level>0 的天数总和，与现有口径一致，真实）。
- **活跃天** = `cells.where(level>0).length`。
- **最长连续** = 最长的「连续 level>0 天数」（新算：遍历按日期排序的 cells，累计连续 >0，遇 0 重置，记最大值）。
- 每盒：大数字（`KkType.h2` 或 `monoLg`，teal 或 t1）+ 下方小标签（`t3`，11px），浅底 `bgSubtle` + 圆角 `KkRadius.md` + `KkSpacing.md` 内边距，三盒等宽 `Expanded`。

## C. 月份 + 星期标签
- **顶部月份标签**：沿列方向，在每月第一列上方标「N月」（`t3` mono 小字）。
- **左侧星期标签**：7 行里在「一 / 三 / 五」对应行左侧标（`t3` 小字），其余行留空（原型只标奇数行，省空间）。
- 网格保持横向可滚动（26 周宽，小屏溢出用 `SingleChildScrollView`，已有）。

## D. 图例保留
底部「少 ▢▢▣▣ 多」图例（现有 `_legend()`），保留。

## E. 调用方对齐
- **me 页贡献卡**（`me_screen._contributionCard`）：头部改「**近 26 周 · 共 N 次贡献**」（N=总贡献），卡内用升级后的 heatmap（`showStats:true` 显 3 盒，或 me 卡自己放 3 盒 + `bare` heatmap，你定，视觉贴原型 #13）。
- **activity 页**（也用 ContributionHeatmap）：确认升级后不崩（`showStats` 默认 true → 显 3 盒；若 activity 另有统计区避免重复，可传 `showStats:false`）。

## 铁律 + 约束（照 SPEC §6）
- 计数全真实（总贡献/活跃天/最长连续都从 cells 真算，**禁编造 ×N**）。coral 只给 take（本任务用 teal/mint/绿阶，不用 coral）。无 emoji。零旁白。
- **别动** `theme/*`、`network/*`、后端接入文件、路由、其它无关屏、`HeatmapCell` 模型字段。
- 改 `contribution_heatmap.dart` + `mock_seed.dart`（heatmap 生成）+ `me_screen._contributionCard`（头部/统计）。activity 页按需微调。
- 向后兼容：`bare`/`showStats`/`showLegend` 参数语义别破坏（activity 页依赖）。
- 在 main 最新基础上增量改，`flutter analyze` 0 error，开 PR。

## 交付
列出改了哪些文件，确认 analyze 无 error，开 PR 给链接。
