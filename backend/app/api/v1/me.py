# ============================================================
# 这个文件是干什么的："我的"相关接口路由——查/改个人资料、推送偏好、onboarding 兴趣、
#   我的收藏列表、我的想试列表。
# 它对应产品里的什么功能："我的"页、设置页、首启兴趣采集、收藏 Tab。
# 如果它出错了，用户会看到什么现象：个人页/收藏页打不开，设置改不动。
# ============================================================
import uuid as uuidlib
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy import delete, func, select, tuple_, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import ERRORS_AUTHED, auth_required
from app.core.db import get_db
from app.core.errors import AppError
from app.core.handle import is_valid_handle, normalize_handle
from app.core.pagination import decode_cursor, encode_cursor
from app.core.security import revoke_user_refresh_tokens
from app.core.utils import parse_datetime_cursor
from app.models import (
    AnalyticsEvent,
    CandidateContent,
    CommentLike,
    Favorite,
    Feedback,
    HowToInterest,
    Notification,
    Post,
    PostLike,
    Project,
    ProjectActionEvent,
    ProjectMedia,
    ProjectReaction,
    PushPreference,
    Report,
    Share,
    TopicFollow,
    TryItem,
    User,
    UserFollow,
)
from app.schemas.common import OkResponse, Page
from app.schemas.project import ProjectCard
from app.schemas.activity import ActivityDay, ActivityEvent, ActivityStats, MyActivityResponse
from app.services import social
from app.services.projects import cards_from_projects_with_stats, list_linked_projects
from app.schemas.user import (
    InterestsWrite,
    MeResponse,
    MeUpdate,
    PushPreferencesResponse,
    PushPreferencesUpdate,
)

router = APIRouter(prefix="/me", tags=["我的"], dependencies=[Depends(auth_required)], responses=ERRORS_AUTHED)


def _me_with_counts(db: Session, user: User) -> MeResponse:
    me = MeResponse.model_validate(user)
    me.following_count = social.following_count(db, user.id)
    me.follower_count = social.follower_count(db, user.id)
    me.favorite_count = (
        db.scalar(select(func.count()).select_from(Favorite).where(Favorite.user_id == user.id)) or 0
    )
    # 获赞 = 我的（未删）项目收到的反应数 + 我的（未删）动态收到的点赞数。
    my_project_ids = select(Project.id).where(
        Project.author_user_id == user.id, Project.deleted_at.is_(None)
    )
    my_post_ids = select(Post.id).where(
        Post.author_user_id == user.id, Post.deleted_at.is_(None)
    )
    reaction_likes = (
        db.scalar(
            select(func.count()).select_from(ProjectReaction).where(
                ProjectReaction.project_id.in_(my_project_ids)
            )
        )
        or 0
    )
    post_likes = (
        db.scalar(
            select(func.count()).select_from(PostLike).where(PostLike.post_id.in_(my_post_ids))
        )
        or 0
    )
    me.received_like_count = reaction_likes + post_likes
    return me


@router.get("", response_model=MeResponse, summary="我的资料")
def get_me(user: User = Depends(auth_required), db: Session = Depends(get_db)):
    return _me_with_counts(db, user)


