# 第三轮代码审查修复说明

> 分支：`fix/round3-review` → `main`
> 基线：commit `2d3d72e`（PR #4 合并后）
> 审查范围：核心基础设施 / Models / Schemas / Services / API 全栈
> 问题总数：**8 Critical + 27 High = 35 项**，全部修复

## 概述

本轮在前两轮（PR #3 / PR #4）基础上做第三轮深度审查，由 4 个并行审查 agent 分别覆盖 core/models/schemas/services/api 四层，共发现 35 个真实问题（8 Critical + 27 High）。修复由另外 4 个并行修复 agent 各自负责一层完成，文件无冲突。

**修改规模**：38 文件，+606 / -141 行；新增 1 个 alembic 迁移（0009）、1 个 core 模块（ratelimit）、1 个 .dockerignore、4 份审查报告。

---

## Critical（8 项）

### API 层刷榜三连（最危险，脚本数分钟可操纵排行榜）

#### C-API-1. `record_action_event` 无频控无去重 → hot_score 可刷
- **位置**：`app/api/v1/project_actions.py:125-161`
- **问题**：游客可用端点，`event_type=success` 每条无条件 `takeaway_count+1`，且 `success` 事件权重 ×6 进 `hot_score`。无去重无频控，脚本循环 POST 1000 次即可把任意项目顶上周榜。
- **修复**（三层防护）：
  1. 按 (actor, action_id, event_type=success) 去重——同身份对同 action 的 success 只计一次
  2. 身份级频控：同一身份 60s 内最多 30 次 action 事件
  3. `takeaway_count` 的 +1 改为以"首次成功"语义，非 success 事件不增计数

#### C-API-2. `record_share` 无频控无去重 → hot_score 可刷
- **位置**：`app/api/v1/project_actions.py:197-222`
- **问题**：游客可用，`completed` 分享每条 +6 进 `hot_score`，无去重无频控。
- **修复**：
  1. `completed` 状态按 (actor, project_id) 日级去重——同身份同项目当日只计一次
  2. 身份级频控：60s 内最多 20 次

#### C-API-3. `ingest_events` 曝光/详情事件直接进 hot_score，anon_client_id 可轮换
- **位置**：`app/api/v1/events.py:58-92`
- **问题**：`card_impression`(×1) / `detail_view`(×2) 直接进 `hot_score`，`anon_client_id` 客户端自填可轮换绕过身份频控。
- **修复**：
  1. 对带 project_id 的 `card_impression`/`detail_view` 做 per-(project, identity) 日级 cap 200，超出静默丢弃
  2. 校验 project_id 存在且 `published`，丢弃指向无效项目的事件

### Services 层数据竞态

#### C-SVC-1. `approve_candidate` 无行级锁 → 并发产生孤儿项目
- **位置**：`app/services/candidates.py:92-150`
- **问题**：两个并发 approve 同一候选会产生两个 published 项目，`candidate.project_id` 只指向后提交的，先创建的变孤儿。
- **修复**：入口用 `SELECT ... FOR UPDATE` 加行级锁，并发 B 阻塞到 A 提交后再读 `status=approved` → 409。

#### C-SVC-2. 点赞计数器 read-modify-write 竞态 + IntegrityError 未捕获
- **位置**：`app/services/comments.py:97-112` / `app/services/posts.py:119-131`
- **问题**：`like_count = (like_count or 0) + 1` 是 read-modify-write，并发 like/unlike 会让计数器漂移（比实际多/少）。并发点赞撞唯一约束未捕获 → 500。
- **修复**：
  1. 改原子 `UPDATE ... SET like_count = like_count + 1`
  2. `IntegrityError` 捕获做幂等（已赞过则 rollback return）
  3. 取消赞用 `DELETE ... returning` 判断 rowcount，配合 `func.greatest(0, like_count - 1)` 防负数

### Models 层结构问题

#### C-MDL-1. 模型-迁移漂移：`ProjectMedia` 缺 `ix_project_media_uploader` 索引
- **位置**：`app/models/media.py` vs `alembic/versions/0004`
- **问题**：迁移 0004 建了该索引，模型没声明，下次 autogenerate 会生成删索引迁移。
- **修复**：`__table_args__` 补 `Index("ix_project_media_uploader", "uploader_user_id")`。

