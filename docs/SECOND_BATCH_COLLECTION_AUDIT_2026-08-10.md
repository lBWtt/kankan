# 第二批国内源采集审计（2026-08-10）

## 结论

小红书、抖音、即刻均已实际运行，不再把帖子页、视频页或列表页当体验入口。程序硬闸已按内容宪法 9.0/9.2/9.3 收紧；本轮没有可诚实作为 v1.1 新验证样本的候选，因此没有为了凑数降低门槛。

## 程序改动

- MediaCrawler 适配器增加 `--constitution`：只保留成果意图，拦截教程/资讯/变现原料，并执行 proof、正文和平台热度机械闸。
- 小红书、抖音条目标记 `requires_manual_experience_url=true`；源帖/视频不写入 `try_url`。
- 即刻改为项目采集：从 `urlsInText`/正文提取真实外链，屏蔽即刻、抖音、小红书、B 站、YouTube 等内容页；没有真实作品外链或 proof 就不产 item。
- 候选入库保留“需人工补体验链接”事实标记。
- 增加精确按本批 URL 查询生产候选的审计快照脚本和 6 个第二批采集契约测试。

## 实跑结果

| 来源 | 原始量 | 硬闸结果 | 生产结果 |
|---|---:|---:|---|
| 抖音历史抓取 | 103 | 9 | 9 个 URL 均已存在，是旧流程记录，不能冒充本轮 v1.1 |
| 抖音 2026-08-10 新抓取 | 41 | 0 | 教程/提示词/产品功能介绍或热度不足，未入池 |
| 即刻历史抓包 | 68 个帖子节点 | 1 | URL 已存在，是旧流程记录 |
| 即刻 2026-08-10 实时抓取 | 108 个帖子节点 | 0 | 没有同时满足成果意图、真实外链、proof 的新条目 |
| 小红书历史抓取 | 20 | 0 | 两个早期泛命中已修正为拦截 |
| 小红书实时抓取 | 等待登录 | — | 独立可见浏览器仍开着，扫码成功后会继续采集 |

## 生产库核验

精确查询上述历史合格 URL：10/10 已存在，其中抖音 7 approved、2 discarded，即刻 1 approved。这些记录的 `attraction_score`、`value_score`、`title_candidates`、`selected_proof_media` 均为空，属于旧流程遗留，不计入本轮 v1.1 快照。

## 验证

- 内容宪法、发布闸、slate 与采集器相关测试：15/15 通过。
- Python 编译检查通过。
- 正确生产机 `ubuntu@118.89.112.187`：backend healthy；DeepSeek provider/key 已配置，v4-flash 调用 `max_tokens=8000`。
- checkpoint：`29753c1 feat: enforce outcome gates for domestic collectors`。

## 剩余唯一外部阻塞

小红书登录二维码需要人工扫码。登录态建立后，运行中的采集器将产出新 JSON；随后按同一硬闸入池、按 `xiaohongshu` 调 DeepSeek、生成最终三源新候选快照。未扫码前不能伪造小红书采集成功。

## 2026-08-11：抖音话题池补测

- 改用话题词 `vibecoding` / `vibecoding大赏`：综合搜索 API 实际返回 126 条；其中 `vibecoding` 可稳定分页，直接单搜 `vibecoding大赏` 返回空页。
- 用户提供的 `source=pc_click_hashtag_feed` 页面在自动浏览器中触发验证码；其 URL 仍是 `/search/vibecoding大赏`，当前不能把它声称为一个已验证的独立话题 API。
- 宪法硬闸初筛 6 条；补拦“活动公告/工具锐评”后留下 4 条具体作品。
- 生产入池：2 条旧 URL 自动去重，2 条为新增；DeepSeek v4-flash 均判定为作品：
  - 3D 简历平台：`attraction=78`、`value=75`，双标题已生成，缺真实体验链接，停 `ai_processed`。
  - 汕头 44 家咖啡店地图：`attraction=69`、`value=75`，双标题已生成，因 `<70` 留候选池。
- 公开检索发现 3D 简历作品疑似对应 `https://intro3d.com`，页面功能与视频描述高度吻合，但没有从抖音原帖直接解析到，未自动写库，留给人工确认。

## 2026-08-11：话题发现层（允许暂缺体验链接）

- 新增 `--discovery`，只把抖音/小红书候选发现热度放宽到“赞 ≥1 万或收藏 ≥2 千”；成果语义、非教程和 proof 三道闸不变，发布闸完全不变。
- `vibecoding` 的 126 条话题结果经发现层留下 8 条：前述 4 条作品 + 4 条新增候选。生产 collect 为“新增 4、去重 4”。
- 新增候选经 DeepSeek v4-flash（`max_tokens=8000`）处理：
  - 背单词闯关游戏：`attraction=77`、`value=72`；真实体验链接待找。
  - Codex + Stitch 点菜 App：`attraction=73`、`value=72`；更偏工作流演示，真实成品链接待找。
  - 100 小时目标进度追踪器：`attraction=70`、`value=70`；真实体验链接待找。
  - 游戏开发 Agent：`attraction=43`、`value=35`，已自动淘汰。
- 修复社交源体验链接污染：DeepSeek 从输入媒体抄出的 `douyin.com/aweme/v1/play` 只能算 proof，不能写成 `experience_url`。带 `requires_manual_experience_url` 的候选只接受采集器确认过的 `known_try_url`；生产两条受影响记录已清理并退回 `ai_processed`。
- 相关宪法/采集器测试共 20 条通过，生产 backend 重建后 healthy。
