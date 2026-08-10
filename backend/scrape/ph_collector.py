# ============================================================
# 这个文件是干什么的：Product Hunt 采集器——从 PH 公开 Atom feed 抓「真人做出来、能直接去用」
#   的 AI/创作类成品，转成本管线「标准条目」JSON（content_kind=project），走：
#   collect → process(DeepSeek 翻译成中文+判成果+提体验链接) → 人工审 → 发布。
# 它对应产品里的什么功能：② 项目来源之一——PH 天生是「launch 了的成品 + 去用链接」，
#   契合 kankan「给别人去用」定位（验证过：try_url 覆盖 86%、成果率 75%，远超抖音/小红书）。
#
# 为什么直连不走代理：PH 直连可达（国内不用翻），而且——关键——**国区可达性过滤**就靠这个：
#   在本机（国区）直连解析产品官网，解析得到＝国区能打开；解析不到/被墙＝国区用户也够不着，丢。
#   另外硬丢美区 App Store / Google Play / TestFlight 链接（国区下不了，纯增门槛，见用户诉求）。
#
# 用法（backend/ 下，无需 key、无需代理）：
#   python scrape/ph_collector.py -o items_ph.json --limit 30
#   python -m app.pipeline collect items_ph.json --platform producthunt
#   AI_PROVIDER=deepseek DEEPSEEK_API_KEY=sk-xxx python -m app.pipeline process
#   → 人工审（管理员端）→ 发布
# ============================================================
from __future__ import annotations

import argparse
import html
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

FEED = "https://www.producthunt.com/feed"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) kankan-ph-collector/1.0"

# 国区高门槛链接：美区 App Store / Google Play(墙) / TestFlight / Chrome 商店(墙)——硬丢。
STORE_LOCKED = re.compile(
    r"apps\.apple\.com|itunes\.apple\.com|testflight\.apple\.com|"
    r"play\.google\.com|chromewebstore\.google\.com|chrome\.google\.com/webstore",
    re.I,
)
# 主题粗筛：AI / 创作 / 工具 / 开发相关（宁宽，最终由 DeepSeek 判成果/水）。
AI_HINT = re.compile(
    r"\bAI\b|agent|LLM|GPT|prompt|chat|gener|image|video|design|code|coding|"
    r"no-?code|app|tool|build|automat|assistant|model|voice|3d|avatar|creat|studio|edit",
    re.I,
)
_OG = {
    "image": re.compile(r'<meta[^>]+property=["\']og:image["\'][^>]+content=["\']([^"\']+)', re.I),
    "tw_image": re.compile(r'<meta[^>]+name=["\']twitter:image["\'][^>]+content=["\']([^"\']+)', re.I),
    "desc": re.compile(r'<meta[^>]+property=["\']og:description["\'][^>]+content=["\']([^"\']+)', re.I),
}


def _get(url: str, timeout: int = 15) -> str | None:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read().decode("utf-8", "replace")
    except Exception:
        return None


