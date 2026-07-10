# ============================================================
# 这个文件是干什么的：定义评论表 comments 与评论点赞表 comment_likes。
# 它对应产品里的什么功能：项目/动态详情下的评论（含一层楼中楼回复）与评论点赞。
# 如果它出错了，用户会看到什么现象：评论发不出/看不到、点赞不生效。
# ============================================================
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import (
    TIMESTAMP,
    CheckConstraint,
    ForeignKey,
    Index,
    Integer,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CreatedAtMixin, uuid_pk


class Comment(CreatedAtMixin, Base):
    """评论（项目/动态共用）。host_type∈{project,post}，parent_comment_id 支持一层楼中楼。
    软删（deleted_at）不物理删。外键带 ON DELETE CASCADE。"""

    __tablename__ = "comments"

    id: Mapped[uuid.UUID] = uuid_pk()
    host_type: Mapped[str] = mapped_column(Text, nullable=False)  # 'project' | 'post'
    host_id: Mapped[uuid.UUID] = mapped_column(nullable=False)
    author_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    content: Mapped[str] = mapped_column(Text, nullable=False)
    # 楼中楼：回复挂在某条顶级评论上（服务层校验 parent 是同宿主的顶级评论）。
    parent_comment_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        ForeignKey("comments.id", ondelete="CASCADE"), nullable=True
    )
    like_count: Mapped[int] = mapped_column(Integer, server_default=text("0"), nullable=False)
    deleted_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMP(timezone=True))

    __table_args__ = (
        CheckConstraint("host_type IN ('project','post')", name="ck_comments_host_type"),
        Index("ix_comments_host", "host_type", "host_id"),
        Index("ix_comments_parent", "parent_comment_id"),
        # H-MDL-8：软删列的部分索引——列表只展示未删评论
        Index("ix_comments_live_host", "host_type", "host_id", postgresql_where=text("deleted_at IS NULL")),
        # 外键 author_user_id 补索引：用户注销时（ON DELETE CASCADE）需回扫其评论，
        # 无索引会全表扫；也支撑「某用户的评论」查询。
        Index("ix_comments_author", "author_user_id"),
    )


class CommentLike(CreatedAtMixin, Base):
    """评论点赞：同一人对同一评论只能赞一次。"""

    __tablename__ = "comment_likes"

    id: Mapped[uuid.UUID] = uuid_pk()
    comment_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("comments.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    __table_args__ = (
        UniqueConstraint("comment_id", "user_id", name="uq_comment_likes_comment_user"),
    )
