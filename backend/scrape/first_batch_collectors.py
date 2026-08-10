"""宪法 v1.1 第一批免登录源。

所有输出均为标准 item；体验入口始终是作品页，且无真实媒体即跳过。
国际源由调用者在本机设置 HTTPS_PROXY，国内源不设置代理。
"""
from __future__ import annotations

import argparse
import html
import json
import re
import sys
import time
import uuid
import urllib.parse
import urllib.request

from collector_covers import gather_media

UA = "Mozilla/5.0 kankan-v11-first-batch/1.0"
VIBE = re.compile(r"vibe.?cod|i (built|made)|side project|showcase|独立开发|做了个|小工具|小游戏", re.I)


def get_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=25) as r:
        return json.load(r)


def request_json(url: str, *, method: str = "GET", payload: dict | None = None,
                 headers: dict | None = None):
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8") if payload is not None else None
    base_headers = {"User-Agent": UA, "Accept": "application/json"}
    if body is not None:
        base_headers["Content-Type"] = "application/json"
    base_headers.update(headers or {})
    req = urllib.request.Request(url, data=body, method=method, headers=base_headers)
    with urllib.request.urlopen(req, timeout=35) as r:
        return json.load(r)


def item(*, source: str, target: str, title: str, text: str, platform: str,
         author: str | None = None, language: str = "en-US",
         extra_media: list[str] | None = None, engagement: dict | None = None) -> dict | None:
    if not target.startswith(("https://", "http://")):
        return None
    media = gather_media(target, 3, extra=extra_media)
    if not media:
        return None
    out = {"source_url": source, "try_url": target, "title": title[:80], "text": text[:2000],
           "source_platform": platform, "content_kind": "project", "language": language, "media": media}
    if author:
        out["original_author_name"] = author
    if engagement:
        out["engagement"] = engagement
    return out


def reddit(limit: int) -> list[dict]:
    out, seen = [], set()
    for sub in ("InternetIsBeautiful", "somethingimade", "SideProject"):
        try:
            data = get_json(f"https://www.reddit.com/r/{sub}/hot.json?limit={limit * 3}&raw_json=1")
        except Exception as exc:
            print(f"reddit/{sub}: {type(exc).__name__}: {exc}", file=sys.stderr)
            continue
        for child in data.get("data", {}).get("children", []):
            d = child.get("data", {})
            target = (d.get("url_overridden_by_dest") or "").strip()
            permalink = "https://www.reddit.com" + (d.get("permalink") or "")
            text = f"{d.get('title','')} {d.get('selftext','')}"
            if not target or "reddit.com" in target or target in seen or not VIBE.search(text):
                continue
            got = item(source=permalink, target=target, title=d.get("title") or "", text=text,
                       platform="reddit", author=d.get("author"),
                       engagement={"likes": d.get("score", 0), "comments": d.get("num_comments", 0)})
            if got:
                out.append(got); seen.add(target)
            if len(out) >= limit:
                return out
    return out


def huggingface(limit: int) -> list[dict]:
    out = []
    data = get_json(f"https://huggingface.co/api/spaces?limit={limit * 4}&sort=likes&direction=-1")
    for s in data:
        sid = s.get("id") or ""
        if not sid or s.get("private"):
            continue
        target = f"https://huggingface.co/spaces/{sid}"
        got = item(source=target, target=target, title=sid, text=(s.get("sdk") or "") + " interactive Space demo",
                   platform="huggingface", author=sid.split("/")[0])
        if got: out.append(got)
        if len(out) >= limit: break
    return out


def itch(limit: int) -> list[dict]:
    # itch 的公开最新页是具体游戏卡；只收带 playable/download 作品页且有 OG/内容图的条目。
    page = urllib.request.urlopen(urllib.request.Request("https://itch.io/games/new-and-popular", headers={"User-Agent": UA}), timeout=25).read().decode("utf-8", "replace")
    out, seen = [], set()
    for href, title in re.findall(r'<a[^>]+href="(https?://[^" ]+\.itch\.io/[^"/?#]+)"[^>]*>(.*?)</a>', page, re.S):
        target = html.unescape(href)
        if target in seen: continue
        clean_title = re.sub(r"<[^>]+>", "", html.unescape(title)).strip()
        if not clean_title:
            detail = urllib.request.urlopen(urllib.request.Request(target, headers={"User-Agent": UA}),
                                            timeout=25).read().decode("utf-8", "replace")
            tm = re.search(r'<meta[^>]+property=["\']og:title["\'][^>]+content=["\']([^"\']+)', detail, re.I)
            clean_title = html.unescape(tm.group(1)).strip() if tm else target.rstrip("/").rsplit("/", 1)[-1]
        got = item(source=target, target=target, title=clean_title,
                   text="独立创作者发布的可玩游戏", platform="itch", language="en-US")
        if got: out.append(got); seen.add(target)
        if len(out) >= limit: break
    return out


