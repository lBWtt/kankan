"""内容宪法 v1.1 首页 slate 编排器：质量先过滤，再做十条组合约束。"""
from __future__ import annotations

import hashlib
from collections import Counter
from dataclasses import dataclass
from datetime import date
from typing import Iterable, List

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Project


POLICY_VERSION = "1.1"
SLATE_SIZE = 10


@dataclass
class SlateResult:
    projects: List[Project]
    slate_id: str
    shortages: List[str]


def _strong(p: Project) -> bool:
    return (p.attraction_score or 0) >= 82


def _valuable(p: Project) -> bool:
    return (p.value_score or 0) >= 70


def _restricted(p: Project) -> bool:
    return (p.source_platform or "").lower() == "github" or p.work_form in {"model", "workflow"}


def _platform_key(p: Project) -> str:
    return (p.source_platform or f"unknown:{p.id}").lower()


def _eligible(p: Project) -> bool:
    return bool(
        p.status == "published"
        and p.deleted_at is None
        and (p.attraction_score or 0) >= 70
        and (p.hook_clarity or 0) >= 60
        and p.selected_proof_media
        and p.work_form
        and p.creator_type
        and p.access_friction
        and p.experience_type
    )


def _composition_valid(items: List[Project]) -> bool:
    platforms = Counter(_platform_key(p) for p in items)
    forms = Counter(p.work_form for p in items)
    if any(n > 2 for n in platforms.values()) or any(n > 2 for n in forms.values()):
        return False
    if sum(1 for p in items if p.creator_type == "company") > 1:
        return False
    if sum(1 for p in items if not _strong(p)) > 4:
        return False
    if any(_restricted(a) and _restricted(b) for a, b in zip(items, items[1:])):
        return False
    if items:
        first = items[0]
        if not (_strong(first) and (first.hook_clarity or 0) >= 80 and (first.visual_impact or 0) >= 80):
            return False
    return True


def _tie(seed: str, p: Project) -> int:
    return int(hashlib.sha256(f"{seed}:{p.id}".encode()).hexdigest()[:12], 16)


def _candidate_score(p: Project, chosen: List[Project], seed: str) -> tuple:
    strong_n = sum(_strong(x) for x in chosen)
    direct_n = sum(bool(x.is_direct_tryable) for x in chosen)
    value_n = sum(_valuable(x) for x in chosen)
    visual_n = sum(bool(x.is_strong_visual) for x in chosen)
    diversity = 30 * (p.work_form not in {x.work_form for x in chosen})
    diversity += 20 * (_platform_key(p) not in {_platform_key(x) for x in chosen})
    quota = 220 * (_strong(p) and strong_n < 6)
    quota += 170 * (p.is_direct_tryable and direct_n < 4)
    quota += 130 * (_valuable(p) and value_n < 3)
    quota += 100 * (p.is_strong_visual and visual_n < 2)
    lower_penalty = -180 if not _strong(p) and strong_n < 6 else 0
    return (
        (p.attraction_score or 0) * 10 + (p.value_score or 0) + diversity + quota + lower_penalty,
        _tie(seed, p),
    )


def _can_append(chosen: List[Project], p: Project) -> bool:
    return _composition_valid([*chosen, p])


def _repair(chosen: List[Project], pool: List[Project]) -> List[Project]:
    """用未选内容替换尾部弱项，补齐四个最低配额，同时守住所有上限/相邻约束。"""
    requirements = (
        (lambda p: _strong(p), 6),
        (lambda p: bool(p.is_direct_tryable), 4),
        (_valuable, 3),
        (lambda p: bool(p.is_strong_visual), 2),
    )
    selected_ids = {p.id for p in chosen}
    for predicate, minimum in requirements:
        while sum(predicate(p) for p in chosen) < minimum:
            replacement = None
            for candidate in pool:
                if candidate.id in selected_ids or not predicate(candidate):
                    continue
                for index in range(len(chosen) - 1, 0, -1):
                    trial = list(chosen)
                    removed = trial[index]
                    trial[index] = candidate
                    if not _composition_valid(trial):
                        continue
                    # 不为补当前项破坏已经满足的其它最低配额。
                    if any(
                        sum(other(p) for p in chosen) >= needed
                        and sum(other(p) for p in trial) < needed
                        for other, needed in requirements
                    ):
                        continue
                    replacement = (index, removed, candidate)
                    break
                if replacement:
                    break
            if replacement is None:
                break
            index, removed, candidate = replacement
            chosen[index] = candidate
            selected_ids.remove(removed.id)
            selected_ids.add(candidate.id)
    return chosen


