# ============================================================
# 这个文件是干什么的：HelloGitHub 采集器——从 HelloGitHub 月刊 markdown
#   (github.com/521xueweihan/HelloGitHub 的 content/HelloGitHub{期号}.md，自动取最新期) 里，
#   把每条开源项目抓成本管线「标准条目」JSON（content_kind=project），走：
#   collect → process(DeepSeek 换角度写中文+判成果+提体验链接) → 人工审 → 发布。
# 它对应产品里的什么功能：内容源之一（中文策展补充）。HelloGitHub 每条**自带项目截图**（省得逐条抓 og），
#   链接是 hellogithub.com/.../click?target=<真实地址> 跳转，解出 target 即 try_url（多为 GitHub 仓库）。
#   偏基建/C·C++，是**配角**（见 memory [[vibe-coding-source-strategy]]），靠评分/人工审过滤。
#
# 用法（backend/ 下，无需 key、无需代理）：
#   python scrape/hellogithub_collector.py -o items_hg.json --limit 30 [--issue 123]
#   python -m app.pipeline collect items_hg.json --platform hellogithub
#   AI_PROVIDER=deepseek DEEPSEEK_API_KEY=sk-xxx python -m app.pipeline process
#   → 人工审（审核台）→ 发布
# ============================================================
from __future__ import annotations

import argparse
import html
import json
import re
import sys
import urllib.parse
import urllib.request

from collector_covers import gather_media

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) kankan-hg-collector/1.0"
API = "https://api.github.com/repos/521xueweihan/HelloGitHub/contents/content"
RAW = "https://raw.githubusercontent.com/521xueweihan/HelloGitHub/master/content/HelloGitHub{n}.md"

# 条目：N、[名字](链接)：中文简介。……
ENTRY = re.compile(r"^\d+、\[([^\]]+)\]\(([^)]+)\)[：:]\s*(.*)$")
IMG = re.compile(r"<img[^>]+src=['\"]([^'\"]+)['\"]", re.I)


def _get(url: str, timeout: int = 12) -> str | None:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read().decode("utf-8", "replace")
    except Exception:
        return None


def latest_issue() -> int | None:
    """列 content/ 目录取最大期号。"""
    try:
        req = urllib.request.Request(API, headers={"User-Agent": UA, "Accept": "application/vnd.github+json"})
        data = json.load(urllib.request.urlopen(req, timeout=15))
        nums = [int(re.search(r"\d+", f["name"]).group())
                for f in data if re.match(r"HelloGitHub\d+\.md", f["name"])]
        return max(nums) if nums else None
    except Exception:
        return None


def _real_url(link: str) -> str:
    """从 hellogithub 跳转链接解出真实地址（?target=...）；非跳转原样返回。"""
    q = urllib.parse.urlparse(link).query
    tgt = urllib.parse.parse_qs(q).get("target")
    return tgt[0] if tgt else link


def parse_entries(md: str) -> list[dict]:
    """解析条目 + 紧随其后的项目截图（HelloGitHub 每条常自带 <img>）。"""
    lines = md.splitlines()
    entries: list[dict] = []
    for i, line in enumerate(lines):
        m = ENTRY.match(line.strip())
        if not m:
            continue
        name, link, desc = m.group(1).strip(), m.group(2).strip(), m.group(3).strip()
        real = _real_url(link)
        if not real.startswith(("http://", "https://")):
            continue
        # 向后看几行找项目截图（跳过空行）
        cover = None
        for j in range(i + 1, min(i + 4, len(lines))):
            im = IMG.search(lines[j])
            if im:
                cover = im.group(1).strip()
                break
            if lines[j].strip() and not lines[j].strip().startswith("<"):
                break  # 撞到下一条目/正文，停
        entries.append({"name": name, "link": real, "desc": desc, "cover": cover})
    return entries


def collect(limit: int, issue: int | None) -> list[dict]:
    n = issue or latest_issue()
    if not n:
        print("找不到 HelloGitHub 最新期号（API 可能限流，用 --issue 指定）", file=sys.stderr)
        return []
    md = _get(RAW.format(n=n))
    if not md:
        print(f"拉不到 HelloGitHub{n}.md", file=sys.stderr)
        return []
    raw = parse_entries(md)
    seen, uniq = set(), []
    for e in raw:
        if e["link"] in seen:
            continue
        seen.add(e["link"])
        uniq.append(e)
    print(f"HelloGitHub 第 {n} 期：解析到 {len(uniq)} 个项目，取前 {limit} 条…")

    items: list[dict] = []
    for e in uniq[:limit]:
        # 多图：月刊自带截图排最前 + 仓库 README 多图，像小红书多图。
        media = gather_media(e["link"], 3, extra=[e["cover"]] if e["cover"] else None)
        items.append({
            "source_url": e["link"],
            "title": e["name"][:80],
            "text": e["desc"][:2000],
            "source_platform": "hellogithub",
            "content_kind": "project",
            "try_url": e["link"],   # 解出的真实地址（多为 GitHub 仓库）＝去体验入口
            "media": media,
        })
    n_cover = sum(1 for it in items if it.get("media"))
    print(f"产出 {len(items)} 条（{n_cover} 条有封面）。")
    return items


def main() -> int:
    ap = argparse.ArgumentParser(description="HelloGitHub 采集器 → 标准条目 JSON")
    ap.add_argument("-o", "--out", default="items_hg.json")
    ap.add_argument("--limit", type=int, default=30)
    ap.add_argument("--issue", type=int, help="指定期号（默认自动取最新）")
    args = ap.parse_args()
    items = collect(args.limit, args.issue)
    if not items:
        return 1
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=2)
    print(f"写出 {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