def modelscope(limit: int) -> list[dict]:
    """魔搭公开创空间。具体 Studio/独立演示域名就是作品，不把首页或模型列表当入口。"""
    endpoint = "https://www.modelscope.cn/api/v1/dolphin/studios"
    rows: list[dict] = []
    seen: set[str] = set()
    for page in range(1, 5):
        payload = {
            "PageSize": 24, "PageNumber": page,
            "SingleCriterion": [{"category": "is_published", "DateType": "int",
                                 "predicate": "equal", "IntValue": 1}],
            "SortBy": "Default",
        }
        data = request_json(endpoint, method="PUT", payload=payload,
                            headers={"Referer": "https://www.modelscope.cn/home?tab=studio"})
        studios = ((data or {}).get("Data") or {}).get("Studios") or []
        # 个人发布优先；组织作品仍交 DeepSeek 的“个人作品/公司原料”闸判断。
        studios.sort(key=lambda x: (x.get("Organization") is not None, -(x.get("Stars") or 0)))
        for s in studios:
            owner, name = (s.get("Path") or "").strip(), (s.get("Name") or "").strip()
            if not owner or not name or s.get("NeedLogin"):
                continue
            source = f"https://www.modelscope.cn/studios/{owner}/{name}"
            target = (s.get("IndependentUrl") or source).strip()
            if target in seen:
                continue
            cover = (s.get("CoverImage") or "").strip()
            got = item(source=source, target=target,
                       title=s.get("ChineseName") or name,
                       text=" ".join(filter(None, [s.get("Description"), s.get("ReadMeContent"), name])),
                       platform="modelscope", author=s.get("NickName") or s.get("CreatedBy") or owner,
                       language="zh-CN", extra_media=[cover] if cover else None,
                       engagement={"likes": s.get("Stars", 0), "views": s.get("Visits", 0)})
            if got:
                rows.append(got)
                seen.add(target)
            if len(rows) >= limit:
                return rows
    return rows


def liblibai(limit: int) -> list[dict]:
    """LiblibAI 公开搜索 API。只搜具体用途词并限定工作流类型，语义优劣交 DeepSeek。"""
    endpoint = "https://api2.liblib.art/api/www/model/search"
    intent_terms = ("产品精修", "图案提取", "照片修复", "背景替换", "排版设计", "风格转换")
    rows: list[dict] = []
    seen: set[str] = set()
    for term in intent_terms:
        webid = f"{int(time.time() * 1000)}kankan"
        payload = {
            "time": "", "keyword": term, "tagIds": [], "periodTime": ["all"],
            "models": [], "types": [], "vipType": [], "modelUsage": [],
            "modelLicense": [], "followed": 0, "liked": 0, "page": 1,
            "pageSize": 30, "cid": webid,
            "requestId": str(uuid.uuid4()), "imageUrl": "",
        }
        data = request_json(endpoint + f"?timestamp={int(time.time() * 1000)}",
                            method="POST", payload=payload, headers={
            "Origin": "https://www.liblib.art",
            "Referer": "https://www.liblib.art/", "webid": webid,
        })
        found = (((data or {}).get("data") or {}).get("data") or [])
        for m in found:
            # 18=传统 Comfy 工作流，21=当前站内“图片模板”（可在具体作品页直接体验）。
            if m.get("modelType") not in {18, 21}:
                continue
            mid = (m.get("uuid") or "").strip()
            if not mid or mid in seen:
                continue
            target = f"https://www.liblib.art/modelinfo/{mid}"
            images: list[str] = []
            for image in m.get("images") or []:
                u = image.get("imageUrl") or image.get("webpUrl")
                if u and u not in images:
                    images.append(u)
            if m.get("imageUrl") and m["imageUrl"] not in images:
                images.insert(0, m["imageUrl"])
            got = item(source=target, target=target, title=m.get("name") or term,
                       text=" ".join(filter(None, [m.get("modelTypeName"), m.get("description"),
                                                   m.get("versionDesc"), term])),
                       platform="liblibai", author=m.get("nickname"), language="zh-CN",
                       extra_media=images,
                       engagement={"likes": m.get("likeCount", 0),
                                   "downloads": m.get("downloadCount", 0),
                                   "runs": m.get("runCount", 0)})
            if got:
                rows.append(got)
                seen.add(mid)
            if len(rows) >= limit:
                return rows
    return rows


