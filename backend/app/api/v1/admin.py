# ============================================================
# 这个文件是干什么的：全部后台管理接口的路由——候选池审核、项目管理（下架/恢复/软删/
#   要求修改/精选位）、需求看板、举报处理、数据看板、每日精选推送、操作日志，全部已实现。
# 它对应产品里的什么功能：运营后台所有页面（字段·API v1.3 §9）。
# 如果它出错了，用户会看到什么现象：用户不直接可见，但内容审核停摆 → App 新内容断供。
# ============================================================
import re
import uuid
from datetime import date, datetime, time as time_cls, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, insert, select, tuple_
from sqlalchemy.orm import Session

from app.api.deps import ERRORS_AUTHED, admin_required
from app.core.db import get_db
from app.core.errors import AppError
from app.core.pagination import decode_cursor, encode_cursor
from app.core.utils import parse_datetime_cursor, safe_like_pattern
from app.models import (
    AdminAction,
    AnalyticsEvent,
    CandidateContent,
    Feedback,
    HowToInterest,
    Notification,
    Project,
    PushPreference,
    Report,
    User,
)
from app.schemas.admin import (
    AdminActionItem,
    AdminProjectActionRequest,
    AdminProjectActionResponse,
    AdminProjectListItem,
    AdminProjectEditRequest,
    AdminReportItem,
    BulkCleanupResponse,
    BulkScoreCleanupRequest,
    CandidateApproveResponse,
    CandidateDetail,
    CandidateDiscardRequest,
    CandidateListItem,
    CandidateManualCreate,
    CandidateManualCreateResponse,
    CandidatePatch,
    DailyPickPushRequest,
    DailyPickPushResponse,
    DashboardFunnel,
    DashboardResponse,
    DemandBoardItem,
    FeatureRequest,
    PersonaContentResponse,
    PersonaListItem,
    PersonaPostItem,
    PersonaProjectItem,
    PersonaUpdateRequest,
    ReportResolveRequest,
    UsageSummary,
    ActiveUserItem,
)
from app.schemas.feedback import AdminFeedbackItem, AdminFeedbackHandleRequest
from app.schemas.project import HomeSlateResponse
from app.schemas.common import (
    CandidateStatus,
    ContentSourceType,
    Domain,
    Language,
    OkResponse,
    Page,
    ProjectStatus,
    ReportStatus,
)
from app.services.audit import log_admin_action
from app.services.candidates import (
    approve_candidate,
    approve_candidate_as_post,
    ensure_actionable,
    transition_candidate,
)
from app.services.ingestion import ingest_raw_items
from app.services.moderation import admin_delete_post, apply_project_action, set_featured_rank
from app.services.moderation import resolve_report as svc_resolve_report
from app.services.personas import is_persona, persona_recent_content, personas_with_stats
from app.services.projects import cards_from_projects_with_stats
from app.services.slate import home_slate

# 全部后台接口：需登录 + is_admin=true，否则 403 FORBIDDEN
router = APIRouter(prefix="/admin", tags=["后台"], dependencies=[Depends(admin_required)], responses=ERRORS_AUTHED)


def _get_candidate(db: Session, candidate_id: uuid.UUID) -> CandidateContent:
    cand = db.get(CandidateContent, candidate_id)
    if cand is None:
        raise AppError(404, "NOT_FOUND", "候选不存在")
    return cand


# ---------- 候选池（V0 已实现） ----------


@router.get(
    "/slate/preview",
    response_model=HomeSlateResponse,
    summary="人工预览内容宪法 v1.1 首页 slate",
)
def preview_home_slate(db: Session = Depends(get_db)):
    result = home_slate(db)
    return HomeSlateResponse(
        slate_id=result.slate_id,
        items=cards_from_projects_with_stats(db, result.projects),
        shortages=result.shortages,
    )


@router.get("/candidates", response_model=Page[CandidateListItem], summary="候选列表（筛选：状态/分数/风险/来源/语言）")
def list_candidates(
    status: Optional[CandidateStatus] = None,
    content_kind: Optional[str] = Query(None, description="project=只看项目 / post=只看动态"),
    min_score: Optional[int] = Query(None, ge=0, le=100),
    max_score: Optional[int] = Query(None, ge=0, le=100),
    has_risk: Optional[bool] = Query(None, description="true=只看带风险标记的"),
    source_platform: Optional[str] = None,
    language: Optional[Language] = None,
    q: Optional[str] = Query(None, max_length=80),
    cursor: Optional[str] = None,
    page_size: int = Query(20, ge=1, le=50),
    db: Session = Depends(get_db),
):
    stmt = select(CandidateContent)
    if status:
        stmt = stmt.where(CandidateContent.status == status.value)
    if content_kind in ("project", "post"):
        stmt = stmt.where(CandidateContent.content_kind == content_kind)
    if min_score is not None:
        stmt = stmt.where(CandidateContent.ai_curation_score >= min_score)
    if max_score is not None:
        stmt = stmt.where(CandidateContent.ai_curation_score <= max_score)
    # PG ARRAY 不能用 != []/== [] 判空(SQLAlchemy 翻译不可靠)；用 array_length：
    # 空数组 array_length(...,1) 返回 NULL，非空返回长度。
    if has_risk is True:
        stmt = stmt.where(func.array_length(CandidateContent.risk_flags, 1) > 0)
    elif has_risk is False:
        stmt = stmt.where(func.array_length(CandidateContent.risk_flags, 1).is_(None))
    if source_platform:
        stmt = stmt.where(CandidateContent.source_platform == source_platform)
    if language:
        stmt = stmt.where(CandidateContent.language == language.value)
    if q:
        # 使用 safe_like_pattern 转义特殊字符 % 和 _，防止模式注入
        stmt = stmt.where(CandidateContent.title.ilike(safe_like_pattern(q)))

    # 按 AI 评分排序：高分优先（无分的用 -1 沉底），同分再按新→旧。
    # 审核台默认让「最该发的」浮到最上面，边审边毙，效率最高（无分 = 还没 AI 打分，排最后）。
    score_key = func.coalesce(CandidateContent.ai_curation_score, -1)
    stmt = stmt.order_by(score_key.desc(), CandidateContent.created_at.desc(), CandidateContent.id.desc())
    if cursor:
        c_score_s, c_dt_s, c_id_s = decode_cursor(cursor, 3)
        c_score, c_dt, c_id = int(c_score_s), datetime.fromisoformat(c_dt_s), uuid.UUID(c_id_s)
        stmt = stmt.where(
            tuple_(score_key, CandidateContent.created_at, CandidateContent.id) < (c_score, c_dt, c_id)
        )

    rows = db.scalars(stmt.limit(page_size + 1)).all()
    has_more = len(rows) > page_size
    rows = rows[:page_size]
    next_cursor = (
        encode_cursor([
            str(rows[-1].ai_curation_score if rows[-1].ai_curation_score is not None else -1),
            rows[-1].created_at.isoformat(),
            str(rows[-1].id),
        ]) if has_more and rows else None
    )
    return Page[CandidateListItem](
        items=[CandidateListItem.model_validate(r) for r in rows], next_cursor=next_cursor, has_more=has_more
    )


