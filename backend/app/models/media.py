# ============================================================
# 这个文件是干什么的：定义"项目媒体表"——每个项目除主封面外的附加图片/视频（画廊）。
# 它对应产品里的什么功能：项目详情页的图片画廊和视频展示。
# 如果它出错了，用户会看到什么现象：详情页只剩文字和封面，画廊图片/视频加载不出来。
# ============================================================
import uuid
from typing import Optional

from sqlalchemy import CheckConstraint, ForeignKey, Index, Integer, String, Text, text
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, CreatedAtMixin, uuid_pk


class ProjectMedia(CreatedAtMixin, Base):
    __tablename__ = "project_media"

    id: Mapped[uuid.UUID] = uuid_pk()
    # 可空 = 暂存态：用户先上传拿 media_id，发布项目时才挂到 project（迁移 0002 放宽）
    # C-MDL-3：ondelete=CASCADE——项目删除时其画廊媒体随删
    project_id: Mapped[Optional[uuid.UUID]] = mapped_column(ForeignKey("projects.id", ondelete="CASCADE"))
    # 上传者（迁移 0004）：发布挂载时校验暂存媒体属于本人，杜绝跨用户挂别人未挂载的媒体。
    # 可空——AI approve 复制进来的项目媒体没有站内上传者（补全决策）。
    # C-MDL-3：ondelete=CASCADE——上传者注销时其媒体随删。
    uploader_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    media_type: Mapped[str] = mapped_column(String(20), nullable=False)  # image / video
    url: Mapped[str] = mapped_column(Text, nullable=False)
    # 视频可配封面缩略图（补全决策：v1.2 原文不可得，按 PRD §8.5 媒体模型合理推断）
    thumbnail_url: Mapped[Optional[str]] = mapped_column(Text)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, server_default=text("0"))

    __table_args__ = (
        CheckConstraint("media_type IN ('image', 'video')", name="media_type_allowed"),
        Index("ix_project_media_project_id", "project_id"),
        # C-MDL-1：补齐 ix_project_media_uploader 索引声明（迁移 0004 已建，模型曾漏声明，避免 autogenerate 漂移）
        Index("ix_project_media_uploader", "uploader_user_id"),
    )
