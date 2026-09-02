# ============================================================
# 这个文件是干什么的：推特/X 采集器——用 Playwright 带登录态跑浏览器、**拦 X 搜索接口的 GraphQL 响应**
#   （干净 JSON，比抓 DOM 稳），把关于 Vibe Coding / AI 成果的英文帖转成本管线「标准条目」
#   （content_kind=project），走：collect → process(DeepSeek 翻译成中文+判成果/水+提体验链接) → 人工审 → 发布。
# 它对应产品里的什么功能：② 项目来源之一——X 上开发者晒的 AI 成果（干货多、常自带链接→体验入口好提）。
#
# 为什么自己写不用第三方库：跟 jike_collector 同思路，不引第三方包、可控；X 帖自带 expanded_url→try_url。
#
# 跑在 mediacrawler conda 环境（3.11 + chromium）：
#   D:/conda/envs/mediacrawler/python.exe scrape/x_collector.py --query "vibe coding" -o items_x.json --scrolls 12 --headful
#   首次 --headful 登录 X（登录态存 .x_userdata，之后免登、可 headless）。
#
# 下一步：
#   python -m app.pipeline collect items_x.json --platform x
#   AI_PROVIDER=deepseek DEEPSEEK_API_KEY=sk-xxx python -m app.pipeline process   # 翻译+判成果+提链接
#   → 人工审（管理员端）→ 发布
# ============================================================
import argparse
import json
import re
import sys
import time
import urllib.parse
from typing import List, Optional

# X 的搜索/时间线接口都走这些域的 GraphQL，拦响应按域过滤。
API_HOSTS = ("x.com/i/api/graphql", "twitter.com/i/api/graphql", "api.x.com", "api.twitter.com")
MIN_LEN = 20  # 太短的帖没料，不当项目

# 只留和 AI / vibe coding 沾边的（搜索已筛一道，这里再兜底；可 --no-filter 关）
AI_KEYWORDS = [
    "ai", "gpt", "claude", "cursor", "vibe coding", "vibecoding", "llm", "agent",
    "built with", "made with", "shipped", "prompt", "midjourney", "stable diffusion",
    "开源", "小程序", "做了", "app", "tool",
]


def _looks_like_tweet(obj: dict) -> bool:
    """一个 JSON 节点像不像一条推：有 full_text（推正文的字段）。"""
    return isinstance(obj, dict) and isinstance(obj.get("full_text"), str)


def _walk_tweets(node, found: List[dict]) -> None:
    """递归扒所有像推的节点（X GraphQL 嵌套很深，改版也不怕）。"""
    if isinstance(node, dict):
        if _looks_like_tweet(node):
            found.append(node)
        for v in node.values():
            _walk_tweets(v, found)
    elif isinstance(node, list):
        for v in node:
            _walk_tweets(v, found)


def _urls(legacy: dict) -> List[str]:
    out = []
    for u in (legacy.get("entities") or {}).get("urls", []) or []:
        eu = u.get("expanded_url") or u.get("url")
        if eu:
            out.append(eu)
    return out


def _media(legacy: dict) -> List[str]:
    ents = (legacy.get("extended_entities") or legacy.get("entities") or {}).get("media", []) or []
    out = []
    for m in ents:
        u = m.get("media_url_https") or m.get("media_url")
        if u:
            out.append(u)
    return out


def _try_url(urls: List[str]) -> Optional[str]:
    """体验入口：取第一个非 X 自身的外链（t.co 是短链、expanded_url 已是真链；排除指向推特自己的）。"""
    for u in urls:
        low = u.lower()
        if "twitter.com" in low or "x.com" in low or "t.co/" in low:
            continue
        if low.startswith("http"):
            return u
    return None


def _to_item(legacy: dict) -> Optional[dict]:
    text = (legacy.get("full_text") or "").strip()
    # 去掉推文尾部的 t.co 短链（正文里那种），保留可读文字
    text = re.sub(r"https?://t\.co/\w+", "", text).strip()
    if len(text) < MIN_LEN:
        return None
    tid = legacy.get("id_str") or legacy.get("id")
    if not tid:
        return None
    urls = _urls(legacy)
    imgs = _media(legacy)
    eng = {
        "likes": legacy.get("favorite_count") or 0,
        "collects": legacy.get("bookmark_count") or 0,
        "comments": legacy.get("reply_count") or 0,
        "shares": legacy.get("retweet_count") or 0,
    }
    return {
        "source_url": f"https://x.com/i/web/status/{tid}",
        "title": text[:40],
        "text": text,
        "source_platform": "x",
        "content_kind": "project",       # X 干货当项目
        "media": [{"url": u, "media_type": "image"} for u in imgs],
        "engagement": eng,
        "try_url_hint": _try_url(urls),  # 供审核参考；DeepSeek 也会自己从正文提
        "lang": legacy.get("lang"),
    }


