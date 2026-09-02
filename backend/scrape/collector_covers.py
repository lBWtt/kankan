# ============================================================
# 这个文件是干什么的：采集器共用的**封面挑选**工具。核心诉求（用户明确）：项目封面别用
#   GitHub 的 opengraph 通用卡片（千篇一律的"仓库名+头像"），要**真实的项目演示图**——
#   优先仓库 README 里的第一张演示图（GIF 最佳，动态最抓人），抓不到才退回 og:image 通用卡。
# 谁用它：github_daily_collector / hellogithub_collector（HelloGitHub 自带截图优先，缺了走这里）。
# ============================================================
from __future__ import annotations

import html
import re
import urllib.request

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) kankan-cover/1.0"

# README 里要跳过的"非演示图"：徽章/图标/统计/许可证等。
_BADGE = re.compile(
    r"shields\.io|img\.shields|/badges?/|badge|travis|circleci|codecov|coveralls|"
    r"license|stars?|forks?|downloads|\.svg($|\?)|githubusercontent\.com/u/|"
    r"avatars\.githubusercontent|/icon|contrib\.rocks|contributors|star-history|"
    r"sponsor|/logo|wechat|weixin|qrcode|二维码|counter|visitor|moe-counter|/cmoe", re.I,
)
_MD_IMG = re.compile(r"!\[[^\]]*\]\(\s*<?([^)\s>]+)")
_HTML_IMG = re.compile(r"<img[^>]+src=[\"']([^\"']+)", re.I)
_OG = re.compile(
    r'<meta[^>]+(?:property|name)=["\'](?:og:image|twitter:image)["\'][^>]+content=["\']([^"\']+)', re.I)


def _get(url: str, timeout: int = 10) -> str | None:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read().decode("utf-8", "replace")
    except Exception:
        return None


def _gh_owner_repo(url: str):
    m = re.match(r"https?://github\.com/([^/]+)/([^/#?]+)", url)
    if not m:
        return None
    return m.group(1), re.sub(r"\.git$", "", m.group(2))


def github_readme_images(url: str) -> list[str]:
    """GitHub 仓库 → README 里的真实演示图**列表**（GIF 排前、去重、过滤徽章）。多图用，供多媒体展示。"""
    or_ = _gh_owner_repo(url)
    if not or_:
        return []
    owner, repo = or_
    readme = None
    branch = "HEAD"
    for br in ("HEAD", "master", "main"):
        readme = _get(f"https://raw.githubusercontent.com/{owner}/{repo}/{br}/README.md")
        if readme:
            branch = br
            break
    if not readme:
        return []

    cands: list[str] = []
    for m in _MD_IMG.finditer(readme):
        cands.append(m.group(1).strip())
    for m in _HTML_IMG.finditer(readme):
        cands.append(m.group(1).strip())

    def _abs(src: str) -> str | None:
        s = html.unescape(src).strip().strip('"\'')
        if not s or s.startswith("data:"):
            return None
        if _BADGE.search(s):
            return None
        if s.startswith("http"):
            return s
        # 相对路径 → raw.githubusercontent
        s = s.lstrip("./")
        if s.startswith("/"):
            s = s[1:]
        return f"https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{s}"

    resolved: list[str] = []
    for a in (_abs(c) for c in cands):
        if a and a not in resolved:
            resolved.append(a)
    # GIF 优先（动态最抓人）排前，其余保序。
    resolved.sort(key=lambda u: 0 if u.lower().split("?")[0].endswith(".gif") else 1)
    return resolved


def github_demo_image(url: str) -> str | None:
    """README 第一张演示图（GIF 优先）；无则 None。"""
    imgs = github_readme_images(url)
    return imgs[0] if imgs else None


_OG_DESC = re.compile(
    r'<meta[^>]+(?:property|name)=["\'](?:og:description|description|twitter:description)["\'][^>]+content=["\']([^"\']+)', re.I)


def og_image(url: str) -> str | None:
    body = _get(url)
    if not body:
        return None
    m = _OG.search(body)
    return html.unescape(m.group(1).strip()) if m else None


def og_description(url: str) -> str | None:
    body = _get(url)
    if not body:
        return None
    m = _OG_DESC.search(body)
    return html.unescape(m.group(1).strip()) if m else None


_PAGE_IMG = re.compile(r'<img[^>]+src=["\']([^"\']+)["\']', re.I)


def page_images(url: str, n: int = 3) -> list[str]:
    """网站落地页里的真实内容图（og 图 + 前几张大图），过滤图标/徽章/logo。供网站类多图。"""
    body = _get(url)
    if not body:
        return []
    out: list[str] = []
    ogm = _OG.search(body)
    if ogm:
        out.append(html.unescape(ogm.group(1).strip()))
    for m in _PAGE_IMG.finditer(body):
        s = html.unescape(m.group(1).strip())
        if not s.startswith("http"):
            continue
        low = s.lower().split("?")[0]
        if low.endswith((".svg", ".ico")) or _BADGE.search(s) or "icon" in low or "logo" in low or "sprite" in low or "avatar" in low:
            continue
        if s not in out:
            out.append(s)
        if len(out) >= n:
            break
    return out[:n]


def best_cover(url: str) -> str | None:
    """只返回源页真实媒体；没有成果 proof 就返回 None，绝不伪造官网截图。"""
    if "github.com/" in url:
        return github_demo_image(url) or og_image(url)
    return og_image(url)


def gather_media(url: str, n: int = 3, extra: list[str] | None = None) -> list[dict]:
    """收集 1~n 张媒体（比单封面丰富，像小红书多图，详情页出图廊）。
    github：README 多图（GIF 优先）；网站：og 图 + 页面实际内容图；`extra` 是采集器自带的
    成果图（如 appinn/HelloGitHub 正文截图）排最前。无真实图则返回空，调用方必须跳过。"""
    urls: list[str] = list(extra or [])
    if "github.com/" in url:
        urls += github_readme_images(url)
    else:
        urls += page_images(url, n)
    seen: list[str] = []
    for u in urls:
        if u and u not in seen:
            seen.append(u)
    return [{"url": u, "media_type": "image"} for u in seen[:n]]
