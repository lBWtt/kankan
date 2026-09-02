# kankan 内容采集 Runbook（agent 无关，任何 AI 照跑结果一致）

目标：往候选池灌**能去用的成品**（带 try_url），**PH 为主力、中文策展为补充，配比约一半一半**，
别单源猛灌。整条流水线：采集 → 入池(ai_collected) → AI 整理(pending_review) → 审核台发布。

前置：Docker 起了 postgres+redis；后端环境 = conda base `D:\conda\python.exe`。所有命令在 `F:\kankan\backend` 下。

---

## 一、采集入池（无需 key、无需代理，可反复跑）

```powershell
cd F:\kankan\backend

# ① Product Hunt —— 主力（真·个人成品 + 去用链接；国区可达 + 商店锁区已在采集器过滤）
D:\conda\python.exe scrape\ph_collector.py -o items_ph.json --limit 30
D:\conda\python.exe -m app.pipeline collect items_ph.json --platform producthunt
#   注：PH feed 约 50 条/天，重复与跑题会被滤，每次「新增」有限（个位~二十几）。想多→隔天再跑。

# ② HelloGitHub —— 中文策展（自动取最新期，每条自带项目截图，封面覆盖~100%；偏基建，配角）
D:\conda\python.exe scrape\hellogithub_collector.py -o items_hg.json --limit 30
D:\conda\python.exe -m app.pipeline collect items_hg.json --platform hellogithub

# ③ GitHubDaily —— 中文策展（只取工具/应用板块；--year 换年份取不同批，避免重复）
D:\conda\python.exe scrape\github_daily_collector.py -o items_ghd.json --limit 30 --year 2024
D:\conda\python.exe -m app.pipeline collect items_ghd.json --platform githubdaily

# ④ Show HN —— 成品·个人开发者秀自己做的东西（Algolia API，免登录；带真实作者；网页无 og 图自动网页截图当封面）
D:\conda\python.exe scrape\showhn_collector.py -o items_shn.json --limit 30 --min-points 30
D:\conda\python.exe -m app.pipeline collect items_shn.json --platform hackernews

# ⑤ 小众软件 appinn —— 中文实用软件/网站策展（RSS，按分类过滤新闻/补丁；feed 只给最近~10 篇，每次约 5~7 条）
D:\conda\python.exe scrape\appinn_collector.py -o items_appinn.json --limit 20
D:\conda\python.exe -m app.pipeline collect items_appinn.json --platform appinn

# ⑥ PH 榜单（GraphQL）—— 最强成品源：top-by-votes 精品 + PH 画廊多图 + makers（需 PH_KEY/PH_SECRET 内联）
$env:PH_KEY="..."; $env:PH_SECRET="..."   # PH 后台 /v2/oauth/applications 拿；只内联、别写文件
D:\conda\python.exe scrape\pipeline_run.py phrank --limit 30 --days 30   # 一条龙(含 collect+process，需 DeepSeek key)
#   或分步：ph_graphql_collector.py -o items_phg.json … → collect --platform producthunt
```

> 多图：`collector_covers.gather_media` 让每条带 2~4 图（github README 多图 / appinn 正文截图 / PH 画廊 /
> 网站 og+落地页图+截图），不再一封面一段文字。appinn 的 try_url 只认真实产品链接，找不到不收。

> PH 榜单（周榜/月榜）**静态和无头浏览器都抓不动**（SPA + 反爬），要走 **PH GraphQL API**：
> 到 https://www.producthunt.com/v2/oauth/applications 登录后生成 Developer Token，内联给 collector。

> 封面固化：github→仓库 README 演示图(GIF优先)→og→**网页截图**兜底，全在 `collector_covers.best_cover`，
> 三个采集器 + 审核台「＋加链接」都走它，不会再出现千篇一律的 GitHub 通用卡片。

**配比铁律**：`PH ≈ (HelloGitHub + GitHubDaily)` 各占一半。PH 供给不足时，中文这半也别猛灌到失衡；
宁可少灌、隔天补 PH，或走 X（见下）。GitHubDaily/HelloGitHub 偏开发者库/框架，是**配角**。

## 二、AI 整理（需要 DeepSeek key —— 只内联传，别写进任何文件/仓库）

```powershell
$env:AI_PROVIDER="deepseek"; $env:DEEPSEEK_API_KEY="<你的key>"
D:\conda\python.exe -m app.pipeline process --limit 60
```

整理会：判成果（非成果/教程/水被拦）、写中文、填分类/领域/封面、提体验链接。
**硬门槛**：无 try_url（网页/App Store/GitHub 三选一）→ 不能发布、分数压 ≤20；GitHub 仓库地址会兜底成 try_url。

## 三、审核发布

审核台 `http://localhost:8000/admin-web/`（管理员登录 dev 万能码 888）：
- 留「能去用的成品」（带界面/能直接用的 App/工具/网站）；纯库/框架/教程点「不推荐」。
- 「＋加链接」可手动补自己找到的链接（同样走 process 整理）。

## 四、找新源（可选，固化在登记册）

内容源登记册 `scrape/sources.yaml`；管理/发现命令：

```powershell
D:\conda\python.exe scrape\discover_sources.py list                 # 看所有源
D:\conda\python.exe scrape\discover_sources.py add --kind x_account --handle 某人 --name "@某人"
D:\conda\python.exe scrape\discover_sources.py discover             # 行为发现：高频"带链接项目贴"作者→提名
```
站类"跑搜索发现新源"：AI 用自己的联网搜索跑 `sources.yaml` 里 `discovery_hints.site_queries`，把结果 `add` 成 proposed。

## 五、X 独立开发者（真·个人成品主力，待打通）

X 反自动化，需 **CDP 复用已登录 Chrome**：桌面 `chrome.exe --remote-debugging-port=9222`（原 profile、已登 X），
再走 `x_collector`（连 `http://localhost:9222`）。种子号在 `sources.yaml`（@levelsio/@dannypostma/@CoderDaMing…）。
