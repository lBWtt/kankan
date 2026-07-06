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

from app.api.deps import ERRORS_PUBLIC
from app.core.db import get_db
from app.core.errors import AppError
from app.core.pagination import decode_cursor, encode_cursor
from app.models import Project, User
from app.schemas.common import Page
from app.schemas.project import ProjectCard
from app.schemas.user import UserPublic
from app.services.projects import card_from_project

router = APIRouter(prefix="/users", tags=["用户主页"], responses=ERRORS_PUBLIC)


def _get_public_user(db: Session, user_id: uuid.UUID) -> User:
    u = db.get(User, user_id)
    if u is None or u.deleted_at is not None:
        raise AppError(404, "NOT_FOUND", "用户不存在")
    return u


@router.get("/{user_id}", response_model=UserPublic, summary="用户公开主页（游客可用）")
def get_user(user_id: uuid.UUID, db: Session = Depends(get_db)):
    """只暴露公开字段（昵称/头像/简介/角色/已发布作品数），手机号邮箱等绝不外泄。"""
    u = _get_public_user(db, user_id)
    count = db.scalar(
        select(func.count()).select_from(Project).where(
            Project.author_user_id == u.id, Project.status == "published", Project.deleted_at.is_(None)
        )
    ) or 0
    return UserPublic(
        id=u.id, nickname=u.nickname, avatar_url=u.avatar_url, role=u.role,
        bio=u.bio, published_project_count=count,
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
        dt_s, id_s = decode_cursor(cursor, 2)
        try:
            c_dt, c_id = datetime.fromisoformat(dt_s), uuid.UUID(id_s)
        except ValueError:
            raise AppError(422, "VALIDATION_FAILED", "cursor 无效")
        stmt = stmt.where(tuple_(Project.published_at, Project.id) < (c_dt, c_id))

    rows = db.scalars(stmt.limit(page_size + 1)).all()
    has_more = len(rows) > page_size
    rows = rows[:page_size]
    next_cursor = (
        encode_cursor([rows[-1].published_at.isoformat(), str(rows[-1].id)]) if has_more and rows else None
    )
    return Page[ProjectCard](items=[card_from_project(p) for p in rows], next_cursor=next_cursor, has_more=has_more)
