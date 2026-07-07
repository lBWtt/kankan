# 任务⑦：看看页「因为你看过 X」推荐条 + 换一批

**先读** `docs/KANKAN_SPEC.md`。目标：在「看看」页 **精选 Tab 顶部**加一条个性化推荐横条——`因为你看过 {X}` 标题 + 一排相关项目小卡 + 「换一批」洗牌。原型的留存钩子：给用户一个"接着逛"的理由。

> ⚠️ **不违反"精选无 shuffle"铁律**：精选列表本身顺序不动，推荐条是**列表之上的独立 section**，洗牌只作用于推荐条内部，不动精选列表。

## 落点
- 只改 `lib/features/kankan/kankan_screen.dart`。
- 推荐条**只在精选（`sort=='featured'`）Tab 出现**，热门/最新不加。
- **`appState.browseHistory` 为空 → 整条不渲染**（零旁白，不占位）。

## 数据 & 推荐逻辑（纯函数，禁编造）
- `X` = 最近看过的项目：`browseHistory.first`（`recordBrowse` 把最新插到 index 0），用 `projectRepository.byId(X)` 取回；取不到就往后找下一个有效 id；都无 → 隐藏。
- 候选 = 与 X **同领域 或 有交集 tag** 的项目，`whereType` 思路，**排除 X 自己**：
  `p.domain == x.domain || p.tags.any((t) => x.tags.contains(t))`，`p.id != x.id`。
- 不足 ~6 个时，用其余项目补齐（仍排除 X）。最多取 ~8 个。
- **换一批**：本地维护一个 `int _seed`（`_RecommendStrip` 用 `ConsumerStatefulWidget`），点「换一批」`setState(() => _seed++)`；用 `_seed` 对候选做**确定性重排**（如按 `(p.id.hashCode ^ _seed)` 排序，或旋转起点），换出不同顺序/子集。别用随机不可复现。

## 视觉
- 一个 section（横向 `KkSpacing.lg` 对齐列表）：
  - **头部行**：左 `因为你看过 ` (`t3`) + `{X.title}`（`t1` 或 teal，加粗，`ellipsis`）；右「**换一批**」文字按钮（`KkColors.teal` + `Icons.refresh` 14px，`Tappable`，热区 ≥44pt）。
  - **主体**：横向滚动小卡列表（约 130 宽，封面 + 标题 + `X 赞`；参考「我的」页最近看过的小卡样式），点击 → `context.push(KkRoutes.detail(p.id))`，同时 `recordBrowse`。
  - section 底部与精选列表之间留 `KkSpacing.lg`；可加一条极浅 `divider` 分隔。
- 小卡封面复用 `CoverArt` + `Image.network`（断链回退 CoverArt），别引新依赖。

## 铁律 + 约束（照 SPEC §6）
- **coral 只给 take**——「换一批」用 teal，推荐条一律不用 coral。
- 无 emoji（用 Icon）。**零旁白**（不写"猜你喜欢""快看看"引导句，标题就是"因为你看过 X"）。
- 禁 `if(artifactType)` 硬编码。触控 ≥44pt。
- **别动** `lib/core/theme/*`、`network/*`、路由、其它屏、`_ProjectList` 的排序逻辑。
- 只改 `kankan_screen.dart`（新增 `_RecommendStrip` 等私有 widget 同文件内）。若要在 repo 加一个 `similar(x)` helper 可选（加在 `project_repository.dart`，纯查询不改现有方法）。
- 在 main 最新基础上增量改，`flutter analyze` 0 error，开 PR。

## 交付
列出改了哪些文件，确认 analyze 无 error，开 PR 给链接。
