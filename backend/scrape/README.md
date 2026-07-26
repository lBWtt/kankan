# ② 小红书/抖音 采集接入（MediaCrawler → 候选池）

把 MediaCrawler 抓的内容接进本项目的 AI 候选池流水线。**采集**用 MediaCrawler（外部工具），
**转格式**用本目录的 `mediacrawler_adapter.py`，**入池/富化/审核**用 `app.pipeline`。

```
MediaCrawler 抓 (jsonl)  →  mediacrawler_adapter.py (转标准 JSON)  →
  prefilter.py (采集标准粗筛)  →  pipeline collect (入候选池)  →
  pipeline process (DeepSeek 富化)  →  人工审核  →  approve  →  App
```

**采集标准（够不够格进池）** 定义在 `collection_standard.py`（唯一真源）：热度门槛
（收藏为主、点赞为辅，按平台）+ **收藏率门槛**（收藏÷点赞 ≥ 0.08，砍情绪/观点帖）+
完整性（有图/视频、正文够长）。`prefilter.py` 按它粗筛并打印**可审计报告**（每条留/砍+原因）。
热度是**粗筛**，内容好不好交下游 DeepSeek 五维分——三道漏斗，别在粗筛里判语义。

## 一、装 MediaCrawler（✅ 已装好，此节仅备查/换机重装用）

MediaCrawler 需要 **Python ≥3.11**（本项目后端是 3.9，故给它单独的 conda 环境）。
**本机已完成**：clone 到 `F:/MediaCrawler`；conda 环境 `mediacrawler`（Python 3.11.15）；
依赖全装（含 playwright/opencv/asyncmy，无失败）；Playwright Chromium 已下。CLI 实测可用。

重装步骤（换机时）：
```bash
git clone https://github.com/NanmiCoder/MediaCrawler.git F:/MediaCrawler
conda create -n mediacrawler python=3.11 -y
D:/conda/envs/mediacrawler/python.exe -m pip install -r F:/MediaCrawler/requirements.txt \
    -i https://pypi.tuna.tsinghua.edu.cn/simple
cd /f/MediaCrawler && HTTPS_PROXY=http://127.0.0.1:7890 \
    D:/conda/envs/mediacrawler/python.exe -m playwright install chromium
```

## 二、配置 MediaCrawler（每次抓前）

编辑 `F:/MediaCrawler/config/base_config.py`：
- `PLATFORM = "xhs"`（小红书）或 `"dy"`（抖音）
- `KEYWORDS = "AI绘画,Midjourney,提示词"`（逗号分隔的搜索词）
- `CRAWLER_TYPE = "search"`
- `LOGIN_TYPE = "qrcode"`（首次扫码登录，最省事）或 `"cookie"` + 填 `COOKIES`
- `SAVE_DATA_OPTION = "jsonl"`（**必须 jsonl**，适配器读它）
- `CRAWLER_MAX_NOTES_COUNT = 30`（一次抓多少）
- 建议关掉评论抓取（我们只要正文+图），看 `ENABLE_GET_COMMENTS` 等开关

## 三、跑一轮

> MediaCrawler 已装好：conda 环境 `mediacrawler`（Python 3.11）+ 依赖 + Playwright Chromium。
> CLI 是 typer，参数可覆盖 config（`SAVE_DATA_OPTION=jsonl` 建议直接在 config 里设死）。

```bash
# 1) 采集（用 mediacrawler 环境的 python，F:/MediaCrawler）
cd /f/MediaCrawler
D:/conda/envs/mediacrawler/python.exe main.py \
    --platform xhs --type search --lt qrcode \
    --keywords "AI绘画,Midjourney,提示词"
#   首次弹二维码 → 你用小红书/抖音 App 扫码登录（登录态会缓存，之后免扫）
#   产出 F:/MediaCrawler/data/xhs/jsonl/search_contents_YYYY-MM-DD.jsonl

# 2) 转成标准条目（在后端环境，backend/）
cd /f/kankan/backend
python scrape/mediacrawler_adapter.py --dir F:/MediaCrawler --platform xhs -o items_xhs.json

# 3) 采集标准粗筛（打印审计报告 + 输出通过项，按收藏率降序）
python scrape/prefilter.py --in items_xhs.json --platform xiaohongshu -o items_xhs_passed.json

# 4) 入候选池（只入通过的）
python -m app.pipeline collect items_xhs_passed.json --platform xiaohongshu

# 5) DeepSeek 富化 → 待审核队列
AI_PROVIDER=deepseek DEEPSEEK_API_KEY=sk-xxx python -m app.pipeline process --limit 30

# 6) 人工审核 → approve（App 内管理员构建的「审核」悬浮球，或后台接口）→ App 里出现
```

