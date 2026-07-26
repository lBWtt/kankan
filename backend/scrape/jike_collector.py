# ============================================================
# 这个文件是干什么的：即刻（web.okjike.com/explore）采集器——用 Playwright 带登录态跑浏览器，
#   **拦截即刻 feed 的 API 响应**（干净 JSON，比抓 DOM 稳），把关于 AI 的动态转成本管线
#   「标准条目」JSON（content_kind=post），走：collector → collect --kind post → process(改写) → 审核 → App。
# 它对应产品里的什么功能：② 动态来源——抓即刻 AI 讨论，DeepSeek 用自己的话重讲一遍，马甲发出。
#
# 为什么拦 API 不抓 DOM：即刻 explore 是 SPA，内容由登录态背后的私有 API 渲染；直接抓 HTML
#   只有空壳。Playwright 监听 page 的 network 响应，抓到的是结构化 post 对象（正文/作者/图/赞），
#   即刻改版 DOM 也不影响。
#
# 跑在哪：即刻要 Playwright，本项目后端是 3.9，故用**已装好的 mediacrawler conda 环境**（3.11 + chromium）：
#   D:/conda/envs/mediacrawler/python.exe scrape/jike_collector.py -o items_jike.json --scrolls 8
#   首次加 --headful 扫码登录（登录态存 user_data_dir，之后免扫、可 headless）。
#
# 下一步（注意：动态**跳过 prefilter**——那是项目导向的粗筛，要图要外链，纯文字动态会被误砍）：
#   cd /f/kankan/backend
#   python -m app.pipeline collect items_jike.json --platform jike --kind post
#   AI_PROVIDER=deepseek DEEPSEEK_API_KEY=sk-xxx python -m app.pipeline process
# ============================================================
import argparse
import json
import os
import re
import sys
import time
from typing import Dict, List, Optional

# AI 相关关键词：explore 是泛内容，只留和 AI 沾边的动态（可用 --no-filter 关掉）。
AI_KEYWORDS = [
    "ai", "gpt", "chatgpt", "claude", "gemini", "大模型", "llm", "agent", "智能体",
    "prompt", "提示词", "midjourney", "stable diffusion", "sd", "comfyui", "aigc",
    "生成式", "文生图", "文生视频", "sora", "扣子", "coze", "deepseek", "通义", "文心",
    "vibe coding", "cursor", "copilot", "多模态", "具身",
]

EXPLORE_URL = "https://web.okjike.com/explore"
# 即刻 API 域名（feed 从这些域回 JSON；拦截响应时按域过滤）
API_HOSTS = ("okjike.com/api", "web-api.okjike.com", "api.ruguoapp.com")
MIN_LEN = 8    # 短帖是好动态（一两句就够），别过滤掉；只砍纯图无字/一个字的
MAX_LEN = 200  # 动态就是要短（一两句、三四行）；超过的多是小作文/长分析/项目展示，不当动态，砍掉


def _looks_like_post(obj: dict) -> bool:
    """一个 JSON 节点像不像即刻动态：有字符串 content，且带 user 或 type=*POST*。"""
    if not isinstance(obj, dict):
        return False
    if not isinstance(obj.get("content"), str):
        return False
    t = str(obj.get("type") or "")
    return ("user" in obj) or ("POST" in t.upper())


def _walk_posts(node, found: List[dict]) -> None:
    """递归扒 JSON 里所有像动态的节点（兼容 GraphQL/REST 各种包裹层，改版也不怕）。"""
    if isinstance(node, dict):
        if _looks_like_post(node):
            found.append(node)
        for v in node.values():
            _walk_posts(v, found)
    elif isinstance(node, list):
        for v in node:
            _walk_posts(v, found)


def _pic_urls(obj: dict) -> List[str]:
    pics = obj.get("pictures") or []
    urls = []
    for p in pics:
        if isinstance(p, dict):
            u = p.get("picUrl") or p.get("middlePicUrl") or p.get("thumbnailUrl") or p.get("url")
            if u:
                urls.append(u)
        elif isinstance(p, str):
            urls.append(p)
    return urls


def _post_id(obj: dict) -> Optional[str]:
    return obj.get("id") or obj.get("pk") or (obj.get("post") or {}).get("id")


def _to_item(obj: dict) -> Optional[dict]:
    content = (obj.get("content") or "").strip()
    if len(content) < MIN_LEN or len(content) > MAX_LEN:
        return None  # 太短没内容 / 太长是小作文——都不是好动态
    pid = _post_id(obj)
    # source_url 是查重键：有 id 用即刻帖链接，没 id 用内容哈希兜底（同内容不重复入池）。
    if pid:
        source_url = f"https://web.okjike.com/originalPost/{pid}"
    else:
        import hashlib
        source_url = f"jike://post/{hashlib.md5(content.encode('utf-8')).hexdigest()}"
    user = obj.get("user") or {}
    imgs = _pic_urls(obj)
    return {
        "source_url": source_url,
        "title": content[:40],                 # 即刻帖无标题，用正文前 40 字（ingestion 要求 title 非空）
        "text": content,
        "source_platform": "jike",
        "content_kind": "post",                # 明确走动态路径（collect 也建议 --kind post）
        "original_author_name": user.get("screenName") or user.get("username") or None,
        "media": [{"url": u, "media_type": "image"} for u in imgs],
        "engagement": {
            "likes": obj.get("likeCount") or 0,
            "collects": obj.get("collectCount") or obj.get("favoriteCount") or 0,
            "comments": obj.get("commentCount") or 0,
            "shares": obj.get("repostCount") or obj.get("shareCount") or 0,
        },
    }