def _shortages(items: List[Project]) -> List[str]:
    checks = [
        (len(items), SLATE_SIZE, "总条数"),
        (sum(_strong(p) for p in items), 6, "attraction_score≥82"),
        (sum(bool(p.is_direct_tryable) for p in items), 4, "可直接玩/试/观看"),
        (sum(_valuable(p) for p in items), 3, "value_score≥70"),
        (sum(bool(p.is_strong_visual) for p in items), 2, "强视觉"),
    ]
    return [f"{label}缺{required - actual}" for actual, required, label in checks if actual < required]


def compose_slate(projects: Iterable[Project], *, seed: str = "") -> SlateResult:
    pool = [p for p in projects if _eligible(p)]
    pool.sort(key=lambda p: ((p.attraction_score or 0), (p.value_score or 0), _tie(seed, p)), reverse=True)
    anchors = [
        p for p in pool
        if _strong(p) and (p.hook_clarity or 0) >= 80 and (p.visual_impact or 0) >= 80
    ]
    chosen: List[Project] = [anchors[0]] if anchors else []
    selected_ids = {p.id for p in chosen}
    while len(chosen) < SLATE_SIZE:
        remaining_slots = SLATE_SIZE - len(chosen)
        strong_need = max(0, 6 - sum(_strong(p) for p in chosen))
        direct_need = max(0, 4 - sum(bool(p.is_direct_tryable) for p in chosen))
        value_need = max(0, 3 - sum(_valuable(p) for p in chosen))
        visual_need = max(0, 2 - sum(bool(p.is_strong_visual) for p in chosen))
        candidates = []
        for p in pool:
            if p.id in selected_ids or not _can_append(chosen, p):
                continue
            # 最后几个位置为尚未满足的配额留座。
            if strong_need >= remaining_slots and not _strong(p):
                continue
            if direct_need >= remaining_slots and not p.is_direct_tryable:
                continue
            if value_need >= remaining_slots and not _valuable(p):
                continue
            if visual_need >= remaining_slots and not p.is_strong_visual:
                continue
            candidates.append(p)
        if not candidates:
            break
        pick = max(candidates, key=lambda p: _candidate_score(p, chosen, seed))
        chosen.append(pick)
        selected_ids.add(pick.id)

    chosen = _repair(chosen, pool)
    digest = hashlib.sha256(
        f"{POLICY_VERSION}:{seed}:".encode() + ",".join(str(p.id) for p in chosen).encode()
    ).hexdigest()[:16]
    return SlateResult(chosen, f"slate-{POLICY_VERSION}-{digest}", _shortages(chosen))


def home_slate(db: Session, *, seed: str | None = None, pool_limit: int = 200) -> SlateResult:
    rows = db.scalars(
        select(Project)
        .where(
            Project.status == "published",
            Project.deleted_at.is_(None),
            Project.attraction_score >= 70,
        )
        .order_by(Project.attraction_score.desc(), Project.value_score.desc(), Project.published_at.desc())
        .limit(pool_limit)
    ).all()
    result = compose_slate(rows, seed=seed or date.today().isoformat())

    # 兜底补位：审核发布过的项目都该能被用户看到。slate 只负责首屏「精选排序」（前面几条），
    # 但历史上 79 个老项目没打吸引力分、进不了 slate；若 slate 太短，接口只返回几条，
    # 客户端(slate<10 就停)会把上百个已发布项目全藏起来（用户反馈「只剩几个」）。
    # 这里在精选之后追加最近发布的已发布项目（去重）补到 ≥ SLATE_SIZE，让接口返回够条数，
    # 新旧客户端都会继续下拉出全部。「不补位」只是不硬凑首屏精选，不是藏掉审核过的内容。
    if len(result.projects) < SLATE_SIZE:
        chosen_ids = {p.id for p in result.projects}
        fillers = db.scalars(
            select(Project)
            .where(Project.status == "published", Project.deleted_at.is_(None))
            .order_by(Project.published_at.desc(), Project.id.desc())
            .limit(SLATE_SIZE * 3)
        ).all()
        for p in fillers:
            if p.id in chosen_ids:
                continue
            result.projects.append(p)
            chosen_ids.add(p.id)
            if len(result.projects) >= SLATE_SIZE:
                break

    return result
