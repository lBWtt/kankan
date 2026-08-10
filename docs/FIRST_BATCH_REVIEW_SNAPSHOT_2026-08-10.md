# 第一批多源审核快照（2026-08-10）

执行口径：内容宪法 v1.1；采集器只提取确定性事实，作品判定、双标题、五维吸引力与价值评分全部由生产 DeepSeek `v4-flash` 完成（`max_tokens=8000`，宪法与校准示例随上下文注入）。本批只进候选池，未自动发布。

## 结论先行

- 5 个来源共入池 33 条，DeepSeek 成功处理 33 条，最终 `pending_review` 16 条、`ai_processed` 8 条、`discarded` 9 条、失败残留 0 条。
- attraction `>=82` 共 2 条：itch.io 1 条、LiblibAI 1 条。
- 当前最有效的源是 LiblibAI：8/8 进入待审；少数派 1/1；itch.io 4/8；ModelScope 3/8；Hugging Face 0/8。
- 大方向验证通过：按“具体成果 + 真实 proof + 可体验入口”采集，再让 DeepSeek 判作品与吸引力，明显能把榜单/基准等原料挡住。HF 的“热门 Space”不适合作为长期入口，下一轮应改为具体成果意图检索。

## 每源结果与分布

| 来源 | 入池 | 待审 | 留池 | 丢弃 | attraction min/median/max | attraction 分桶 `<60 / 60-69 / 70-81 / >=82` | value min/median/max | `>=82` |
|---|---:|---:|---:|---:|---|---|---|---:|
| Hugging Face Space | 8 | 0 | 1 | 7 | 22 / 46.5 / 63 | 7 / 1 / 0 / 0 | 30 / 51 / 75 | 0 |
| itch.io | 8 | 4 | 3 | 1 | 52 / 70.5 / 82 | 1 / 3 / 3 / 1 | 35 / 52.5 / 65 | 1 |
| ModelScope | 8 | 3 | 4 | 1 | 42 / 69.5 / 75 | 1 / 3 / 4 / 0 | 35 / 71 / 80 | 0 |
| LiblibAI | 8 | 8 | 0 | 0 | 72 / 74 / 82 | 0 / 0 / 7 / 1 | 75 / 79 / 85 | 1 |
| 少数派 | 1 | 1 | 0 | 0 | 79 / 79 / 79 | 0 / 0 / 1 / 0 | 80 / 80 / 80 | 0 |
| **合计** | **33** | **16** | **8** | **9** | — | **9 / 7 / 15 / 2** | — | **2** |

“留池”是 `ai_processed`：60–69 分按宪法保留但不进待审，或达到 70 分但缺少模型选定的 proof。

## 代表卡片

### LiblibAI：商品照一键变白底精修图

- 双标题：`商品照一键变白底精修图，角度歪也能顺手纠正` / `随手拍张商品照，自动抠成白底精修图`
- attraction / value：`82 / 85`
- proof：[动态成果图](https://liblibai-online.liblib.cloud/img/ea845bc2267c4c1aa6df5099a6da594c/c022cb75f4a08c289513a2c16e17a72211732bc1874aefabd7766742c8efcae4.gif)
- experience：`model_page` · [具体作品页](https://www.liblib.art/modelinfo/6cf7fa75d6e94514a76b136d11d6b478)

### itch.io：网页里玩的恶作剧小游戏

- 双标题：`不装软件，网页里就能玩恶作剧整人小游戏` / `打开网页就能玩的整蛊小游戏，专治无聊`
- attraction / value：`82 / 60`
- proof：[成果图](https://img.itch.zone/aW1hZ2UvMTE4NzQxNi83MzA0MTk2LnBuZw==/347x500/y8ZM9n.png)
- experience：`game` · [具体可玩页](https://underweardemesne.itch.io/wedgie-simulator)

### 少数派：F1 赛程积分桌面看板

- 双标题：`F1 赛程积分桌面看板，打开电脑一眼看完` / `不用开网页查 F1，桌面直接看积分`
- attraction / value：`79 / 80`
- proof：[正文成果图](https://cdnfile.sspai.com/2026/08/06/article/a80b7d16cf2dee29f00b8539dde10393.png?imageView2/2/w/1120/q/90/interlace/1/ignore-error/1)
- experience：`download` · [作者作品仓库](https://github.com/belcheckyoung/f1-quote0)
- 解析核对：少数派文章只作出处，没有被当成体验入口。

### ModelScope：实时音乐生成

- 双标题：`弹出音符就能实时生成，AI 帮你把旋律补完` / `实时音乐生成：你的每次演奏 AI 都即兴跟上`
- attraction / value：`75 / 70`
- proof：[Studio 成果封面](https://resources.modelscope.cn/studio-cover-prod/studio-cover_f5aab922-3617-4272-8356-365ae0120ad0.png)
- experience：`web` · [独立演示](https://google-magenta-realtime-2-demo.ms.show)

### Hugging Face：虚拟试衣（被 proof 闸挡住）

- 双标题：`上传衣服和照片，下一秒看上身效果` / `挑衣服不用靠想象，照片上传就能试穿`
- attraction / value：`63 / 75`
- experience：`web` · [具体 Space](https://huggingface.co/spaces/Kwai-Kolors/Kolors-Virtual-Try-On)
- 结果：留在候选池；采到的页面媒体没有被 DeepSeek 选为成果 proof，不进待审。

## 拦截原因

| 原因 | 条数 | 说明 |
|---|---:|---|
| attraction `<60` | 7 | HF 5、itch 1、ModelScope 1，直接丢弃 |
| 非作品/基础设施 | 2 | HF 的通用模型排行榜与文本嵌入基准榜 |
| attraction `60–69` | 7 | HF 1、itch 3、ModelScope 3，保留但不进待审 |
| 缺 `selected_proof_media` | 1 | ModelScope 1，达到分数但 proof 不成立 |

Reddit 本轮通过 Clash 访问官方 JSON/RSS 均返回 403；未使用第三方镜像绕过。Product Hunt 本机和生产环境均没有 `PH_KEY/PH_SECRET`，已有 GraphQL 采集器保留但本轮不伪造执行结果。两者不计入本批 5 源。

## 审核入口与判断

- 审核台：[https://lovluu.com/admin-web/](https://lovluu.com/admin-web/)（外网未认证请求返回 401，访问保护正常）。
- 数据判断：这批已经出现一组明显“知道是什么、能看到成果、可以去体验”的卡片，且水货没有全进审核台，第一批采集策略可以继续。
- 下一轮优先级：保留 LiblibAI/少数派的具体成果入口；itch 加价值型品类词；ModelScope 优先个人 Studio；HF 从热门榜改成具体任务/成果意图搜索；Reddit 等官方可达后再启用；PH 配凭据后再跑 GraphQL。
