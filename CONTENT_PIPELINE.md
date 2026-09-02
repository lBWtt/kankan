# 内容流水线 · SSOT（唯一真源）

> 这是"每次抓内容照着做"的规则总纲。**不靠对话记忆**——要抓内容先读这份。
> 细节命令见 `backend/scrape/README.md`；代码规则见 `backend/scrape/collection_standard.py`、`backend/app/services/ai_processor.py`。

## 0. 两类内容
- **项目**（能用的东西，**有封面**）：
  ① GitHub 开源项目/工具；② 抖音/小红书的 **Vibe Coding 成果**（小程序/APP/网页，搜 "Vibe Coding"）；③ **推特 X** 上的 AI 成果（干货多、**帖子自带链接→体验入口好提**，英文帖 DeepSeek 翻译成中文）。
  ②天生有真实图片封面（解决"封面千篇一律"）；X 用 `scrape/x_collector.py`（Playwright 拦搜索接口，首次登录，`.x_userdata` 缓存），跳过 prefilter、is_maker_showcase 判成果、人工审。
- **动态**（聊 AI 的氛围，**纯文字、不需要封面**）：即刻（主）+ 小红书上关于 AI 的真人发言。
  **即刻只进动态、不进项目**；动态就是文字帖，别纠结封面。
  - **长度铁律**：**就是要短**——一两句为主，**三四行就算多了**，绝不写成段落/小作文/报告。
  - **改写力度**：**轻改**（原创化换词 + 删无关/私人/身份信息 + 顺通顺），**不重写、不扩写、不解释、不升华**。原帖多短你多短。
  - **选材**：优先短的、有网感的帖（别把短帖过滤掉）。
  - **小红书分流**：小红书上「Vibe Coding 成果」→ 项目；「AI 观点闲聊」→ 动态。同平台按内容分。

## 1. 统一七步流程
```
① 采集(collector)     → 标准条目 JSON（带 content_kind: project/post）
② 粗筛(prefilter)     → 只项目走；动态跳过（prefilter 要图要外链，纯文字动态会被误砍）
③ 入池(collect --kind)→ 候选池 ai_collected
④ 富化/改写(process)  → DeepSeek。项目=五维分+结构化+真口吻；动态=真口吻改写 → pending_review
⑤ 审核(approve)       → 人工过一遍（管理员）——【策略待定，见文末】
⑥ 发布                → 项目=马甲发 Project；动态=马甲发 Post；approve 时媒体转存到本地/OSS
⑦ 上架 App            → 用户下拉刷新可见
```

## 2. 焊死的规则（每次都必须遵守）
1. **口吻对照即刻真人（仅动态）**：`scrape/jike_voice_samples.json` 是口吻样本库（从即刻真帖抓的）。
   `ai_processor._pick_voice()` 每条随机取一个真样本当风格参照（**学腔调、不抄内容**）。**只给动态用**，样本旧了就重抓即刻刷新。
2. **项目=客观第三方视角**：我们用**马甲号发别人做的东西、不是创作者本人**——项目 tagline/summary/description 一律**客观第三方**（「有人用 AI 做了…」「一位抖音用户做了…」），**绝不用「我做了/我试了」冒充作者或编亲历**。有网感但别说明书、别『X 是一个』开头。项目**不注入**即刻第一人称口吻。
   **长文换行**：`_paragraphize()` 按句子切 2~3 句一段、段间空行（模型不爱加换行，后处理补）。
3. **采集标准**（`collection_standard.py` 唯一真源）：热度门槛（收藏为主）+ 完整性（有图/正文够长/有外链）。改阈值只改这一处。
4. **马甲发布**：外部内容随机派 `@persona.kankan` 马甲当作者，不留出处（冷启动做种）。
5. **媒体转存**：approve 时把外部图/视频下载到本地/OSS（防盗链，不热链他人 CDN）。
6. **封面现实**：图片优先平台（小红书/抖音）天生封面各异；GitHub 是代码平台、多数没截图 → 用社交卡/README 截图兜底，注定不如前者花。要"每张不同的真封面" → 优先小红书/抖音。

