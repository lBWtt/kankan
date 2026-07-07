# ============================================================
# 这个文件是干什么的：动态的业务逻辑——发/删/赞动态、动态流/详情/某人动态（批量载防 N+1）。
# 它对应产品里的什么功能：发现页动态流、发动态、动态详情、动态点赞。
# 如果它出错了：动态发不出/看不到、点赞不生效、动态流加载慢。
# ============================================================
import uuid
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

from sqlalchemy import func, select, tuple_
from sqlalchemy.orm import Session

from app.core.errors import AppError
from app.core.pagination import encode_cursor
from app.core.utils import parse_datetime_cursor
from app.models import (
    Comment,
    Post,
    PostLike,
    PostMedia,
    ProjectMedia,
    User,
)
from app.schemas.post import PostMediaOut, PostOut
from app.schemas.user import UserBrief


def _attach_media(db: Session, post_id: uuid.UUID, media_ids: List[uuid.UUID], uploader_id: uuid.UUID) -> None:
    """把上传的暂存媒体（POST /media 拿的 id）复制进 post_media。校验：存在 + 暂存态 + 本人上传。"""
    if not media_ids:
        return
    rows = {m.id: m for m in db.scalars(select(ProjectMedia).where(ProjectMedia.id.in_(media_ids)))}
    bad = []
    for mid in media_ids:
        m = rows.get(mid)
        if m is None or m.project_id is not None or m.uploader_user_id != uploader_id:
            bad.append(str(mid))
    if bad:
        raise AppError(422, "VALIDATION_FAILED", "media_ids 含不存在/已占用/非本人上传的媒体",
                       {"invalid_media_ids": bad})
    for i, mid in enumerate(media_ids):
        m = rows[mid]
        db.add(PostMedia(post_id=post_id, media_type=m.media_type, url=m.url, sort_order=i))


def _get_visible(db: Session, post_id: uuid.UUID) -> Post:
    p = db.get(Post, post_id)
    if p is None or p.deleted_at is not None:
        raise AppError(404, "NOT_FOUND", "动态不存在或已删除")
    return p


def _posts_to_out(db: Session, posts: List[Post], viewer: Optional[User]) -> List[PostOut]:
    """批量组装 PostOut：一次性载作者、配图、viewer 点赞、评论数（防 N+1）。"""
    if not posts:
        return []
    ids = [p.id for p in posts]
    author_ids = list({p.author_user_id for p in posts})
    authors = {
        u.id: UserBrief.model_validate(u, from_attributes=True)
        for u in db.scalars(select(User).where(User.id.in_(author_ids)))
    }
    # 配图（按 sort_order）
    media_by_post: Dict[uuid.UUID, List[PostMediaOut]] = {}
    for m in db.scalars(select(PostMedia).where(PostMedia.post_id.in_(ids)).order_by(PostMedia.sort_order.asc())):
        media_by_post.setdefault(m.post_id, []).append(PostMediaOut(type=m.media_type, url=m.url))
    # viewer 点赞
    liked = set()
    if viewer is not None:
        liked = set(db.scalars(
            select(PostLike.post_id).where(PostLike.user_id == viewer.id, PostLike.post_id.in_(ids))
        ).all())
    # 评论数（该动态下未删评论总数，含楼中楼）
    cc_rows = db.execute(
        select(Comment.host_id, func.count())
        .where(Comment.host_type == "post", Comment.host_id.in_(ids), Comment.deleted_at.is_(None))
        .group_by(Comment.host_id)
    ).all()
    comment_counts = {hid: n for hid, n in cc_rows}

    out = []
    for p in posts:
        out.append(PostOut(
            id=p.id, content=p.content, author=authors.get(p.author_user_id),
            media=media_by_post.get(p.id, []), tags=list(p.tags or []),
            quote_project_id=p.quote_project_id, likes=p.like_count or 0,
            comment_count=comment_counts.get(p.id, 0), created_at=p.created_at,
            is_liked=p.id in liked,
        ))
    return out


def create_post(db: Session, user: User, content: str, tags: List[str],
                quote_project_id: Optional[uuid.UUID], media_ids: List[uuid.UUID]) -> PostOut:
    p = Post(author_user_id=user.id, content=content, tags=tags or [], quote_project_id=quote_project_id)
    db.add(p)
    db.flush()
    _attach_media(db, p.id, media_ids, user.id)
    db.commit()
    db.refresh(p)
    return _posts_to_out(db, [p], user)[0]


def get_post(db: Session, post_id: uuid.UUID, viewer: Optional[User]) -> PostOut:
    p = _get_visible(db, post_id)
    return _posts_to_out(db, [p], viewer)[0]


def delete_post(db: Session, user: User, post_id: uuid.UUID) -> None:
    p = db.get(Post, post_id)
    if p is None or p.deleted_at is not None:
        raise AppError(404, "NOT_FOUND", "动态不存在")
    if p.author_user_id != user.id:
        raise AppError(403, "FORBIDDEN", "只能删除自己的动态")
    p.deleted_at = datetime.now(timezone.utc)
    db.commit()


def set_post_like(db: Session, user: User, post_id: uuid.UUID, on: bool) -> None:
    p = _get_visible(db, post_id)
    existing = db.scalar(
        select(PostLike).where(PostLike.post_id == post_id, PostLike.user_id == user.id)
    )
    if on and existing is None:
        db.add(PostLike(post_id=post_id, user_id=user.id))
        p.like_count = (p.like_count or 0) + 1
        db.commit()
    elif not on and existing is not None:
        db.delete(existing)
        p.like_count = max(0, (p.like_count or 0) - 1)
        db.commit()


def _paged(db: Session, base_stmt, viewer: Optional[User], cursor: Optional[str], page_size: int):
    stmt = base_stmt.order_by(Post.created_at.desc(), Post.id.desc())
    if cursor:
        c_dt, c_id = parse_datetime_cursor(cursor)
        stmt = stmt.where(tuple_(Post.created_at, Post.id) < (c_dt, c_id))
    rows = db.scalars(stmt.limit(page_size + 1)).all()
    has_more = len(rows) > page_size
    rows = list(rows[:page_size])
    next_cursor = (
        encode_cursor([rows[-1].created_at.isoformat(), str(rows[-1].id)]) if has_more and rows else None
    )
    return _posts_to_out(db, rows, viewer), next_cursor, has_more


def list_posts(db: Session, viewer: Optional[User], cursor: Optional[str], page_size: int) -> Tuple[List[PostOut], Optional[str], bool]:
    return _paged(db, select(Post).where(Post.deleted_at.is_(None)), viewer, cursor, page_size)


def list_user_posts(db: Session, user_id: uuid.UUID, viewer: Optional[User], cursor: Optional[str], page_size: int):
    return _paged(db, select(Post).where(Post.author_user_id == user_id, Post.deleted_at.is_(None)), viewer, cursor, page_size)
