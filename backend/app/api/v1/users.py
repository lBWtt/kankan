# ============================================================
# 这个文件是干什么的：用户公开主页接口的路由——看别人的资料和 TA 发布的作品。
# 它对应产品里的什么功能：详情页点作者头像 → 用户主页 → TA 的作品列表。
# 如果它出错了，用户会看到什么现象：点作者头像打不开主页。
# ============================================================
import uuid
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select, tuple_
from sqlalchemy.orm import Session

from app.api.deps import ERRORS_AUTHED, ERRORS_PUBLIC, auth_optional, auth_required
from app.core.db import get_db
from app.core.errors import AppError
from app.core.pagination import decode_cursor, encode_cursor
from app.core.utils import parse_datetime_cursor, safe_like_pattern
from app.models import Project, User
from app.schemas.common import OkResponse, Page
from app.schemas.post import PostOut
from app.schemas.project import ProjectCard
from app.schemas.user import UserBrief, UserPublic
from app.services import posts as post_svc
from app.services import social
from app.services.projects import cards_from_projects_with_stats

router = APIRouter(prefix="/users", tags=["用户主页"], responses=ERRORS_PUBLIC)


def _get_public_user(db: Session, user_id: uuid.UUID) -> User:
    u = db.get(User, user_id)
    if u is None or u.deleted_at is not None:
        raise AppError(404, "NOT_FOUND", "用户不存在")
    return u


@router.get("/search", response_model=list[UserBrief], summary="搜索用户（@handle/昵称/简介，游客可用）")
def search_users(
    q: str = Query(..., min_length=1, max_length=50, description="关键词，匹配 @handle/昵称/简介"),
    limit: int = Query(30, ge=1, le=50),
    db: Session = Depends(get_db),
):
    """按 @handle/昵称/简介模糊匹配未软删用户，按昵称升序返回前 N 个。
    @handle 是稳定用户名（改名后仍能搜到人）——查询里可带或不带前导 @。"""
    # 去掉用户可能输入的前导 @，让 "@lin" 和 "lin" 都能命中 handle。
    like = safe_like_pattern(q.lstrip("@"))
    rows = db.scalars(
        select(User)
        .where(
            User.deleted_at.is_(None),
            func.coalesce(User.handle, "").ilike(like)
            | func.coalesce(User.nickname, "").ilike(like)
            | func.coalesce(User.bio, "").ilike(like),
        )
        .order_by(User.nickname.asc())
        .limit(limit)
    ).all()
    return [
        UserBrief(id=u.id, handle=u.handle, nickname=u.nickname, avatar_url=u.avatar_url, role=u.role)
        for u in rows
    ]


@router.get("/{user_id}", response_model=UserPublic, summary="用户公开主页（游客可用）")
def get_user(
    user_id: uuid.UUID,
    db: Session = Depends(get_db),
    viewer: Optional[User] = Depends(auth_optional),
):
    """只暴露公开字段（昵称/头像/简介/角色/作品数/关注粉丝数），手机号邮箱等绝不外泄。
    登录时附带 is_followed_by_me（当前用户是否已关注 ta）。"""
    u = _get_public_user(db, user_id)
    count = db.scalar(
        select(func.count()).select_from(Project).where(
            Project.author_user_id == u.id, Project.status == "published", Project.deleted_at.is_(None)
        )
    ) or 0
    followed = (
        viewer is not None and social.is_following(db, viewer.id, u.id)
    )
    return UserPublic(
        id=u.id, handle=u.handle, nickname=u.nickname, avatar_url=u.avatar_url, role=u.role,
        bio=u.bio, school=u.school, age=u.age, published_project_count=count,
        following_count=social.following_count(db, u.id),
        follower_count=social.follower_count(db, u.id),
        is_followed_by_me=followed,
    )


@router.post("/{user_id}/follow", response_model=OkResponse, status_code=201,
             responses=ERRORS_AUTHED, summary="关注用户（需登录）")
def follow_user(user_id: uuid.UUID, user: User = Depends(auth_required), db: Session = Depends(get_db)):
    """已关注幂等 201；关注自己 409 CANNOT_FOLLOW_SELF；目标不存在 404。"""
    social.follow(db, user, user_id)
    return OkResponse()


@router.delete("/{user_id}/follow", status_code=204, responses=ERRORS_AUTHED, summary="取消关注（需登录）")
def unfollow_user(user_id: uuid.UUID, user: User = Depends(auth_required), db: Session = Depends(get_db)):
    social.unfollow(db, user, user_id)


@router.get("/{user_id}/followers", response_model=Page[UserBrief], summary="TA 的粉丝（游客可用）")
def user_followers(
    user_id: uuid.UUID,
    cursor: Optional[str] = None,
    page_size: int = Query(20, ge=1, le=50),
    db: Session = Depends(get_db),
):
    _get_public_user(db, user_id)
    users, next_cursor, has_more = social.list_followers(db, user_id, cursor, page_size)
    return Page[UserBrief](
        items=[UserBrief.model_validate(x, from_attributes=True) for x in users],
        next_cursor=next_cursor, has_more=has_more,
    )


@router.get("/{user_id}/following", response_model=Page[UserBrief], summary="TA 关注的人（游客可用）")
def user_following(
    user_id: uuid.UUID,
    cursor: Optional[str] = None,
    page_size: int = Query(20, ge=1, le=50),
    db: Session = Depends(get_db),
):
    _get_public_user(db, user_id)
    users, next_cursor, has_more = social.list_following(db, user_id, cursor, page_size)
    return Page[UserBrief](
        items=[UserBrief.model_validate(x, from_attributes=True) for x in users],
        next_cursor=next_cursor, has_more=has_more,
    )


@router.get("/{user_id}/projects", response_model=Page[ProjectCard], summary="TA 的作品（仅 published）")
def user_projects(
    user_id: uuid.UUID,
    cursor: Optional[str] = None,
    page_size: int = Query(20, ge=1, le=50),
    db: Session = Depends(get_db),
):
    """对外只给 published（草稿/下架/审核中只有本人在 me/projects 里能看到）。"""
    _get_public_user(db, user_id)
    stmt = (
        select(Project)
        .where(
            Project.author_user_id == user_id,
            Project.status == "published",
            Project.deleted_at.is_(None),
        )
        .order_by(Project.published_at.desc(), Project.id.desc())
    )
    if cursor:
        c_dt, c_id = parse_datetime_cursor(cursor)
        stmt = stmt.where(tuple_(Project.published_at, Project.id) < (c_dt, c_id))

    rows = db.scalars(stmt.limit(page_size + 1)).all()
    has_more = len(rows) > page_size
    rows = rows[:page_size]
    next_cursor = (
        encode_cursor([rows[-1].published_at.isoformat(), str(rows[-1].id)]) if has_more and rows else None
    )
    # 批量填充 author 和 counts，与发现流/收藏列表一致（否则主页作品卡片没互动数据）
    items = cards_from_projects_with_stats(db, rows)
    return Page[ProjectCard](items=items, next_cursor=next_cursor, has_more=has_more)


@router.get("/{user_id}/posts", response_model=Page[PostOut], summary="TA 的动态（游客可用）")
def user_posts_list(
    user_id: uuid.UUID,
    cursor: Optional[str] = None,
    page_size: int = Query(20, ge=1, le=50),
    viewer: Optional[User] = Depends(auth_optional),
    db: Session = Depends(get_db),
):
    _get_public_user(db, user_id)
    items, next_cursor, has_more = post_svc.list_user_posts(db, user_id, viewer, cursor, page_size)
    return Page[PostOut](items=items, next_cursor=next_cursor, has_more=has_more)
