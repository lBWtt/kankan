# ============================================================
# 这个文件是干什么的：GitHub 采集器——抓「又新又火」+「小众好用」的仓库，转成本管线
#   collect 命令吃的「标准条目」JSON（形状见 app/services/ingestion.py 文件头），
#   走和小红书/抖音同一条漏斗：collector → prefilter → collect → DeepSeek → 审核 → App。
# 它对应产品里的什么功能：② 采集入口之一——工具/资讯类「项目」的自动来源（GitHub 官方 API，
#   比爬抖音稳）。定位：kankan「给别人去用」→ 优先能直接体验（有 homepage/demo）的成品。
#
# 选品策略（7:3，见 CONTENT_SOURCING_PLAN.md）：
#   A 桶「新+火」70%：github.com/trending（增速榜）+ Search「近 N 天新建、按 star 排」兜底。
#   B 桶「挖宝小众」30%：Search「star 在 [min,max] 之间、近期还在维护」——好用但没火、还活着。
#   别只看绝对 star（大项目人人皆知没发现感）；排序看 **star 增速**（stars/建库天数），
#   有 demo 链接 / 命中主题白名单加分。内容好不好最后交 DeepSeek 五维分 + 人工审核。
#
# 用法（在 backend/ 下）：
#   set GITHUB_TOKEN=ghp_xxx   # 强烈建议：无 token 限流 60 次/时，会不够用
#   python scrape/github_collector.py -o items_github.json --limit 40
#   python scrape/prefilter.py --in items_github.json --platform github -o items_github_passed.json
#   python -m app.pipeline collect items_github_passed.json --platform github
#   AI_PROVIDER=deepseek DEEPSEEK_API_KEY=sk-xxx python -m app.pipeline process
#
# 注意：GitHub 社交预览图 opengraph.githubassets.com 是可直接下载的公开图（无防盗链），
#   当封面很合适；approve→建项目时的媒体转存能直接把它转到本地/OSS。
# ============================================================
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

# ---- 主题白名单：只要 AI/创作/工具类，排除纯底层库/别人跑不起来的东西 ----
# 每个主题各跑一次 Search（GitHub 的多个 topic: 是 AND，无法一句 OR，故逐个查再合并）。
DEFAULT_TOPICS = [
    "ai", "llm", "agent", "stable-diffusion", "text-to-image",
    "chatbot", "prompt", "comfyui", "rag", "ai-tools",
]

API = "https://api.github.com"
TRENDING = "https://github.com/trending"
UA = "kankan-github-collector/1.0"

# star 增速加分用的主题命中权重、demo 权重
BONUS_HOMEPAGE = 1.30   # 有 homepage/demo（能直接体验）→ 契合「给别人去用」
BONUS_TOPIC = 1.15      # 命中主题白名单