@router.get("/candidates/{candidate_id}", response_model=CandidateDetail, summary="候选详情")
def get_candidate(candidate_id: uuid.UUID, db: Session = Depends(get_db)):
    return CandidateDetail.model_validate(_get_candidate(db, candidate_id))


@router.patch("/candidates/{candidate_id}", response_model=CandidateDetail, summary="编辑候选（状态自动→edited）")
def patch_candidate(
    candidate_id: uuid.UUID,
    body: CandidatePatch,
    admin: User = Depends(admin_required),
    db: Session = Depends(get_db),
):
    cand = _get_candidate(db, candidate_id)
    ensure_actionable(cand, "编辑")
    changes = body.model_dump(exclude_unset=True)
    quality_fields = {
        "title", "is_work", "work_form", "creator_type", "access_friction",
        "experience_type", "experience_url", "experience_content", "selected_proof_media",
        "title_candidates", "hook_clarity", "visual_impact", "surprise", "tryability",
        "shareability", "value_score",
    }
    overridden = {field: value for field, value in changes.items() if field in quality_fields}
    if overridden and not (changes.get("override_reason") or "").strip():
        raise AppError(422, "OVERRIDE_REASON_REQUIRED", "修改内容宪法字段必须填写 override_reason")
    for field, value in changes.items():
        setattr(cand, field, value.value if hasattr(value, "value") else value)
    if overridden:
        cand.human_override_json = {**(cand.human_override_json or {}), **overridden}
    if "experience_url" in changes:
        cand.try_url = cand.experience_url  # 旧客户端兼容
    elif "try_url" in changes:
        cand.experience_url = cand.try_url
    if "selected_proof_media" in changes:
        cand.cover_media_url = (cand.selected_proof_media or {}).get("url")
    score_fields = ("hook_clarity", "visual_impact", "surprise", "tryability", "shareability")
    if any(field in changes for field in score_fields) and all(getattr(cand, field) is not None for field in score_fields):
        cand.attraction_score = round(
            cand.hook_clarity * .25 + cand.visual_impact * .25 + cand.surprise * .20
            + cand.tryability * .15 + cand.shareability * .15
        )
        cand.ai_curation_score = cand.attraction_score
    cand.is_strong_visual = bool((cand.visual_impact or 0) >= 80 and cand.selected_proof_media)
    cand.is_direct_tryable = bool(
        (
            cand.experience_type in {"web", "video", "gallery", "game"}
            and cand.experience_url
        )
        or (
            cand.experience_type == "prompt_content"
            and cand.experience_content
        )
    )
    cand.status = "edited"  # 人工已改（PRD §8.4：发布前仍需 approve）
    log_admin_action(db, admin.id, "edit_candidate", "candidate", cand.id, {"fields": list(changes)})
    db.commit()
    db.refresh(cand)
    return CandidateDetail.model_validate(cand)


@router.post("/candidates/{candidate_id}/approve", response_model=CandidateApproveResponse, status_code=201,
             summary="通过：复制建项目并发布（§5.3）")
def approve(candidate_id: uuid.UUID, admin: User = Depends(admin_required), db: Session = Depends(get_db)):
    """准入不满足 → 409 PUBLISH_GATE_FAILED（details.problems 列全）；
    状态不允许（approved/discarded 终态）→ 409 CANDIDATE_INVALID_STATE。"""
    cand = _get_candidate(db, candidate_id)
    # 动态候选 → 建马甲发的动态；项目候选 → 复制建项目。二者返回不同 id。
    if cand.content_kind == "post":
        post = approve_candidate_as_post(db, cand, admin)
        db.commit()
        author = db.get(User, post.author_user_id)
        return CandidateApproveResponse(
            post_id=post.id,
            persona_name=author.nickname if author else None,
        )
    project = approve_candidate(db, cand, admin)
    db.commit()
    # 返回实际派到的马甲昵称（作者），让审核员知道发布后作者显示成谁。
    author = db.get(User, project.author_user_id) if project.author_user_id else None
    return CandidateApproveResponse(
        project_id=project.id,
        persona_name=author.nickname if author else None,
    )


