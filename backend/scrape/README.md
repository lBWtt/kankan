# ② 小红书/抖音 采集接入（MediaCrawler → 候选池）

把 MediaCrawler 抓的内容接进本项目的 AI 候选池流水线。**采集**用 MediaCrawler（外部工具），
**转格式**用本目录的 `mediacrawler_adapter.py`，**入池/富化/审核**用 `app.pipeline`。

```
MediaCrawler 抓 (jsonl)  →  mediacrawler_adapter.py (转标准 JSON)  →
  pipeline collect (入候选池)  →  pipeline process (DeepSeek 富化)  →  人工审核  →  approve  →  App
```

## 一、装 MediaCrawler（一次性）

MediaCrawler 需要 **Python ≥3.11**（本项目后端是 3.9，故给它单独的 conda 环境）。

```bash
# 1) 已 clone 到 F:/MediaCrawler
# 2) 建 3.11 环境 + 装依赖
conda create -n mediacrawler python=3.11 -y
conda activate mediacrawler
cd /f/MediaCrawler
pip install -r requirements.txt
python -m playwright install chromium      # 装浏览器内核（Playwright 自动化）
```
> 若 `asyncmy` / `aiomysql`（MySQL）在 Windows 编译失败：我们用 jsonl 输出、不碰 MySQL，
> 可从 requirements.txt 里去掉这两行再装（或忽略其报错，其余装上即可）。

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

```bash
# 1) 采集（在 mediacrawler 环境，F:/MediaCrawler）
conda activate mediacrawler
cd /f/MediaCrawler && python main.py
#   产出 F:/MediaCrawler/data/xhs/jsonl/search_contents_YYYY-MM-DD.jsonl

# 2) 转成标准条目（在后端环境，backend/）
cd /f/kankan/backend
python scrape/mediacrawler_adapter.py --dir F:/MediaCrawler --platform xhs -o items_xhs.json

# 3) 入候选池
python -m app.pipeline collect items_xhs.json --platform xiaohongshu

# 4) DeepSeek 富化 → 待审核队列
AI_PROVIDER=deepseek DEEPSEEK_API_KEY=sk-xxx python -m app.pipeline process --limit 30

# 5) 人工审核 → approve（审核接口/后台）→ App 里出现
```

## 四、待办（下一步）

- **媒体转存**：小红书/抖音图/视频是它们 CDN 链接，**有防盗链**，App 直接显示可能挂。
  生产要在 approve 时把媒体**下载转存到本地/OSS**（见 `PIPELINE_PLAN.md` 决策4）。当前适配器先透传 URL。
- **原创化改写**：DeepSeek 富化时做「风格像、内容原创、带出处链接+原作者」，别逐字搬（见 `CONTENT_SCRAPE_PLAN.md` 版权一节）。
- **定时调度**：MVP 手工跑；跑顺后可加定时（每日一轮）+ 成本上限。

## 文件
- `mediacrawler_adapter.py` — MediaCrawler jsonl → 管线 collect 标准 JSON（已测：字段映射正确、无 url 的丢弃）
- 标准条目形状：见 `app/services/ingestion.py` 文件头