## 3. 每个源的确切命令（在 `backend/` 下）
**GitHub（项目，免登录）**
```
$env:GITHUB_TOKEN="ghp_xxx"   # 建议，否则限流
python scrape/github_collector.py -o items_github.json --limit 40
python scrape/prefilter.py --in items_github.json --platform github -o items_github_passed.json
python -m app.pipeline collect items_github_passed.json --platform github
AI_PROVIDER=deepseek DEEPSEEK_API_KEY=sk-xxx python -m app.pipeline process
# → 审核 approve
```
**即刻（动态，首次扫码登录，之后免扫）**
```
# 登录态存 .jike_userdata；首次 --headful 扫码。goto 必须 domcontentloaded（已固定）
D:/conda/envs/mediacrawler/python.exe scrape/jike_collector.py -o items_jike.json --dump-raw jike_raw.json --scrolls 10 --headful
python -m app.pipeline collect items_jike.json --platform jike --kind post   # 动态跳过 prefilter
AI_PROVIDER=deepseek DEEPSEEK_API_KEY=sk-xxx python -m app.pipeline process
# → 审核 approve（建 Post）。顺带：抓到的即刻真帖会刷新口吻样本库
```
**抖音 / 小红书（项目·Vibe Coding 成果，MediaCrawler，需扫码）**
- **搜索词**（MediaCrawler config.KEYWORDS）：`AI做了个,独立开发 上线了,cursor做了个,我用AI写了个小程序,我用AI做了个网站,vibe coding 作品`
- **分清真成果**：DeepSeek 判 `is_maker_showcase`——只有"有人做出了能用/能看的东西(小程序/APP/网站+截图/demo)"才留；卖课/培训/引流广告、纯教程、纯观点、水贴 → 判 False、标 suspected_ad、**拦在审核前**（不进待审核队列）。
- **有链接优先**：DeepSeek 提 `try_url`（网址/小程序名/公众号/TestFlight），有体验入口的 usable 给高分、排前面；小红书常屏蔽链接 → 提不到的**人工审时补**。
- **一律人工审**（管理员端过一遍 + 补体验链接）。封面 = 抖音/小红书真实截图（各不相同）。
```
# 一键：python scrape/pipeline_run.py dy --mc-dir F:/MediaCrawler   （需先 MediaCrawler 抓好）
# 分步见 backend/scrape/README.md：MediaCrawler 抓 → adapter 转 → prefilter → collect → process → 人工审
```

## 4. 决策已定（2026-07-17 拍板，写死）
- **审核策略**：**GitHub 自动过审发布**（低风险，DeepSeek+采集标准已把关）；**小红书/抖音/即刻 人工审核**（版权/质量风险，管理员端过一遍再发）。
- **节奏**：**手动 on-demand**（`pipeline_run.py` 就是手动入口；定时 `ingest_scheduler` 暂不开）。
- **DeepSeek/GitHub key**：只经环境变量传，绝不写进任何提交文件。

## 5. 一键驱动（首选入口，规则焊在 `scrape/pipeline_run.py` 里）
```powershell
cd F:\kankan\backend
$env:DEEPSEEK_API_KEY="sk-xxx"; $env:GITHUB_TOKEN="ghp_xxx"
python scrape/pipeline_run.py github --limit 40            # 采集→粗筛→入池→富化→自动过审+封面兜底
python scrape/pipeline_run.py jike  --scrolls 10 --headful # 首次扫码；之后免扫去掉 --headful。跑完自动刷新口吻库；停待审核
python scrape/pipeline_run.py xhs   --mc-dir F:/MediaCrawler   # 需先 MediaCrawler 抓好；停待审核
python scrape/pipeline_run.py dy    --mc-dir F:/MediaCrawler
```
一键脚本做的：github=全自动上架；jike/xhs/dy=富化完停在待审核队列等人工。第 3 节的分步命令仍可用（想手动控每一步时）。