def login_only(user_data_dir: str, proxy: Optional[str]) -> int:
    """只登录：开 x.com/home 让用户登，检测到主页时间线真的加载出来（＝登录成功）就存态退出。
    把「登录」（要人）和「抓取」（可 headless 无人）拆开——比在搜索页边等边抓稳得多。"""
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("没装 playwright。用 mediacrawler 环境跑。", file=sys.stderr)
        return 1
    got = {"n": 0}

    def on_response(resp):
        if any(h in resp.url for h in API_HOSTS):
            try:
                data = resp.json()
            except Exception:
                return
            found: List[dict] = []
            _walk_tweets(data, found)
            got["n"] += len(found)

    with sync_playwright() as p:
        ctx = p.chromium.launch_persistent_context(
            user_data_dir=user_data_dir, headless=False,
            viewport={"width": 1280, "height": 900},
            proxy={"server": proxy} if proxy else None,
        )
        page = ctx.pages[0] if ctx.pages else ctx.new_page()
        page.on("response", on_response)
        page.goto("https://x.com/home", wait_until="domcontentloaded", timeout=60000)
        print(">>> 请在这个窗口登录 X（最多等 5 分钟）。检测到主页时间线加载出来＝登录成功，自动保存并退出…")
        for i in range(60):
            page.wait_for_timeout(5000)
            if got["n"] > 0:
                print(f"    ✓ 检测到已登录（主页时间线 {got['n']} 条），登录态已存 {user_data_dir}。")
                break
            if i % 6 == 5:
                print(f"    …还在等登录（{(i+1)*5}s）。登录后会自动继续。")
        else:
            print("    ⚠ 5 分钟内没检测到登录态。要么没登完，要么没登进这个窗口——可重试。")
        ctx.close()
    return 0 if got["n"] > 0 else 2