#### C-MDL-2. `User` 表允许既无 email 也无 phone 的"幽灵账号"
- **位置**：`app/models/user.py:23-24`
- **问题**：email/phone 都可空且无"至少一个"CHECK，可插入完全无联系方式的用户。
- **修复**：加 `CheckConstraint("email IS NOT NULL OR phone IS NOT NULL", name="contact_present")`。

#### C-MDL-3. 大量外键缺 ondelete 策略 → 孤儿数据/删除被阻塞
- **位置**：~15 张表 FK 默认 RESTRICT，与已设 CASCADE 的表割裂
- **问题**：
  - `Project.author_user_id` 语义可空，用户硬删时应 SET NULL，RESTRICT 会阻塞删除
  - `CandidateContent.project_id` approve 回写，project 删后应 SET NULL 可重新 approve
  - `Notification`/`PushPreference` 用户从属数据应 CASCADE
  - `Favorite`/`TryItem` 等关联表与 `UserFollow` 的 CASCADE 策略自相矛盾
- **修复**（按语义分组，迁移 0009 落地 33 个 FK 重建）：
  - SET NULL（5 个）：Project.author_user_id、CandidateContent.{reviewed_by_user_id, project_id}、ProjectAction.file_media_id、Report.handled_by_user_id
  - CASCADE（27 个）：所有用户从属表 + user↔project 关联表
  - RESTRICT（1 个）：AdminAction.admin_user_id（审计日志保留，显式声明）

---

## High（27 项）

### 核心基础设施（5 项）

#### H-CORE-1. Redis 客户端无 socket 超时 → 慢 Redis 卡死整个服务
- **位置**：`app/core/redis.py:11`
- **修复**：`Redis.from_url` 加 `socket_connect_timeout=2`、`socket_timeout=2`、`retry_on_timeout=True`、`health_check_interval=30`。慢/挂的 Redis 2 秒放弃，避免吃光 threadpool 连 `/health` 一起死。

#### H-CORE-2. 依赖未锁定 → 构建不可复现 + 供应链风险
- **位置**：`requirements.txt`
- **修复**：13 个依赖全部加上界（fastapi<1、redis<7、pyjwt<3、anthropic<1 等），防止破坏性版本断构建。

#### H-CORE-3. Dockerfile 以 root 运行 + 无 .dockerignore
- **位置**：`Dockerfile` + 新建 `.dockerignore`
- **修复**：
  - 加非 root 用户 `app`（groupadd/useradd/chown/USER app）
  - HEALTHCHECK `start-period` 20s→60s（覆盖 alembic upgrade 冷启动）
  - 新建 `.dockerignore` 排除 `.git/.venv/__pycache__/tests/docs/.env/uploads`

#### H-CORE-4. `create_token_pair` 写 Redis 失败抛裸异常 → 500 + 幽灵账号
- **位置**：`app/core/security.py:34-46` + `app/api/v1/auth.py:143-149`
- **修复**：
  - security.py：`setex`/`delete` 失败转 `AppError(503, DEPENDENCY_DOWN)`
  - auth.py login：`create_token_pair` 失败且 `is_new_user` 时回滚新建用户行，避免幽灵账号

#### H-CORE-5. 无兜底 Exception handler → 违反响应契约
- **位置**：`app/main.py:77-78` + `app/core/errors.py`
- **修复**：加 `unhandled_exception_handler`，`RedisError`→503，其余→500，统一返回 `{code, message, details}` 结构。在 `AppError`/`RequestValidationError` handler 之后注册。

### Models + Schemas（12 项）

