# ============================================================
# 这个文件是干什么的：项目互动按钮的路由——收藏、想试、想看怎么做（游客可用！）、
#   创意反馈、线索订阅、分享卡、分享记录、举报。
# 它对应产品里的什么功能：详情页/线索页上的全部按钮；其中想看怎么做是全产品主信号。
# 如果它出错了，用户会看到什么现象：按钮点了没反应；最严重的是主信号丢失，
#   整个产品假设验证不了。
# ============================================================
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends
from sqlalchemy import select as _sel, update
from sqlalchemy.orm import Session

from app.api.deps import ERRORS_AUTHED, ERRORS_PUBLIC, auth_optional, auth_required
from app.core.config import settings
from app.core.db import get_db
from app.core.errors import AppError
from app.core.ratelimit import rate_limit
from app.models import Favorite, Project, ProjectAction, ProjectActionEvent, Report, Share, TryItem, User
from app.schemas.common import OkResponse, ReactionType
from app.schemas.interaction import (
    HowToInterestRequest,
    HowToInterestResponse,
    ReportCreate,
    ReportCreated,
    ShareCardResponse,
    ShareCreate,
)
from app.schemas.project import ProjectActionEventCreate, ProjectActionEventResponse
from app.services import interactions as svc
from app.services.projects import counts_for_project

router = APIRouter(prefix="/projects/{project_id}", tags=["项目互动"])

# ---------- 需登录的互动（登录拦截点：成功后回到原动作） ----------


@router.post("/favorite", response_model=OkResponse, status_code=201, responses=ERRORS_AUTHED,
             summary="收藏（需登录）")
def add_favorite(project_id: uuid.UUID, user: User = Depends(auth_required), db: Session = Depends(get_db)):
    """重复收藏幂等成功（不报 409）。"""
    svc.add_user_link(db, Favorite, user, project_id)
    return OkResponse()


@router.delete("/favorite", status_code=204, responses=ERRORS_AUTHED,
               summary="取消收藏")
def remove_favorite(project_id: uuid.UUID, user: User = Depends(auth_required), db: Session = Depends(get_db)):
    svc.remove_user_link(db, Favorite, user, project_id)


@router.post("/try", response_model=OkResponse, status_code=201, responses=ERRORS_AUTHED,
             summary="加入想试（需登录）")
def add_try(project_id: uuid.UUID, user: User = Depends(auth_required), db: Session = Depends(get_db)):
    svc.add_user_link(db, TryItem, user, project_id)
    return OkResponse()


@router.delete("/try", status_code=204, responses=ERRORS_AUTHED,
               summary="移出想试")
def remove_try(project_id: uuid.UUID, user: User = Depends(auth_required), db: Session = Depends(get_db)):
    svc.remove_user_link(db, TryItem, user, project_id)


@router.post("/reactions/{reaction_type}", response_model=OkResponse, status_code=201, responses=ERRORS_AUTHED,
             summary="点创意反馈（需登录，toggle）")
def add_reaction(
    project_id: uuid.UUID,
    reaction_type: ReactionType,
    user: User = Depends(auth_required),
    db: Session = Depends(get_db),
):
    svc.add_reaction(db, user, project_id, reaction_type.value)
    return OkResponse()


@router.delete("/reactions/{reaction_type}", status_code=204, responses=ERRORS_AUTHED,
               summary="取消创意反馈（删行即取消）")
def remove_reaction(
    project_id: uuid.UUID,
    reaction_type: ReactionType,
    user: User = Depends(auth_required),
    db: Session = Depends(get_db),
):
    svc.remove_reaction(db, user, project_id, reaction_type.value)


@router.post("/reports", response_model=ReportCreated, status_code=201, responses=ERRORS_AUTHED,
             summary="举报（需登录）")
def report_project(
    project_id: uuid.UUID,
    body: ReportCreate,
    user: User = Depends(auth_required),
    db: Session = Depends(get_db),
):
    """同一人可多次举报（流水不去重，后台按队列处理）。"""
    # H-API-5: 举报刷量频控（同一用户 60 秒最多 5 条），超出 429
    rate_limit(f"reports:rl:{user.id}", limit=5, window=60)
    svc.get_published_project(db, project_id)
    report = Report(
        reporter_user_id=user.id,
        project_id=project_id,
        reason=body.reason.value,
        description=body.description,
    )
    db.add(report)
    db.commit()
    return ReportCreated(report_id=report.id)


# ---------- 游客可用的互动（红线：不走登录拦截） ----------


@router.post("/actions/{action_id}/events", response_model=ProjectActionEventResponse, status_code=201,
             responses=ERRORS_PUBLIC, summary="记录新版详情页 action 点击/成功（游客可用）")
