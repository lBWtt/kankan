# ============================================================
# 这个文件是干什么的：小众软件（appinn.com）采集器——中文老牌"能直接用的好软件/网站"策展站，
#   有 WordPress RSS，好抓。转成本管线「标准条目」JSON（content_kind=project）：
#   collect → process(DeepSeek 换角度写中文+判成果+提体验链接) → 人工审 → 发布。
# 它对应产品里的什么功能：成品来源之一（中文·很对味）——appinn 专推普通人能上手的实用软件/网站，
#   每篇自带真实截图。见 memory [[vibe-coding-source-strategy]]。
#
# try_url 策略（混合）：正文里能找到干净的官方外链就用它；找不到就退回 appinn 文章页
#   （中文介绍+下载，本身也是"去看/去用"的落地页）。封面取正文首张真实截图（跳过 avif/svg）。
#
# 用法（backend/ 下，无需 key、无需代理）：
#   python scrape/appinn_collector.py -o items_appinn.json --limit 20
#   python -m app.pipeline collect items_appinn.json --platform appinn
#   AI_PROVIDER=deepseek DEEPSEEK_API_KEY=sk-xxx python -m app.pipeline process
#   → 人工审（审核台）→ 发布
# ============================================================
from __future__ import annotations

import argparse
import html
import json
import re
import sys
import urllib.request

from collector_covers import gather_media

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

FEED = "https://www.appinn.com/feed/"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) kankan-appinn-collector/1.0"

_ITEM = re.compile(r"<item>(.*?)</item>", re.S)
_TITLE = re.compile(r"<title>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</title>", re.S)
_CAT = re.compile(r"<category>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</category>", re.S)
# 非成品帖（appinn feed 混了新闻/补丁/自家榜单）——按分类跳过，只留真软件/应用推荐。
_SKIP_CAT = re.compile(r"业界消息|每日发现|热门排行榜|周二补丁|赛博领鸡蛋|资讯|新闻")
_LINK = re.compile(r"<link>(.*?)</link>", re.S)
_BODY = re.compile(r"<content:encoded>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</content:encoded>", re.S)
_HREF = re.compile(r'href=["\'](https?://[^"\']+)["\']', re.I)
_IMG = re.compile(r'<img[^>]+src=["\']([^"\']+)["\']', re.I)
_TAG = re.compile(r"<[^>]+>")
# 正文里要跳过的"非官方"外链：appinn 自身/社交/统计。
_SKIP_LINK = re.compile(r"appinn\.(com|net)|t\.me|twitter\.com|x\.com|facebook\.com|weibo\.com|/feed|utm_", re.I)


def _get(url: str, timeout: int = 20) -> str | None:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read().decode("utf-8", "replace")
    except Exception:
        return None


def _clean(s: str) -> str:
    return html.unescape(_TAG.sub("", s)).strip()


def _official_link(body: str) -> str | None:
    for h in _HREF.findall(body):
        h = html.unescape(h)
        if not _SKIP_LINK.search(h):
            return h
    return None


def _body_images(body: str, n: int = 3) -> list[str]:
    """正文里的真实截图（多张，供多图展示）；跳过 avif/svg（Flutter/旧机支持差）。"""
    out: list[str] = []
    for src in _IMG.findall(body):
        s = html.unescape(src).strip()
        low = s.lower().split("?")[0]
        if low.endswith((".svg", ".avif")):
            continue
        if s.startswith("http") and s not in out:
            out.append(s)
        if len(out) >= n:
            break
    return out


def collect(limit: int) -> list[dict]:
    xml = _get(FEED)
    if not xml:
        print("拉不到 appinn feed", file=sys.stderr)
        return []
    items = _ITEM.findall(xml)
    print(f"小众软件 feed：{len(items)} 篇，取前 {limit} 篇…")

    out: list[dict] = []
    seen = set()
    for raw in items:
        if len(out) >= limit:
            break
        # 分类过滤：跳过新闻/补丁/榜单这类非成品帖。
        if any(_SKIP_CAT.search(c) for c in _CAT.findall(raw)):
            continue
        t = _TITLE.search(raw)
        l = _LINK.search(raw)
        b = _BODY.search(raw)
        if not (t and l):
            continue
        title = html.unescape(t.group(1)).strip()
        article = l.group(1).strip()
        body = b.group(1) if b else ""
        if article in seen:
            continue
        seen.add(article)

        official = _official_link(body)
        if not official:
            continue  # 找不到真实产品链接就不收——不拿 appinn 介绍页当「去用」入口（用户明确）。
        excerpt = _clean(body)[:500]
        text = title if not excerpt else f"{title}。{excerpt}"
        media = gather_media(official, 3, extra=_body_images(body, 3))
        if not media:
            continue  # 不拿官网截图/空封面凑数
        out.append({
            "source_url": article,   # appinn 文章页仅作去重键（不展示、不当 try_url）
            "title": title[:80],
            "text": text[:2000],
            "source_platform": "appinn",
            "content_kind": "project",
            "try_url": official,     # 真实产品链接（官网 / github / steam …）
            "language": "zh-CN",
            # 多图：正文真实截图（排前）+ 产品页 og/截图，像小红书多图，不再一封面一段文字。
            "media": media,
        })
    n_cover = sum(1 for it in out if it.get("media"))
    print(f"产出 {len(out)} 条（{n_cover} 条有封面）。")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="小众软件 appinn 采集器 → 标准条目 JSON")
    ap.add_argument("-o", "--out", default="items_appinn.json")
    ap.add_argument("--limit", type=int, default=20)
    args = ap.parse_args()
    items = collect(args.limit)
    if not items:
        return 1
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=2)
    print(f"写出 {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
