# 任务⑪：发动态 compose 屏（新建）+ 发项目页精修

**先读** `docs/KANKAN_SPEC.md`。两件事：(A) 建「发动态」compose 屏——现在点「发动态」**什么也没有**（`onPublishPost` 根本没注入、也没 compose 屏）；(B) 精修「发作品(项目)」`publish_screen`。质量标杆参考 **发现页 `PostCard`**（动态最终长这样）。

## A. 发动态 compose 屏（当前是死的，必须建）
现状：`publish_entry_sheet` 的「发动态」`onTap` 调 `onPublishPost?.call()`，但 `app_router._showPublishEntrySheet` **只注入了 `onPublishProject`**，没注入 `onPublishPost` → 点了 sheet 关闭、无事发生。且 `lib/features/publish/` 下**没有 compose 屏**。

**做**：
1. 新建 `lib/features/publish/compose_screen.dart`（`ComposeScreen`），发动态用（轻内容，对应 `Post`）：
   - 多行文字输入（`hintText: '分享你的灵感、发现、或一个问题'`，零旁白）。
   - 可选**加图**（复用发项目页的 `media_picker` 那套占位/选择方式，别引新依赖；真上传 Phase 5）。
   - 可选**选话题**（`#话题`，从现有 tag 里选/输入）。
   - 可选**引用项目**（选一个 project 内嵌卡片引用，对应 `Post` 的引用项目字段——照 `Post` 模型现有字段来，别改模型）。
   - 顶栏「发送」按钮：校验非空 → 造一个 `Post` 加进 `postRepository`（加一个 `addPost` 方法，对称现有 `addComment`/`removeComment`）→ 关屏 → 新动态出现在发现页推荐流顶部。
   - 空内容禁止发送（按钮置灰或 toast「写点什么再发」，照现有发项目页的校验风）。
2. 路由：加 `KkRoutes.compose = '/compose'` + 在 `app_router` 注册；`_showPublishEntrySheet` 注入 `onPublishPost: () { Navigator.pop(context); context.push(KkRoutes.compose); }`。
3. 参考 `publish_screen.dart` 的输入/媒体/顶栏结构，别从零发明风格。

## B. 发作品(项目)页精修
`publish_screen.dart`（发项目）保留全部现有逻辑（准入校验、成果/素材、`publishDraftProvider`），只做**视觉精修**：
- 分区更清晰（一句话价值 / 成果 / 可拿走的东西 / 领域 / 标签 / 封面 各段有呼吸感、段标题克制）。
- 输入框、媒体占位、按钮达到发现页卡片那种精致度。
- 别改发布逻辑与字段。

## 铁律 + 约束（照 SPEC §6）
- coral 只给 take。无 emoji（用 Icon）。零旁白（不写引导句，输入框 hint 只写事实）。触控 ≥44pt。
- 禁 `if(artifactType)` 硬编码；`Post` 引用项目按现有模型字段，别改模型。
- **别动** `lib/core/theme/*`、`network/*`、后端接入文件、其它无关屏。
- 主要新增 `compose_screen.dart` + 改 `app_router.dart`/`routes.dart`/`publish_entry_sheet` 注入 + `post_repository.dart` 加 `addPost` + 精修 `publish_screen.dart`。
- 在 main 最新基础上增量改，`flutter analyze` 0 error，开 PR。

## 交付
列出改了哪些文件，确认 analyze 无 error，开 PR 给链接。
