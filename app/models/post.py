# ============================================================
# 这个文件是干什么的：定义动态表 posts、动态配图表 post_media、动态点赞表 post_likes。
# 它对应产品里的什么功能：发现页动态流、发动态、动态详情、动态点赞。
# 如果它出错了，用户会看到什么现象：动态发不出/看不到、点赞不生效。
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
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CreatedAtMixin, uuid_pk


class Post(CreatedAtMixin, Base):
    """动态（轻内容）：文字 + 可选图 + 话题 + 引用项目。软删（deleted_at）不物理删。"""

    __tablename__ = "posts"

    id: Mapped[uuid.UUID] = uuid_pk()
    author_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    content: Mapped[str] = mapped_column(Text, nullable=False)
    tags: Mapped[list] = mapped_column(ARRAY(Text), nullable=False, server_default=text("'{}'::text[]"))
    # 引用项目（可选）：项目被删则置 NULL，不连带删动态。
    quote_project_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        ForeignKey("projects.id", ondelete="SET NULL"), nullable=True
    )
    like_count: Mapped[int] = mapped_column(Integer, server_default=text("0"), nullable=False)
    deleted_at: Mapped[Optional[datetime]] = mapped_column(TIMESTAMP(timezone=True))

    __table_args__ = (
        Index("ix_posts_created", "created_at"),
        Index("ix_posts_author", "author_user_id"),
        # H-MDL-8：软删列的部分索引——发现页只刷未删的动态
        Index("ix_posts_live_created", "created_at", postgresql_where=text("deleted_at IS NULL")),
    )


class PostMedia(CreatedAtMixin, Base):
    """动态配图（仅 image；视频走 Project）。url/media_type 从上传的暂存媒体复制过来。"""

    __tablename__ = "post_media"

    id: Mapped[uuid.UUID] = uuid_pk()
    post_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("posts.id", ondelete="CASCADE"), nullable=False
    )
    media_type: Mapped[str] = mapped_column(String(20), nullable=False)  # image / video
    url: Mapped[str] = mapped_column(Text, nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, server_default=text("0"), nullable=False)

    __table_args__ = (
        CheckConstraint("media_type IN ('image','video')", name="ck_post_media_type"),
        Index("ix_post_media_post_id", "post_id"),
    )


class PostLike(CreatedAtMixin, Base):
    """动态点赞：同一人对同一动态只能赞一次。"""

    __tablename__ = "post_likes"

    id: Mapped[uuid.UUID] = uuid_pk()
    post_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("posts.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    __table_args__ = (
        UniqueConstraint("post_id", "user_id", name="uq_post_likes_post_user"),
    )