def _resolve(url: str, timeout: int = 12, hops: int = 5) -> str | None:
    """跟随 PH /r/ 跳转拿真实产品站 URL；直连（国区）成功＝国区可达。失败/没跳出去→None。
    手动跟 308/307（Py3.9 urllib 不自动跟 308，PH 部分 /r/ 就是 308，会漏掉真链接）。"""
    cur, seen = url, set()
    for _ in range(hops):
        if cur in seen:
            return None
        seen.add(cur)
        try:
            req = urllib.request.Request(cur, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                final = r.geturl()
            return None if "producthunt.com" in final else final
        except urllib.error.HTTPError as e:
            if e.code in (301, 302, 303, 307, 308):
                loc = e.headers.get("Location")
                if not loc:
                    return None
                cur = urllib.parse.urljoin(cur, loc)
                continue
            return None
        except Exception:
            return None
    return None


def _og_meta(page_html: str) -> tuple[str | None, str | None]:
    """从产品站 HTML 里取 og:image(封面) + og:description(补充正文)。"""
    if not page_html:
        return None, None
    img = _OG["image"].search(page_html) or _OG["tw_image"].search(page_html)
    desc = _OG["desc"].search(page_html)
    img_u = html.unescape(img.group(1).strip()) if img else None
    if img_u and img_u.startswith("//"):
        img_u = "https:" + img_u
    desc_t = html.unescape(desc.group(1).strip()) if desc else None
    return (img_u if (img_u or "").startswith("http") else None), desc_t


def parse_feed() -> list[dict]:
    xml = _get(FEED, timeout=20)
    if not xml:
        return []
    out = []
    for b in re.findall(r"<entry>(.*?)</entry>", xml, re.S):
        title = re.search(r"<title>(.*?)</title>", b, re.S)
        alt = re.search(r'<link rel="alternate"[^>]*href="([^"]+)"', b)
        published = re.search(r"<published>(.*?)</published>", b, re.S)
        content = re.search(r"<content[^>]*>(.*?)</content>", b, re.S)
        c = html.unescape(content.group(1)) if content else ""
        paras = re.findall(r"<p>(.*?)</p>", c, re.S)
        tagline = re.sub(r"<[^>]+>", "", paras[0]).strip() if paras else ""
        rlink = re.search(r'href="(https://www\.producthunt\.com/r/[^"]+)"', c)
        out.append({
            "title": (title.group(1).strip() if title else ""),
            "tagline": tagline,
            "ph_url": (alt.group(1) if alt else ""),
            "redirect": (rlink.group(1) if rlink else ""),
            "published_at": (published.group(1).strip() if published else None),
        })
    return out


def to_items(feed: list[dict], limit: int, verbose: bool) -> list[dict]:
    items = []
    dropped = {"no_link": 0, "store_locked": 0, "off_topic": 0, "no_cover": 0}
    for e in feed:
        if not e["title"] or not e["ph_url"]:
            continue
        if not AI_HINT.search(f"{e['title']} {e['tagline']}"):
            dropped["off_topic"] += 1
            continue
        try_url = _resolve(e["redirect"]) if e["redirect"] else None
        if not try_url:
            dropped["no_link"] += 1  # 没外链 / 国区解析不到 → 够不着，丢
            continue
        if STORE_LOCKED.search(try_url):
            dropped["store_locked"] += 1  # 美区商店/Play/TestFlight → 国区门槛，丢
            if verbose:
                print(f"  丢(商店锁区): {e['title'][:22]} → {try_url[:50]}")
            continue
        cover, og_desc = _og_meta(_get(try_url))  # 顺便再证一次国区可达
        text = e["tagline"]
        if og_desc and og_desc.lower() != e["tagline"].lower():
            text = f"{e['tagline']}。{og_desc}"
        item = {
            "source_url": e["ph_url"],
            "title": e["title"],
            "text": text[:2000],
            "source_platform": "producthunt",
            "content_kind": "project",
            "try_url": try_url,           # 确定性体验入口 → ingestion 落库 → 项目 try_url
            "language": "en-US",
            "published_at": e["published_at"],
        }
        if not cover:
            dropped["no_cover"] += 1
            continue  # v1.1：采集阶段补不到成果 proof，宁可不收
        item["media"] = [{"url": cover, "media_type": "image"}]
        items.append(item)
        if verbose:
            tag = "✓" if cover else "⚠无封面"
            print(f"  {tag} {e['title'][:22]:22} → {try_url[:46]}")
        if len(items) >= limit:
            break
    print(f"\n丢弃统计：{dropped}")
    return items


def main() -> int:
    ap = argparse.ArgumentParser(description="Product Hunt 采集器 → 管线标准条目（国区可达过滤）")
    ap.add_argument("-o", "--out", default="items_ph.json")
    ap.add_argument("--limit", type=int, default=30)
    ap.add_argument("-q", "--quiet", action="store_true")
    args = ap.parse_args()
    try:  # Windows 控制台默认 GBK，✓/→ 会崩；强制 utf-8 输出（含 pipeline_run 子进程调用）
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

    feed = parse_feed()
    print(f"PH Atom feed 抓到 {len(feed)} 条，逐条解析国区可达 + 主题过滤…")
    items = to_items(feed, args.limit, verbose=not args.quiet)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=2)
    n_cover = sum(1 for it in items if it.get("media"))
    print(f"\n输出 {len(items)} 条（{n_cover} 有封面）→ {args.out}")
    print(f"下一步：python -m app.pipeline collect {args.out} --platform producthunt")
    return 0


if __name__ == "__main__":
    sys.exit(main())
