# Claude 改动记录（给接手的人 / Codex 看）

> 目的：把这一轮 Claude 的改动集中记清楚，避免「各改各的、改了又忘、老 bug 复现」。
> 配套：DeepSeek 的改动见 `ZCODE_CHANGES.md`；采集/上线运营见 `CONTENT_SOURCING_PLAN.md`、`backend/scrape/README.md`。
> 约定：改交互/状态/接口前，先看本文件「关键不变量」，别破坏已修好的东西。

---

## 一、后端能力（已测）

### 内容采集三条线
- `backend/scrape/github_collector.py`：GitHub 采集器（7:3 新火/挖宝，star 增速排序）。
- `backend/scrape/jike_collector.py`：即刻采集器（Playwright 拦 feed API），跑在 mediacrawler conda 环境。
- 动态管线：candidate 加 `content_kind`（project/post，迁移 0016）；`collect --kind post`；
  `ai_processor` 动态改写 prompt；`candidates.approve_candidate_as_post`（马甲发 Post）。

### 站内互动通知
- `backend/app/services/notify.py`：统一出口 `push_interaction`（**不通知自己**、尊重推送开关、挂调用方事务）。
- 埋点四处：`social.follow`、`interactions.add_reaction`、`posts.set_post_like`、`comments.create_comment`。
- 接口：`GET /notifications/unread-count`、`POST /notifications/read-all`。
- **深链（#4，已做）**：`notifications` 加 `actor_user_id` + `post_id`（迁移 0018）；notify.py 落这两个字段；
  API/schema 暴露；前端 `notifications_api._fromJson` 映射 actor/target/hostType，`_handleTap` 跳转：
  项目互动→作品详情、动态互动→动态详情、关注→触发者主页。

### 意见反馈
- `feedbacks` 表（迁移 0017，**id 有 gen_random_uuid 默认**）；`POST /feedback`（游客可提）；
  后台 `GET /admin/feedback` + `POST /admin/feedback/{id}/handle`。

### 使用情况分析
- 前端 `app.dart` 冷启动/resume 埋 `app_open`；后台 `GET /admin/usage`（真实用户/DAU/活跃清单，排除马甲）。
- 速览：`backend/usage_report.py`（`PYTHONIOENCODING=utf-8 python usage_report.py --days 7`）。

---

## 二、前端（本轮 UI 修复）

| # | 问题 | 改动文件 | 做法 |
|---|---|---|---|
| 登录 | 一键切测试号 | `features/auth/login_screen.dart` | 本地 API 下加 chip（管理员/用户一~六），免输手机号 |
| 反馈 | 真提交 | `features/settings/settings_screen.dart` + `features/feedback/feedback_sheet.dart` + `data/api/feedback_api.dart` | 原来只复制模板→改真提交底部表单 |
| 长动态 | 折叠 | `features/shared/post_card.dart` `_ExpandableText` | >6 行折叠 + 展开/收起 |
| 贡献 | 不算动态 | `backend/app/api/v1/me.py` | 热力图 counts 去掉 `*posts`（动态仍进时间线/发布数）|
| 头像 | 白弧/偏下/看大图 | `features/shared/profile_header.dart` | 白弧改**整圈 border+投影**；撤销上移 10px；点头像开灯箱看大图 |
| me 头部 | 编辑资料错位 | `features/me/me_screen.dart` | 编辑资料从名字旁挪到头部下方整齐按钮（`_editProfileButton`）|
| me 动态 | 太丑/太多 | `features/me/me_screen.dart` `_recentPostRow` | 堆叠大卡→紧凑一行，只显 3 条 + 查看全部 |
| 评论框 | 置底 | `features/post_detail/post_detail_screen.dart` `_PostCommentBar` | 远端模式：评论输入固定屏幕底部；mock 不变 |
| 回复 | 点回复没反应 | `providers/paginated_comments_provider.dart` + `features/shared/comment_thread.dart` | 输入外置时用 `commentReplyTargetProvider` 把回复目标交给底部栏 |
| 火箭 | 账号没分开 | `providers/clue_provider.dart` | `ClueInteractionNotifier` 加 authListener，切号清 `markedProjectIds` |

---

### 通知/评论显示修复（后端有数据但前端不显示的坑）
- `remoteNotificationsProvider` 原是普通 `FutureProvider` → **缓存到死**，换账号/新互动后通知不刷新。
  改成 **`FutureProvider.autoDispose`** + 通知屏加**下拉刷新**（`RefreshIndicator` + `AlwaysScrollableScrollPhysics`）。
- 动态详情评论数：动作行原读 mock repo（远端恒 0，显示「0」但下面有评论）→ 远端改用 `post.commentCount` 真值。
  评论列表本身走 `paginatedCommentsProvider`（autoDispose.family，watch 即自动拉首页），正常加载。

### 内容口吻：对照即刻真人（别用自己编的）
- `scrape/jike_collector.py` 抓即刻 explore（Playwright 拦 `api.ruguoapp.com/1.0/recommendFeed/list`）→ 真帖。
  **登录坑**：goto 必须 `wait_until="domcontentloaded"`（networkidle 在 SPA 永不触发会超时）；headful 首次扫码登录，登录态存 `.jike_userdata`。
- 真帖存 `scrape/jike_voice_samples.json`（口吻样本库）。`ai_processor._pick_voice()` **优先返回真样本**当风格参照（学腔调不抄内容），没有才退回内置档位 `CONTENT_VOICES`。
- 每条内容随机换一个真样本 → 文风各异。**description 字段已重构语义**：从「客观详细介绍」改成「用真人口吻写的展开心得」，硬禁『X 是一个…』开头（否则详情永远是说明书腔）。

## 三、关键不变量（别踩）

- **账号隔离**：`AppStateNotifier` 和 `ClueInteractionNotifier` 都靠 `ref.listen(authProvider)` 在切号时重载/清个人态。
  任何「本人已点过」类的本地集合（liked/marked/saved/followed）都必须按账号隔离，别做成全局单例。
- **点赞双轨**：`togglePostLike/toggleLike` = 乐观本地 toggle + 后端同步（UUID 才发）+ 失败回滚。计数 = 后端基数 + 本地 isLiked。
- **评论输入两态**：post_detail **远端**用底部固定栏（`_PostCommentBar`，走 `commentReplyTargetProvider` 支持回复）；
  **mock** 仍用 `CommentThread` 内联输入。改一处要想另一处，别只改远端把 mock 弄坏。
- **马甲号**：`@persona.kankan` 结尾；审核 approve 外部内容时随机派马甲当作者；usage/真实用户口径都要排除马甲。
- **通知**：站内通知（红点+列表），不是系统推送；type=interaction；project_id 是唯一 deep-link 字段。

---

## 四、已知未完成（下一步）

- 系统级推送（FCM/APNs）未做——目前只有站内通知（红点+列表），无锁屏/通知栏横幅。
- 审核仍是手机 ADMIN 构建；web 后台/自动过审阈值未做。
- 即刻采集器 `jike_collector.py` 的真实 API 字段名待用真数据校准（首次 headful 跑，抓 0 条就调 `_walk_posts`/`_to_item`）。