def collect(query: str, out: str, scrolls: int, headful: bool, do_filter: bool,
            latest: bool, user_data_dir: str, dump_raw: Optional[str],
            proxy: Optional[str] = None) -> int:
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("没装 playwright。用 mediacrawler 环境跑：\n"
              "  D:/conda/envs/mediacrawler/python.exe scrape/x_collector.py ...", file=sys.stderr)
        return 1

    captured: List[dict] = []
    raw_dump: List[dict] = []

    def on_response(resp):
        url = resp.url
        if not any(h in url for h in API_HOSTS):
            return
        # 拦所有 X GraphQL/API 响应（不只 SearchTimeline）——X 搜索的 operation 名会变，
        # 全拦 + 递归找 full_text 节点更稳；dump 也记全，好调试。
        try:
            data = resp.json()
        except Exception:
            return
        if dump_raw:
            raw_dump.append({"url": url[:120], "data": data})
        _walk_tweets(data, captured)

    f = "live" if latest else "top"
    search_url = f"https://x.com/search?q={urllib.parse.quote(query)}&src=typed_query&f={f}"
    seen_ops: set = set()

    # 把 op 名记进 on_response（诊断用：抓 0 时能看到到底走了哪些接口）
    _orig_walk = on_response

    def on_response(resp):  # noqa: F811
        m = re.search(r"/graphql/[^/]+/(\w+)", resp.url)
        if m:
            seen_ops.add(m.group(1))
        elif any(h in resp.url for h in API_HOSTS):
            seen_ops.add(resp.url.split("?")[0].split("/")[-1])
        _orig_walk(resp)

    with sync_playwright() as p:
        # X 国内被墙，chromium 必须走代理（Clash 默认 127.0.0.1:7890）。显式传给浏览器，
        # 不依赖系统代理/TUN——也就不会波及后端/模拟器（那些走 NO_PROXY）。--no-proxy 可关。
        ctx = p.chromium.launch_persistent_context(
            user_data_dir=user_data_dir, headless=not headful,
            viewport={"width": 1280, "height": 900},
            proxy={"server": proxy} if proxy else None,
        )
        page = ctx.pages[0] if ctx.pages else ctx.new_page()
        page.on("response", on_response)
        # 1) 先开首页确认登录态（首页时间线能抓到推＝已登录）。X 是重 SPA 用 domcontentloaded。
        page.goto("https://x.com/home", wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(4000)
        if not captured and headful:
            print(">>> 没检测到登录态，请在这个窗口登录 X（最多等 5 分钟，登录后自动继续）...")
            for i in range(60):
                page.wait_for_timeout(5000)
                if captured:
                    break
        if not captured:
            print("  ⚠ 首页没抓到时间线——可能没登录/被墙/无头被拦。诊断见下方。")

        # 2) 关键：用**搜索框真输入 + 回车**触发搜索（直接 goto /search 不会发 SearchTimeline）。
        captured.clear()  # 丢掉首页时间线，只保留搜索结果
        searched = False
        try:
            box = page.wait_for_selector('[data-testid="SearchBox_Search_Input"]', timeout=15000)
            box.click()
            box.fill(query)
            page.wait_for_timeout(800)
            box.press("Enter")
            searched = True
            print(f"  已在搜索框输入「{query}」并回车")
        except Exception as e:
            print(f"  搜索框没找到（{e}），回退直接 goto 搜索页…")
            try:
                page.goto(search_url, wait_until="domcontentloaded", timeout=30000)
            except Exception:
                pass
        page.wait_for_timeout(3500)
        # 切到 Latest（最新）标签——热门(Top)有时只给几条
        if searched and latest:
            try:
                page.get_by_role("tab", name=re.compile("Latest|最新")).click(timeout=5000)
                page.wait_for_timeout(2500)
            except Exception:
                pass

        # 3) 滚动抓取
        for i in range(scrolls):
            page.mouse.wheel(0, 3000)
            page.wait_for_timeout(2500)
            print(f"  滚动 {i + 1}/{scrolls}，已抓到候选 {len(captured)} 个原始节点")
        if not captured:
            print(f"  [诊断] 期间捕获的接口: {sorted(seen_ops) or '无'}")
            print(f"  [诊断] 当前页 URL: {page.url}")
        ctx.close()

    items, seen = [], set()
    for t in captured:
        it = _to_item(t)
        if not it or it["source_url"] in seen:
            continue
        if do_filter and not any(k in (it["text"] or "").lower() for k in AI_KEYWORDS):
            continue
        seen.add(it["source_url"])
        items.append(it)

    with open(out, "w", encoding="utf-8") as fp:
        json.dump(items, fp, ensure_ascii=False, indent=2)
    if dump_raw:
        with open(dump_raw, "w", encoding="utf-8") as fp:
            json.dump(raw_dump, fp, ensure_ascii=False, indent=2)
        print(f"（调试）原始 API 响应已存 {len(raw_dump)} 条 → {dump_raw}")
    print(f"\n拦截 {len(captured)} 个节点 → 去重/过滤后 {len(items)} 条 → {out}")
    if not items:
        print("抓到 0 条：X 字段可能和默认解析对不上，把 --dump-raw 的文件发我校准。")
    print(f"下一步：python -m app.pipeline collect {out} --platform x")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="推特/X 采集器（Playwright 拦搜索接口）→ 项目标准条目")
    ap.add_argument("--query", default="vibe coding", help="搜索词（X 搜一次一个 query）")
    ap.add_argument("-o", "--out", default="items_x.json")
    ap.add_argument("--scrolls", type=int, default=12)
    ap.add_argument("--headful", action="store_true", help="首次登录用")
    ap.add_argument("--latest", action="store_true", help="按最新(Latest)而非默认热门(Top)")
    ap.add_argument("--no-filter", dest="do_filter", action="store_false", help="不按 AI 关键词过滤")
    ap.add_argument("--dump-raw", default=None, help="存原始 API JSON（抓 0 条时发我校准）")
    ap.add_argument("--user-data-dir", default=None)
    ap.add_argument("--proxy", default="http://127.0.0.1:7890",
                    help="chromium 走的代理（X 被墙必须走；默认 Clash 7890）")
    ap.add_argument("--no-proxy", dest="proxy", action="store_const", const=None,
                    help="不走代理（已开 TUN/全局代理时用）")
    ap.add_argument("--login-only", action="store_true",
                    help="只开窗口登录 X 存登录态（不抓取）；之后可 headless 抓")
    args = ap.parse_args()
    import os
    try:  # Windows 控制台 GBK，⚠/✓/→ 会崩，强制 utf-8
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    udd = args.user_data_dir or os.path.abspath("./.x_userdata")
    if args.login_only:
        return login_only(udd, args.proxy)
    return collect(args.query, args.out, args.scrolls, args.headful, args.do_filter,
                   args.latest, udd, args.dump_raw, args.proxy)


if __name__ == "__main__":
    sys.exit(main())
