# AI 抓取管线规划（Track B · "从地基到盖楼"）

> 定位：这是产品前期展现价值的核心 —— 爬取 → AI 富整理 → 人工审核 → 发布。
> 状态：规划中（未开工）。后端"引擎"部分已有雏形（candidate 状态机 + ai_processor + 审核），
> 缺的是**内容来源、自动化调度、内容加厚、存储/发布身份、合规与护栏**。

---

## 一、逐条回应初始 4 点（含修正）

### ① 怎么抓 / 谁抓 / 平台
- **谁抓：程序抓，不是 agent 抓。** Claude Code 在 dev 会话里、非常驻服务，不能当生产爬虫；
  但这个抓取程序**由我来建**（定时 worker 调 API）。"AI 整理"那步是**程序调 Claude API**
  （后端 `ai_processor` 已有雏形），也不是 agent。
- **平台分级（关键判断）：**

  | 平台 | 评级 | 原因 |
  |---|---|---|
  | **GitHub** | 🟢 首选 | 官方 API、读公开仓合规、结构化数据全（star/README/topic/license）、法律风险低 |
  | Hugging Face / Product Hunt / arXiv / Reddit | 🟢 第二批 | 同样 API 友好、许可清晰 |
  | **小红书 / 抖音** | 🔴 前期不碰 | 无官方内容 API、反爬极凶（签名+风控）、ToS 禁抓、内容是他人版权 UGC，技术+法律双高危 |
  | 即刻 | 🟡 灰色 | 无官方 API、小平台 |

- **关于"动态复制即刻/小红书"（修正）：** 直接搬别人帖子 = **侵权 + 违反 ToS**。
  改法：用 Claude 把我们精选的项目/AI 资讯**原创**成即刻/小红书那种口吻的短动态
  （**风格像、内容原创、带出处链接**）。同样调性，没有法律坑。

### ② 账户 + 存储
- **发布身份：** 用"官方编辑"账号发（种子里的**「看看小编」就是雏形**），可再来几个分栏编辑号。
  **不是**爬来的用户号。
- **存储：** 内容进 Postgres（已有）；媒体**下载后转存到自己的 S3** —— 绝不热链他人 CDN
  （会挂 + 法律），生产绝不放本地。后端**已有 storage 抽象（local/s3）**，Track C 配真 S3 即可。
  转存媒体挑版权干净的（仓库自带截图/许可图，或我们生成封面——渐变封面已有）。

### ③ 内容加厚（不能只给链接）
- `ai_processor` 已在做结构化抽取，要**加厚**：GitHub 项目 → 抽 README → Claude 整理出
  「亮点 / 怎么做 / 用了什么工具 / 适合谁 / 上手步骤 / takeaways / actions」+ 拉真截图，
  填进 project 富字段（intro / ai_implementation_hint / takeaways / media / actions）。
- 顺带：Claude 整理时做**中文本地化**（英文源→中文），正好发挥它的价值。

### ④ 原创作者标记（地基已在）
project 表已有 `source_type / source_url / source_platform / original_author_name /
original_author_url / is_original`。抓 GitHub 时把仓主填进 `original_author_*`。
以后原作者入驻做**"认领"流程**关联到其账号。数据模型不用动。

---

## 二、初始没提但会绊脚的
- ⚖️ **法律 / ToS / 版权（最大的）**：robots.txt / API ToS / 限频要守；媒体转存与许可；
  不搬运 UGC。前期只碰 API 友好 + 许可清晰的源。
- **去重**：跨轮次查重（已有"入池查重"雏形）。
- **成本护栏**：Claude 预算 / 单轮条数上限 / token 统计。
- **质量 / 审核闸**：先 **review-before-publish**（人工过一遍保质+合规），高置信度再自动发；
  审核界面现在是空的，需**种候选数据**。
- **失败重试 + 死信**：坏/恶意内容别反复烧钱重试。
- **Prompt 注入防御**：抓来的原文进 Claude 前隔离/清洗。
- **content_type 填充**：刚建的轴，抓取整理时让 Claude 一起推断填上。
- **调度**：多久一轮、每轮几条。

---

## 三、建议分期（先盖一层能住的）
- **Phase 1（打通一层楼）**：GitHub 源 → Claude 富整理（中文/真截图/富字段/填 content_type + 原作者归属）
  → 人工审核 → 「看看小编」发布 → 媒体转存 S3 → 每日定时 + 成本上限。**一个源、全链路跑通、合规。**
- **Phase 2**：加 HF / Product Hunt / arXiv / Reddit；用 Claude **原创生成**即刻/小红书风格「动态」（非搬运）。
- **Phase 3（远期/高风险）**：小红书/抖音走人工精选或合规途径；原作者认领流程。

