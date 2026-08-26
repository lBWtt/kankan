# ============================================================
# 这个文件是干什么的：Hacker News「Show HN」采集器——HN 上开发者**秀自己做的成品**的板块，
#   用 HN Algolia API 抓（免登录、免代理），转成本管线「标准条目」JSON（content_kind=project）：
#   collect → process(DeepSeek 换角度写中文+判成果+提体验链接) → 人工审 → 发布。
# 它对应产品里的什么功能：成品来源之一，且**天然对味**——Show HN 就是"我做了个东西，来看看"，
#   多是**个人开发者**的真成品 + 可去用链接（网站/App/GitHub），还带**真实作者**（HN 用户名）。
#   见 memory [[vibe-coding-source-strategy]]（成品侧：PH榜单 + Show HN + appinn + AI导航）。
#
# 取"最近的精品"：search_by_date（按时间倒序）+ 点赞阈值（--min-points，默认 30），
#   过滤掉无 url / 指回 HN 自身的帖；封面走共享 best_cover（github→README 演示图，否则 og）。
#
# 用法（backend/ 下，无需 key、无需代理）：
#   python scrape/showhn_collector.py -o items_shn.json --limit 30 --min-points 30
#   python -m app.pipeline collect items_shn.json --platform hackernews
#   AI_PROVIDER=deepseek DEEPSEEK_API_KEY=sk-xxx python -m app.pipeline process
#   → 人工审（审核台）→ 发布
# ============================================================
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.parse
import urllib.request

from collector_covers import gather_media, og_description

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

API = "http://hn.algolia.com/api/v1/search_by_date"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) kankan-showhn-collector/1.0"
_PREFIX = re.compile(r"^\s*show\s*hn\s*[:：]?\s*[–\-—]?\s*", re.I)


def _fetch(min_points: int, want: int) -> list[dict]:
    q = urllib.parse.urlencode({
        "tags": "show_hn",
        "numericFilters": f"points>={min_points}",
        "hitsPerPage": want,
    })
    req = urllib.request.Request(f"{API}?{q}", headers={"User-Agent": UA})
    return json.load(urllib.request.urlopen(req, timeout=20)).get("hits", [])


def collect(limit: int, min_points: int) -> list[dict]:
    # 多取些再过滤（无 url / 指回 HN 的会被丢），保证够 limit。
    hits = _fetch(min_points, limit * 4)
    print(f"Show HN：拉到 {len(hits)} 条（points≥{min_points}），过滤+深挖前 {limit} 条…")

    items: list[dict] = []
    seen = set()
    for h in hits:
        if len(items) >= limit:
            break
        url = (h.get("url") or "").strip()
        if not url.startswith(("http://", "https://")):
            continue
        if "news.ycombinator.com" in url or url in seen:
            continue
        seen.add(url)
        title = _PREFIX.sub("", h.get("title") or "").strip()
        if not title:
            continue
        author = h.get("author")
        desc = og_description(url) or ""
        text = title if not desc else f"{title}。{desc}"
        media = gather_media(url, 3)   # 多图（github README 多图 / 网站 og+截图）
        if not media:
            continue  # 宪法 v1.1：没有真实成果 proof 不入池
        item = {
            "source_url": url,
            "title": title[:80],
            "text": text[:2000],
            "source_platform": "hackernews",
            "content_kind": "project",
            "try_url": url,   # Show HN 提交的链接就是去体验入口（网站/App/GitHub）
            "language": "en-US",
            "engagement": {"likes": h.get("points") or 0, "comments": h.get("num_comments") or 0},
            "media": media,
        }
        if author:  # 真实创作者（HN 用户）——留作出处/将来收录 makers
            item["original_author_name"] = author
            item["original_author_url"] = f"https://news.ycombinator.com/user?id={author}"
        items.append(item)
    n_cover = sum(1 for it in items if it.get("media"))
    print(f"产出 {len(items)} 条（{n_cover} 条有封面）。")
    return items


def main() -> int:
    ap = argparse.ArgumentParser(description="Hacker News Show HN 采集器 → 标准条目 JSON")
    ap.add_argument("-o", "--out", default="items_shn.json")
    ap.add_argument("--limit", type=int, default=30)
    ap.add_argument("--min-points", type=int, default=30, help="点赞阈值（越高越精，越少）")
    args = ap.parse_args()
    items = collect(args.limit, args.min_points)
    if not items:
        return 1
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=2)
    print(f"写出 {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
