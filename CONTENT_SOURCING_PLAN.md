# 内容来源策略 & 现状盘点

> 日期：2026-07-16
> 结论：**先做 GitHub 采集器 + 动态内容管线**，推送通知随后。

---

## 一、现状盘点

### 已跑通的采集管线（目前只喂「项目」）

```
MediaCrawler 抓 → adapter 转格式 → prefilter 粗筛(收藏率≥0.08)
  → collect 入候选池 → DeepSeek 富化 → 人工审核 approve
  → 派马甲当作者（不留出处） → App 展示
```

存量数据（本地）：

| 来源 | 抓取 | 粗筛通过 |
|---|---|---|
| 抖音 | 71 | 61 |
| 小红书 | 20 | 13 |

- 马甲号机制在（`app/services/personas.py`）：approve 时随机派一个 `@persona.kankan` 账号当作者。

### 两个关键缺口

1. **GitHub 没有采集器**。历史上是手工塞了 4 条 GitHub 项目（commit d533630），不是自动管线。`scrape/` 里只有 xhs/dy 的 adapter。
2. **「动态」没有任何采集/入库管线**。scrape 出来的东西全走 `候选→approve→项目`；`posts.py` 只服务真人手动发的动态。**「抓资讯/即刻 → 改写 → 发成动态」这条路不存在。**

### 关于 ZCode 那批改动

`ZCODE_CHANGES.md` 记录的是 **DeepSeek** 改的（分享按钮、本周精选、我的页「我的动态」区、编辑资料重做、删设置页假按钮）。方向都对，保留。

---

## 二、内容拆成两条产品线

这个拆分天然解决了之前「热门/精选/动态同质」的问题：**项目=能用的东西，动态=聊 AI 的氛围**。

| 来源 | 落地为 | 管线现状 |
|---|---|---|
| 抖音/小红书 vibe coding 成果 | **项目**（别人做好的作品） | ✅ 已通 |
| GitHub 前沿工具/资讯 | **项目**（工具类） | ⚠️ 无采集器，要写 |
| 资讯 + 即刻 AI 讨论（改写后发） | **动态** | ❌ 无管线，要从头搭 |

---

## 三、要补的三件事（按性价比）

### 1. GitHub 采集器（优先，复用现成管线）
- GitHub 有官方 API，比爬抖音稳得多：trending / 关键词搜 repo → star / README / social-preview 封面。
- 产物直接进现有 `candidate → approve → 项目`，改造成本低。

### 2. 动态采集管线（新链路，工作量最大）
- 来源：**即刻 explore** `https://web.okjike.com/explore` + AI 资讯源。
- 即刻没有开放 API → 走爬取（MediaCrawler 或专用抓取），注意封控与稳定性。
- DeepSeek「重新说一遍」（风格像、内容原创）→ 产出 **Post**，由马甲发布。
- 需要新增：动态入库路径（区别于项目的 `candidate→project`）。

### 3. 推送通知（想法1 的闭环才需要）
- 多账号互动（关注/点赞/评论）目前没有站内红点/推送反馈。
- 想法2（灌内容）不依赖它，故排最后。

---

## 四、真机多用户模拟（想法1，暂缓）

- 多账号是现成的：**万能码 `888888` + 任意手机号** 会按手机号建独立隔离账号 → 3 个手机号 = 甲/乙/丙。
  - （`888`→固定管理员、`777`→固定普通用户 是单例，模拟不了互相互动。）
- 可测闭环：甲发内容 → 乙刷到 → 乙点赞/评论/关注甲 → 甲主页粉丝+1。
- **唯一断点：推送通知未实现**，乙关注甲后甲收不到通知。

---

## 五、执行顺序（进度）

1. ✅ **GitHub 采集器** `backend/scrape/github_collector.py` —— 7:3 trending/挖宝，star 增速排序，
   有 demo 加分；封面用 GitHub 社交预览图。已用真实数据跑通。
2. ✅ **动态采集管线（即刻 explore）** ——
   - 后端源无关核心：candidate `content_kind`（迁移 0016）+ `collect --kind post` +
     DeepSeek 动态改写 prompt + `approve_candidate_as_post`（马甲发 Post）。已端到端测过。
   - 即刻采集器 `backend/scrape/jike_collector.py`：Playwright 带登录态、拦 feed API 响应
     （跑在 mediacrawler conda 环境）。解析逻辑离线测过；**首次需 headful 扫码登录，且真实
     API 字段名待用真数据校准**（若抓到 0 条，抓一份响应样例调 `_walk_posts`/`_to_item`）。
3. ⬜ **推送通知** —— 让多账号互动有反馈（想法1 的闭环）。

> 动态跳过 prefilter（那是项目导向粗筛，要图要外链，纯文字动态会被误砍）。
> 采集运行手册见 `backend/scrape/README.md`。