@router.patch("", response_model=MeResponse, summary="修改资料（语言/昵称/兴趣等）")
def update_me(body: MeUpdate, user: User = Depends(auth_required), db: Session = Depends(get_db)):
    """只改传了的字段；传 null 视为不修改（资料字段没有"清空"语义，头像/简介除外）。"""
    changes = body.model_dump(exclude_unset=True)
    # @handle 单独处理：规范化 + 格式校验 + 唯一性校验（撞了给 409，不走 IntegrityError→500）。
    if "handle" in changes and changes.get("handle") is not None:
        new_handle = normalize_handle(changes.pop("handle"))
        if not is_valid_handle(new_handle):
            raise AppError(422, "VALIDATION_FAILED",
                           "用户名只能用小写字母/数字/下划线，字母开头，3–30 位", {"handle": new_handle})
        if new_handle != (user.handle or ""):
            taken = db.scalar(
                select(User.id).where(User.handle == new_handle, User.id != user.id)
            )
            if taken is not None:
                raise AppError(409, "HANDLE_TAKEN", "这个用户名已被占用", {"handle": new_handle})
            user.handle = new_handle
    else:
        changes.pop("handle", None)  # 显式传 null 视为不改
    for field, value in changes.items():
        if value is None and field not in (
            "avatar_url", "bio", "school", "age", "country_region", "role"
        ):
            continue
        if field in ("interests", "interest_content_types") and value is not None:
            setattr(user, field, [d.value if hasattr(d, "value") else d for d in value])
        elif hasattr(value, "value"):
            setattr(user, field, value.value)
        else:
            setattr(user, field, value)
    db.commit()
    return _me_with_counts(db, user)


@router.delete("", response_model=OkResponse, summary="注销当前账号")
def delete_me(user: User = Depends(auth_required), db: Session = Depends(get_db)):
    """立即注销账号、撤销全部设备会话，并匿名化保留公开内容。

    已发布的作品/动态/评论可能已经参与公共讨论，保留内容但作者统一显示为
    “已注销用户”；收藏、点赞、关注、通知、埋点等账号行为数据会解除关联或删除。
    管理员账号承载不可抵赖的审核日志，必须先在运维侧移交权限，不能在 App 内注销。
    """
    if user.is_admin:
        raise AppError(403, "ADMIN_ACCOUNT_PROTECTED", "管理员账号请先移交权限后再注销")

    uid = user.id
    tombstone = uid.hex

    # 私人/行为数据：物理删除，避免注销后仍可还原用户画像。
    for model in (
        Favorite,
        TryItem,
        HowToInterest,
        ProjectReaction,
        CommentLike,
        PostLike,
        Share,
        ProjectActionEvent,
        TopicFollow,
        PushPreference,
        Report,
    ):
        db.execute(delete(model).where(model.user_id == uid)) if hasattr(model, "user_id") else db.execute(
            delete(model).where(model.reporter_user_id == uid)
        )
    db.execute(
        delete(UserFollow).where(
            (UserFollow.follower_user_id == uid) | (UserFollow.followee_user_id == uid)
        )
    )
    db.execute(delete(Notification).where(Notification.user_id == uid))

    # 保留其他人的记录和公开内容，但移除对注销账号的身份指向。
    db.execute(
        update(Notification).where(Notification.actor_user_id == uid).values(actor_user_id=None)
    )
    db.execute(update(ProjectMedia).where(ProjectMedia.uploader_user_id == uid).values(uploader_user_id=None))
    db.execute(update(Feedback).where(Feedback.user_id == uid).values(user_id=None))
    db.execute(
        update(CandidateContent)
        .where(CandidateContent.reviewed_by_user_id == uid)
        .values(reviewed_by_user_id=None)
    )
    db.execute(update(AnalyticsEvent).where(AnalyticsEvent.user_id == uid).values(user_id=None))

    # 用唯一墓碑邮箱满足 contact_present 约束，同时释放原手机号/邮箱供重新注册。
    user.email = f"deleted+{tombstone}@invalid.local"
    user.phone = None
    user.handle = f"deleted_{tombstone[:16]}"
    user.nickname = "已注销用户"
    user.avatar_url = None
    user.bio = None
    user.school = None
    user.age = None
    user.country_region = None
    user.interests = []
    user.interest_content_types = []
    user.role = None
    user.membership_tier = None
    user.membership_expires_at = None
    user.deleted_at = datetime.now(timezone.utc)

    # 先 flush 验证数据库约束，再撤销所有设备的 refresh；任一步失败都回滚数据库。
    try:
        db.flush()
        revoke_user_refresh_tokens(uid)
        db.commit()
    except Exception:
        db.rollback()
        raise
    return OkResponse()


