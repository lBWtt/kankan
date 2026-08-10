"""Export a read-only audit snapshot for exact second-batch source URLs."""
from __future__ import annotations

import argparse
from collections import Counter
import json
from statistics import median

from sqlalchemy import select

from app.core.db import SessionLocal
from app.models.candidate import CandidateContent


def distribution(values: list[int]) -> dict:
    return {
        "count": len(values),
        "min": min(values) if values else None,
        "median": median(values) if values else None,
        "max": max(values) if values else None,
        "buckets": {
            "<60": sum(value < 60 for value in values),
            "60-69": sum(60 <= value <= 69 for value in values),
            "70-81": sum(70 <= value <= 81 for value in values),
            ">=82": sum(value >= 82 for value in values),
        },
    }


def blocker(candidate: CandidateContent) -> str | None:
    if candidate.status == "pending_review":
        return None
    if candidate.is_work is False:
        return "非作品：" + (candidate.work_rejection_reason or "未给原因")
    if candidate.attraction_score is not None and candidate.attraction_score < 60:
        return "attraction < 60"
    if candidate.attraction_score is not None and candidate.attraction_score < 70:
        return "attraction 60-69（留候选池）"
    if not candidate.selected_proof_media:
        return "缺 selected_proof_media"
    if not candidate.experience_type or (
        not candidate.experience_url and not candidate.experience_content
    ):
        return "缺真实体验入口（小红书/抖音待人工补链）"
    return "其他发布闸字段不完整"


def card(candidate: CandidateContent) -> dict:
    raw = candidate.raw_json or {}
    proof = candidate.selected_proof_media or {}
    return {
        "id": str(candidate.id),
        "source_url": candidate.source_url,
        "status": candidate.status,
        "raw_title": raw.get("title"),
        "title": candidate.title,
        "title_candidates": candidate.title_candidates,
        "attraction_score": candidate.attraction_score,
        "value_score": candidate.value_score,
        "is_work": candidate.is_work,
        "proof": proof.get("url") if isinstance(proof, dict) else proof,
        "experience_type": candidate.experience_type,
        "experience_url": candidate.experience_url,
        "blocker": blocker(candidate),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="+", help="Standard item JSON files inside container")
    args = parser.parse_args()
    expected: dict[str, set[str]] = {}
    for path in args.files:
        with open(path, encoding="utf-8") as handle:
            for item in json.load(handle):
                expected.setdefault(item["source_platform"], set()).add(item["source_url"])
    urls = {url for values in expected.values() for url in values}
    with SessionLocal() as db:
        rows = db.execute(
            select(CandidateContent).where(CandidateContent.source_url.in_(urls))
        ).scalars().all()

    result = {"expected": len(urls), "found": len(rows), "platforms": {}}
    for platform, platform_urls in expected.items():
        group = [row for row in rows if row.source_url in platform_urls]
        attraction = [row.attraction_score for row in group if row.attraction_score is not None]
        value = [row.value_score for row in group if row.value_score is not None]
        ranked = sorted(group, key=lambda row: row.attraction_score or -1, reverse=True)
        result["platforms"][platform] = {
            "expected": len(platform_urls),
            "found": len(group),
            "statuses": dict(Counter(row.status for row in group)),
            "attraction": distribution(attraction),
            "value": distribution(value),
            "ge82": sum((row.attraction_score or 0) >= 82 for row in group),
            "blockers": dict(Counter(blocker(row) for row in group if blocker(row))),
            "representative_cards": [card(row) for row in ranked[:5]],
            "rejections": [card(row) for row in group if row.is_work is False][:5],
        }
    print(json.dumps(result, ensure_ascii=False, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
