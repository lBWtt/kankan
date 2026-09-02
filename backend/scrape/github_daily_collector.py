# ============================================================
# 这个文件是干什么的：GitHubDaily 采集器——从 GitHubDaily 仓库的年度复盘 markdown
#   (github.com/GitHubDaily/GitHubDaily 的 2025.md/2024.md…) 里，把「工具/应用/插件」板块的
#   开源成品抓成本管线「标准条目」JSON（content_kind=project），走：
#   collect → process(DeepSeek 换角度写中文+判成果+提体验链接) → 人工审 → 发布。
# 它对应产品里的什么功能：内容源之一——中文策展号已帮我们筛好、每条自带项目链接（多为
#   GitHub 仓库＝天然 try_url，契合「给别人去用」）。见 memory [[vibe-coding-source-strategy]] 登记册。
#
# 为什么只取「工具/应用/插件」板块：定位是「能去用的成品」，不是教程/书籍/资料集合——
#   那些板块整段跳过。每条会最佳努力抓项目页 og:image 当封面（缺封面过不了发布准入）。
#
# 用法（backend/ 下，无需 key、无需代理）：
#   python scrape/github_daily_collector.py -o items_ghd.json --limit 30
#   python -m app.pipeline collect items_ghd.json --platform githubdaily
#   AI_PROVIDER=deepseek DEEPSEEK_API_KEY=sk-xxx python -m app.pipeline process
#   → 人工审（审核台）→ 发布
# ============================================================
from __future__ import annotations

import argparse
import datetime
import html
import json
import re
import sys
import urllib.error
import urllib.request

from collector_covers import gather_media

try:  # GBK 控制台下也能打印中文/emoji
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

RAW = "https://raw.githubusercontent.com/GitHubDaily/GitHubDaily/master/{year}.md"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) kankan-ghd-collector/1.0"

# 只收「能去用的成品」板块；教程/书籍/资料集合整段跳过（定位：去用，不是学怎么做）。
SECTION_KEEP = re.compile(r"工具|应用|插件|AI\s*技术", re.I)
SECTION_SKIP = re.compile(r"书籍|教程|资料|集合|目录|声明|复盘|宗旨", re.I)

# 表格行：[名字](链接) | 中文简述 | 源
ROW = re.compile(r"^\s*\[([^\]]+)\]\(([^)]+)\)\s*\|\s*(.+?)\s*\|")

_OG_IMG = re.compile(
    r'<meta[^>]+(?:property|name)=["\'](?:og:image|twitter:image)["\'][^>]+content=["\']([^"\']+)', re.I)
_OG_DESC = re.compile(
    r'<meta[^>]+property=["\']og:description["\'][^>]+content=["\']([^"\']+)', re.I)


def _get(url: str, timeout: int = 12) -> str | None:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read().decode("utf-8", "replace")
    except Exception:
        return None


def _resolve(url: str, timeout: int = 8) -> str:
    """短链（t.cn 等）跟跳转拿真实地址；失败原样返回。
    用 GET（不读 body）——t.cn 等短链服务常拒 HEAD；urlopen 自动跟跳转，geturl() 即终点。"""
    if "t.cn/" not in url:
        return url
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.geturl() or url
    except Exception:
        return url


def _og(url: str) -> tuple[str | None, str | None]:
    """最佳努力抓项目页 og:image（封面）+ og:description（补充原料）。"""
    body = _get(url, timeout=10)
    if not body:
        return None, None
    img = _OG_IMG.search(body)
    desc = _OG_DESC.search(body)
    return (html.unescape(img.group(1).strip()) if img else None,
            html.unescape(desc.group(1).strip()) if desc else None)


def latest_year_md() -> tuple[int, str] | None:
    """从今年往前找到第一个存在的年度复盘 md。"""
    this_year = datetime.date.today().year
    for year in range(this_year, this_year - 4, -1):
        txt = _get(RAW.format(year=year))
        if txt and "项目 | 简述" in txt:
            return year, txt
    return None


def parse_entries(md: str) -> list[dict]:
    """按板块解析表格行；只留 SECTION_KEEP 板块，跳过 SECTION_SKIP。链接非 http 的丢。"""
    entries: list[dict] = []
    keep = False
    for line in md.splitlines():
        h = re.match(r"^#{2,4}\s+(.*)$", line)
        if h:
            title = h.group(1).strip()
            keep = bool(SECTION_KEEP.search(title)) and not SECTION_SKIP.search(title)
            continue
        if not keep:
            continue
        m = ROW.match(line)
        if not m:
            continue
        name, link, desc = m.group(1).strip(), m.group(2).strip(), m.group(3).strip()
        if not link.startswith(("http://", "https://")):
            continue
        # 名字列里若混进了徽章图，跳过
        if "img.shields.io" in link or "/assets/" in link:
            continue
        entries.append({"name": name, "link": link, "desc": desc})
    return entries


def collect(limit: int, year: int | None) -> list[dict]:
    if year:
        md = _get(RAW.format(year=year))
        got = (year, md) if md else None
    else:
        got = latest_year_md()
    if not got:
        print("找不到 GitHubDaily 年度复盘 md（仓库结构可能变了）", file=sys.stderr)
        return []
    yr, md = got
    raw_entries = parse_entries(md)
    # 去重（按链接），保序
    seen, uniq = set(), []
    for e in raw_entries:
        if e["link"] in seen:
            continue
        seen.add(e["link"])
        uniq.append(e)
    print(f"GitHubDaily {yr}.md：解析到 {len(uniq)} 条工具/应用类条目，深挖前 {limit} 条…")

    items: list[dict] = []
    for e in uniq[:limit]:
        link = _resolve(e["link"])
        # 多图：优先仓库 README 真实演示图（GIF 最佳），多张，别用 GitHub 通用卡片（用户明确要求）。
        media = gather_media(link, 3)
        _, og_desc = _og(link)
        text = e["desc"]
        if og_desc and og_desc not in text:
            text = f"{text}\n\n{og_desc}"
        items.append({
            "source_url": link,
            "title": e["name"][:80],
            "text": text[:2000],
            "source_platform": "githubdaily",
            "content_kind": "project",
            "try_url": link,   # 确定性体验入口（多为 GitHub 仓库）→ ingestion 落库 → 项目 try_url
            "media": media,
        })
    n_cover = sum(1 for it in items if it.get("media"))
    print(f"产出 {len(items)} 条（{n_cover} 条抓到封面）。")
    return items


def main() -> int:
    ap = argparse.ArgumentParser(description="GitHubDaily 采集器 → 标准条目 JSON")
    ap.add_argument("-o", "--out", default="items_ghd.json")
    ap.add_argument("--limit", type=int, default=30, help="深挖（抓封面）多少条")
    ap.add_argument("--year", type=int, help="指定年度复盘（默认自动取最新）")
    args = ap.parse_args()
    items = collect(args.limit, args.year)
    if not items:
        return 1
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=2)
    print(f"写出 {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