## 三·五、GitHub 采集（工具/资讯类项目，不走 MediaCrawler）

GitHub 有官方 API，比爬抖音稳，直接一步出标准条目。选品 7:3：A 桶「新+火」
（trending 增速榜 + 近期新建按 star）70%，B 桶「挖宝小众」（star 在区间内、近期还在维护）30%。
排序看 **star 增速**（stars/建库天数），有 demo / 命中主题白名单加分；细节见 `CONTENT_SOURCING_PLAN.md`。

```bash
cd /f/kankan/backend
# 强烈建议先设 token（无 token 限流 60 次/时、Search 10 次/分，易中途 403）
set GITHUB_TOKEN=ghp_xxx            # PowerShell: $env:GITHUB_TOKEN="ghp_xxx"

# 1) 采集（一步出标准条目；可调 --limit/--ratio/--topics/--min-stars 等）
python scrape/github_collector.py -o items_github.json --limit 40

# 2) 粗筛（github 门槛只做完整性/活性兜底，真筛在 collector；stars→收藏、forks→点赞列）
python scrape/prefilter.py --in items_github.json --platform github -o items_github_passed.json

# 3) 入池 → 富化 → 审核（与 xhs/dy 同）
python -m app.pipeline collect items_github_passed.json --platform github
AI_PROVIDER=deepseek DEEPSEEK_API_KEY=sk-xxx python -m app.pipeline process
```

> 封面用 GitHub 社交预览图（`opengraph.githubassets.com`，公开可下载、无防盗链），
> approve→建项目时的媒体转存能直接转到本地/OSS。`homepage` 字段是体验链接候选（可填项目 try_url）。

## 三·六、即刻采集（动态来源，content_kind=post）

即刻 explore 是登录态 SPA，直连只有空壳。用 **Playwright 带登录态跑浏览器、拦 feed 的 API 响应**
（干净 JSON，改版也不怕）。抓到的 AI 动态 → DeepSeek「用自己的话重讲一遍」→ 马甲发出。

> 跑在 **mediacrawler conda 环境**（3.11 + chromium，已装）。首次 `--headful` 扫码登录，登录态存
> `.jike_userdata/`，之后免扫、可 headless。

```bash
# 1) 采集（首次登录）
D:/conda/envs/mediacrawler/python.exe scrape/jike_collector.py -o items_jike.json --scrolls 8 --headful
#   之后免扫：去掉 --headful 即可

# 2) 入池（动态**跳过 prefilter**：prefilter 是项目导向的粗筛，要图要外链，纯文字动态会被误砍）
cd /f/kankan/backend
python -m app.pipeline collect items_jike.json --platform jike --kind post

# 3) 改写 → 待审核（走动态改写 prompt：第一人称/口语/原创重述，不搬运）
AI_PROVIDER=deepseek DEEPSEEK_API_KEY=sk-xxx python -m app.pipeline process

# 4) 审核 approve → 马甲发的动态出现在 App（后台审核悬浮球 / approve 接口）
```

动态与项目的区别：`content_kind=post` 走 `check_post_gate`（正文≥20 + 标签≥1，无封面/分类要求），
approve 建 **Post**（马甲作者、图片转存），不建 Project。

## 四、待办（下一步）

- **媒体转存**：小红书/抖音图/视频是它们 CDN 链接，**有防盗链**，App 直接显示可能挂。
  生产要在 approve 时把媒体**下载转存到本地/OSS**（见 `PIPELINE_PLAN.md` 决策4）。当前适配器先透传 URL。
- **原创化改写**：DeepSeek 富化时做「风格像、内容原创、带出处链接+原作者」，别逐字搬（见 `CONTENT_SCRAPE_PLAN.md` 版权一节）。
- **定时调度**：MVP 手工跑；跑顺后可加定时（每日一轮）+ 成本上限。

## 文件
- `mediacrawler_adapter.py` — MediaCrawler jsonl → 管线 collect 标准 JSON（已测：字段映射正确、无 url 的丢弃）
- 标准条目形状：见 `app/services/ingestion.py` 文件头