def _headers(extra: Optional[dict] = None) -> dict:
    h = {
        "User-Agent": UA,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        h["Authorization"] = f"Bearer {token}"
    if extra:
        h.update(extra)
    return h


def _get(url: str, accept_html: bool = False) -> Optional[str]:
    """GET 文本（API 用 JSON header，trending 页用 HTML）。失败返回 None（不阻断整轮）。"""
    hdr = {"User-Agent": UA} if accept_html else _headers()
    req = urllib.request.Request(url, headers=hdr)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        if e.code == 403:
            print(f"  ! 403（多半是限流；设 GITHUB_TOKEN 提额）：{url}", file=sys.stderr)
        else:
            print(f"  ! HTTP {e.code}：{url}", file=sys.stderr)
    except (urllib.error.URLError, TimeoutError) as e:
        print(f"  ! 网络错误：{e} · {url}", file=sys.stderr)
    return None


def _get_json(url: str):
    txt = _get(url)
    if txt is None:
        return None
    try:
        return json.loads(txt)
    except json.JSONDecodeError:
        return None


def _iso(dt_str: Optional[str]) -> Optional[str]:
    if not dt_str:
        return None
    return dt_str  # GitHub 已是 ISO8601（如 2026-05-01T00:00:00Z），直接透传


def _age_days(created_at: Optional[str]) -> int:
    if not created_at:
        return 9999
    try:
        dt = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
        return max(1, (datetime.now(timezone.utc) - dt).days)
    except ValueError:
        return 9999


def _social_preview(full_name: str) -> str:
    """GitHub 社交预览卡（avatar+名称+描述+star 的自动大图，或作者自传的封面）。
    路径里的 hash 段任意值都行，用时间戳避开 CDN 缓存串味。可直接下载、无防盗链。
    注意：这是**兜底**——所有仓库都长一个模板样、很千篇一律，优先用 README 里的真实截图。"""
    return f"https://opengraph.githubassets.com/{int(time.time())}/{full_name}"


# README 里 badge/徽章/logo 类小图，不当封面（它们也很千篇一律）。
_BAD_IMG = ("shields.io", "badge", "/badges/", "githubusercontent.com/badges",
            "travis-ci", "circleci", "codecov", "//img.shields", "vercel.app/button",
            "herokucdn", "gitpod.io/button", "opencollective",
            "logo", "icon", "banner-", "/logos/", "avatar")  # logo/图标不当封面（还是千篇一律）
_IMG_SRC_RE = re.compile(r'<img[^>]+src="([^"]+)"', re.IGNORECASE)


def _has_github_token() -> bool:
    return bool(os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN"))


def readme_cover(full_name: str) -> Optional[str]:
    """从仓库 README 里挑第一张**真实截图/GIF/演示图**当封面（各仓库不同，摆脱千篇一律）。
    用 GitHub API 的 HTML 渲染（相对路径已转成绝对 URL），过滤掉 badge/logo。拿不到返回 None。"""
    req = urllib.request.Request(
        f"{API}/repos/{full_name}/readme",
        headers=_headers({"Accept": "application/vnd.github.html"}),
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            html = resp.read().decode("utf-8", "replace")
    except Exception:
        return None
    for m in _IMG_SRC_RE.finditer(html):
        url = m.group(1).strip()
        low = url.lower()
        if not low.startswith("http"):
            continue
        if any(b in low for b in _BAD_IMG):
            continue
        if low.endswith(".svg"):  # 多是 logo/图标，非截图
            continue
        # 真实截图多是 png/jpg/gif/webp，或经 GitHub camo 代理（user-images / camo）
        if (low.split("?")[0].endswith((".png", ".jpg", ".jpeg", ".gif", ".webp"))
                or "user-images.githubusercontent" in low or "camo.githubusercontent" in low):
            return url
    return None


# ------------------------------------------------------------------
# 打分：star 增速为主，有 demo / 命中主题加分。用于最终排序（非硬门槛）。
# ------------------------------------------------------------------
def _score(repo: Dict) -> float:
    stars = repo.get("stargazers_count") or 0
    velocity = stars / _age_days(repo.get("created_at"))  # 每天涨多少星 ≈ 火不火
    mult = 1.0
    if (repo.get("homepage") or "").strip():
        mult *= BONUS_HOMEPAGE
    topics = repo.get("topics") or []
    if any(t in DEFAULT_TOPICS for t in topics):
        mult *= BONUS_TOPIC
    return round(velocity * mult, 4)


def _to_item(repo: Dict, bucket: str) -> Optional[dict]:
    """一个 GitHub repo 对象 → 管线标准条目。缺 html_url/描述则丢。"""
    url = (repo.get("html_url") or "").strip()
    full = repo.get("full_name") or repo.get("name") or ""
    desc = (repo.get("description") or "").strip()
    if not url or not full or not desc:
        return None
    topics = repo.get("topics") or []
    owner = repo.get("owner") or {}
    homepage = (repo.get("homepage") or "").strip()
    stars = repo.get("stargazers_count") or 0
    # 正文：描述 + 主题标签（DeepSeek 富化的原料；也让完整性门槛 text_len 达标）
    text = desc
    if topics:
        text += "  ·  " + " ".join(f"#{t}" for t in topics[:8])
    return {
        "source_url": url,
        "title": full,
        "text": text,
        "source_platform": "github",
        "original_author_name": owner.get("login") or None,
        "original_author_url": owner.get("html_url") or None,
        # 封面：**有 token 时**才扒 README 真实截图（每仓库多一次 API 调用，无 token 会限流/变慢）；
        # 没 token 就直接用社交卡兜底（快、稳）。
        "media": [{"url": ((readme_cover(full) if _has_github_token() else None)
                           or _social_preview(full)), "media_type": "image"}],
        "language": "en-US",
        "published_at": _iso(repo.get("created_at")),
        # stars→collects（主信号/排序）、forks→likes；对齐 prefilter 的收藏/点赞两档
        "engagement": {
            "likes": repo.get("forks_count") or 0,
            "collects": stars,
            "comments": repo.get("open_issues_count") or 0,
            "shares": repo.get("forks_count") or 0,
        },
        # 给下游/审核的参考字段（ingestion 忽略未知键）：
        "homepage": homepage,        # 体验链接候选（可填进项目 try_url）
        "topics": topics,
        "github_stars": stars,
        "score": _score(repo),
        "bucket": bucket,            # A=新+火 / B=挖宝小众
    }


# ------------------------------------------------------------------
# 数据源
# ------------------------------------------------------------------
def search_repos(query: str, per_page: int = 20) -> List[Dict]:
    """Search API：q 里带 sort/order 用 URL 参数。返回 repo 对象列表。"""
    qs = urllib.parse.urlencode({
        "q": query, "sort": "stars", "order": "desc", "per_page": per_page,
    })
    data = _get_json(f"{API}/search/repositories?{qs}")
    if not data:
        return []
    return data.get("items") or []


def hydrate(full_name: str) -> Optional[Dict]:
    """trending 页只给 owner/repo，用 API 补全 star/描述/homepage/topics。"""
    return _get_json(f"{API}/repos/{full_name}")


# trending 页：<h2 ... lh-condensed> 后接 <a>，但 <a> 上先挂了 data-hydro-click 等属性，
# href 不紧跟 <a，故容忍中间属性（GitHub 2024+ 起改的 markup，别退回 `<a href` 直贴写法）。
_TREND_RE = re.compile(r'<h2[^>]*lh-condensed[^>]*>\s*<a\b[^>]*?href="/([^"]+)"')


def fetch_trending(since: str = "weekly") -> List[str]:
    """抓 github.com/trending（增速榜），解析出 owner/repo 列表。since=daily/weekly/monthly。
    HTML 解析天生脆，失败返回空、由 Search 兜底，不阻断整轮。"""
    html = _get(f"{TRENDING}?since={since}", accept_html=True)
    if not html:
        return []
    names, seen = [], set()
    for m in _TREND_RE.finditer(html):
        name = m.group(1).strip().strip("/")
        if name.count("/") == 1 and name not in seen:
            seen.add(name)
            names.append(name)
    return names


# ------------------------------------------------------------------
# 组装
# ------------------------------------------------------------------
def _dedup_by_url(items: List[dict]) -> List[dict]:
    out, seen = [], set()
    for it in items:
        if it["source_url"] in seen:
            continue
        seen.add(it["source_url"])
        out.append(it)
    return out


def collect_bucket_a(topics: List[str], min_stars: int, created_since: str,
                     trending_since: str, per_topic: int, sleep: float) -> List[dict]:
    """A 桶「新+火」：trending 增速榜（主）+ Search 近期新建按 star（兜底）。"""
    items: List[dict] = []
    # 1) trending：真·增速榜
    names = fetch_trending(trending_since)
    print(f"  trending/{trending_since}: 命中 {len(names)} 个仓库，逐个补全…")
    for name in names:
        repo = hydrate(name)
        if repo and (repo.get("stargazers_count") or 0) >= min_stars:
            it = _to_item(repo, "A")
            if it:
                items.append(it)
        time.sleep(sleep)
    # 2) Search 兜底：近期新建、按 star 降序 ≈ 新且已积累人气
    for t in topics:
        q = f"topic:{t} created:>{created_since} stars:>={min_stars} fork:false"
        for repo in search_repos(q, per_page=per_topic):
            it = _to_item(repo, "A")
            if it:
                items.append(it)
        time.sleep(sleep)
    return items


def collect_bucket_b(topics: List[str], min_stars: int, max_stars: int,
                     pushed_since: str, per_topic: int, sleep: float) -> List[dict]:
    """B 桶「挖宝小众」：star 在 [min,max] 之间、近期还在维护——好用但没火、还活着。"""
    items: List[dict] = []
    for t in topics:
        q = (f"topic:{t} stars:{min_stars}..{max_stars} "
             f"pushed:>{pushed_since} fork:false")
        for repo in search_repos(q, per_page=per_topic):
            it = _to_item(repo, "B")
            if it:
                items.append(it)
        time.sleep(sleep)
    return items


def _days_ago(days: int) -> str:
    from datetime import timedelta
    return (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%d")


def main() -> int:
    ap = argparse.ArgumentParser(description="GitHub 采集器 → 管线标准条目 JSON（7:3 新火/挖宝）")
    ap.add_argument("-o", "--out", default="items_github.json")
    ap.add_argument("--limit", type=int, default=40, help="最终输出条数上限")
    ap.add_argument("--ratio", type=float, default=0.7, help="A 桶（新+火）占比，默认 0.7")
    ap.add_argument("--topics", default=",".join(DEFAULT_TOPICS), help="主题白名单，逗号分隔")
    ap.add_argument("--min-stars", type=int, default=50, help="A 桶最低 star（滤死项目）")
    ap.add_argument("--niche-min", type=int, default=50, help="B 桶 star 下限")
    ap.add_argument("--niche-max", type=int, default=2500, help="B 桶 star 上限（超了算已火）")
    ap.add_argument("--new-days", type=int, default=120, help="A 桶：近多少天新建算「新」")
    ap.add_argument("--active-days", type=int, default=60, help="B 桶：近多少天有 push 算「还活着」")
    ap.add_argument("--trending-since", default="weekly", choices=["daily", "weekly", "monthly"])
    ap.add_argument("--per-topic", type=int, default=5, help="每个主题每桶取几条")
    ap.add_argument("--sleep", type=float, default=1.0, help="请求间隔秒（防限流）")
    args = ap.parse_args()

    if not (os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")):
        print("提示：未设 GITHUB_TOKEN，未认证限流 60 次/时、Search 10 次/分，可能中途 403。\n"
              "      set GITHUB_TOKEN=ghp_xxx 后重跑更稳。", file=sys.stderr)

    topics = [t.strip() for t in args.topics.split(",") if t.strip()]
    print(f"主题：{topics}")
    print("A 桶（新+火）…")
    bucket_a = collect_bucket_a(
        topics, args.min_stars, _days_ago(args.new_days),
        args.trending_since, args.per_topic, args.sleep,
    )
    print(f"A 桶原始 {len(bucket_a)} 条")
    print("B 桶（挖宝小众）…")
    bucket_b = collect_bucket_b(
        topics, args.niche_min, args.niche_max,
        _days_ago(args.active_days), args.per_topic, args.sleep,
    )
    print(f"B 桶原始 {len(bucket_b)} 条")

    # 各自去重、按 score 降序
    bucket_a = sorted(_dedup_by_url(bucket_a), key=lambda x: x["score"], reverse=True)
    bucket_b = sorted(_dedup_by_url(bucket_b), key=lambda x: x["score"], reverse=True)
    # B 桶排掉已在 A 桶的
    a_urls = {it["source_url"] for it in bucket_a}
    bucket_b = [it for it in bucket_b if it["source_url"] not in a_urls]

    # 7:3 取数
    n_a = round(args.limit * args.ratio)
    n_b = args.limit - n_a
    picked = bucket_a[:n_a] + bucket_b[:n_b]
    # 若某桶不够，用另一桶补满
    if len(picked) < args.limit:
        rest = [it for it in (bucket_a[n_a:] + bucket_b[n_b:])][: args.limit - len(picked)]
        picked += rest
    picked = _dedup_by_url(picked)

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(picked, f, ensure_ascii=False, indent=2)
    got_a = sum(1 for it in picked if it["bucket"] == "A")
    print(f"\n输出 {len(picked)} 条（A 新火 {got_a} / B 挖宝 {len(picked) - got_a}）→ {args.out}")
    print(f"下一步：python scrape/prefilter.py --in {args.out} --platform github "
          f"-o {args.out.rsplit('.', 1)[0]}_passed.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