def record_action_event(
    project_id: uuid.UUID,
    action_id: uuid.UUID,
    body: ProjectActionEventCreate,
    user: Optional[User] = Depends(auth_optional),
    db: Session = Depends(get_db),
):
    """新版主行为流水：游客不设登录墙，但必须带 anonClientId；take success 会增加拿走计数。"""
    project = svc.get_published_project(db, project_id)
    if user is None and not body.anon_client_id:
        raise AppError(422, "ANON_ID_REQUIRED", "游客触发项目动作必须携带 anonClientId")
    action = db.get(ProjectAction, action_id)
    if action is None or action.project_id != project_id:
        raise AppError(404, "NOT_FOUND", "项目动作不存在")

    # C-API-1(b): 身份级频控——同一身份 60 秒最多 30 条事件，超出 429（防刷流水与热度分）
    identity = str(user.id) if user else (body.anon_client_id or "anon")
    rate_limit(f"action_events:rl:{identity}", limit=30, window=60)

    # C-API-1(a): success 去重——同一身份对同一 action 的 success 只计一次，
    # 防 (actor, action_id, success) 反复刷高 takeaway_count（×6 权重进 hot_score）。
    # click 事件不去重（仍是有效行为流水），只控制 success 不重复 +1。
    if body.event_type.value == "success":
        actor_filter = (
            [ProjectActionEvent.user_id == user.id]
            if user
            else [ProjectActionEvent.user_id.is_(None),
                  ProjectActionEvent.anon_client_id == body.anon_client_id]
        )
        already = db.scalar(
            _sel(ProjectActionEvent.id).where(
                ProjectActionEvent.action_id == action_id,
                ProjectActionEvent.event_type == "success",
                *actor_filter,
            ).limit(1)
        )
        should_increment = not already
    else:
        should_increment = False  # 非 success 不增 takeaway_count

    event = ProjectActionEvent(
        project_id=project_id,
        action_id=action_id,
        user_id=user.id if user else None,
        anon_client_id=None if user else body.anon_client_id,
        event_type=body.event_type.value,
    )
    db.add(event)
    db.flush()

    takeaway_count = project.takeaway_count or 0
    if should_increment and action.action_type == "take":
        takeaway_count = db.scalar(
            update(Project)
            .where(Project.id == project_id)
            .values(takeaway_count=Project.takeaway_count + 1)
            .returning(Project.takeaway_count)
        )
    db.commit()
    return ProjectActionEventResponse(action_event_id=event.id, takeaway_count=takeaway_count or 0)


@router.post("/how-to-interest", response_model=HowToInterestResponse, status_code=201, responses=ERRORS_PUBLIC,
             summary="想看怎么做（主信号，游客可用）")
def how_to_interest(
    project_id: uuid.UUID,
    body: HowToInterestRequest,
    user: Optional[User] = Depends(auth_optional),
    db: Session = Depends(get_db),
):
    """红线：绝不设登录墙。登录态取 token 身份；游客必须带 anon_client_id（缺 → 422 ANON_ID_REQUIRED）。
    项目关闭此功能 → 409 HOW_TO_DISABLED。重复点按幂等返回当前计数。
    路由规则（§5.1）：平台原创→通知作者（每日 1 条聚合）；外部内容→汇入需求看板。"""
    count = svc.add_how_to_interest(db, project_id, user, body.anon_client_id)
    return HowToInterestResponse(how_to_interest_count=count)


@router.post("/share-card", response_model=ShareCardResponse, responses=ERRORS_PUBLIC,
             summary="生成分享卡素材（游客可用）")
def share_card(project_id: uuid.UUID, db: Session = Depends(get_db)):
    """返回分享卡素材（PRD §3.1），客户端渲染成图。share_url 回流 Web 分享页
    （域名走配置 share_base_url；二维码由客户端按 share_url 生成，服务端不出图——补全决策）。"""
    p = svc.get_published_project(db, project_id)
    return ShareCardResponse(
        share_url=f"{settings.share_base_url}/p/{p.id}",
        qr_image_url=None,
        title=p.title,
        tagline=p.tagline,
        cover_media_url=p.cover_media_url,
        domains=p.domains or [],
        category=p.category,
        counts=counts_for_project(db, p.id),
    )


@router.post("/shares", response_model=OkResponse, status_code=201, responses=ERRORS_PUBLIC,
             summary="记录分享行为（游客可用）")
def record_share(
    project_id: uuid.UUID,
    body: ShareCreate,
    user: Optional[User] = Depends(auth_optional),
    db: Session = Depends(get_db),
):
    """clicked=点了分享，completed=分享完成；completed 进 hot_score（×6 权重）。
    流水表不去重（同一人多次分享都算行为）。"""
    svc.get_published_project(db, project_id)
    # 游客必须带 anon_client_id，否则会写出 user_id/anon_client_id 双空的脏行
    # （Share 表没有 HowToInterest/ProjectActionEvent 那样的 identity CHECK 约束兜底）。
    if user is None and not body.anon_client_id:
        raise AppError(422, "ANON_ID_REQUIRED", "游客记录分享必须携带 anon_client_id")

    # C-API-2(b): 身份级频控——同一身份 60 秒最多 20 条分享，超出 429
    identity = str(user.id) if user else (body.anon_client_id or "anon")
    rate_limit(f"shares:rl:{identity}", limit=20, window=60)

    # C-API-2(a): completed 状态按 (actor, project_id) 日级去重——
    # completed 每条 +6 进 hot_score，同身份同项目当日只计一次（防刷热度榜）。
    # clicked 状态不去重（仍是有效漏斗行为），只对 completed 做日级幂等。
    if body.status.value == "completed":
        since_today = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
        dup_filter = (
            [Share.user_id == user.id]
            if user
            else [Share.user_id.is_(None), Share.anon_client_id == body.anon_client_id]
        )
        existed = db.scalar(
            _sel(Share.id).where(
                Share.project_id == project_id,
                Share.share_status == "completed",
                Share.created_at >= since_today,
                *dup_filter,
            ).limit(1)
        )
        if existed:
            return OkResponse()  # 幂等：当日已记过 completed，不再重复落库/计热度

    db.add(
        Share(
            user_id=user.id if user else None,
            anon_client_id=None if user else body.anon_client_id,
            project_id=project_id,
            share_channel=body.channel.value,
            share_status=body.status.value,
        )
    )
    db.commit()
    return OkResponse()