def _is_ai(item: dict) -> bool:
    blob = (item["text"] or "").lower()
    return any(k in blob for k in AI_KEYWORDS)


def collect(out: str, scrolls: int, headful: bool, do_filter: bool, user_data_dir: str,
            dump_raw: Optional[str] = None) -> int:
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("没装 playwright。请用 mediacrawler 环境跑：\n"
              "  D:/conda/envs/mediacrawler/python.exe scrape/jike_collector.py ...", file=sys.stderr)
        return 1

    captured: List[dict] = []
    raw_dump: List[dict] = []  # --dump-raw：把拦到的原始 API JSON 存下来，供解析器校准

    def on_response(resp):
        url = resp.url
        if not any(h in url for h in API_HOSTS):
            return
        ctype = (resp.headers or {}).get("content-type", "")
        if "json" not in ctype:
            return
        try:
            data = resp.json()
        except Exception:
            return
        if dump_raw:
            raw_dump.append({"url": url, "data": data})
        _walk_posts(data, captured)

    with sync_playwright() as p:
        # 持久化上下文：登录态（cookie/localStorage）存 user_data_dir，扫码一次之后免登。
        ctx = p.chromium.launch_persistent_context(
            user_data_dir=user_data_dir,
            headless=not headful,
            viewport={"width": 1280, "height": 900},
        )
        page = ctx.pages[0] if ctx.pages else ctx.new_page()
        page.on("response", on_response)
        # 用 domcontentloaded（DOM 一就绪就返回）；即刻是 SPA、长连接不断，networkidle 永远不触发会超时。
        page.goto(EXPLORE_URL, wait_until="domcontentloaded", timeout=60000)

        if headful:
            print(">>> 浏览器已打开：请用手机即刻 App 扫码登录（最多等 3 分钟，登录后自动继续）...")
            # 轮询：登录后 explore 才加载 feed → 拦到 posts 就提前继续；1 分钟还没有就 reload 一次强制加载。
            reloaded = False
            for i in range(36):  # 36 × 5s = 180s
                page.wait_for_timeout(5000)
                if captured:
                    print(f"    已检测到 feed 加载（{len(captured)} 个节点），继续抓取…")
                    break
                if i == 12 and not reloaded:  # 约 1 分钟：登录后页面可能没自动刷 feed，reload 一下
                    reloaded = True
                    print("    还没抓到 feed，reload 一次页面…")
                    try:
                        page.reload(wait_until="domcontentloaded", timeout=30000)
                    except Exception:
                        pass

        for i in range(scrolls):
            page.mouse.wheel(0, 3000)
            page.wait_for_timeout(2500)  # 等 feed 下一页 API 回来被拦截
            print(f"  滚动 {i + 1}/{scrolls}，已抓到候选 {len(captured)} 个原始节点")
        ctx.close()

    # 去重 + 转标准条目 + AI 过滤
    items, seen = [], set()
    for obj in captured:
        it = _to_item(obj)
        if not it or it["source_url"] in seen:
            continue
        if do_filter and not _is_ai(it):
            continue
        seen.add(it["source_url"])
        items.append(it)

    with open(out, "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=2)
    if dump_raw:
        with open(dump_raw, "w", encoding="utf-8") as f:
            json.dump(raw_dump, f, ensure_ascii=False, indent=2)
        print(f"（调试）原始 API 响应已存 {len(raw_dump)} 条 → {dump_raw}")
    print(f"\n拦截 {len(captured)} 个节点 → 去重/过滤后 {len(items)} 条动态 → {out}")
    if not items:
        print("抓到 0 条：多半是即刻 API 字段和默认解析对不上。把上面 --dump-raw 的文件发我，我照真实结构改解析器。")
    print(f"下一步（动态跳过 prefilter）：python -m app.pipeline collect {out} --platform jike --kind post")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="即刻 explore 采集器（Playwright 拦 API）→ 动态标准条目")
    ap.add_argument("-o", "--out", default="items_jike.json")
    ap.add_argument("--scrolls", type=int, default=8, help="向下滚动几次（每次触发一页 feed）")
    ap.add_argument("--headful", action="store_true", help="显示浏览器（首次扫码登录用）")
    ap.add_argument("--no-filter", dest="do_filter", action="store_false", help="不按 AI 关键词过滤")
    ap.add_argument("--dump-raw", default=None,
                    help="把拦到的原始即刻 API JSON 存到该文件（抓 0 条时发我校准解析器）")
    ap.add_argument("--user-data-dir", default=os.path.abspath("./.jike_userdata"),
                    help="登录态持久化目录（扫码一次后复用）")
    args = ap.parse_args()
    return collect(args.out, args.scrolls, args.headful, args.do_filter, args.user_data_dir,
                   dump_raw=args.dump_raw)


if __name__ == "__main__":
    sys.exit(main())
