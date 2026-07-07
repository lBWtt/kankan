# ============================================================
# 这个文件是干什么的：AI 抓取管线的"进货口"——把外部抓回来的原始条目（标题/正文/链接/
#   作者/图片）查重后写进候选池，状态 ai_collected，等 AI 整理。
# 它对应产品里的什么功能：PRD §10 内容抓取流程的第一步"AI 收集候选"；
#   各平台抓取脚本只要产出统一的 JSON 条目，都从这里入池。
# 如果它出错了，用户会看到什么现象：App 新内容断供（抓回来的东西进不了审核流水），
#   或同一条内容反复出现在候选池里浪费审核人力。
# ============================================================
import re
from datetime import datetime, timezone
from typing import Dict, List, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import CandidateContent, Project

# 原始条目的标准形状（各平台抓取脚本对齐到这个形状即可入池）：
# {
#   "source_url": "https://...",          # 必填，也是查重键（红线：外部抓取来源链接必填）
#   "title": "原文标题",                   # 必填
#   "text": "原始正文/描述",               # 建议有，AI 整理的主要原料
#   "source_platform": "xiaohongshu",     # 平台名；缺省用 ingest 的 default_platform
#   "original_author_name": "...",        # 可选；拿不到则展示层标"原作者未识别"
#   "original_author_url": "...",         # 可选
#   "media": ["https://...jpg", ...]      # 可选；字符串或 {"url","media_type","thumbnail_url"}
#   "language": "zh-CN" / "en-US"         # 可选；缺省按正文是否含中文猜
# }

_CJK = re.compile(r"[一-鿿]")


def _guess_language(item: dict) -> str:
    text = f"{item.get('title') or ''} {item.get('text') or ''}"
    return "zh-CN" if _CJK.search(text) else "en-US"


def _normalize_media(raw_media) -> List[dict]:
    """把字符串/字典混排的媒体列表统一成 media_json 的条目形状（事实数据，入池时就定型）。"""
    items: List[dict] = []
    if not isinstance(raw_media, list):
        return items
    for m in raw_media:
        if isinstance(m, str) and m.strip():
            items.append({"url": m.strip(), "media_type": "image"})
        elif isinstance(m, dict) and m.get("url"):
            items.append({
                "url": m["url"],
                "media_type": m.get("media_type", "image"),
                **({"thumbnail_url": m["thumbnail_url"]} if m.get("thumbnail_url") else {}),
            })
    return items


def _existing_source_urls(db: Session, urls: List[str]) -> set:
    """同一条来源链接，候选池里有过或已是正式项目，都算重复（防审核人力浪费）。"""
    found = set(db.execute(
        select(CandidateContent.source_url).where(CandidateContent.source_url.in_(urls))
    ).scalars())
    found |= set(db.execute(
        select(Project.source_url).where(Project.source_url.in_(urls))
    ).scalars())
    return found


def ingest_raw_items(
    db: Session, items: List[dict], default_platform: Optional[str] = None
) -> Dict[str, int]:
    """原始条目批量入池。返回统计：{"ingested": n, "duplicate": n, "invalid": n}。
    单批内同链接也只收第一条。不在这里调用 AI——收集和整理分两步，抓取失败不影响整理重跑。"""
    stats = {"ingested": 0, "duplicate": 0, "invalid": 0}
    urls = [i.get("source_url") for i in items if isinstance(i, dict) and i.get("source_url")]
    seen = _existing_source_urls(db, urls) if urls else set()

    for item in items:
        if not isinstance(item, dict) or not item.get("source_url") or not item.get("title"):
            stats["invalid"] += 1
            continue
        url = item["source_url"].strip()
        if url in seen:
            stats["duplicate"] += 1
            continue
        seen.add(url)

        media = _normalize_media(item.get("media"))
        db.add(CandidateContent(
            status="ai_collected",
            source_type="ai_crawled",
            source_url=url,
            source_platform=(item.get("source_platform") or default_platform or None),
            original_author_name=item.get("original_author_name"),
            original_author_url=item.get("original_author_url"),
            language=item.get("language") or _guess_language(item),
            # 媒体是事实数据不需要 AI 生成：入池就定型；封面取第一张图
            cover_media_url=(media[0]["url"] if media else None),
            media_json={"items": media} if media else None,
            # 原料仓：原文标题/正文整理后也不删（PRD 外文处理要求保留原文标题）
            raw_json={
                "title": item["title"],
                "text": item.get("text") or "",
                "media": media,
                "fetched_at": datetime.now(timezone.utc).isoformat(),
            },
        ))
        stats["ingested"] += 1

    db.commit()
    return stats