_SSPAI_INTENT = re.compile(r"我.{0,8}(做|开发|写|搭).{0,6}(一个|了|款)|独立开发|做了个", re.I)
_SSPAI_BLOCKED_HOST = re.compile(
    r"sspai\.com|weixin|weibo|xiaohongshu|bilibili|douyin|zhihu|miit|qq\.com|"
    r"apple\.com|google\.com|twitter|facebook|jolpi|openf1|f1db", re.I)


def sspai(limit: int) -> list[dict]:
    """少数派只作出处；正文里的作者官网/GitHub 才是体验入口，正文成果图作 proof。"""
    raw = urllib.request.urlopen(urllib.request.Request("https://sspai.com/feed", headers={"User-Agent": UA}),
                                 timeout=35).read().decode("utf-8", "replace")
    rows: list[dict] = []
    for block in re.findall(r"<item>(.*?)</item>", raw, re.S):
        tm = re.search(r"<title>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</title>", block, re.S)
        lm = re.search(r"<link>(.*?)</link>", block, re.S)
        if not tm or not lm:
            continue
        title = html.unescape(re.sub(r"<[^>]+>", "", tm.group(1))).strip()
        if not _SSPAI_INTENT.search(title):
            continue
        source = lm.group(1).strip()
        body = urllib.request.urlopen(urllib.request.Request(source, headers={"User-Agent": UA}),
                                      timeout=35).read().decode("utf-8", "replace")
        links: list[str] = []
        for u in re.findall(r"href=[\"'](https?://[^\"']+)", body, re.I):
            u = html.unescape(u).replace("\\/", "/")
            if not _SSPAI_BLOCKED_HOST.search(urllib.parse.urlparse(u).netloc) and u not in links:
                links.append(u)
        # 作者项目仓库优先；文档/API/依赖链接降级，避免把原料文档当作品。
        links.sort(key=lambda u: (0 if "github.com/" in u else 1,
                                  1 if re.search(r"/docs?|/api(?:/|$)", u, re.I) else 0))
        images = []
        for u in re.findall(r"https?[^\"' ]+\.(?:png|jpe?g|webp)(?:\?[^\"' ]*)?", body, re.I):
            u = html.unescape(u).replace("\\/", "/")
            if "/article/" in u and u not in images:
                images.append(u)
        if not links or not images:
            continue
        got = item(source=source, target=links[0], title=title, text=title,
                   platform="sspai", language="zh-CN", extra_media=images)
        if got:
            rows.append(got)
        if len(rows) >= limit:
            break
    return rows


def rss_site(feed: str, platform: str, limit: int) -> list[dict]:
    raw = urllib.request.urlopen(urllib.request.Request(feed, headers={"User-Agent": UA}), timeout=25).read().decode("utf-8", "replace")
    out = []
    for block in re.findall(r"<item>(.*?)</item>", raw, re.S):
        title = re.search(r"<title>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</title>", block, re.S)
        link = re.search(r"<link>(.*?)</link>", block, re.S)
        if not (title and link): continue
        t, source = html.unescape(title.group(1)).strip(), link.group(1).strip()
        # 国内策展帖不当体验入口：正文外链解析留给专用适配器；无可验证 target 就跳过。
        if platform == "sspai": continue
        got = item(source=source, target=source, title=t, text=t, platform=platform, language="zh-CN")
        if got: out.append(got)
        if len(out) >= limit: break
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("source", choices=["reddit", "huggingface", "itch", "modelscope", "liblibai", "sspai"])
    ap.add_argument("-o", "--out", required=True); ap.add_argument("--limit", type=int, default=10)
    a = ap.parse_args()
    if a.source == "reddit": rows = reddit(a.limit)
    elif a.source == "huggingface": rows = huggingface(a.limit)
    elif a.source == "itch": rows = itch(a.limit)
    elif a.source == "modelscope": rows = modelscope(a.limit)
    elif a.source == "liblibai": rows = liblibai(a.limit)
    else: rows = sspai(a.limit)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)
    print(f"{a.source}: {len(rows)} 条（均带作品入口+真实媒体）")
    return 0 if rows else 1

if __name__ == "__main__": raise SystemExit(main())