| 编号 | 位置 | 修复 |
|------|------|------|
| H-MDL-1 | `interaction.py` UserFollow | 加 `no_self_follow` CHECK |
| H-MDL-2 | `interaction.py` SimilarProjectLink | 加 `no_self_similar` CHECK |
| H-MDL-3 | `schemas/comment.py` | `host_type` 改 `CommentHostType` 枚举（422 而非 500） |
| H-MDL-4 | `schemas/post.py` | `PostMediaOut.type` 改 `MediaType` 枚举 |
| H-MDL-5 | `models/report.py` + `schemas/admin.py` | 加 `report_reason_allowed` CHECK，`AdminReportItem.reason` 改 `ReportReason` 枚举 |
| H-MDL-6 | `models/admin_action.py` + `schemas/admin.py` | 加 `admin_action_allowed` / `admin_target_type_allowed` CHECK，schema 改 `Literal` |
| H-MDL-7 | `models/base.py` | `updated_at` 加 DB 触发器（迁移 0009 在 26 张表建 `touch_updated_at` 触发器，兜底 bulk update） |
| H-MDL-8 | 4 张软删表 | 加部分索引 `ix_*_live`（`postgresql_where=deleted_at IS NULL`） |
| H-MDL-9 | `schemas/project.py` + `schemas/post.py` | `tags` 加 `max_length=20` + 元素长度 1-50 validator |
| H-MDL-10 | `schemas/auth.py` | `identifier` 按 type 做格式校验（phone 正则 / email 正则） |
| H-MDL-11 | `schemas/analytics.py` | `occurred_at` 加 validator clamp 未来/超 7 天前为 None |
| H-MDL-12 | `schemas/admin.py` | `CandidateDetail` 字段声明移到 validator 之前 |

### Services（3 项）

| 编号 | 位置 | 修复 |
|------|------|------|
| H-SVC-1 | `services/posts.py` _attach_media | 复制 URL 后 `db.delete(m)` 删源 ProjectMedia，防跨动态复用 + 防 purge_staged_media 误删 |
| H-SVC-2 | `services/rankings.py` 分布式锁 | token + Lua 脚本安全释放（`GET` 比对 token 才 `DEL`），TTL 30→120s |
| H-SVC-3 | `services/social.py` 计数 | `follower_count`/`following_count` join User 过滤 `deleted_at`，与列表口径一致 |

### API（7 项）

| 编号 | 位置 | 修复 |
|------|------|------|
| H-API-1 | `auth.py` send_code | 加 IP 级频控 10/3600s（防 SMS pumping），补 `request: Request` 参数 |
| H-API-2 | `media.py` upload_media | 用户级频控 20/60s |
| H-API-3 | `admin.py` dashboard | `clue_views` 从 `events("how_to_interest")`（恒 0）改查 `HowToInterest` 表 |
| H-API-4 | `admin.py` push_daily_pick | 分批 5000 拉取+插入，防百万级用户 OOM |
| H-API-5 | `project_actions.py` report_project | 用户级频控 5/60s |
| H-API-6 | posts/comments/projects 创建端点 | 各加用户级频控（5/10/20 per 60s） |
| H-API-7 | schemas 列表字段 | `media_ids`/`tags`/`actions`/`tools` 加 `max_length`，防大 payload DoS |

---

## 新增基础设施

### `app/core/ratelimit.py`（通用限流工具）
固定窗口限流，供 API 层统一调用：
```python
from app.core.ratelimit import rate_limit
rate_limit("send_code:ip:1.2.3.4", limit=10, window=3600)  # 超限抛 AppError(429)
```
Redis 不可用时 fail-open（放行 + 记日志），避免拖垮主流程。

### 迁移 `alembic/versions/0009_round3_review.py`
- 6 个 CHECK 约束
- 33 个 FK 重建（5 SET NULL + 27 CASCADE + 1 RESTRICT）
- 26 张表的 `touch_updated_at` 触发器
- 4 个软删部分索引
- 2 个 Medium 索引（`posts.tags` GIN + `analytics_events` user+created）
- `down_revision = "0008"`，downgrade 完整（FK 保留新策略不回滚，注释说明）

---

## 修改文件清单（38 文件）

