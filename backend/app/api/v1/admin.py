# ============================================================
# 这个文件是干什么的：全部后台管理接口的路由——候选池审核、项目管理（下架/恢复/软删/
#   要求修改/精选位）、需求看板、举报处理、数据看板、每日精选推送、操作日志，全部已实现。
# 它对应产品里的什么功能：运营后台所有页面（字段·API v1.3 §9）。
# 如果它出错了，用户会看到什么现象：用户不直接可见，但内容审核停摆 → App 新内容断供。
# ============================================================
import uuid
from datetime import date, datetime, time as time_cls, timedelta, timezone
from typing import Optional

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
    ClueSubscription,
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
    AdminReportItem,
    CandidateApproveResponse,
    CandidateDetail,
    CandidateDiscardRequest,
    CandidateListItem,
    CandidatePatch,
    DailyPickPushRequest,
    DailyPickPushResponse,
    DashboardFunnel,
    DashboardResponse,
    DemandBoardItem,
    FeatureRequest,
    ReportResolveRequest,
)
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
from app.services.candidates import approve_candidate, ensure_actionable, transition_candidate
from app.services.moderation import apply_project_action, set_featured_rank
from app.services.moderation import resolve_report as svc_resolve_report

# 全部后台接口：需登录 + is_admin=true，否则 403 FORBIDDEN
router = APIRouter(prefix="/admin", tags=["后台"], dependencies=[Depends(admin_required)], responses=ERRORS_AUTHED)


def _get_candidate(db: Session, candidate_id: uuid.UUID) -> CandidateContent:
    cand = db.get(CandidateContent, candidate_id)
    if cand is None:
        raise AppError(404, "NOT_FOUND", "候选不存在")
    return cand


# ---------- 候选池（V0 已实现） ----------


@router.get("/candidates", response_model=Page[CandidateListItem], summary="候选列表（筛选：状态/分数/风险/来源/语言）")
def list_candidates(
    status: Optional[CandidateStatus] = None,
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
    if min_score is not None:
        stmt = stmt.where(CandidateContent.ai_curation_score >= min_score)
    if max_score is not None:
        stmt = stmt.where(CandidateContent.ai_curation_score <= max_score)
    if has_risk is True:
        stmt = stmt.where(CandidateContent.risk_flags != [])
    elif has_risk is False:
        stmt = stmt.where(CandidateContent.risk_flags == [])
    if source_platform:
        stmt = stmt.where(CandidateContent.source_platform == source_platform)
    if language:
        stmt = stmt.where(CandidateContent.language == language.value)
    if q:
        # 使用 safe_like_pattern 转义特殊字符 % 和 _，防止模式注入
        stmt = stmt.where(CandidateContent.title.ilike(safe_like_pattern(q)))

    stmt = stmt.order_by(CandidateContent.created_at.desc(), CandidateContent.id.desc())
    if cursor:
        c_dt, c_id = parse_datetime_cursor(cursor)
        stmt = stmt.where(tuple_(CandidateContent.created_at, CandidateContent.id) < (c_dt, c_id))

    rows = db.scalars(stmt.limit(page_size + 1)).all()
    has_more = len(rows) > page_size
    rows = rows[:page_size]
    next_cursor = (
        encode_cursor([rows[-1].created_at.isoformat(), str(rows[-1].id)]) if has_more and rows else None
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
    for field, value in changes.items():
        setattr(cand, field, value.value if hasattr(value, "value") else value)
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
    project = approve_candidate(db, cand, admin)
    db.commit()
    return CandidateApproveResponse(project_id=project.id)


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
        clue_subscribes=rows_in_window(ClueSubscription),
    )
    downstream = (
        funnel.clue_source_clicks + funnel.clue_tool_clicks + funnel.clue_related_clicks + funnel.clue_subscribes
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