@router.post("/interests", response_model=OkResponse, summary="onboarding 写入兴趣领域")
def set_interests(body: InterestsWrite, user: User = Depends(auth_required), db: Session = Depends(get_db)):
    user.interests = [d.value for d in body.interests]
    db.commit()
    return OkResponse()


def _get_or_create_prefs(db: Session, user: User) -> PushPreference:
    """每用户一行、默认全开；首次访问时建行（注册时不预建，省一次写）。"""
    prefs = db.scalar(select(PushPreference).where(PushPreference.user_id == user.id))
    if prefs is None:
        prefs = PushPreference(user_id=user.id)
        db.add(prefs)
        try:
            db.commit()
        except IntegrityError:
            # 并发下首屏多请求同时建行，撞 user_id 唯一约束：回滚后取已建好的那行
            db.rollback()
            return db.scalar(select(PushPreference).where(PushPreference.user_id == user.id))
        db.refresh(prefs)  # 拿到 server_default 的全开默认值
    return prefs


@router.get("/push-preferences", response_model=PushPreferencesResponse, summary="推送偏好")
def get_push_preferences(user: User = Depends(auth_required), db: Session = Depends(get_db)):
    prefs = _get_or_create_prefs(db, user)
    return PushPreferencesResponse.model_validate(prefs, from_attributes=True)


@router.patch("/push-preferences", response_model=PushPreferencesResponse, summary="修改推送偏好")
def update_push_preferences(
    body: PushPreferencesUpdate, user: User = Depends(auth_required), db: Session = Depends(get_db)
):
    prefs = _get_or_create_prefs(db, user)
    for field, value in body.model_dump(exclude_unset=True).items():
        if value is not None:
            setattr(prefs, field, value)
    db.commit()
    return PushPreferencesResponse.model_validate(prefs, from_attributes=True)


@router.get("/favorites", response_model=Page[ProjectCard], summary="我的收藏（收藏 Tab）")
def my_favorites(
    cursor: Optional[str] = None,
    page_size: int = Query(20, ge=1, le=50),
    user: User = Depends(auth_required),
    db: Session = Depends(get_db),
):
    """按收藏时间倒序；被下架/删除的项目自动隐藏。"""
    rows, next_cursor, has_more = list_linked_projects(db, Favorite, user, cursor, page_size)
    # 使用批量组装函数，填充 author 和 counts（author 在函数内批量自查，无需 selectinload）
    items = cards_from_projects_with_stats(db, [project for _, project in rows])
    for item, (link, _) in zip(items, rows):
        item.linked_at = link.created_at
    return Page[ProjectCard](items=items, next_cursor=next_cursor, has_more=has_more)


@router.get("/try", response_model=Page[ProjectCard], summary="我的想试（收藏 Tab 第二栏）")
def my_try_items(
    cursor: Optional[str] = None,
    page_size: int = Query(20, ge=1, le=50),
    user: User = Depends(auth_required),
    db: Session = Depends(get_db),
):
    rows, next_cursor, has_more = list_linked_projects(db, TryItem, user, cursor, page_size)
    # 使用批量组装函数，填充 author 和 counts
    items = cards_from_projects_with_stats(db, [project for _, project in rows])
    for item, (link, _) in zip(items, rows):
        item.linked_at = link.created_at
    return Page[ProjectCard](items=items, next_cursor=next_cursor, has_more=has_more)


