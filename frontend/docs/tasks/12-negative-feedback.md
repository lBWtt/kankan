# 任务⑫：负反馈闭环（举报原因流 + 不感兴趣生效）

**先读** `docs/KANKAN_SPEC.md`。现状：「举报」「不感兴趣」是**空壳死按钮**——`post_detail._showMoreSheet` 的举报/不感兴趣 onTap 只是 `Navigator.pop`，点了啥也不干；profile 拉黑/举报、comment 举报同理。本任务把它们变成真功能。

## A. 举报原因选择流（新建共享 sheet）
- 新建 `lib/features/shared/report_sheet.dart`：`showReportSheet(context, {required String targetType, required String targetId})`。
- 内容：标题「选择举报原因」+ 一列原因（照原型）：
  - `垃圾内容`（广告、刷屏、恶意推广）
  - `抄袭侵权`（盗用他人原创内容）
  - `不实信息`（虚假、误导性内容）
  - `以上都不是`（→ 展开一个补充说明输入框）
  - 点某原因（或填补充说明后确认）→ 关 sheet + toast「已举报，我们会尽快核实」。
  - **零旁白**：只列原因，不写"举报后会怎样"。原因项 `t1` 文字，**不用 coral**。
- 接线三处入口（都改成打开这个 sheet）：
  - `post_detail._showMoreSheet` 的「举报」→ `showReportSheet(context, targetType:'post', targetId: post.id)`。
  - `profile_screen` 更多 sheet 的「举报」→ `targetType:'user'`。
  - `comment_actions_sheet`：`_CommentThreadState._showActions` 给他人评论传 `onReport: () => showReportSheet(..., targetType:'comment', targetId: c.id)`（`onReport` 参数已存在，传了就自动出「举报」按钮）。

## B. 不感兴趣 / 减少类似推荐 真生效
- `app_state_provider` 加 `Set<String> notInterestedIds`（默认空）+ `void markNotInterested(String id)`（对称 toggleSave；写入后 `copyWith`）。
- feed 过滤：**发现页**（`discover_screen` 的推荐/关注流）和**看看页**（`kankan_screen` 的 `_mockList` 项目流）渲染前 `where((x) => !notInterestedIds.contains(x.id))` 过滤掉。
  - ⚠️ kankan 的 `_remoteList`（真数据）先不过滤（后端另说），只过滤 `_mockList`。别动 remote 分支逻辑。
- `post_detail._showMoreSheet` 的「不感兴趣」→ `markNotInterested(post.id)` + toast「已减少类似推荐」+ pop（该动态从流里消失）。
- （可选）项目卡也能加不感兴趣入口，但本任务先做动态；范围别膨胀。

## 铁律 + 约束（照 SPEC §6）
- **coral 只给 take**——举报/不感兴趣/原因项一律 `t1`/`t2`，不用 coral。无 emoji（用 Icon）。**零旁白**（sheet 只列动作/原因）。触控 ≥44pt。
- **别动** `lib/core/theme/*`、`network/*`、路由（除非加 sheet，不需路由）、后端接入文件、kankan 的 `_remoteList`。
- 改：新增 `report_sheet.dart`；`app_state_provider`（加 set+方法）；`discover_screen`/`kankan_screen._mockList`（过滤）；`post_detail_screen`/`profile_screen`（接举报+不感兴趣）；`comment_thread`（传 onReport）。
- 在 main 最新基础上增量改，`flutter analyze` 0 error，开 PR。

## 交付
列出改了哪些文件，确认 analyze 无 error，开 PR 给链接。
