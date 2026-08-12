"""Collect concrete vibe-coding works from Jike.

The Jike post is provenance only. A candidate is emitted only when the post
contains concrete outcome evidence. A real external work URL is preferred but
may be added later by a human; proof media is still mandatory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import re
import sys
from typing import Iterable, List, Optional
from urllib.parse import urlparse

from collector_covers import gather_media


EXPLORE_URL = "https://web.okjike.com/explore"
DEFAULT_KEYWORDS = "vibecoding,我做了个网站,我做了个APP,独立开发上线,用AI做了个"
API_HOSTS = ("okjike.com/api", "web-api.okjike.com", "api.ruguoapp.com")
OUTCOME_RE = re.compile(
    r"我(?:用|拿|让).{0,12}(?:做|搓|写|搭|开发)|我做了|做了个|做了一个|"
    r"一个人做|独立开发|周末做|我.{0,20}(?:上线|发布|开源)了|vibe\s*cod(?:ing|ed)|"
    r"做出来",
    re.I,
)
MATERIAL_RE = re.compile(
    r"教程|入门|课程|保姆级|怎么用|如何使用|提示词合集|新闻|融资|发布会|"
    r"盘点|周报|日报|快讯|观点|测评|接单|变现|副业|资料包|指南|如何组队|"
    r"全流程|安装|学习计划|训练营|如何|怎么用|方法|技巧",
    re.I,
)
URL_RE = re.compile(r"https?://[^\s<>\]\[()\"'，。；、]+", re.I)
BLOCKED_HOST_RE = re.compile(
    r"(^|\.)(?:okjike\.com|ruguoapp\.com|douyin\.com|iesdouyin\.com|"
    r"xiaohongshu\.com|xhslink\.com|bilibili\.com|youtube\.com|youtu\.be|"
    r"weibo\.com|weixin\.qq\.com)$",
    re.I,
)


def _looks_like_post(obj: dict) -> bool:
    return isinstance(obj, dict) and isinstance(obj.get("content"), str) and (
        "user" in obj or "POST" in str(obj.get("type") or "").upper()
    )


def _walk_posts(node, found: List[dict]) -> None:
    if isinstance(node, dict):
        if _looks_like_post(node):
            found.append(node)
        for value in node.values():
            _walk_posts(value, found)
    elif isinstance(node, list):
        for value in node:
            _walk_posts(value, found)


def _post_id(obj: dict) -> Optional[str]:
    return obj.get("id") or obj.get("pk") or (obj.get("post") or {}).get("id")


def _pic_urls(obj: dict) -> List[str]:
    urls: List[str] = []
    for picture in obj.get("pictures") or []:
        if isinstance(picture, str):
            value = picture
        elif isinstance(picture, dict):
            value = (
                picture.get("picUrl") or picture.get("middlePicUrl")
                or picture.get("thumbnailUrl") or picture.get("url")
            )
        else:
            value = None
        if value and value not in urls:
            urls.append(value)
    video = obj.get("video") or {}
    if isinstance(video, dict):
        for key in ("coverUrl", "thumbnailUrl", "picUrl"):
            value = video.get(key)
            if value and value not in urls:
                urls.append(value)
    return urls


def _external_urls(obj: dict) -> List[str]:
    candidates: List[str] = []
    for row in obj.get("urlsInText") or []:
        if isinstance(row, dict):
            candidates.extend([row.get("originalUrl"), row.get("url")])
        elif isinstance(row, str):
            candidates.append(row)
    candidates.extend(URL_RE.findall(obj.get("content") or ""))

    result: List[str] = []
    for value in candidates:
        value = str(value or "").strip().rstrip(".,;:!?)】）")
        if not value.startswith(("http://", "https://")):
            continue
        host = (urlparse(value).hostname or "").lower()
        if not host or BLOCKED_HOST_RE.search(host):
            continue
        if value not in result:
            result.append(value)
    return result


def _is_outcome(content: str) -> bool:
    return bool(OUTCOME_RE.search(content)) and not bool(MATERIAL_RE.search(content))


def _to_project_item(obj: dict) -> Optional[dict]:
    content = (obj.get("content") or "").strip()
    if len(content) < 8 or not _is_outcome(content):
        return None
    targets = _external_urls(obj)
    target = targets[0] if targets else None
    post_proof = _pic_urls(obj)
    # 有真实作品入口时同时核验作品页；没有入口时允许用即刻帖内成果图/视频封面先入池，
    # 标记待人工补链接。proof 仍是硬闸，纯文字自述不能进项目池。
    media = (
        gather_media(target, 3, extra=post_proof)
        if target else
        [{"url": url, "media_type": "image"} for url in post_proof[:3]]
    )
    if not media:
        return None

    post_id = _post_id(obj)
    source = (
        f"https://web.okjike.com/originalPost/{post_id}" if post_id else
        f"jike://post/{hashlib.md5(content.encode('utf-8')).hexdigest()}"
    )
    user = obj.get("user") or {}
    item = {
        "source_url": source,
        "title": content[:80],
        "text": content,
        "source_platform": "jike",
        "content_kind": "project",
        "original_author_name": user.get("screenName") or user.get("username") or None,
        "media": media,
        "engagement": {
            "likes": obj.get("likeCount") or 0,
            "collects": obj.get("collectCount") or obj.get("favoriteCount") or 0,
            "comments": obj.get("commentCount") or 0,
            "shares": obj.get("repostCount") or obj.get("shareCount") or 0,
        },
        "requires_manual_experience_url": not bool(target),
    }
    if target:
        item["try_url"] = target
    return item


def convert_posts(posts: Iterable[dict]) -> List[dict]:
    items: List[dict] = []
    seen = set()
    for post in posts:
        item = _to_project_item(post)
        if item and item["source_url"] not in seen:
            seen.add(item["source_url"])
            items.append(item)
    return items


def convert_raw(raw_path: str, out: str) -> int:
    with open(raw_path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
    posts: List[dict] = []
    _walk_posts(payload, posts)
    items = convert_posts(posts)
    with open(out, "w", encoding="utf-8") as handle:
        json.dump(items, handle, ensure_ascii=False, indent=2)
    print(f"raw nodes={len(posts)} -> concrete works={len(items)} -> {out}")
    return 0


def collect(out: str, scrolls: int, headful: bool, user_data_dir: str,
            dump_raw: Optional[str] = None, keywords: str = DEFAULT_KEYWORDS) -> int:
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("Playwright is required; use the MediaCrawler Python environment.", file=sys.stderr)
        return 1

    captured: List[dict] = []
    raw_dump: List[dict] = []

    def on_response(response):
        if not any(host in response.url for host in API_HOSTS):
            return
        if "json" not in (response.headers or {}).get("content-type", ""):
            return
        try:
            data = response.json()
        except Exception:
            return
        if dump_raw:
            raw_dump.append({"url": response.url, "data": data})
        _walk_posts(data, captured)

    with sync_playwright() as playwright:
        context = playwright.chromium.launch_persistent_context(
            user_data_dir=user_data_dir, headless=not headful,
            viewport={"width": 1280, "height": 900},
        )
        page = context.pages[0] if context.pages else context.new_page()
        page.on("response", on_response)
        page.goto(EXPLORE_URL, wait_until="domcontentloaded", timeout=60000)
        if headful:
            print("Browser opened. Log in to Jike if requested; collection starts when feed loads.")
            for _ in range(36):
                page.wait_for_timeout(5000)
                if captured:
                    break
        queries = [value.strip() for value in keywords.split(",") if value.strip()]
        for query in queries:
            search = page.locator("input").first
            search.wait_for(state="visible", timeout=30000)
            # 即刻会弹“为你推荐新内容”toast，可能短暂遮挡搜索框。focus 不走鼠标命中，
            # 再用键盘全选清空，既能避开浮层，也保持逐字输入的正常用户行为。
            search.focus()
            search.press("Control+A")
            search.press("Backspace")
            search.press_sequentially(query, delay=random.randint(70, 140))
            page.wait_for_timeout(random.randint(500, 1100))
            search.press("Enter")
            page.wait_for_timeout(random.randint(2200, 3600))
            for index in range(scrolls):
                page.mouse.wheel(0, random.randint(1700, 2800))
                page.wait_for_timeout(random.randint(1500, 2600))
            print(f"query={query!r}, captured nodes={len(captured)}")
        context.close()

    items = convert_posts(captured)
    with open(out, "w", encoding="utf-8") as handle:
        json.dump(items, handle, ensure_ascii=False, indent=2)
    if dump_raw:
        with open(dump_raw, "w", encoding="utf-8") as handle:
            json.dump(raw_dump, handle, ensure_ascii=False, indent=2)
    print(f"captured nodes={len(captured)} -> concrete works={len(items)} -> {out}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Jike concrete-work collector")
    parser.add_argument("-o", "--out", default="items_jike_projects.json")
    parser.add_argument("--from-raw", help="Convert an earlier raw API dump without logging in")
    parser.add_argument("--scrolls", type=int, default=8)
    parser.add_argument("--keywords", default=DEFAULT_KEYWORDS,
                        help="Comma-separated outcome-oriented search terms")
    parser.add_argument("--headful", action="store_true")
    parser.add_argument("--dump-raw")
    parser.add_argument("--user-data-dir", default=os.path.abspath("./.jike_userdata"))
    args = parser.parse_args()
    if args.from_raw:
        return convert_raw(args.from_raw, args.out)
    return collect(args.out, args.scrolls, args.headful, args.user_data_dir,
                   args.dump_raw, args.keywords)


if __name__ == "__main__":
    sys.exit(main())
