# zai 通捋任务 —— 上线前全代码库梳理

> 收件人：zai（云端 AI，看不到运行结果、盲写代码）
> 目标：本仓 `backend/` + `frontend/` 已前后端全通、功能基本齐、后端过了三轮安全审查。
> 这一轮是**上线前通捋**：找剩余 bug、补边角、对齐契约、清死代码——**不加新功能**。
> 交付后由 Claude 逐 PR 复核 + 二次通扫。

---

## 0. 硬性护栏（违反=白干，Claude 复核必打回）

这些是你之前反复踩的坑，这轮**每一条都要主动自查**：

1. **别幻觉「枚举/白名单词表」。** 任何 `CHECK` 约束、`Literal[...]`、`Enum` 的取值集，
   **必须对照代码里实际写入/读取的值**逐一核验。反例（真实发生过）：
   - 把审计 `action` 约束成固定枚举，但代码是 f-string 生成 `{action}_project` / `edit_candidate` → 迁移崩 + 写入 500。
   - 把 `anthropic_model` 默认值「修」成一个更旧的 ID（你训练数据过时，`claude-opus-4-8` 是真在售模型）。
   → 不确定某个值集是否完整，就**别加约束**，或保持 `str`。
2. **别用本仓依赖版本里不存在的 API。** 前端是 **Riverpod 3.3.2**：
   - **没有** `ref.listenSelf`（3.x 移除）→ 自持久化用覆盖 `set state`。
   - **没有** `AsyncValue.valueOrNull` → 用 `.value`。
   改前端 provider 前先在 `frontend/pubspec.lock` 确认版本，别照搬 2.x 写法。
3. **别破坏前后端契约。** 后端响应字段名/形状、分页参数（`page_size` + `cursor`，**不是** `limit`）、
   枚举值，前端都直接依赖。改任何 API 返回形状前，先搜前端 `frontend/lib/data/` 有没有在读它。
4. **必须自测再提。**
   - 后端：`python -m compileall app/` + `import app.main` 通过；能连库就跑 `tests/smoke_v0.py`~`smoke_v13.py`（需 PG+Redis）。
   - 前端：`flutter analyze`（0 error）+ `flutter test`（当前 299 项应保持全绿）。
   - 提交说明里写清你跑了什么、结果如何。
5. **拆小 PR，别一个巨型 PR。** 按下面的板块分（后端一批、前端一批、契约一批），每个 PR 聚焦一件事，方便复核。

---

## 1. 后端通捋（backend/）

- **红线复核**（改动别碰穿）：`candidate_status` 用 ai_collected/…/approved/parked/discarded；下架=`taken_down`、删除=`deleted` 两独立状态；`how_to_interests.user_id` 必须可空（游客主信号，不设登录墙）；hot_score 含 how_to_interest ×5 权重 + `0.5^(age/72h)` 衰减；发布准入 tools≥1 或简介含可复现说明。
- **错误处理**：每个端点的异常路径是否都回统一错误结构（`app/core/errors.py`）？有没有裸 `except` 吞异常、或未捕获 `IntegrityError` 导致 500？
- **N+1 / 性能**：列表类端点是否都走了批量组装（`cards_from_projects_with_stats` 那种），没有循环里查库？
- **契约一致性**：`app/schemas/` 的响应模型字段，和 `app/api/v1/` 实际返回、和前端读取，三者一致？
- **迁移**：`alembic/versions/` 到 0009，`alembic upgrade head` / `downgrade` 能跑通；模型 `__table_args__` 与迁移 DDL 一致（别再出现「模型加了约束但迁移没有」或反之的漂移）。
- **prod 配置**：`app/core/config.validate_production_settings` 覆盖是否够（默认 JWT、console 短信、s3 配不全都该拒启动）；`.env.example` 的【生产必改】项是否齐。
- **死代码 / TODO**：清掉不再调用的函数、注释掉的旧逻辑；`# TODO` 该做的做、做不了的标清楚。

## 2. 前端通捋（frontend/）

- **双轨一致性**：收藏/关注/点赞/clue 订阅都是「乐观本地 toggle + 登录且 UUID 才同步后端、失败回滚」。逐个确认没有漏 UUID 判定（`looksLikeBackendId`）、没有对 mock 短 id 发后端请求、失败都回滚。
- **三态覆盖**：所有远程读（feed/详情/列表/收藏/关注/评论/动态）都有 loading（骨架/spinner）、error（`RemoteError` 可重试）、empty（`EmptyState`，零旁白）。找有没有哪个屏 error 时白屏或崩。
- **USE_REMOTE 门控**：所有 `if (AppConfig.useRemote)` 分支，mock 侧行为不变（默认不带 flag 就是纯 mock 演示）。
- **契约对齐**：`frontend/lib/data/dto/` 与 `data/api/` 里读的字段名/形状，和后端 `schemas/` 对得上；分页统一 `page_size` + `cursor`。
- **设计红线**（复核别碰穿）：珊瑚橙 coral 只给 take（榜单下降箭头例外）；无 emoji（用 Icon）；零旁白；不出现「拿走」二字；禁 `if(artifactType)` 用 `whereType`；真实计数禁 ×N 编造。
- **死代码 / warning**：`flutter analyze` 的 unused import/param、redundant `!`、类型推断 warning 清干净。

## 3. 前后端契约对齐（本轮重点）

逐个端点对一遍「后端返回 ↔ 前端读取」：
- 卡片 `ProjectCard`（author + counts）、`PostOut`、`CommentOut`、`UserPublic`、`MeResponse`（含 following/follower/favorite/received_like 四计数）、分页信封 `{items,next_cursor,has_more}`。
- 列出所有**前端已依赖、但后端若改形状会炸**的字段，写进 PR 说明，作为「契约冻结清单」。
- 发现不一致：**优先改成前端已依赖的形状**（别让前端跟着改），除非后端形状明显更对——那种情况在 PR 里说明理由。

---

## 4. 交付方式

- 分 PR：`sweep/backend-*`、`sweep/frontend-*`、`sweep/contract-*`，每个聚焦一件事。
- 每个 PR 说明写：**改了什么、为什么、跑了哪些自测、结果**。
- 拿不准的（尤其涉及枚举/约束/契约形状/Riverpod API）——**宁可在 PR 里标注「待 Claude 确认」也别硬改**。

## 5. 一句话总结

**不加功能，只找 bug + 补边角 + 对齐契约 + 清死代码；改任何枚举/约束/契约/provider 前，先对照代码实际值核验；提交前必跑 analyze + test + compile。**
