# ============================================================
# 这个文件是干什么的：评论的业务逻辑——发/删/赞评论、列出评论（含楼中楼、批量载作者防 N+1）。
# 它对应产品里的什么功能：项目/动态详情评论区。
# 如果它出错了：评论发不出/看不到、点赞不生效、评论区加载慢。
# ============================================================
import uuid
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

from sqlalchemy import func, select, tuple_
from sqlalchemy.orm import Session

from app.core.errors import AppError
from app.core.pagination import encode_cursor
from app.core.utils import parse_datetime_cursor
from app.models import Comment, CommentLike, Post, Project, User
from app.schemas.comment import CommentOut
from app.schemas.user import UserBrief

_HOST_TYPES = ("project", "post")


def _validate_host(db: Session, host_type: str, host_id: uuid.UUID) -> None:
    if host_type not in _HOST_TYPES:
        raise AppError(422, "VALIDATION_FAILED", "host_type 只能是 project 或 post")
    if host_type == "project":
        p = db.get(Project, host_id)
        if p is None or p.deleted_at is not None or p.status != "published":
            raise AppError(404, "NOT_FOUND", "评论的项目不存在或未发布")
    else:  # post（阶段3 建表后启用宿主校验）
        post = db.get(Post, host_id)
        if post is None or post.deleted_at is not None:
            raise AppError(404, "NOT_FOUND", "评论的动态不存在或已删除")


def _authors_map(db: Session, ids: List[uuid.UUID]) -> Dict[uuid.UUID, UserBrief]:
    """批量载作者（防 N+1）。"""
    if not ids:
        return {}
    rows = db.scalars(select(User).where(User.id.in_(ids))).all()
    return {u.id: UserBrief.model_validate(u, from_attributes=True) for u in rows}


def _liked_set(db: Session, viewer: Optional[User], comment_ids: List[uuid.UUID]) -> set:
    if viewer is None or not comment_ids:
        return set()
    rows = db.scalars(
        select(CommentLike.comment_id).where(
            CommentLike.user_id == viewer.id, CommentLike.comment_id.in_(comment_ids)
        )
    ).all()
    return set(rows)


def _to_out(c: Comment, authors: Dict, liked: set, replies: List[CommentOut]) -> CommentOut:
    return CommentOut(
        id=c.id, host_type=c.host_type, host_id=c.host_id,
        author=authors.get(c.author_user_id),
        content=c.content, likes=c.like_count or 0,
        replies=replies, created_at=c.created_at,
        is_liked=c.id in liked,
    )


def create_comment(db: Session, user: User, host_type: str, host_id: uuid.UUID,
                   content: str, parent_comment_id: Optional[uuid.UUID]) -> CommentOut:
    _validate_host(db, host_type, host_id)
    if parent_comment_id is not None:
        parent = db.get(Comment, parent_comment_id)
        if parent is None or parent.deleted_at is not None:
            raise AppError(404, "NOT_FOUND", "回复的评论不存在")
        if parent.parent_comment_id is not None:
            raise AppError(422, "VALIDATION_FAILED", "只能回复顶级评论（楼中楼仅一层）")
        if parent.host_type != host_type or parent.host_id != host_id:
            raise AppError(422, "VALIDATION_FAILED", "回复的评论不属于该内容")
    c = Comment(
        host_type=host_type, host_id=host_id, author_user_id=user.id,
        content=content, parent_comment_id=parent_comment_id,
    )
    db.add(c)
    db.commit()
    db.refresh(c)
    authors = _authors_map(db, [c.author_user_id])
    return _to_out(c, authors, set(), [])


def delete_comment(db: Session, user: User, comment_id: uuid.UUID) -> None:
    c = db.get(Comment, comment_id)
    if c is None or c.deleted_at is not None:
        raise AppError(404, "NOT_FOUND", "评论不存在")
    if c.author_user_id != user.id:
        raise AppError(403, "FORBIDDEN", "只能删除自己的评论")
    c.deleted_at = datetime.now(timezone.utc)
    db.commit()


def set_comment_like(db: Session, user: User, comment_id: uuid.UUID, on: bool) -> None:
    c = db.get(Comment, comment_id)
    if c is None or c.deleted_at is not None:
        raise AppError(404, "NOT_FOUND", "评论不存在")
    existing = db.scalar(
        select(CommentLike).where(CommentLike.comment_id == comment_id, CommentLike.user_id == user.id)
    )
    if on and existing is None:
        db.add(CommentLike(comment_id=comment_id, user_id=user.id))
        c.like_count = (c.like_count or 0) + 1
        db.commit()
    elif not on and existing is not None:
        db.delete(existing)
        c.like_count = max(0, (c.like_count or 0) - 1)
        db.commit()
    # 幂等：重复赞/重复取消不报错、不重复计


def list_comments(db: Session, host_type: str, host_id: uuid.UUID, viewer: Optional[User],
                  cursor: Optional[str], page_size: int) -> Tuple[List[CommentOut], Optional[str], bool]:
    """列顶级评论（一页）+ 每条内嵌其楼中楼回复。批量载作者/点赞防 N+1。"""
    stmt = (
        select(Comment)
        .where(
            Comment.host_type == host_type, Comment.host_id == host_id,
            Comment.parent_comment_id.is_(None), Comment.deleted_at.is_(None),
        )
        .order_by(Comment.created_at.desc(), Comment.id.desc())
    )
    if cursor:
        c_dt, c_id = parse_datetime_cursor(cursor)
        stmt = stmt.where(tuple_(Comment.created_at, Comment.id) < (c_dt, c_id))
    tops = db.scalars(stmt.limit(page_size + 1)).all()
    has_more = len(tops) > page_size
    tops = list(tops[:page_size])
    next_cursor = (
        encode_cursor([tops[-1].created_at.isoformat(), str(tops[-1].id)]) if has_more and tops else None
    )

    top_ids = [c.id for c in tops]
    # 批量取所有回复（parent in 本页顶级评论），按时间升序（楼中楼旧→新）。
    replies_by_parent: Dict[uuid.UUID, List[Comment]] = {}
    if top_ids:
        rep_rows = db.scalars(
            select(Comment).where(
                Comment.parent_comment_id.in_(top_ids), Comment.deleted_at.is_(None)
            ).order_by(Comment.created_at.asc())
        ).all()
        for r in rep_rows:
            replies_by_parent.setdefault(r.parent_comment_id, []).append(r)

    all_comments = list(tops) + [r for rs in replies_by_parent.values() for r in rs]
    authors = _authors_map(db, [c.author_user_id for c in all_comments])
    liked = _liked_set(db, viewer, [c.id for c in all_comments])

    out = []
    for top in tops:
        reps = [_to_out(r, authors, liked, []) for r in replies_by_parent.get(top.id, [])]
        out.append(_to_out(top, authors, liked, reps))
    return out, next_cursor, has_more
