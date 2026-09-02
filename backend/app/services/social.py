# ============================================================
# 这个文件是干什么的：关注关系的业务逻辑——关注/取关、粉丝/关注数、是否已关注、列表。
# 它对应产品里的什么功能：我的页关注/粉丝数、个人主页关注按钮、关注/粉丝列表。
# 如果它出错了，用户会看到什么现象：关注点了没反应或重复、粉丝数不对、关注列表空。
# ============================================================
import uuid
from typing import List, Optional, Tuple

from sqlalchemy import func, select, tuple_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.errors import AppError
from app.core.pagination import encode_cursor
from app.core.utils import parse_datetime_cursor
from app.models import User, UserFollow
from app.services.notify import push_interaction


def _require_user(db: Session, user_id: uuid.UUID) -> User:
    u = db.get(User, user_id)
    if u is None or u.deleted_at is not None:
        raise AppError(404, "NOT_FOUND", "用户不存在")
    return u


def follow(db: Session, follower: User, followee_id: uuid.UUID) -> None:
    """关注。自己关注自己 → 409；目标不存在 → 404；已关注 → 幂等（捕获唯一约束）。"""
    if follower.id == followee_id:
        raise AppError(409, "CANNOT_FOLLOW_SELF", "不能关注自己")
    _require_user(db, followee_id)
    db.add(UserFollow(follower_user_id=follower.id, followee_user_id=followee_id))
    # 关注通知：与 UserFollow 同事务——重复关注撞唯一约束回滚时，通知一并作废（不重复提醒）。
    push_interaction(db, recipient_id=followee_id, actor=follower,
                     title=f"{follower.nickname} 关注了你")
    try:
        db.commit()
    except IntegrityError:
        db.rollback()  # 已关注（唯一约束撞）→ 幂等成功，不报错


def unfollow(db: Session, follower: User, followee_id: uuid.UUID) -> None:
    """取消关注。未关注 → 幂等（无行可删，静默成功）。"""
    row = db.scalar(
        select(UserFollow).where(
            UserFollow.follower_user_id == follower.id,
            UserFollow.followee_user_id == followee_id,
        )
    )
    if row is not None:
        db.delete(row)
        db.commit()


def follower_count(db: Session, user_id: uuid.UUID) -> int:
    """粉丝数 = 关注 ta 的人数（排除已注销用户，与 list_followers 口径一致）。

    H-SVC-3：原来 count 不过滤 deleted_at，但列表过滤，导致“显示 100 实际 95”。
    这里 join User 过滤 deleted_at，保证 count 与列表口径一致。
    """
    return db.scalar(
        select(func.count())
        .select_from(UserFollow)
        .join(User, User.id == UserFollow.follower_user_id)
        .where(UserFollow.followee_user_id == user_id, User.deleted_at.is_(None))
    ) or 0


def following_count(db: Session, user_id: uuid.UUID) -> int:
    """关注数 = ta 关注的人数（排除已注销用户，与 list_following 口径一致）。"""
    return db.scalar(
        select(func.count())
        .select_from(UserFollow)
        .join(User, User.id == UserFollow.followee_user_id)
        .where(UserFollow.follower_user_id == user_id, User.deleted_at.is_(None))
    ) or 0


def is_following(db: Session, follower_id: uuid.UUID, followee_id: uuid.UUID) -> bool:
    return db.scalar(
        select(UserFollow.id).where(
            UserFollow.follower_user_id == follower_id,
            UserFollow.followee_user_id == followee_id,
        ).limit(1)
    ) is not None


def _paged_users(
    db: Session, follow_col, filter_col, filter_id: uuid.UUID,
    cursor: Optional[str], page_size: int,
) -> Tuple[List[User], Optional[str], bool]:
    """按关注时间倒序返回一页用户。follow_col=要取的那一端的 user_id 列，filter_col=过滤端。"""
    stmt = (
        select(User, UserFollow.created_at, UserFollow.id)
        .join(UserFollow, follow_col == User.id)
        .where(filter_col == filter_id, User.deleted_at.is_(None))
        .order_by(UserFollow.created_at.desc(), UserFollow.id.desc())
    )
    if cursor:
        c_dt, c_id = parse_datetime_cursor(cursor)
        stmt = stmt.where(tuple_(UserFollow.created_at, UserFollow.id) < (c_dt, c_id))
    rows = db.execute(stmt.limit(page_size + 1)).all()
    has_more = len(rows) > page_size
    rows = rows[:page_size]
    users = [r[0] for r in rows]
    next_cursor = (
        encode_cursor([rows[-1][1].isoformat(), str(rows[-1][2])]) if has_more and rows else None
    )
    return users, next_cursor, has_more


def list_followers(db: Session, user_id: uuid.UUID, cursor: Optional[str], page_size: int):
    """粉丝：关注 user_id 的人（follower 端），按关注时间倒序。"""
    return _paged_users(
        db, UserFollow.follower_user_id, UserFollow.followee_user_id, user_id, cursor, page_size
    )


def list_following(db: Session, user_id: uuid.UUID, cursor: Optional[str], page_size: int):
    """关注：user_id 关注的人（followee 端），按关注时间倒序。"""
    return _paged_users(
        db, UserFollow.followee_user_id, UserFollow.follower_user_id, user_id, cursor, page_size
    )