@router.post("/candidates/{candidate_id}/discard", response_model=OkResponse, summary="不推荐（→discarded）")
def discard(
    candidate_id: uuid.UUID,
    body: CandidateDiscardRequest,
    admin: User = Depends(admin_required),
    db: Session = Depends(get_db),
):
    cand = _get_candidate(db, candidate_id)
    transition_candidate(db, cand, admin, "discarded", body.reason)
    db.commit()
    return OkResponse()


@router.post("/candidates/{candidate_id}/park", response_model=OkResponse, summary="暂存（→parked，补全端点）")
def park(candidate_id: uuid.UUID, admin: User = Depends(admin_required), db: Session = Depends(get_db)):
    cand = _get_candidate(db, candidate_id)
    transition_candidate(db, cand, admin, "parked")
    db.commit()
    return OkResponse()


@router.post("/candidates/bulk-discard", response_model=BulkCleanupResponse,
             summary="批量不推荐：把待审候选里 AI 分低于阈值的一次性毙掉（人为设阈值，先 dry_run 预览）")
def bulk_discard_candidates(
    body: BulkScoreCleanupRequest,
    admin: User = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """人为设分数、批量清理待审队列里的低分候选。可恢复（→discarded，非真删）。
    只动还在队列里的（pending_review/ai_processed/edited），不碰已 approve/已 parked/已 discarded。"""
    rows = db.scalars(select(CandidateContent).where(
        CandidateContent.status.in_(("pending_review", "ai_processed", "edited")),
        CandidateContent.ai_curation_score.isnot(None),
        CandidateContent.ai_curation_score < body.below_score,
    )).all()
    if body.dry_run:
        return BulkCleanupResponse(matched=len(rows), executed=False)
    done = 0
    for c in rows:
        try:
            transition_candidate(db, c, admin, "discarded", f"批量清理：AI 分 < {body.below_score}")
            db.commit()
            done += 1
        except Exception:
            db.rollback()
    return BulkCleanupResponse(matched=done, executed=True)


@router.post("/projects/bulk-take-down", response_model=BulkCleanupResponse,
             summary="批量下架：把已发布项目里（原候选）AI 分低于阈值的一次性下架（人为设阈值，先 dry_run 预览）")
def bulk_take_down_projects(
    body: BulkScoreCleanupRequest,
    admin: User = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """人为设分数、批量下架线上低分项目。分数来自原候选（candidate.project_id=project.id）；
    无关联候选的项目（如用户自建）不受影响。可恢复（take_down→taken_down，非真删）。"""
    ids = db.scalars(
        select(Project.id).distinct()
        .join(CandidateContent, CandidateContent.project_id == Project.id)
        .where(
            Project.status == "published",
            Project.deleted_at.is_(None),
            CandidateContent.ai_curation_score.isnot(None),
            CandidateContent.ai_curation_score < body.below_score,
        )
    ).all()
    if body.dry_run:
        return BulkCleanupResponse(matched=len(ids), executed=False)
    done = 0
    for pid in ids:
        try:
            apply_project_action(db, admin, pid, "take_down", f"批量清理：AI 分 < {body.below_score}")
            db.commit()
            done += 1
        except Exception:
            db.rollback()
    return BulkCleanupResponse(matched=done, executed=True)


def _fetch_og_best_effort(url: str) -> dict:
    """最佳努力抓页面 title / og:image / og:description，用于手动加链接时预填封面和标题。
    任何失败（超时/被墙/非 HTML）都吞掉返回空——手动加链接绝不因抓不到元数据而失败。"""
    try:
        import httpx  # 局部导入：只有手动加链接才用到，不拖慢常规接口

        r = httpx.get(
            url, timeout=6.0, follow_redirects=True,
            headers={"User-Agent": "Mozilla/5.0 (compatible; kankan-admin/1.0)"},
        )
        html = r.text[:200_000]

        def _meta(prop: str) -> Optional[str]:
            m = re.search(
                rf'<meta[^>]+(?:property|name)=["\']{prop}["\'][^>]+content=["\']([^"\']+)["\']',
                html, re.I,
            )
            if not m:  # content 可能在 property 之前
                m = re.search(
                    rf'<meta[^>]+content=["\']([^"\']+)["\'][^>]+(?:property|name)=["\']{prop}["\']',
                    html, re.I,
                )
            return m.group(1).strip() if m else None

        title = _meta("og:title")
        if not title:
            mt = re.search(r"<title[^>]*>([^<]+)</title>", html, re.I)
            title = mt.group(1).strip() if mt else None
        return {"title": title, "image": _meta("og:image"), "desc": _meta("og:description")}
    except Exception:
        return {}


@router.post("/candidates/manual", response_model=CandidateManualCreateResponse, status_code=201,
             summary="手动添加链接建候选（自己找到的链接入池，跑 AI 整理后进待审队列）")
def manual_add_candidate(
    body: CandidateManualCreate,
    admin: User = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """把自己找到的链接注入候选池（采集阶段，status=ai_collected）。链接本身作为 try_url「去体验」入口，
    最佳努力抓 og:title/og:image 预填标题与封面。之后跑 `python -m app.pipeline process` AI 整理
    → 进待审队列 → 审核发布（与采集内容同一条流水线）。链接已在候选池/已发布则不重复创建。"""
    url = body.url.strip()
    if not (url.startswith("http://") or url.startswith("https://")):
        raise AppError(422, "VALIDATION_FAILED", "请填写 http(s) 链接")

    og = _fetch_og_best_effort(url)
    # 封面：与采集器同一套 best_cover（github 链接优先仓库 README 真实演示图，GIF 最优先；否则 og 通用图），
    # 全流程固化——手动加的链接也不再拿到 GitHub 千篇一律的通用卡片。
    try:
        from scrape.collector_covers import best_cover
        cover = best_cover(url)
    except Exception:
        cover = og.get("image")
    title = (body.title or og.get("title") or url.split("//", 1)[-1].split("/", 1)[0]).strip()[:80]
    media = [{"url": cover, "media_type": "image"}] if cover else []
    item = {
        "source_url": url,
        "title": title or url[:80],
        "text": og.get("desc") or "",
        "source_platform": body.source_platform or "manual",
        "content_kind": body.content_kind,
        "try_url": url,   # 手动加的链接本身就是「去体验」入口（ingestion 存 known_try_url）
        "media": media,
    }
    stats = ingest_raw_items(db, [item], default_platform="manual", default_kind=body.content_kind)
    duplicate = stats.get("ingested", 0) == 0
    cand = db.scalar(
        select(CandidateContent)
        .where(CandidateContent.source_url == url)
        .order_by(CandidateContent.created_at.desc())
    )
    if cand is not None and not duplicate:
        cand.try_url = url  # try_url 列即时落地：AI 整理前也带着「去体验」
        log_admin_action(db, admin.id, "manual_add_candidate", "candidate", cand.id, {"url": url})
        db.commit()
    return CandidateManualCreateResponse(
        candidate_id=cand.id if cand else None,
        duplicate=duplicate,
        fetched_title=og.get("title"),
    )


# ---------- 已发布项目管理 ----------


@router.get("/projects", response_model=Page[AdminProjectListItem], summary="项目管理列表")
def admin_list_projects(
    status: Optional[ProjectStatus] = None,
    source_type: Optional[ContentSourceType] = None,
    q: Optional[str] = Query(None, max_length=80),
    cursor: Optional[str] = None,
    page_size: int = Query(20, ge=1, le=50),
    db: Session = Depends(get_db),
):
    """后台视角：软删的也能查（status 筛 deleted），report_count=该项目累计被举报次数。"""
    report_counts = (
        select(Report.project_id, func.count().label("n")).group_by(Report.project_id).subquery()
    )
    stmt = (
        select(Project, func.coalesce(report_counts.c.n, 0))
        .outerjoin(report_counts, report_counts.c.project_id == Project.id)
        .order_by(Project.created_at.desc(), Project.id.desc())
    )
    if status:
        stmt = stmt.where(Project.status == status.value)
    if source_type:
        stmt = stmt.where(Project.source_type == source_type.value)
    if q:
        # 使用 safe_like_pattern 转义特殊字符 % 和 _，防止模式注入
        stmt = stmt.where(Project.title.ilike(safe_like_pattern(q)))
    if cursor:
        c_dt, c_id = parse_datetime_cursor(cursor)
        stmt = stmt.where(tuple_(Project.created_at, Project.id) < (c_dt, c_id))

    rows = db.execute(stmt.limit(page_size + 1)).all()
    has_more = len(rows) > page_size
    rows = rows[:page_size]
    next_cursor = (
        encode_cursor([rows[-1][0].created_at.isoformat(), str(rows[-1][0].id)]) if has_more and rows else None
    )
    return Page[AdminProjectListItem](
        items=[
            AdminProjectListItem(
                id=p.id, title=p.title, status=p.status, source_type=p.source_type, category=p.category,
                author_user_id=p.author_user_id, featured_rank=p.featured_rank, hot_score=p.hot_score,
                report_count=n, published_at=p.published_at, created_at=p.created_at,
            )
            for p, n in rows
        ],
        next_cursor=next_cursor,
        has_more=has_more,
    )


def _project_action_route(action: str):
    """四个管理动作（下架/恢复/软删/要求修改）共用一个执行器，只差动作名。"""
    def handler(
        project_id: uuid.UUID,
        body: AdminProjectActionRequest,
        admin: User = Depends(admin_required),
        db: Session = Depends(get_db),
    ):
        project = apply_project_action(db, admin, project_id, action, body.reason)
        db.commit()
        return AdminProjectActionResponse(status=project.status)
    return handler


router.post("/projects/{project_id}/take-down", response_model=AdminProjectActionResponse,
            summary="下架（→taken_down，可恢复，通知作者）")(_project_action_route("take_down"))
router.post("/projects/{project_id}/restore", response_model=AdminProjectActionResponse,
            summary="恢复（taken_down/hidden/under_review→published）")(_project_action_route("restore"))
router.post("/projects/{project_id}/soft-delete", response_model=AdminProjectActionResponse,
            summary="删除（→deleted，软删；红线：与下架是两个状态）")(_project_action_route("soft_delete"))
router.post("/projects/{project_id}/require-edit", response_model=AdminProjectActionResponse,
            summary="要求修改（→under_review + 通知作者）")(_project_action_route("require_edit"))


@router.patch("/projects/{project_id}", response_model=OkResponse,
              summary="再剪辑：管理员改已发布项目的文案（标题/一句话/摘要/正文/体验链接）")
def admin_edit_project(
    project_id: uuid.UUID,
    body: AdminProjectEditRequest,
    admin: User = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """审核台对「已通过」的内容再编辑——直接改线上项目文案（不动所有权/媒体/状态）。"""
    p = db.get(Project, project_id)
    if p is None or p.deleted_at is not None:
        raise AppError(404, "NOT_FOUND", "项目不存在")
    changes = body.model_dump(exclude_unset=True)
    for field, value in changes.items():
        setattr(p, field, value)
    log_admin_action(db, admin.id, "edit_project", "project", p.id, changes)
    db.commit()
    return OkResponse()


@router.post("/projects/{project_id}/feature", response_model=OkResponse,
             summary="设置/取消今日精选（featured_rank，null=取消）")
def feature(
    project_id: uuid.UUID,
    body: FeatureRequest,
    admin: User = Depends(admin_required),
    db: Session = Depends(get_db),
):
    set_featured_rank(db, admin, project_id, body.featured_rank)
    db.commit()
    return OkResponse()


# ---------- 需求看板（只读聚合，§5.5）----------

_EXTERNAL_SOURCES = ("ai_crawled", "manual_import", "user_discovery")


@router.get("/demand-board", response_model=Page[DemandBoardItem], summary="需求看板：外部内容想看怎么做聚合")
def demand_board(
    domain: Optional[Domain] = None,
    source_type: Optional[ContentSourceType] = Query(None, description="默认含全部外部来源三类"),
    cursor: Optional[str] = None,
    page_size: int = Query(20, ge=1, le=50),
    db: Session = Depends(get_db),
):
    """MVP 只读（不建认领表）：按 project 聚合需求数降序，内容缺口信号。游标=（需求数,项目id）。"""
    agg = (
        select(
            HowToInterest.project_id.label("pid"),
            func.count().label("cnt"),
            func.max(HowToInterest.created_at).label("last_at"),
        )
        .group_by(HowToInterest.project_id)
        .subquery()
    )
    sources = (source_type.value,) if source_type else _EXTERNAL_SOURCES
    stmt = (
        select(Project, agg.c.cnt, agg.c.last_at)
        .join(agg, agg.c.pid == Project.id)
        .where(Project.source_type.in_(sources), Project.deleted_at.is_(None))
        # 排序：需求数降序，最后需求时间降序（第二排序键确保稳定性），项目 ID 降序（第三排序键）
        .order_by(agg.c.cnt.desc(), agg.c.last_at.desc(), Project.id.desc())
    )
    if domain:
        stmt = stmt.where(Project.domains.any(domain.value))
    if cursor:
        # 需求看板游标：(需求数, 最后需求时间, 项目id)——必须与 ORDER BY 的三个键完全对齐，
        # 否则需求数相同的项目会因 last_at 不同而被游标比较漏掉或重复（翻页丢条/重复）。
        cnt_s, last_at_s, id_s = decode_cursor(cursor, 3)
        try:
            c_cnt = int(cnt_s)
            c_last_at = datetime.fromisoformat(last_at_s)
            c_id = uuid.UUID(id_s)
        except ValueError:
            raise AppError(422, "VALIDATION_FAILED", "cursor 无效")
        stmt = stmt.where(tuple_(agg.c.cnt, agg.c.last_at, Project.id) < (c_cnt, c_last_at, c_id))

    rows = db.execute(stmt.limit(page_size + 1)).all()
    has_more = len(rows) > page_size
    rows = rows[:page_size]
    next_cursor = (
        encode_cursor([str(rows[-1][1]), rows[-1][2].isoformat(), str(rows[-1][0].id)])
        if has_more and rows else None
    )
    return Page[DemandBoardItem](
        items=[
            DemandBoardItem(
                project_id=p.id, title=p.title, cover_media_url=p.cover_media_url, source_type=p.source_type,
                source_platform=p.source_platform, domains=p.domains or [], demand_count=cnt, last_demand_at=last_at,
            )
            for p, cnt, last_at in rows
        ],
        next_cursor=next_cursor,
        has_more=has_more,
    )


# ---------- 举报处理 ----------


@router.get("/reports", response_model=Page[AdminReportItem], summary="举报列表")
def admin_list_reports(
    status: Optional[ReportStatus] = None,
    cursor: Optional[str] = None,
    page_size: int = Query(20, ge=1, le=50),
    db: Session = Depends(get_db),
):
    stmt = (
        select(Report, Project.title)
        .join(Project, Project.id == Report.project_id)
        .order_by(Report.created_at.desc(), Report.id.desc())
    )
    if status:
        stmt = stmt.where(Report.status == status.value)
    if cursor:
        c_dt, c_id = parse_datetime_cursor(cursor)
        stmt = stmt.where(tuple_(Report.created_at, Report.id) < (c_dt, c_id))

    rows = db.execute(stmt.limit(page_size + 1)).all()
    has_more = len(rows) > page_size
    rows = rows[:page_size]
    next_cursor = (
        encode_cursor([rows[-1][0].created_at.isoformat(), str(rows[-1][0].id)]) if has_more and rows else None
    )
    return Page[AdminReportItem](
        items=[
            AdminReportItem(
                id=r.id, project_id=r.project_id, project_title=title, reporter_user_id=r.reporter_user_id,
                reason=r.reason, description=r.description, status=r.status,
                handled_by_user_id=r.handled_by_user_id, handled_at=r.handled_at,
                resolution_note=r.resolution_note, created_at=r.created_at,
            )
            for r, title in rows
        ],
        next_cursor=next_cursor,
        has_more=has_more,
    )


@router.post("/reports/{report_id}/resolve", response_model=OkResponse, summary="处理举报（可连带项目动作）")
def resolve_report(
    report_id: uuid.UUID,
    body: ReportResolveRequest,
    admin: User = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """result=resolved（成立）/rejected（不成立）；连带动作复用项目管理的状态机（含作者通知与留痕）。"""
    svc_resolve_report(db, admin, report_id, body.result.value, body.project_action.value, body.note)
    db.commit()
    return OkResponse()


# ---------- 数据看板 / 推送 / 日志 ----------


@router.get("/dashboard", response_model=DashboardResponse, summary="数据看板（主信号漏斗）")
def dashboard(
    date_from: Optional[date] = Query(None, description="默认近 7 天"),
    date_to: Optional[date] = None,
    db: Session = Depends(get_db),
):
    """漏斗口径（补全决策）：曝光/点击/详情/线索页各事件取自埋点表（埋点接收端点不在本契约，
    客户端接入前为 0）；想看怎么做与线索订阅直接数子表（真实落库记录，不依赖埋点）。"""
    end = datetime.combine(date_to, time_cls.max, tzinfo=timezone.utc) if date_to else datetime.now(timezone.utc)
    start = (
        datetime.combine(date_from, time_cls.min, tzinfo=timezone.utc)
        if date_from else end - timedelta(days=7)
    )

    def events(name: str) -> int:
        return db.scalar(
            select(func.count()).select_from(AnalyticsEvent).where(
                AnalyticsEvent.event_name == name,
                AnalyticsEvent.created_at >= start,
                AnalyticsEvent.created_at <= end,
            )
        ) or 0

    def rows_in_window(model) -> int:
        return db.scalar(
            select(func.count()).select_from(model).where(model.created_at >= start, model.created_at <= end)
        ) or 0

    funnel = DashboardFunnel(
        card_impressions=events("card_impression"),
        card_clicks=events("card_click"),
        detail_views=events("detail_view"),
        how_to_interest_clicks=rows_in_window(HowToInterest),
        # H-API-3: 原来查 events("how_to_interest") 用未定义事件名 → 恒 0 → clue_downstream_rate 恒 0。
        # 改成查 how_to_interests 表（与 how_to_interest_clicks 同源）：点想看怎么做即打开线索页，
        # 以此作为线索页打开数的代理，clue_downstream_rate 才有意义的分母。
        clue_views=rows_in_window(HowToInterest),
        clue_source_clicks=events("clue_source_click"),
        clue_tool_clicks=events("clue_tool_click"),
        clue_related_clicks=events("clue_related_click"),
    )
    downstream = (
        funnel.clue_source_clicks + funnel.clue_tool_clicks + funnel.clue_related_clicks
    )
    return DashboardResponse(
        period_start=start,
        period_end=end,
        funnel=funnel,
        how_to_interest_rate=funnel.how_to_interest_clicks / funnel.detail_views if funnel.detail_views else 0,
        clue_downstream_rate=downstream / funnel.clue_views if funnel.clue_views else 0,
        published_projects=db.scalar(
            select(func.count()).select_from(Project).where(
                Project.status == "published", Project.deleted_at.is_(None))
        ) or 0,
        pending_candidates=db.scalar(
            select(func.count()).select_from(CandidateContent).where(
                CandidateContent.status == "pending_review")
        ) or 0,
        open_reports=db.scalar(
            select(func.count()).select_from(Report).where(Report.status.in_(("pending", "processing")))
        ) or 0,
    )


@router.post("/push/daily-pick", response_model=DailyPickPushResponse, summary="发每日精选推送")
def push_daily_pick(
    body: DailyPickPushRequest,
    admin: User = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """目标人群按 push_preferences.daily_pick_enabled 过滤（没设置过=默认开）。
    MVP 落为站内通知（设备推送通道接入是生产 TODO），返回触达人数。"""
    project = db.get(Project, body.project_id)
    if project is None or project.deleted_at is not None or project.status != "published":
        raise AppError(404, "NOT_FOUND", "项目不存在或未发布")

    opted_out = select(PushPreference.user_id).where(PushPreference.daily_pick_enabled.is_(False))
    title = body.title_override or "今日精选"
    notif_body = body.body_override or f"今天值得一看：《{project.title}》"
    # H-API-4: 原实现一次性 db.scalars(...).all() 把全量用户 ID 载入内存 → 用户量上去后 OOM。
    # 改成分批拉取（BATCH=5000）+ 分批 executemany 插入：单批内存常量级，百万级用户也不会爆。
    # offset 分页在此稳定：循环内只写 notifications 表，User 表无变更，偏移量不会错位。
    BATCH = 5000
    offset = 0
    total = 0
    while True:
        batch = db.scalars(
            select(User.id)
            .where(User.deleted_at.is_(None), User.id.notin_(opted_out))
            .offset(offset).limit(BATCH)
        ).all()
        if not batch:
            break
        db.execute(
            insert(Notification),
            [
                {"user_id": uid, "type": "daily_pick", "title": title,
                 "body": notif_body, "project_id": project.id}
                for uid in batch
            ],
        )
        total += len(batch)
        offset += BATCH
    log_admin_action(db, admin.id, "push_daily_pick", "project", project.id,
                     {"audience_count": total})
    db.commit()
    return DailyPickPushResponse(audience_count=total)


@router.get("/actions", response_model=Page[AdminActionItem], summary="操作日志")
def admin_actions(
    admin_user_id: Optional[uuid.UUID] = None,
    target_type: Optional[str] = Query(None, description="project / candidate / report / user"),
    cursor: Optional[str] = None,
    page_size: int = Query(20, ge=1, le=50),
    db: Session = Depends(get_db),
):
    stmt = select(AdminAction).order_by(AdminAction.created_at.desc(), AdminAction.id.desc())
    if admin_user_id:
        stmt = stmt.where(AdminAction.admin_user_id == admin_user_id)
    if target_type:
        stmt = stmt.where(AdminAction.target_type == target_type)
    if cursor:
        c_dt, c_id = parse_datetime_cursor(cursor)
        stmt = stmt.where(tuple_(AdminAction.created_at, AdminAction.id) < (c_dt, c_id))

    rows = db.scalars(stmt.limit(page_size + 1)).all()
    has_more = len(rows) > page_size
    rows = rows[:page_size]
    next_cursor = (
        encode_cursor([rows[-1].created_at.isoformat(), str(rows[-1].id)]) if has_more and rows else None
    )
    return Page[AdminActionItem](
        items=[
            AdminActionItem(
                id=a.id, admin_user_id=a.admin_user_id, action=a.action, target_type=a.target_type,
                target_id=a.target_id, detail=a.detail, created_at=a.created_at,
            )
            for a in rows
        ],
        next_cursor=next_cursor,
        has_more=has_more,
    )


# ---------- 意见反馈 ----------
@router.get("/feedback", response_model=Page[AdminFeedbackItem], summary="意见反馈列表")
def admin_list_feedback(
    status: Optional[str] = Query(None, description="new / handled"),
    cursor: Optional[str] = None,
    page_size: int = Query(20, ge=1, le=50),
    db: Session = Depends(get_db),
):
    stmt = select(Feedback).order_by(Feedback.created_at.desc(), Feedback.id.desc())
    if status:
        stmt = stmt.where(Feedback.status == status)
    if cursor:
        c_dt, c_id = parse_datetime_cursor(cursor)
        stmt = stmt.where(tuple_(Feedback.created_at, Feedback.id) < (c_dt, c_id))
    rows = db.scalars(stmt.limit(page_size + 1)).all()
    has_more = len(rows) > page_size
    rows = list(rows[:page_size])
    # 批量取提交者昵称（防 N+1）
    uids = {f.user_id for f in rows if f.user_id}
    names = (
        {u.id: u.nickname for u in db.scalars(select(User).where(User.id.in_(uids)))}
        if uids else {}
    )
    next_cursor = (
        encode_cursor([rows[-1].created_at.isoformat(), str(rows[-1].id)]) if has_more and rows else None
    )
    return Page[AdminFeedbackItem](
        items=[
            AdminFeedbackItem(
                id=f.id, category=f.category, content=f.content, contact=f.contact,
                app_version=f.app_version, platform=f.platform, device_info=f.device_info,
                source_page=f.source_page, error_code=f.error_code,
                status=f.status, user_id=f.user_id, user_nickname=names.get(f.user_id),
                admin_note=f.admin_note, created_at=f.created_at,
            )
            for f in rows
        ],
        next_cursor=next_cursor,
        has_more=has_more,
    )


@router.post("/feedback/{feedback_id}/handle", response_model=OkResponse, summary="标记反馈已处理")
def admin_handle_feedback(
    feedback_id: uuid.UUID,
    body: AdminFeedbackHandleRequest,
    admin: User = Depends(admin_required),
    db: Session = Depends(get_db),
):
    fb = db.get(Feedback, feedback_id)
    if fb is None:
        raise AppError(404, "NOT_FOUND", "反馈不存在")
    fb.status = "handled"
    fb.handled_by_user_id = admin.id
    fb.handled_at = datetime.now(timezone.utc)
    if body.note:
        fb.admin_note = body.note
    log_admin_action(db, admin.id, "handle_feedback", "feedback", fb.id,
                     {"note": body.note} if body.note else None)
    db.commit()
    return OkResponse()


# ---------- 马甲号统一管理（初期内容质量把控）----------


@router.get("/personas", response_model=List[PersonaListItem], summary="马甲号一览（含各自内容产出量）")
def list_personas(db: Session = Depends(get_db)):
    """全部马甲号 + 每个名下未删的项目/动态数、动态获赞、最近活跃。内容多的排前面。"""
    return [PersonaListItem(**row) for row in personas_with_stats(db)]


@router.get("/personas/{persona_id}/content", response_model=PersonaContentResponse,
            summary="某马甲最近的动态 + 项目（可逐条删）")
def get_persona_content(
    persona_id: uuid.UUID,
    limit: int = Query(30, ge=1, le=100),
    db: Session = Depends(get_db),
):
    user, posts, projects = persona_recent_content(db, persona_id, limit)
    if user is None:
        raise AppError(404, "NOT_FOUND", "马甲号不存在")
    # 该马甲的统计行（复用一览逻辑，避免各处口径不一）
    stats = next((r for r in personas_with_stats(db) if r["id"] == persona_id), None)
    persona = PersonaListItem(**stats) if stats else PersonaListItem(
        id=user.id, nickname=user.nickname, handle=user.handle, avatar_url=user.avatar_url, bio=user.bio,
    )
    return PersonaContentResponse(
        persona=persona,
        posts=[
            PersonaPostItem(
                id=p.id, content=p.content, tags=list(p.tags or []),
                quote_project_id=p.quote_project_id, like_count=p.like_count, created_at=p.created_at,
            )
            for p in posts
        ],
        projects=[
            PersonaProjectItem(
                id=pr.id, title=pr.title, status=pr.status, cover_media_url=pr.cover_media_url,
                hot_score=pr.hot_score, featured_rank=pr.featured_rank, created_at=pr.created_at,
            )
            for pr in projects
        ],
    )


@router.patch("/personas/{persona_id}", response_model=PersonaListItem, summary="改马甲：昵称/签名/头像")
def update_persona(
    persona_id: uuid.UUID,
    body: PersonaUpdateRequest,
    admin: User = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """后台改马甲的 昵称/签名/头像（只改传了的字段）。头像先 POST /media 拿 url 再传进来。
    只允许改马甲号（email 以 @persona.kankan 结尾）——防误改真实用户资料。昵称全局唯一。"""
    user = db.get(User, persona_id)
    if user is None or user.deleted_at is not None or not is_persona(user):
        raise AppError(404, "NOT_FOUND", "马甲号不存在")

    if body.nickname is not None:
        nick = body.nickname.strip()
        if not nick:
            raise AppError(422, "VALIDATION_FAILED", "昵称不能为空")
        clash = db.scalar(
            select(User).where(User.nickname == nick, User.id != user.id, User.deleted_at.is_(None))
        )
        if clash is not None:
            raise AppError(409, "CONFLICT", "昵称已被占用")
        user.nickname = nick
    if body.bio is not None:
        user.bio = body.bio.strip() or None
    if body.avatar_url is not None:
        user.avatar_url = body.avatar_url.strip() or None

    log_admin_action(db, admin.id, "update_persona", "user", user.id, {
        k: v for k, v in body.model_dump(exclude_none=True).items()
    })
    db.commit()
    stats = next((r for r in personas_with_stats(db) if r["id"] == user.id), None)
    return PersonaListItem(**stats) if stats else PersonaListItem(
        id=user.id, nickname=user.nickname, handle=user.handle,
        avatar_url=user.avatar_url, bio=user.bio,
    )


@router.delete("/posts/{post_id}", status_code=204, summary="删任意动态（管理员，含马甲/真实用户）")
def admin_delete_post_route(
    post_id: uuid.UUID,
    admin: User = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """后台软删动态——不限本人，用于统一管理马甲、清理违规内容（App 端删动态仍仅限本人）。"""
    admin_delete_post(db, admin, post_id)
    db.commit()


# ---------- 使用情况（真实用户 / 行为分析）----------
@router.get("/usage", response_model=UsageSummary, summary="使用情况：真实用户/DAU/活跃清单")
def admin_usage(days: int = Query(7, ge=1, le=90), db: Session = Depends(get_db)):
    """回答"到底有没有人用、是不是自嗨"：窗口内活跃用户、新增、DAU、活跃清单（含是否管理员）。
    真实用户口径排除马甲号（email 以 @persona.kankan 结尾）。"""
    now = datetime.now(timezone.utc)
    start = now - timedelta(days=days)
    today_start = datetime.combine(now.date(), time_cls.min, tzinfo=timezone.utc)
    real_user = ~func.coalesce(User.email, "").like("%@persona.kankan")

    total_users = db.scalar(
        select(func.count()).select_from(User).where(User.deleted_at.is_(None), real_user)
    ) or 0
    new_users = db.scalar(
        select(func.count()).select_from(User)
        .where(User.deleted_at.is_(None), real_user, User.created_at >= start)
    ) or 0
    active_users = db.scalar(
        select(func.count(func.distinct(AnalyticsEvent.user_id)))
        .where(AnalyticsEvent.user_id.isnot(None), AnalyticsEvent.created_at >= start)
    ) or 0
    dau_today = db.scalar(
        select(func.count(func.distinct(AnalyticsEvent.user_id)))
        .where(AnalyticsEvent.user_id.isnot(None), AnalyticsEvent.created_at >= today_start)
    ) or 0
    admin_active = db.scalar(
        select(func.count(func.distinct(AnalyticsEvent.user_id)))
        .select_from(AnalyticsEvent).join(User, User.id == AnalyticsEvent.user_id)
        .where(User.is_admin.is_(True), AnalyticsEvent.created_at >= start)
    ) or 0
    guest_opens = db.scalar(
        select(func.count()).select_from(AnalyticsEvent)
        .where(AnalyticsEvent.user_id.is_(None), AnalyticsEvent.event_name == "app_open",
               AnalyticsEvent.created_at >= start)
    ) or 0
    breakdown = db.execute(
        select(AnalyticsEvent.event_name, func.count())
        .where(AnalyticsEvent.created_at >= start)
        .group_by(AnalyticsEvent.event_name)
    ).all()

    rows = db.execute(
        select(AnalyticsEvent.user_id, func.count().label("c"),
               func.max(AnalyticsEvent.created_at).label("last"))
        .where(AnalyticsEvent.user_id.isnot(None), AnalyticsEvent.created_at >= start)
        .group_by(AnalyticsEvent.user_id)
        .order_by(func.max(AnalyticsEvent.created_at).desc())
        .limit(50)
    ).all()
    uids = [r.user_id for r in rows]
    users = {u.id: u for u in db.scalars(select(User).where(User.id.in_(uids)))} if uids else {}
    active_list = [
        ActiveUserItem(
            user_id=r.user_id,
            nickname=users[r.user_id].nickname if r.user_id in users else None,
            is_admin=bool(r.user_id in users and users[r.user_id].is_admin),
            event_count=r.c, last_active=r.last,
        )
        for r in rows
    ]
    return UsageSummary(
        period_start=start, period_end=now,
        total_users=total_users, new_users=new_users, active_users=active_users,
        admin_active=admin_active, dau_today=dau_today, guest_opens=guest_opens,
        event_breakdown={name: n for name, n in breakdown},
        active_list=active_list,
    )
