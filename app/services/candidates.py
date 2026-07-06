# ============================================================
# 这个文件是干什么的：候选审核的核心业务规则——最关键的是 approve：把候选复制成
#   正式项目并发布（字段·API v1.3 §5.3），含发布准入把关和 ai_badge 阈值映射。
# 它对应产品里的什么功能：后台点"通过"按钮后，内容从候选池变成用户能刷到的项目。
# 如果它出错了，用户会看到什么现象：审核通过了但 App 里看不到内容（断供），
#   或不合格内容（纯单图无方法）漏发出去。
# ============================================================
import uuid
from datetime import datetime, timezone
from typing import List, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.errors import AppError
from app.models import CandidateContent, Project, ProjectMedia, User
from app.services.audit import log_admin_action
from app.services.publishing import attach_tags

# 这些状态允许 discard / park / 编辑；approved 和 discarded 是终态
ACTIONABLE_STATUSES = {"ai_collected", "ai_processed", "pending_review", "edited", "parked"}
# approve 比其它动作更严：ai_collected（刚抓回来、未经 AI 整理或人工编辑）不许直接发布——
# 必须先经 ai_processed/pending_review 或人工 edited，杜绝跳过整理流程把生料推上线。
APPROVABLE_STATUSES = {"ai_processed", "pending_review", "edited", "parked"}


def badge_for_score(score: Optional[int]) -> str:
    """决策B（项目总纲 §3）：≥80 high_potential；65-79 worth_a_look；其余 none。staff_pick 仅运营手动。"""
    if score is None:
        return "none"
    if score >= 80:
        return "high_potential"
    if score >= 65:
        return "worth_a_look"
    return "none"


def _as_list(value) -> list:
    """tags_json / media_json 兼容两种存法：直接列表，或 {"items"/"tags": [...]} 包一层。"""
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        for key in ("items", "tags"):
            if isinstance(value.get(key), list):
                return value[key]
    return []


def ensure_actionable(candidate: CandidateContent, action: str) -> None:
    if candidate.status not in ACTIONABLE_STATUSES:
        raise AppError(
            409,
            "CANDIDATE_INVALID_STATE",
            f"候选当前状态为 {candidate.status}，不允许执行 {action}",
            {"status": candidate.status},
        )


def ensure_approvable(candidate: CandidateContent) -> None:
    if candidate.status not in APPROVABLE_STATUSES:
        raise AppError(
            409,
            "CANDIDATE_INVALID_STATE",
            f"候选当前状态为 {candidate.status}，不允许 approve："
            "ai_collected 必须先经 AI 整理或人工编辑后才能发布",
            {"status": candidate.status},
        )


def check_publish_gate(candidate: CandidateContent) -> None:
    """发布准入（PRD §2.3 红线）+ 必填字段完整性，不满足全部列在 details 里一次性返回。"""
    problems: List[str] = []
    if not candidate.title or len(candidate.title) < 2:
        problems.append("title 缺失或过短（≥2 字）")
    if not candidate.tagline or len(candidate.tagline) < 5:
        problems.append("tagline 缺失或过短（≥5 字）")
    if not candidate.summary or len(candidate.summary) < 20:
        problems.append("summary 缺失或过短（≥20 字）")
    if not candidate.category:
        problems.append("category 缺失")
    if not candidate.domains:
        problems.append("domains 至少 1 个")
    if not candidate.cover_media_url:
        problems.append("封面缺失（PRD §8.5 主封面必填）")
    # 红线：tools≥1 或 description 含可复现说明（启发式：≥20 字视为有说明）；纯单图无方法不发布
    if not candidate.tools and not (candidate.description and len(candidate.description.strip()) >= 20):
        problems.append("准入不满足：tools≥1 或 description 含可复现方法说明（≥20 字）")
    if problems:
        raise AppError(409, "PUBLISH_GATE_FAILED", "发布准入不满足，不能通过", {"problems": problems})


def approve_candidate(db: Session, candidate: CandidateContent, admin: User) -> Project:
    """§5.3 复制 + 关联：候选 → 正式项目（published，hot_score=0），媒体/标签一并落表，回写 project_id。"""
    ensure_approvable(candidate)
    check_publish_gate(candidate)

    now = datetime.now(timezone.utc)
    project = Project(
        author_user_id=None,  # 外部内容无站内作者
        title=candidate.title,
        tagline=candidate.tagline,
        summary=candidate.summary,
        description=candidate.description,
        category=candidate.category,
        language=candidate.language,
        source_type=candidate.source_type,
        is_original=False,
        source_url=candidate.source_url,
        source_platform=candidate.source_platform,
        original_author_name=candidate.original_author_name,
        original_author_url=candidate.original_author_url,
        cover_media_url=candidate.cover_media_url,
        tools=candidate.tools or [],
        domains=candidate.domains or [],
        ai_badge=badge_for_score(candidate.ai_curation_score),
        ai_implementation_hint=candidate.ai_implementation_hint,
        target_users=candidate.target_users,
        use_cases=candidate.use_cases,
        status="published",
        hot_score=0,
        published_at=now,
    )
    db.add(project)
    db.flush()  # 拿到 project.id

    # 媒体：media_json 暂存 → project_media 落表
    for i, item in enumerate(_as_list(candidate.media_json)):
        if not isinstance(item, dict) or not item.get("url"):
            continue
        db.add(
            ProjectMedia(
                project_id=project.id,
                media_type=item.get("media_type", "image"),
                url=item["url"],
                thumbnail_url=item.get("thumbnail_url"),
                sort_order=i,
            )
        )

    # 标签：tags_json 拆解 → 字典表去重 + 关系表（与用户发布共用 attach_tags）
    attach_tags(db, project.id, _as_list(candidate.tags_json))

    candidate.status = "approved"
    candidate.project_id = project.id
    candidate.reviewed_by_user_id = admin.id
    candidate.reviewed_at = now

    log_admin_action(db, admin.id, "approve_candidate", "candidate", candidate.id,
                     {"project_id": str(project.id)})
    return project


def transition_candidate(
    db: Session, candidate: CandidateContent, admin: User, new_status: str, reason: Optional[str] = None
) -> None:
    """discard / park 共用的简单状态流转 + 留痕。"""
    ensure_actionable(candidate, new_status)
    candidate.status = new_status
    candidate.reviewed_by_user_id = admin.id
    candidate.reviewed_at = datetime.now(timezone.utc)
    log_admin_action(db, admin.id, f"{new_status}_candidate", "candidate", candidate.id,
                     {"reason": reason} if reason else None)
