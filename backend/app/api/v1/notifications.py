# ============================================================
# 这个文件是干什么的：通知中心接口的路由——通知列表和标记已读。
# 它对应产品里的什么功能：通知中心页、App 角标红点。
# 如果它出错了，用户会看到什么现象：通知中心打不开、红点消不掉。
# ============================================================
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import func, select, tuple_, update
from sqlalchemy.orm import Session

from app.api.deps import ERRORS_AUTHED, auth_required
from app.core.db import get_db
from app.core.errors import AppError
from app.core.pagination import decode_cursor, encode_cursor
from app.models import Notification, User
from app.schemas.common import OkResponse, Page
from app.schemas.notification import NotificationItem


class UnreadCountResponse(BaseModel):
    count: int

router = APIRouter(prefix="/notifications", tags=["通知"], responses=ERRORS_AUTHED)


@router.get("", response_model=Page[NotificationItem], summary="通知列表")
def list_notifications(
    unread_only: bool = Query(False),
    cursor: Optional[str] = None,
    page_size: int = Query(20, ge=1, le=50),
    user: User = Depends(auth_required),
    db: Session = Depends(get_db),
):
    stmt = (
        select(Notification)
        .where(Notification.user_id == user.id)
        .order_by(Notification.created_at.desc(), Notification.id.desc())
    )
    if unread_only:
        stmt = stmt.where(Notification.is_read.is_(False))
    if cursor:
        dt_s, id_s = decode_cursor(cursor, 2)
        try:
            c_dt = datetime.fromisoformat(dt_s)
            c_id = uuid.UUID(id_s)
        except ValueError:
            raise AppError(422, "VALIDATION_FAILED", "cursor 无效")
        stmt = stmt.where(tuple_(Notification.created_at, Notification.id) < (c_dt, c_id))

    rows = db.scalars(stmt.limit(page_size + 1)).all()
    has_more = len(rows) > page_size
    rows = rows[:page_size]
    next_cursor = None
    if has_more and rows:
        last = rows[-1]
        next_cursor = encode_cursor([last.created_at.isoformat(), str(last.id)])
    return Page[NotificationItem](
        items=[
            NotificationItem(
                id=n.id, type=n.type, title=n.title, body=n.body,
                project_id=n.project_id, actor_user_id=n.actor_user_id, post_id=n.post_id,
                is_read=n.is_read, created_at=n.created_at,
            )
            for n in rows
        ],
        next_cursor=next_cursor,
        has_more=has_more,
    )


@router.get("/unread-count", response_model=UnreadCountResponse, summary="未读通知数（红点角标）")
def unread_count(user: User = Depends(auth_required), db: Session = Depends(get_db)):
    """给底部「消息」Tab 的红点用：只数自己的未读通知。"""
    n = db.scalar(
        select(func.count())
        .select_from(Notification)
        .where(Notification.user_id == user.id, Notification.is_read.is_(False))
    )
    return UnreadCountResponse(count=int(n or 0))


@router.post("/read-all", response_model=OkResponse, summary="全部标记已读")
def mark_all_read(user: User = Depends(auth_required), db: Session = Depends(get_db)):
    """进通知中心时一键清红点：把自己所有未读标为已读。"""
    db.execute(
        update(Notification)
        .where(Notification.user_id == user.id, Notification.is_read.is_(False))
        .values(is_read=True, read_at=datetime.now(timezone.utc))
    )
    db.commit()
    return OkResponse()


@router.patch("/{notification_id}/read", response_model=OkResponse, summary="标记已读")
def mark_read(
    notification_id: uuid.UUID,
    user: User = Depends(auth_required),
    db: Session = Depends(get_db),
):
    """只能标自己的通知；别人的通知一律 404（不暴露存在性）。重复标记幂等成功。"""
    n = db.get(Notification, notification_id)
    if n is None or n.user_id != user.id:
        raise AppError(404, "NOT_FOUND", "通知不存在")
    if not n.is_read:
        n.is_read = True
        n.read_at = datetime.now(timezone.utc)
        db.commit()
    return OkResponse()
