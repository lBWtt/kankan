"""从生产候选表导出宪法 v1.1 第一批多源审核快照（只读）。"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime
import json
from statistics import median

from sqlalchemy import select

from app.core.db import SessionLocal
from app.models.candidate import CandidateContent


def buckets(values: list[int]) -> dict[str, int]:
    return {
        "<60": sum(v < 60 for v in values),
        "60-69": sum(60 <= v <= 69 for v in values),
        "70-81": sum(70 <= v <= 81 for v in values),
        ">=82": sum(v >= 82 for v in values),
    }


def distribution(values: list[int]) -> dict:
    return {
        "count": len(values), "min": min(values) if values else None,
        "median": median(values) if values else None, "max": max(values) if values else None,
        "buckets": buckets(values),
    }


def card(c: CandidateContent) -> dict:
    raw = c.raw_json or {}
    proof = c.selected_proof_media or {}
    return {
        "id": str(c.id), "status": c.status,
        "raw_title": raw.get("original_title") or raw.get("title"),
        "title": c.title, "title_candidates": c.title_candidates,
        "attraction_score": c.attraction_score, "value_score": c.value_score,
        "is_work": c.is_work, "work_rejection_reason": c.work_rejection_reason,
        "proof": proof.get("url") if isinstance(proof, dict) else proof,
        "experience_type": c.experience_type, "experience_url": c.experience_url,
    }


def blocker(c: CandidateContent) -> str | None:
    if c.status == "pending_review":
        return None
    if c.is_work is False:
        return "非作品：" + (c.work_rejection_reason or "未给原因")
    if c.attraction_score is not None and c.attraction_score < 60:
        return "attraction < 60"
    if c.attraction_score is not None and c.attraction_score < 70:
        return "attraction 60-69（留候选池）"
    if not c.selected_proof_media:
        return "缺 selected_proof_media"
    if not c.experience_type or (not c.experience_url and not c.experience_content):
        return "体验三件套不完整"
    return "其他发布闸字段不完整"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--platforms", nargs="+", required=True)
    ap.add_argument("--after", required=True, help="ISO-8601 UTC lower bound")
    args = ap.parse_args()
    after = datetime.fromisoformat(args.after.replace("Z", "+00:00"))
    with SessionLocal() as db:
        rows = db.execute(
            select(CandidateContent)
            .where(CandidateContent.source_platform.in_(args.platforms),
                   CandidateContent.created_at >= after)
            .order_by(CandidateContent.created_at)
        ).scalars().all()

    result = {"after": args.after, "total": len(rows), "platforms": {}}
    for platform in args.platforms:
        group = [c for c in rows if c.source_platform == platform]
        attraction = [c.attraction_score for c in group if c.attraction_score is not None]
        values = [c.value_score for c in group if c.value_score is not None]
        ranked = sorted(group, key=lambda c: (c.attraction_score is not None,
                                               c.attraction_score or -1), reverse=True)
        rejected = [c for c in group if c.is_work is False or c.status == "discarded"]
        result["platforms"][platform] = {
            "count": len(group), "statuses": dict(Counter(c.status for c in group)),
            "attraction": distribution(attraction), "value": distribution(values),
            "ge82": sum((c.attraction_score or 0) >= 82 for c in group),
            "blockers": dict(Counter(reason for c in group if (reason := blocker(c)))),
            "representative_cards": [card(c) for c in ranked[:3]],
            "rejections": [card(c) for c in rejected[:5]],
        }
    print(json.dumps(result, ensure_ascii=False, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
