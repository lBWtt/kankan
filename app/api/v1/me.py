# ============================================================
# 这个文件是干什么的："我的"相关接口路由——查/改个人资料、推送偏好、onboarding 兴趣、
#   我的收藏列表、我的想试列表。
# 它对应产品里的什么功能："我的"页、设置页、首启兴趣采集、收藏 Tab。
# 如果它出错了，用户会看到什么现象：个人页/收藏页打不开，设置改不动。
# ============================================================
import uuid as uuidlib
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select, tuple_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import ERRORS_AUTHED, auth_required
from app.core.db import get_db
from app.core.errors import AppError
from app.core.pagination import decode_cursor, encode_cursor
from app.core.utils import parse_datetime_cursor
from app.models import Favorite, Project, PushPreference, TryItem, User
from app.schemas.common import OkResponse, Page
from app.schemas.project import ProjectCard
from app.services import social
from app.services.projects import card_from_project, cards_from_projects_with_stats, list_linked_projects
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
    return me


@router.get("", response_model=MeResponse, summary="我的资料")
def get_me(user: User = Depends(auth_required), db: Session = Depends(get_db)):
    return _me_with_counts(db, user)


@router.patch("", response_model=MeResponse, summary="修改资料（语言/昵称/兴趣等）")
def update_me(body: MeUpdate, user: User = Depends(auth_required), db: Session = Depends(get_db)):
    """只改传了的字段；传 null 视为不修改（资料字段没有"清空"语义，头像/简介除外）。"""
    changes = body.model_dump(exclude_unset=True)
    for field, value in changes.items():
        if value is None and field not in ("avatar_url", "bio", "country_region", "role"):
            continue
        if field == "interests" and value is not None:
            user.interests = [d.value if hasattr(d, "value") else d for d in value]
        elif hasattr(value, "value"):
            setattr(user, field, value.value)
        else:
            setattr(user, field, value)
    db.commit()
    return _me_with_counts(db, user)


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
    rows, next_cursor, has_more = list_linked_projects(db, Favorite, user, cursor, page_size, load_author=True)
    # 使用批量组装函数，填充 author 和 counts
    items = cards_from_projects_with_stats(db, rows)
    return Page[ProjectCard](items=items, next_cursor=next_cursor, has_more=has_more)


@router.get("/try", response_model=Page[ProjectCard], summary="我的想试（收藏 Tab 第二栏）")
def my_try_items(
    cursor: Optional[str] = None,
    page_size: int = Query(20, ge=1, le=50),
    user: User = Depends(auth_required),
    db: Session = Depends(get_db),
):
    rows, next_cursor, has_more = list_linked_projects(db, TryItem, user, cursor, page_size, load_author=True)
    # 使用批量组装函数，填充 author 和 counts
    items = cards_from_projects_with_stats(db, rows)
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
    return Page[ProjectCard](items=[card_from_project(p) for p in rows], next_cursor=next_cursor, has_more=has_more)