### 端到端数据流（Phase 1）
```
GitHub API (trending/topics, token)
   → 原始条目入池（查重）        candidate: ai_collected
   → Claude 富整理（中文/结构化/content_type/原作者/截图）  candidate: ai_processed
   → 人工审核队列               candidate: pending_review
   → approve                    → 建 Project（富字段 + 原作者归属）+ 媒体转存 S3 → published
   ↑ 定时调度（每日）+ 成本上限 + 去重 + 死信 + prompt 注入清洗
```

---

## 四、决策（已定）
1. **前期源**：**GitHub 优先**。"搜索太麻烦"由 AI 解决——程序按过滤器拉候选池，Claude 打分挑好的，不用人手搜。
2. **小红书/抖音**：**绕开，直接去源头 GitHub**。抄 XHS 帖子 = 抄中间商的版权表达（文案/图）；直接抓 GitHub 项目 + Claude 原创中文介绍 = 拿真东西、不碰版权。且非所有 XHS 都是搬 github（真人原创的 AI图/prompt/教程抄了是实打实侵权）。
3. **发布方式**：**先人工审核**（review-before-publish），高置信度后再自动。
4. **存储**：**上云存储（阿里云 OSS，S3 兼容）**。媒体下载后转存 OSS，不放本地/不热链他人 CDN。后端 storage 抽象已支持，开桶填配置即可（前期本地可先跑，上线前必切）。
5. **发布身份**：**几个正常名字的编辑号，表现像真实用户**（冷启动常见做法）。提醒：真人用户进来后，过度装真人的透明度问题是产品调性选择。

### 谁来抓：Program 还是 Agent —— 混合，分阶段
- **确定性/重复的活**（定时、调 API、拉 README/图、存储、去重、限频、算成本）→ **程序**（稳、便宜、可控）。
- **聪明的活**（挑哪些值得发、把 README 变中文富内容）→ **LLM / Agent**（判断力）。
- **近期（bootstrap）：Agent 主导先跑起来** —— 用 agent（含本 CLI）先精选+加厚头几十条，快、便宜、**先验证内容质量**，不急着建全套程序。
- **生产（每日无人值守）：程序编排 + 在"挑"和"整理"两步调 Claude** —— 不用纯自主 agent 跑生产（成本不可控、要托管、ToS/限频难管）。
- 一句话：**先 agent 验证质量，再固化成"程序编排 + LLM 调用"的生产管线。**

---

## 五、下一步
- ✅ **已完成：Agent-bootstrap 第一批** —— 用 agent（本 CLI）精选 + 中文加厚 4 条真实 GitHub 项目入库、已发布、验证通过。
  - 脚本：`backend/curate_github.py`（幂等，按 source_url 去重；`--force` 重灌）。
  - 选题（覆盖 4 种 content_type）：ComfyUI（tool）、Ollama（opensource）、Dify（app）、prompts.chat（prompt）。
  - 每条含富字段：`intro`（中文结构化正文）/`ai_implementation_hint`/`tools`/`domains`/`ai_badge`/`repo_stars`，
    原作者归属（`source_url`+`source_platform=github`+`original_author_*`+`is_original=false`），本地渐变封面（无外网可显示）。
  - 发布身份：两个正常名字编辑号「陈屿」「林岸」。
  - 已验证：`GET /projects?content_type=…` 按类型筛得中、详情页富字段齐全、封面 200、归属字段完整。
  - **结论（内容质量验证）**：agent 读真实仓库 → 中文本地化改写 → 富字段结构，产出可用、不搬运、带出处。可据此固化成程序管线。
- ▶️ **之后**：把 agent 验证过的"挑 + 整理"逻辑固化成程序化 Phase 1 管线（GitHub API 采集 + 调度 + 成本护栏 + OSS 媒体 + 审核队列）。

## 附：已有 vs 待建
| 环节 | 现状 |
|---|---|
| candidate 状态机（ai_collected→…→approved） | ✅ 已有 |
| ai_processor（Claude 结构化整理，逐条隔离） | ✅ 雏形，待加厚 |
| 入池查重 | ✅ 有雏形 |
| project 原作者归属字段 | ✅ 已有 |
| storage 抽象（local/s3） | ✅ 有，待配真 S3 |
| 内容来源采集（GitHub 等 API） | ❌ 待建 |
| 定时调度 | ❌ 待建（手工 CLI） |
| 成本护栏 / 死信 / prompt 注入清洗 | ❌ 待建 |
| 媒体下载→转存 S3→封面 | ❌ 待建（封面生成已有） |
| 动态原创生成 | ❌ 待建 |
| 原作者认领流程 | ❌ 远期 |