```
核心基础设施（8）：
  app/core/redis.py            H-CORE-1
  app/core/security.py         H-CORE-4
  app/core/errors.py           H-CORE-5
  app/core/ratelimit.py        新建（通用限流）
  app/main.py                  H-CORE-5
  requirements.txt             H-CORE-2
  Dockerfile                   H-CORE-3
  .dockerignore                新建

Models（13）：
  app/models/user.py           C-MDL-2, H-MDL-8
  app/models/project.py        C-MDL-3, H-MDL-8
  app/models/candidate.py      C-MDL-3
  app/models/media.py          C-MDL-1, C-MDL-3
  app/models/interaction.py    C-MDL-3, H-MDL-1, H-MDL-2
  app/models/share.py          C-MDL-3
  app/models/report.py         C-MDL-3, H-MDL-5
  app/models/notification.py   C-MDL-3
  app/models/tag.py            C-MDL-3
  app/models/project_action.py C-MDL-3
  app/models/admin_action.py   C-MDL-3, H-MDL-6
  app/models/comment.py        H-MDL-8
  app/models/post.py           H-MDL-8

Schemas（6）：
  app/schemas/comment.py       H-MDL-3
  app/schemas/post.py          H-MDL-4, H-MDL-9, H-API-7
  app/schemas/project.py       H-MDL-9, H-API-7
  app/schemas/auth.py          H-MDL-10
  app/schemas/analytics.py     H-MDL-11
  app/schemas/admin.py         H-MDL-5, H-MDL-6, H-MDL-12

Services（5）：
  app/services/candidates.py   C-SVC-1
  app/services/comments.py     C-SVC-2
  app/services/posts.py        C-SVC-2, H-SVC-1
  app/services/rankings.py     H-SVC-2
  app/services/social.py       H-SVC-3

API（8）：
  app/api/v1/auth.py           H-API-1, H-CORE-4 协调
  app/api/v1/project_actions.py C-API-1, C-API-2, H-API-5
  app/api/v1/events.py         C-API-3
  app/api/v1/media.py          H-API-2
  app/api/v1/admin.py          H-API-3, H-API-4
  app/api/v1/posts.py          H-API-6
  app/api/v1/comments.py       H-API-6
  app/api/v1/projects.py       H-API-6

迁移（1）：
  alembic/versions/0009_round3_review.py  全部 DB 层改动

文档（1）：
  docs/round3-修复说明.md      本文件
```

---

## 自测结果

1. **语法检查**：38 个修改文件 `py_compile` 全部通过
2. **Import 集成**：models / schemas / services / api / core / main 全部 import 通过，app 装配 79 条路由
3. **ORM 元数据**：26 张表 DDL 用 PostgreSQL 方言编译全部通过，关键约束抽查正确（contact_present / no_self_follow / author_user_id SET NULL / report_reason_allowed / admin_action_allowed / ix_project_media_uploader / ix_comments_live_host）
4. **迁移链**：`0001→…→0008→0009_round3` 完整，head 正确，upgrade/downgrade 函数齐全
5. **迁移内容统计**：6 CHECK + 33 FK 重建（5 SET NULL + 27 CASCADE + 1 RESTRICT）+ 26 触发器 + 6 索引，与模型层改动一一对应
6. **关键修复验证**：C-API-1/2/3 去重+频控逻辑、H-API-1 IP 频控、8 处 rate_limit 调用全部在代码中确认

> 注：完整 smoke 测试（`tests/smoke_v0.py` 等）需要 PostgreSQL + Redis 环境，沙箱内无法运行。建议合并前在真实环境跑一遍 smoke 全套。

---

## 给 Claude 审查的提示

1. **重点看 3 个 Critical 刷榜修复**（C-API-1/2/3）：这是产品可信度根基，建议重点验证去重 + 频控逻辑是否真的堵住了刷量路径
2. **迁移 0009 是破坏性的**：FK 重建会短暂锁表，建议低峰期执行；downgrade 不回滚 FK 策略（保留新语义更安全）
3. **触发器会增加写开销**：26 张表的 `BEFORE UPDATE` 触发器，每次 UPDATE 多一次函数调用。若写密集表性能敏感，可评估只保留热表触发器
4. **ratelimit 是 fail-open**：Redis 挂时限流失效，这是有意取舍（避免 Redis 故障拖垮主流程），但意味着 Redis 挂时刷榜防护会降级
