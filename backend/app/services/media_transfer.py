# ============================================================
# 这个文件是干什么的：媒体转存——把外部平台（小红书/抖音…）的图/视频**下载到我们自己的存储**
#   （本地 /uploads 或 OSS），替换掉原始外链。因为各平台 CDN 有**防盗链**（校验 Referer），
#   App 直接引用原链会裂图/被拒；转存后用我们自己的 URL，稳定可控、也符合"不热链"原则。
# 它对应产品里的什么功能：approve 候选→建项目时，把抓来的媒体落到自己盘（PIPELINE_PLAN 决策4）。
# 如果它出错了：图显不出（转存失败会跳过该图，不阻断 approve——缺图好过整条挂掉）。
#
# 平台可扩展：加一个平台，只需在 _PLATFORM_HEADERS 里加一行它的 Referer（关键防盗链头）。
# ============================================================
import logging
import os
import tempfile
import uuid
from typing import Optional

import httpx

from app.services.storage import save_media_file

logger = logging.getLogger("app.media_transfer")

# 转存下载可走代理：国内服务器直连 GitHub raw / HuggingFace / mshots 常被墙/限速，
# 转存大面积失败（见运维记录）。配 MEDIA_PROXY=http://host:port 让**转存下载**走代理，
# 只作用于本模块的下载 client，不影响 DeepSeek/短信等其它出网（那些要直连国内）。
_MEDIA_PROXY = os.environ.get("MEDIA_PROXY", "").strip() or None


def _make_client() -> httpx.Client:
    """建下载用 httpx client。配了 MEDIA_PROXY 就走代理（兼容 httpx 新老版本的 proxy/proxies 参数）。"""
    kw = dict(timeout=30.0, follow_redirects=True, trust_env=True)
    if _MEDIA_PROXY:
        try:
            return httpx.Client(proxy=_MEDIA_PROXY, **kw)      # httpx >= 0.26
        except TypeError:
            return httpx.Client(proxies=_MEDIA_PROXY, **kw)    # 老版本
    return httpx.Client(**kw)

_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
)

# 平台 → 下载媒体时附加的请求头（关键是 Referer，绕过各家 CDN 防盗链）。
# **新增平台就往这里加一行**（source_platform 用 ingestion 里的友好名，小写）。
_PLATFORM_HEADERS = {
    "xiaohongshu": {"Referer": "https://www.xiaohongshu.com/"},
    "douyin": {"Referer": "https://www.douyin.com/"},
    "kuaishou": {"Referer": "https://www.kuaishou.com/"},
    "bilibili": {"Referer": "https://www.bilibili.com/"},
    "weibo": {"Referer": "https://weibo.com/"},
    "zhihu": {"Referer": "https://www.zhihu.com/"},
    "github": {},  # GitHub 媒体无需 Referer
}

_EXT_BY_CT = {
    "image/jpeg": "jpg", "image/jpg": "jpg", "image/png": "png", "image/webp": "webp",
    "image/gif": "gif", "video/mp4": "mp4", "video/quicktime": "mov", "video/webm": "webm",
}
_IMG_EXT = {"jpg", "jpeg", "png", "webp", "gif"}
_VID_EXT = {"mp4", "mov", "webm"}
_MAX_BYTES = 80 * 1024 * 1024  # 单文件上限 80MB（防超大视频拖垮存储）


def _headers_for(platform: Optional[str]) -> dict:
    h = {"User-Agent": _UA}
    h.update(_PLATFORM_HEADERS.get((platform or "").lower(), {}))
    return h


def _guess_ext(content_type: str, url: str) -> str:
    ext = _EXT_BY_CT.get(content_type)
    if ext:
        return ext
    tail = url.split("?")[0].rsplit(".", 1)[-1].lower()
    if tail in _IMG_EXT or tail in _VID_EXT:
        return "jpg" if tail == "jpeg" else tail
    return "jpg"  # 兜底当图


def transfer_media(
    url: str, platform: Optional[str], media_type_hint: str = "image"
) -> Optional[dict]:
    """把外部媒体 url 下载（带平台 Referer 绕防盗链）→ 转存 storage → 返回
    {url: 我们的URL, media_type: image|video}。
    - 已是本地/相对 URL（非 http）：原样返回，不重复下载。
    - 下载/转存失败：返回 None（调用方跳过该条，不阻断 approve）。
    """
    if not url:
        return None
    if not url.startswith(("http://", "https://")):
        return {"url": url, "media_type": media_type_hint}  # 已是本地

    tmp = None
    try:
        # 配了 MEDIA_PROXY 走代理（绕 GFW），否则直连；trust_env 也让系统 HTTP(S)_PROXY 生效。
        with _make_client() as client:
            with client.stream("GET", url, headers=_headers_for(platform)) as r:
                r.raise_for_status()
                ct = r.headers.get("content-type", "").split(";")[0].strip().lower()
                ext = _guess_ext(ct, url)
                media_type = "video" if (ct.startswith("video/") or ext in _VID_EXT) else "image"
                fd, tmp = tempfile.mkstemp(suffix="." + ext)
                total = 0
                with os.fdopen(fd, "wb") as f:
                    for chunk in r.iter_bytes(65536):
                        total += len(chunk)
                        if total > _MAX_BYTES:
                            raise ValueError(f"媒体超过 {_MAX_BYTES} 字节上限，跳过")
                        f.write(chunk)
        if total < 512:  # 太小八成是错误页/占位
            raise ValueError("下载内容过小，疑似防盗链拦截页")
        filename = f"src_{uuid.uuid4().hex}.{ext}"
        new_url = save_media_file(tmp, filename)  # 移走 tmp（成功后 tmp 已不在）
        tmp = None
        return {"url": new_url, "media_type": media_type}
    except Exception as e:
        logger.warning("媒体转存失败 platform=%s url=%s err=%s", platform, url[:80], e)
        return None
    finally:
        if tmp and os.path.exists(tmp):
            try:
                os.remove(tmp)
            except OSError:
                pass


def transfer_candidate_media(media_items, platform: Optional[str]) -> list:
    """转存候选的一组媒体（media_json 的 items）。返回转存成功的条目列表
    [{url, media_type, thumbnail_url?}]；失败的自动跳过。"""
    out = []
    for item in media_items or []:
        if not isinstance(item, dict) or not item.get("url"):
            continue
        t = transfer_media(item["url"], platform, item.get("media_type", "image"))
        if t:
            if item.get("thumbnail_url"):
                thumbnail = transfer_media(item["thumbnail_url"], platform, "image")
                if thumbnail:
                    t["thumbnail_url"] = thumbnail["url"]
            out.append(t)
    return out
