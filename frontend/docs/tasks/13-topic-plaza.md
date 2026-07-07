# 任务⑬：话题广场 + 今日话题入口

**先读** `docs/KANKAN_SPEC.md`。现状：只有单个话题页 `topic_screen`（`/topic/:tag`），没有原型的「话题广场」（热门话题榜）和「今日话题」入口。本任务补上发现效率这条线。

## A. 话题聚合方法（复用现有基础设施）
- `search_repository` 已能把 tags 聚合成 `Topic`（`searchTopics` + `Topic` 模型有 `heat/projectCount/postCount/totalLikes`，heat 是真实加权，禁编造）。
- 加一个 `List<Topic> topTopics({int limit = 30})`：聚合**所有** project/post 的 tags → 造 `Topic` → **按 heat 降序**排。别新造 heat 公式，复用现有聚合逻辑。

## B. 话题广场屏（新建）
- 新建 `lib/features/topic/topic_plaza_screen.dart`（`TopicPlazaScreen`）：
  - 顶栏「话题广场」（`KkBackButton` + 标题）。
  - 列表：每行一个话题 = `#tag`（`t1` 加粗）+ 右侧热度/计数（`{projectCount} 项目 · {postCount} 动态`，`t3` mono）+ 名次（可选 1/2/3…）。整行 `Tappable` → `context.push(KkRoutes.topic(tag))`。
  - 空态：`EmptyState` 或浅字。
- 路由：加 `KkRoutes.topicPlaza = '/topics'` + 注册到 `app_router`。

## C. 发现页「今日话题」入口
- 在 `discover_screen` 的**推荐流顶部**（feed 第一项之上，或 tab 下方）加一条「今日话题」横条：
  - 左「**今日话题**」小标题（`t1` 加粗）+ 右「**话题广场 →**」链接（`teal`，→ `KkRoutes.topicPlaza`）。
  - 下方一排横向话题 chip（`topTopics(limit:8)` 的前几个，`#tag` 样式沿用现有话题 chip 克制风），点 chip → `topic(tag)`。
  - 话题为空 → 整条不渲染（零旁白）。
- 只在**推荐**流顶部加，关注流不加。别动现有 feed 逻辑，作为 feed 之上的独立 section（参考任务⑦推荐条的做法）。

## 铁律 + 约束（照 SPEC §6）
- **coral 只给 take**——话题/热度/入口一律 teal 或中性色，不用 coral。无 emoji（用 Icon/`#`）。**零旁白**（不写"快来逛话题"，标题就是"今日话题"）。触控 ≥44pt。
- 计数用真实聚合值（禁编造 heat 公式，复用 search_repository）。
- **别动** `lib/core/theme/*`、`network/*`、后端接入文件、其它无关屏、topic_screen 本身。
- 改：`search_repository`（加 topTopics）；新增 `topic_plaza_screen.dart`；`routes.dart`/`app_router.dart`（加路由）；`discover_screen`（加今日话题横条）。
- 在 main 最新基础上增量改，`flutter analyze` 0 error，开 PR。

## 交付
列出改了哪些文件，确认 analyze 无 error，开 PR 给链接。