@router.get("/projects", response_model=Page[ProjectCard], summary="我的发布（含非 published 状态）")
def my_projects(
    cursor: Optional[str] = None,
    page_size: int = Query(20, ge=1, le=50),
    user: User = Depends(auth_required),
    db: Session = Depends(get_db),
):
    """自己的全部项目（草稿/已发布/下架/审核中都给，软删的不给），按创建时间倒序。"""
    stmt = (
        select(Project)
        .where(Project.author_user_id == user.id, Project.deleted_at.is_(None))
        .order_by(Project.created_at.desc(), Project.id.desc())
    )
    if cursor:
        c_dt, c_id = parse_datetime_cursor(cursor)
        stmt = stmt.where(tuple_(Project.created_at, Project.id) < (c_dt, c_id))

    rows = db.scalars(stmt.limit(page_size + 1)).all()
    has_more = len(rows) > page_size
    rows = rows[:page_size]
    next_cursor = None
    if has_more and rows:
        next_cursor = encode_cursor([rows[-1].created_at.isoformat(), str(rows[-1].id)])
    # 与收藏/想试列表一致：填充 author 和 counts，否则“我的发布”卡片没互动数据
    items = cards_from_projects_with_stats(db, rows)
    return Page[ProjectCard](items=items, next_cursor=next_cursor, has_more=has_more)


@router.get("/activity", response_model=MyActivityResponse, summary="我的真实贡献与活动")
def my_activity(
    user: User = Depends(auth_required), db: Session = Depends(get_db)
):
    now = datetime.now(timezone.utc)
    start = now - timedelta(days=181)
    year_start = datetime(now.year, 1, 1, tzinfo=timezone.utc)

    projects = list(db.scalars(select(Project).where(
        Project.author_user_id == user.id,
        Project.deleted_at.is_(None),
        Project.created_at >= start,
    )).all())
    posts = list(db.scalars(select(Post).where(
        Post.author_user_id == user.id,
        Post.deleted_at.is_(None),
        Post.created_at >= start,
    )).all())
    favorites = list(db.scalars(select(Favorite).where(
        Favorite.user_id == user.id, Favorite.created_at >= start
    )).all())
    tries = list(db.scalars(select(TryItem).where(
        TryItem.user_id == user.id, TryItem.created_at >= start
    )).all())
    notifications = list(db.scalars(select(Notification).where(
        Notification.user_id == user.id, Notification.created_at >= start
    )).all())

    # 贡献热力图只计「作品发布 + 收藏 + 想试」，不计动态——动态是轻内容，算进贡献会虚高。
    # （动态仍进下面的活动时间线 events 和 publish_count，只是不进热力格子。）
    counts: dict = {}
    for row in [*projects, *favorites, *tries]:
        day = row.created_at.date()
        counts[day] = counts.get(day, 0) + 1
    days = []
    for offset in range(182):
        day = (start + timedelta(days=offset)).date()
        count = counts.get(day, 0)
        days.append(ActivityDay(date=day, count=count, level=min(4, count)))

    events = [
        *[ActivityEvent(type="publish_project", text=f"发布了作品《{p.title}》", created_at=p.created_at, target_id=str(p.id)) for p in projects],
        *[ActivityEvent(type="publish_post", text="发布了动态", created_at=p.created_at, target_id=str(p.id)) for p in posts],
        *[ActivityEvent(type="favorite", text="收藏了一个作品", created_at=f.created_at, target_id=str(f.project_id)) for f in favorites],
        *[ActivityEvent(type="try", text="标记了想试的作品", created_at=t.created_at, target_id=str(t.project_id)) for t in tries],
        *[ActivityEvent(type="notification", text=n.title, created_at=n.created_at, target_id=str(n.project_id) if n.project_id else None) for n in notifications],
    ]
    events.sort(key=lambda e: e.created_at, reverse=True)
    me = _me_with_counts(db, user)
    publish_count = sum(1 for row in [*projects, *posts] if row.created_at >= year_start)
    favorite_count = sum(1 for row in favorites if row.created_at >= year_start)
    return MyActivityResponse(
        stats=ActivityStats(
            publish_count=publish_count,
            received_like_count=me.received_like_count,
            favorite_count=favorite_count,
        ),
        days=days,
        events=events[:30],
    )
